function runExperiment(protocol, opts)
% runExperiment  Config-driven session orchestrator (replaces Experimenter5000).
%
%   runExperiment(protocol)
%   runExperiment(protocol, opts)
%
%   Runs a sequence of stimulus BLOCKS, each for a number of epochs (presentations),
%   triggering Clampex acquisition once per epoch. Each stimulus writes its own row to
%   the day's stim manifest (see writeStimManifest.m), so the epoch order stays aligned
%   with the .abf files Clampex saves (paired by order downstream in the Analysis Suite).
%
%   protocol : struct array, one element per block, fields:
%       .stim   - stimulus function handle (e.g. @AASeededGaussianGreyScaleStimFinal2026)
%       .args   - cell array of arguments passed to .stim         (default {})
%       .epochs - number of epochs (presentations) of this block  (default 1)
%       .label  - optional block label (char) for the progress printout
%       .seedArg- (seeded stimuli only) index of the seed argument in .args. When set,
%                 runExperiment overwrites it with an auto-incrementing seed per epoch
%                 (seedBase, seedBase+1, ...) so repeated epochs are INDEPENDENT noise,
%                 each seed recorded in the manifest. Omit / 0 for non-seeded stimuli.
%
%   opts : struct (all optional), fields + defaults:
%       .preStim         2       pause (s) after the acquisition trigger, before the stimulus
%       .postStim        1       pause (s) after the stimulus
%       .itp             3       inter-trial pause (s)
%       .settle          1       pause (s) at the start of each epoch
%       .triggerAcq      true    trigger Clampex acquisition each epoch
%       .preflight       true    verify the Stage server is reachable before running
%       .continueOnError false   keep going after a failed epoch (default: ABORT the
%                                session, so no .abf is left without its manifest row)
%       .seedBase        2       first auto-increment seed (used with protocol.seedArg)
%       .leds            []      optional LED-driver setup for the whole session via
%                                NeitzLedRig (ml-uled). Struct with: .enabled (logical),
%                                .port ('AUTO' | a COM / '/dev/cu.*' name), .mode (0 off |
%                                1 DC-red | 2/3 video RGB), .intensity (4x3 of 0..1 LINEAR
%                                DUTY; rows = LED 0..3, cols = R/G/B). Opened AFTER the Stage
%                                pre-flight, before any acquisition, and darkened + closed
%                                automatically on normal finish OR abort. Omit / enabled=false
%                                leaves the LEDs untouched (local tests, no FPGA present).
%       .ledFactory      @NeitzLedRig  driver constructor (a test seam; leave default at rig)
%
%   Example protocol + call: see Experimenter5000.m
%
%   An "epoch" here = one stimulus presentation = one Clampex sweep = one .abf.

    if nargin < 2 || isempty(opts), opts = struct(); end
    d = struct('preStim', 2, 'postStim', 1, 'itp', 3, 'settle', 1, ...
               'triggerAcq', true, 'preflight', true, 'continueOnError', false, ...
               'seedBase', 2, 'serverTimeout', 10);   % serverTimeout (s): preflight liveness bound
    fn = fieldnames(d);
    for i = 1:numel(fn)
        if ~isfield(opts, fn{i}) || isempty(opts.(fn{i})), opts.(fn{i}) = d.(fn{i}); end
    end

    % ---- validate protocol ----
    if isempty(protocol) || ~isstruct(protocol) || ~isfield(protocol, 'stim')
        error('runExperiment:badProtocol', 'protocol must be a struct array with a .stim field.');
    end

    getf = @(s, f, dv) subsref_default(s, f, dv);   % local: field-or-default

    % ---- pre-flight: is the OpenGL/Stage server up AND answering? (fail fast) ----
    % Bounded by a receive timeout so a server that accepts the TCP connection but
    % never replies (not fully started, wedged, or a stale client still attached)
    % fails in seconds with a clear message -- instead of hanging forever in
    % TcpConnection.read (whose readTimeout defaults to 0 = infinite).
    if opts.preflight
        local_preflightStage(stageHost(), 5678, opts.serverTimeout);
    end

    % ---- optional LED-driver setup (additive; darks + closes on ANY exit) ----
    if isfield(opts, 'leds') && isstruct(opts.leds) && getf(opts.leds, 'enabled', false)
        ledCleanup = local_setupLeds(opts.leds, getf(opts, 'ledFactory', @NeitzLedRig)); %#ok<NASGU>
    end

    % ---- run ----
    nBlocks     = numel(protocol);
    totalEpochs = 0;
    for b = 1:nBlocks, totalEpochs = totalEpochs + getf(protocol(b), 'epochs', 1); end
    fprintf('[runExperiment] %d block(s), %d epoch(s) total.\n', nBlocks, totalEpochs);

    epochCount  = 0;
    seedCounter = 0;   % advances only for seeded epochs, so seeds are seedBase, +1, +2, ...
    for b = 1:nBlocks
        blk  = protocol(b);
        args = getf(blk, 'args', {});
        nEp  = getf(blk, 'epochs', 1);
        lbl  = getf(blk, 'label', sprintf('block %d', b));
        sa   = getf(blk, 'seedArg', 0);   % index of the seed arg in .args (0 = stimulus takes no seed)

        for e = 1:nEp
            epochCount = epochCount + 1;
            epochArgs  = args;
            if sa >= 1
                % Auto-increment the seed so repeated epochs are INDEPENDENT noise
                % realizations; each seed is recorded in that epoch's manifest row.
                epochArgs{sa} = opts.seedBase + seedCounter;
                seedCounter   = seedCounter + 1;
            end
            pause(opts.settle);
            if opts.triggerAcq
                triggerAcquisition(epochCount == 1);   % Alt+Tab to Clampex on the very first epoch
            end
            pause(opts.preStim);
            fprintf('[runExperiment] epoch %d/%d  (%s, %d/%d)\n', epochCount, totalEpochs, lbl, e, nEp);
            try
                blk.stim(epochArgs{:});                % presents stimulus + writes its manifest row
            catch err
                fprintf(2, '[runExperiment] epoch %d FAILED: %s\n', epochCount, err.message);
                if ~opts.continueOnError
                    error('runExperiment:aborted', ...
                          'Aborted at epoch %d to keep the manifest aligned with the .abf files.', epochCount);
                end
            end
            pause(opts.postStim);
            pause(opts.itp);
        end
    end
    fprintf('[runExperiment] Experiment done (%d epochs).\n', epochCount);
end


function v = subsref_default(s, f, dv)
% field-or-default: s.(f) if present and non-empty, else dv
    if isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = dv; end
end


function local_preflightStage(host, port, timeoutS)
% Liveness probe for the Stage server with a RECEIVE TIMEOUT, using netbox's
% public API (the timeout setter is buried private inside StageClient, so we
% drive one bounded getCanvasSize round-trip ourselves). The probe connects,
% asks for the canvas size, and requires a reply within timeoutS seconds. A
% clean disconnect frees the single-client server before the real run connects.
    if isempty(host), host = 'localhost'; end
    conn = [];
    try
        conn = netbox.Connection(host, port);              % TCP connect (10 s built-in)
        conn.setReceiveTimeout(round(max(1, timeoutS) * 1000));
        conn.sendEvent(netbox.NetEvent('getCanvasSize'));
        conn.receiveMessage();                             % returns iff the server answered
    catch probeErr
        local_safeDisconnect(conn);
        if strcmp(probeErr.identifier, 'Connection:ReceiveTimeout')
            error('runExperiment:serverSilent', ...
                ['Stage server at %s:%d accepted the connection but did not answer within %g s.\n' ...
                 'The port is open yet the Stage.Server app is not responding -- usually it is not\n' ...
                 'fully started (no presentation window yet), a previous client is still attached, or\n' ...
                 'it is wedged. On %s: (re)start Stage.Server, wait until it is waiting for a client,\n' ...
                 'then run again.'], host, port, timeoutS, host);
        else
            error('runExperiment:noServer', ...
                'Stage server not reachable at %s:%d (start it first). Underlying error: %s', ...
                host, port, probeErr.message);
        end
    end
    local_safeDisconnect(conn);
    fprintf('[runExperiment] Stage server responded at %s:%d.\n', host, port);
end


function local_safeDisconnect(conn)
% Close a netbox probe connection, ignoring any error (best-effort cleanup).
    if ~isempty(conn)
        try
            conn.disconnect();
        catch
        end
    end
end


function cu = local_setupLeds(L, newRig)
% Open the LED driver, load the 4x3 intensity grid (0..1 linear duty), enable the requested
% mode, and return an onCleanup that darks (mode 0) + closes the port on ANY exit (normal
% finish, an aborted epoch, or Ctrl-C). Values are passed straight to NeitzLedRig.setIntensity
% as LINEAR DUTY -- pre-distort (like lcGammaCorrect) beforehand if you want light linear at
% the eye. The stimulus m-scripts are untouched; the LEDs are configured AROUND the run.
    % the LED driver class lives in the ml-uled/ subfolder -- ensure it's on the path
    % (so a bare addpath(repo), not addpath(genpath(repo)), still finds NeitzLedRig)
    if exist('NeitzLedRig', 'class') ~= 8
        addpath(fullfile(fileparts(mfilename('fullpath')), 'ml-uled'));
    end
    port = subsref_default(L, 'port', char(loadRigConfig('led_port', 'AUTO')));
    mode = subsref_default(L, 'mode', 2);
    I    = subsref_default(L, 'intensity', zeros(4, 3));
    led  = newRig(port);                 % opens the serial port (an error here ABORTS, intended)
    led.setMode(0);                      % dark while the registers load
    cols = {'r', 'g', 'b'};
    for li = 1:size(I, 1)
        for ci = 1:min(3, size(I, 2))
            led.setIntensity(li - 1, cols{ci}, I(li, ci));
        end
    end
    led.setMode(mode);
    fprintf('[runExperiment] LED driver configured on %s (mode %d).\n', string(port), mode);
    cu = onCleanup(@() delete(led));     % NeitzLedRig destructor sets mode 0 + closes the port
end
