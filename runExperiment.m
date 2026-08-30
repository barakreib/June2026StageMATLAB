function status = runExperiment(protocol, opts)
% runExperiment  Config-driven session orchestrator (replaces Experimenter5000).
%
%   runExperiment(protocol)
%   runExperiment(protocol, opts)
%   status = runExperiment(protocol, opts)
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
%       .onProtocolComplete []   optional function handle called ONCE when the protocol has
%                                finished (or was cancelled after recording epochs), as
%                                fn(nBlocksRecorded, nEpochs, cellName) -> newCellName. The
%                                stimulusGUI shows its "stimulus protocol complete" Keep /
%                                Discard dialog here. Deliberately NOT per block: a protocol
%                                with per-epoch parameters spans several blocks and must still
%                                run straight through.
%       .isCancelled     []      optional function handle returning TRUE to stop the session
%                                early (stimulusGUI's Cancel button sets a flag it reads).
%                                Polled at EPOCH BOUNDARIES and inside the settle / inter-trial
%                                waits only: an epoch whose acquisition has already been
%                                triggered is always presented and logged, so cancelling can
%                                never leave an .abf without its manifest row. Cancelling is a
%                                normal return, not an error -- and the Keep/Discard hook still
%                                fires for a partly-run protocol, so a mistyped run can be
%                                thrown away immediately. Omitted => the waits are plain
%                                pause() calls, exactly as before.
%
%   status : struct with .cancelled (logical), .epochs (epochs actually presented) and
%            .blocks. Requesting it is optional; existing callers are unaffected.
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

    % ---- cancel hook (stimulusGUI's Cancel button); absent => plain pause(), as before ----
    isCancelled = getf(opts, 'isCancelled', []);
    live        = isa(isCancelled, 'function_handle') || stimProgress('isAttached');
    if ~isa(isCancelled, 'function_handle'), isCancelled = @() false; end
    % waitFn(seconds, phaseName) -> true if cancelled during the wait. When nothing is
    % watching (Experimenter5000, a headless script) it is exactly the old single pause().
    if live
        waitFn = @(secs, ph) local_waitOrCancel(secs, isCancelled, ph);
    else
        waitFn = @(secs, ph) local_plainWait(secs, ph);
    end
    cancelled = false;

    sessionCell = getf(opts, 'cellName', '');
    sessionLeds = getf(opts, 'leds', struct('enabled', false));
    nBlocks     = numel(protocol);
    totalEpochs = 0;
    for b = 1:nBlocks, totalEpochs = totalEpochs + getf(protocol(b), 'epochs', 1); end

    % ---- publish the planned session to any live monitor, BEFORE the pre-flight ----
    % This has to come first. The pre-flight is the single most likely thing to go wrong
    % (Stage server not started, wrong host, a stale client still attached) and it can take
    % ten seconds to say so -- if the monitor only woke up afterwards, the operator would
    % watch a dead window with a dead Cancel through exactly the wait they most want to
    % abort. Published here, the monitor is live and cancellable from the first moment.
    stimProgress('begin', local_plan(protocol, opts, getf, nBlocks, totalEpochs, sessionCell));
    % Guarantees the monitor is told the run ended even on an abort / Ctrl-C.
    progCleanup = onCleanup(@() stimProgress('finish', struct('done', true)));

    % ---- pre-flight: is the OpenGL/Stage server up AND answering? (fail fast) ----
    % Bounded by a receive timeout so a server that accepts the TCP connection but
    % never replies (not fully started, wedged, or a stale client still attached)
    % fails in seconds with a clear message -- instead of hanging forever in
    % TcpConnection.read (whose readTimeout defaults to 0 = infinite).
    if opts.preflight && ~local_cancelled(isCancelled)
        if local_preflightStage(stageHost(), 5678, opts.serverTimeout, isCancelled)
            status = local_finish(true, 0, nBlocks, totalEpochs, 'cancelled while connecting');
            return;
        end
    end
    if local_cancelled(isCancelled)
        status = local_finish(true, 0, nBlocks, totalEpochs, 'cancelled before the first epoch');
        return;
    end

    % ---- optional LED-driver setup (additive; darks + closes on ANY exit) ----
    if isfield(opts, 'leds') && isstruct(opts.leds) && getf(opts.leds, 'enabled', false)
        stimProgress('report', struct('phase', 'leds', 'phaseElapsed', 0, 'phaseTotal', 0));
        ledCleanup = local_setupLeds(opts.leds, getf(opts, 'ledFactory', @NeitzLedRig)); %#ok<NASGU>
    end

    % ---- publish the session context for the nested manifest (cell / block / LEDs) ----
    % writeStimManifest reads base-workspace `neitzSessionContext` to file each trial under
    % day -> cell -> block -> epoch. Cleared on ANY exit (normal, abort, Ctrl-C) so a later
    % standalone run cannot inherit a stale cell/block. No effect on the flat .jsonl, the
    % Stage presentation, or Clampex acquisition.
    ctxCleanup = onCleanup(@() evalin('base', 'clear neitzSessionContext'));

    % ---- run ----
    fprintf('[runExperiment] %d block(s), %d epoch(s) total.\n', nBlocks, totalEpochs);

    epochCount     = 0;
    blocksRecorded = 0;   % blocks that got at least one epoch in -- what a discard must undo
    seedCounter    = 0;   % advances only for seeded epochs, so seeds are seedBase, +1, +2, ...
    for b = 1:nBlocks
        blk  = protocol(b);
        args = getf(blk, 'args', {});
        nEp  = getf(blk, 'epochs', 1);
        lbl  = getf(blk, 'label', sprintf('block %d', b));
        sa   = getf(blk, 'seedArg', 0);   % index of the seed arg in .args (0 = stimulus takes no seed)

        % Tell writeStimManifest which cell/block/LEDs these epochs belong to (nested manifest).
        local_setContext(sessionCell, b, lbl, sessionLeds);

        epochsThisBlock = 0;
        for e = 1:nEp
            % Identify this epoch to the monitor before anything else happens, so the
            % readout is already on the right row while the settle pause runs.
            local_reportEpoch(epochCount + 1, totalEpochs, b, nBlocks, e, nEp, lbl, blk);

            % ---- cancel is honoured only HERE, before anything is triggered ----
            % Past this point the epoch owns a Clampex sweep, so it always runs to
            % completion and writes its manifest row; no .abf is left unpaired.
            if local_cancelled(isCancelled),   cancelled = true; break; end
            if waitFn(opts.settle, 'settle'),  cancelled = true; break; end
            if local_cancelled(isCancelled),   cancelled = true; break; end

            epochCount = epochCount + 1;
            epochArgs  = args;
            if sa >= 1
                % Auto-increment the seed so repeated epochs are INDEPENDENT noise
                % realizations; each seed is recorded in that epoch's manifest row.
                epochArgs{sa} = opts.seedBase + seedCounter;
                seedCounter   = seedCounter + 1;
                stimProgress('report', struct('seed', epochArgs{sa}));
            end
            if opts.triggerAcq
                stimProgress('report', struct('phase', 'trigger', 'phaseElapsed', 0, 'phaseTotal', 0));
                triggerAcquisition(epochCount == 1);   % Alt+Tab to Clampex on the very first epoch
            end
            % preStim / postStim sit INSIDE the recorded sweep, so they are never cut short:
            % the wait still ticks the monitor and lets a Cancel click land, but its verdict
            % is ignored here and picked up at the next epoch boundary.
            waitFn(opts.preStim, 'prestim');
            fprintf('[runExperiment] epoch %d/%d  (%s, %d/%d)\n', epochCount, totalEpochs, lbl, e, nEp);
            % blk.stim spends real time BEFORE the first frame reaches the projector --
            % connecting to Stage, precomputing every frame, serialising the presentation to
            % the server -- and none of that yields, so nothing can repaint until it is done.
            % Say so up front rather than leaving the monitor looking stalled.
            stimProgress('report', struct('phase', 'prep', 'phaseElapsed', 0, 'phaseTotal', 0));
            try
                blk.stim(epochArgs{:});                % presents stimulus + writes its manifest row
            catch err                                  % (playAndLogTrial reports 'presenting')
                fprintf(2, '[runExperiment] epoch %d FAILED: %s\n', epochCount, err.message);
                if ~opts.continueOnError
                    error('runExperiment:aborted', ...
                          'Aborted at epoch %d to keep the manifest aligned with the .abf files.', epochCount);
                end
            end
            epochsThisBlock = epochsThisBlock + 1;
            waitFn(opts.postStim, 'poststim');
            if waitFn(opts.itp, 'itp'), cancelled = true; break; end
        end

        if epochsThisBlock > 0, blocksRecorded = blocksRecorded + 1; end
        if cancelled, break; end
    end

    % ---- protocol completion hook (the stimulusGUI "stimulus protocol complete" dialog) ----
    % Fired ONCE, when the whole protocol is done -- not per block. A protocol whose epochs do
    % not all share one parameter set spans several blocks, and stopping to ask Keep/Discard
    % between them interrupts a session that the operator intended to run straight through.
    % Every epoch's own parameters are already in its manifest row either way, so the blocks
    % are only a grouping; the decision belongs to the protocol.
    %
    % Called with (nBlocksRecorded, nEpochs, cellName) and returns a possibly-renamed cell
    % name. A CANCELLED run still fires it when any epoch was recorded, so a run stopped
    % because of a typo can be discarded on the spot. No hook (Experimenter5000, a dry run)
    % => nothing happens.
    opc = getf(opts, 'onProtocolComplete', []);
    if blocksRecorded > 0 && ~isempty(opc) && isa(opc, 'function_handle')
        try
            newCell = opc(blocksRecorded, epochCount, sessionCell);
            if (ischar(newCell) || isstring(newCell)) && strlength(string(newCell)) > 0
                sessionCell = char(newCell); %#ok<NASGU>
            end
        catch hookErr
            fprintf(2, '[runExperiment] onProtocolComplete hook error: %s\n', hookErr.message);
        end
    end
    if cancelled
        fprintf('[runExperiment] CANCELLED by the user after %d epoch(s).\n', epochCount);
    else
        fprintf('[runExperiment] Experiment done (%d epochs).\n', epochCount);
    end
    status = struct('cancelled', cancelled, 'epochs', epochCount, 'blocks', nBlocks);
    stimProgress('finish', struct('cancelled', cancelled, 'epochs', epochCount, ...
                                  'totalEpochs', totalEpochs, 'done', true));
end


function local_reportEpoch(epoch, totalEpochs, b, nBlocks, e, nEp, lbl, blk)
% Tell the monitor which epoch is starting. Wrapped so a monitor that is not attached
% costs one persistent lookup.
    name = '';
    try
        name = func2str(blk.stim);
    catch
    end
    stimProgress('report', struct('epoch', epoch, 'totalEpochs', totalEpochs, ...
        'block', b, 'nBlocks', nBlocks, 'epochInBlock', e, 'epochsInBlock', nEp, ...
        'label', char(string(lbl)), 'stimName', name, 'phase', 'settle', ...
        'phaseElapsed', 0, 'phaseTotal', 0));
end


function plan = local_plan(protocol, opts, getf, nBlocks, totalEpochs, sessionCell)
% One-shot description of the whole planned session, so the monitor can draw the timeline
% before the first epoch runs.
    blocks = struct('label', {}, 'stimName', {}, 'epochs', {});
    for b = 1:nBlocks
        name = '';
        try
            name = func2str(protocol(b).stim);
        catch
        end
        blocks(b) = struct('label', char(string(getf(protocol(b), 'label', sprintf('block %d', b)))), ...
                           'stimName', name, 'epochs', getf(protocol(b), 'epochs', 1));
    end
    plan = struct('cellName', char(string(sessionCell)), ...
                  'nBlocks', nBlocks, 'totalEpochs', totalEpochs, ...
                  'triggerAcq', logical(opts.triggerAcq), 'seedBase', opts.seedBase, ...
                  'timings', struct('settle', opts.settle, 'preStim', opts.preStim, ...
                                    'postStim', opts.postStim, 'itp', opts.itp), ...
                  'leds', getf(opts, 'leds', struct('enabled', false)));
    plan.blocks = blocks;
end


function tf = local_cancelled(isCancelled)
% Poll the caller's cancel hook. A hook that errors is treated as "keep going" -- a broken
% callback must never take a session down mid-run.
    try
        v  = isCancelled();
        tf = ~isempty(v) && all(logical(v(:)));
    catch
        tf = false;
    end
end


function stopped = local_plainWait(secs, ~)
% Nothing watching: the original single pause(), with identical timing.
    pause(secs);
    stopped = false;
end


function stopped = local_waitOrCancel(secs, isCancelled, phase)
% pause(secs) split into short slices against a DEADLINE, so a Cancel click (a GUI callback
% that runs during pause) is seen within ~50 ms instead of at the end of the wait. Deadline-
% based rather than slice-summing, so the total wait keeps plain-pause accuracy -- these are
% rig timings. Returns true if the run was cancelled during the wait.
    t0 = tic;
    while true
        remaining = secs - toc(t0);
        if remaining <= 0, break; end
        stimProgress('report', struct('phase', phase, ...
            'phaseElapsed', secs - remaining, 'phaseTotal', secs));
        pause(min(0.05, remaining));
        if local_cancelled(isCancelled), stopped = true; return; end
    end
    drawnow;   % a zero-length wait never paused: still let a queued Cancel click land
    stimProgress('report', struct('phase', phase, 'phaseElapsed', secs, 'phaseTotal', secs));
    stopped = local_cancelled(isCancelled);
end


function v = subsref_default(s, f, dv)
% field-or-default: s.(f) if present and non-empty, else dv
    if isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = dv; end
end


function local_setContext(cellName, blockIndex, label, leds)
% Publish the current cell/block/LED state to the base workspace so writeStimManifest can
% nest each trial under day -> cell -> block -> epoch. Constant across a block's epochs.
    assignin('base', 'neitzSessionContext', ...
        struct('cell_name',   char(string(cellName)), ...
               'block_index', blockIndex, ...
               'block_label', char(string(label)), ...
               'leds',        leds));
end


function cancelled = local_preflightStage(host, port, timeoutS, isCancelled)
% Liveness probe for the Stage server, using netbox's public API (the timeout setter is
% buried private inside StageClient, so we drive one bounded getCanvasSize round-trip
% ourselves). Connect, ask for the canvas size, require a reply within timeoutS seconds. A
% clean disconnect frees the single-client server before the real run connects.
%
% The wait is SLICED rather than taken in one go. netbox's TcpConnection.read is a bare
% `while in.available() == 0` busy-spin: it never yields, so one 10 s receive pegs a core
% AND freezes every figure in MATLAB -- which is what made a non-answering Stage server look
% like a hung GUI with a dead Cancel button. Its read timeout is only a field, and a timed
% out read leaves the socket untouched, so the SAME connection can simply be read again.
% One request is sent; we poll its reply in short slices with a pause() between, which both
% yields the event queue (Cancel becomes clickable) and stops the spin burning CPU.
%
% Returns TRUE if the operator cancelled while waiting -- that is a clean stop, not an error.
    if isempty(host), host = 'localhost' ; end
    cancelled = false;
    slice     = 0.15;                                   % seconds per read attempt
    budget    = max(1, timeoutS);
    conn      = [];
    try
        conn = netbox.Connection(host, port);              % TCP connect (10 s built-in)
        conn.setReceiveTimeout(round(slice * 1000));
        conn.sendEvent(netbox.NetEvent('getCanvasSize'));  % asked ONCE; the reply is polled
        t0 = tic;
        while true
            try
                conn.receiveMessage();                     % returns iff the server answered
                break;
            catch readErr
                if ~strcmp(readErr.identifier, 'Connection:ReceiveTimeout'), rethrow(readErr); end
                el = toc(t0);
                if local_cancelled(isCancelled)
                    local_safeDisconnect(conn);
                    fprintf('[runExperiment] cancelled while waiting for the Stage server at %s:%d.\n', host, port);
                    cancelled = true;
                    return;
                end
                if el >= budget
                    error('Connection:ReceiveTimeout', 'Receive timeout');
                end
                stimProgress('report', struct('phase', 'connecting', ...
                    'phaseElapsed', el, 'phaseTotal', budget));
                pause(0.05);      % yield: repaint, run callbacks, stop pinning the CPU
            end
        end
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


function status = local_finish(cancelled, epochs, nBlocks, totalEpochs, why)
% Single exit for a run that stops before the epoch loop (cancelled during the pre-flight).
% Cancelling is a normal return, not an error -- the GUI must come back clean.
    fprintf('[runExperiment] %s.\n', why);
    status = struct('cancelled', cancelled, 'epochs', epochs, 'blocks', nBlocks);
    stimProgress('finish', struct('cancelled', cancelled, 'epochs', epochs, ...
                                  'totalEpochs', totalEpochs, 'done', true));
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
