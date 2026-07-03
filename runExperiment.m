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
%
%   Example protocol + call: see exampleProtocol.m
%
%   An "epoch" here = one stimulus presentation = one Clampex sweep = one .abf.

    if nargin < 2 || isempty(opts), opts = struct(); end
    d = struct('preStim', 2, 'postStim', 1, 'itp', 3, 'settle', 1, ...
               'triggerAcq', true, 'preflight', true, 'continueOnError', false);
    fn = fieldnames(d);
    for i = 1:numel(fn)
        if ~isfield(opts, fn{i}) || isempty(opts.(fn{i})), opts.(fn{i}) = d.(fn{i}); end
    end

    % ---- validate protocol ----
    if isempty(protocol) || ~isstruct(protocol) || ~isfield(protocol, 'stim')
        error('runExperiment:badProtocol', 'protocol must be a struct array with a .stim field.');
    end

    getf = @(s, f, dv) subsref_default(s, f, dv);   % local: field-or-default

    % ---- pre-flight: is the OpenGL/Stage server up? (fail fast, before any acquisition) ----
    if opts.preflight
        try
            c  = stage.core.network.StageClient();
            c.connect();
            cs = c.getCanvasSize();
            c.disconnect();
            fprintf('[runExperiment] Stage server OK. Canvas: %d x %d\n', cs(1), cs(2));
        catch err
            error('runExperiment:noServer', ...
                  'Stage server not reachable (start it first). Underlying error: %s', err.message);
        end
    end

    % ---- run ----
    nBlocks     = numel(protocol);
    totalEpochs = 0;
    for b = 1:nBlocks, totalEpochs = totalEpochs + getf(protocol(b), 'epochs', 1); end
    fprintf('[runExperiment] %d block(s), %d epoch(s) total.\n', nBlocks, totalEpochs);

    epochCount = 0;
    for b = 1:nBlocks
        blk  = protocol(b);
        args = getf(blk, 'args', {});
        nEp  = getf(blk, 'epochs', 1);
        lbl  = getf(blk, 'label', sprintf('block %d', b));

        for e = 1:nEp
            epochCount = epochCount + 1;
            pause(opts.settle);
            if opts.triggerAcq
                triggerAcquisition(epochCount == 1);   % Alt+Tab to Clampex on the very first epoch
            end
            pause(opts.preStim);
            fprintf('[runExperiment] epoch %d/%d  (%s, %d/%d)\n', epochCount, totalEpochs, lbl, e, nEp);
            try
                blk.stim(args{:});                     % presents stimulus + writes its manifest row
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
