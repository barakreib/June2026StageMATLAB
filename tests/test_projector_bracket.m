function test_projector_bracket()
% runExperiment's projector gamma bracket, end to end with a fake state module.
% No hardware, no Python, no config writes: opts.projectors chooses the roles and
% opts.projectorStateFn (the .ledFactory-style seam) supplies the outcomes.
    cleanup = onCleanup(@() lcProjectorState('clear')); %#ok<NASGU>

    presented = {};
    stim = @(varargin) local_present(varargin);
    function local_present(a)
        presented{end+1} = a; %#ok<AGROW>
    end
    base  = struct('preStim', 0, 'postStim', 0, 'itp', 0.05, 'settle', 0.05, ...
                   'triggerAcq', false, 'preflight', false);
    proto = struct('stim', {stim}, 'args', {{}}, 'epochs', {2}, 'label', {'A'}, 'seedArg', {0});
    both  = struct('stim',    struct('required_for_run', true), ...
                   'monitor', struct('required_for_run', false));

    calls = {};
    ensureByRole  = struct();   % role -> struct local_fake returns for 'ensure'
    refreshResult = [];         % what local_fake returns for 'refresh'
    function out = local_fake(action, varargin)
        calls{end+1} = [{action}, varargin]; %#ok<AGROW>
        out = [];
        switch action
            case 'ensure',  out = ensureByRole.(varargin{1});
            case 'refresh', out = refreshResult;
        end
    end
    function o = mkopts(projectors)
        o = base;
        o.projectors = projectors;
        o.projectorStateFn = @local_fake;
    end

    okState = struct('known', true, 'reachable', true, 'linear', true, 'gamma', 0, ...
                     'mode', 'video', 'changed', false, 'checkedAt', NaT, 'source', 'ensure');
    downState = okState; downState.reachable = false; downState.linear = false;
    downState.gamma = NaN; downState.mode = '';
    lutState = okState; lutState.linear = false; lutState.gamma = 128;
    patState = okState; patState.mode = 'pattern';

    % ---- 1. required stim not linear: run refused before any epoch ----
    ensureByRole = struct('stim', lutState, 'monitor', okState);
    calls = {}; presented = {};
    err = [];
    try
        runExperiment(proto, mkopts(both));
    catch err
    end
    assert(~isempty(err) && strcmp(err.identifier, 'runExperiment:projectorNotLinear'), ...
        'a stim projector that will not verify linear refuses the run');
    assert(isempty(presented), 'refusal happens before the first epoch');
    assert(strcmp(calls{1}{1}, 'clear'), ...
        'the bracket clears stale state first (the Ctrl-C staleness fix)');

    % ---- 2. required stim unreachable ----
    ensureByRole = struct('stim', downState, 'monitor', okState);
    presented = {};
    err = [];
    try
        runExperiment(proto, mkopts(both));
    catch err
    end
    assert(~isempty(err) && strcmp(err.identifier, 'runExperiment:projectorUnreachable'), ...
        'an unreachable stim projector refuses the run');
    assert(isempty(presented), 'nothing was presented');

    % ---- 3. required stim in pattern mode ----
    ensureByRole = struct('stim', patState, 'monitor', okState);
    presented = {};
    err = [];
    try
        runExperiment(proto, mkopts(both));
    catch err
    end
    assert(~isempty(err) && strcmp(err.identifier, 'runExperiment:projectorPatternMode'), ...
        'pattern mode refuses a video-mode run even though ensure "succeeded"');

    % ---- 4. non-required monitor failure only warns; the run completes ----
    ensureByRole = struct('stim', okState, 'monitor', downState);
    refreshResult = okState;
    presented = {}; lastwarn('');
    st = runExperiment(proto, mkopts(both));
    assert(st.epochs == 2 && numel(presented) == 2, 'the run completed');
    [~, wid] = lastwarn;
    assert(strcmp(wid, 'runExperiment:monitorProjector'), ...
        'the monitor failure surfaced as a warning, not an error');

    % ---- 5. state reverts mid-run: warning + data_quality_warnings in the manifest ----
    sandbox = tempname;
    mkdir(sandbox);
    oldPwd = pwd;
    cdBack = onCleanup(@() cd(oldPwd)); %#ok<NASGU>
    cd(sandbox);
    dateStr = char(datetime('now', 'Format', 'yyyy_MM_dd'));
    blk = struct('label', 'b1'); blk.epochs = {};
    cellNode = struct('cell_name', 'c1'); cellNode.blocks = {blk};
    tree = struct('format', 'neitz-stim-manifest/2', 'date', strrep(dateStr, '_', '-'));
    tree.cells = {cellNode};
    fid = fopen([dateStr '_stim_manifest.json'], 'w');
    fwrite(fid, jsonencode(tree));
    fclose(fid);

    ensureByRole = struct('stim', okState);
    refreshResult = lutState;                   % the register reverted during the run
    presented = {}; lastwarn('');
    st = runExperiment(proto, mkopts(struct('stim', struct('required_for_run', true))));
    assert(st.epochs == 2, 'the revert is detected AFTER the run, not by killing it');
    [~, wid] = lastwarn;
    assert(strcmp(wid, 'runExperiment:projectorRevertedMidRun'), 'the loud warning fired');
    t2 = jsondecode(fileread([dateStr '_stim_manifest.json']));
    assert(isfield(t2, 'data_quality_warnings'), 'the manifest carries the flag');
    w = t2.data_quality_warnings;
    if iscell(w), w = w{1}; else, w = w(1); end
    assert(strcmp(w.type, 'projector_gamma_reverted') && strcmp(w.cell_name, 'c1'), ...
        'the flag names the problem and the cell');
    cd(oldPwd);

    % ---- 6. inert paths: empty config, and the master switch ----
    calls = {}; presented = {};
    o = base; o.projectors = struct(); o.projectorStateFn = @local_fake;
    st = runExperiment(proto, o);
    assert(st.epochs == 2 && isempty(calls), 'no configured roles -> bracket fully inert');
    calls = {};
    o = mkopts(both); o.projectorCheck = false;
    st = runExperiment(proto, o);
    assert(st.epochs == 2 && isempty(calls), 'projectorCheck=false disables the bracket');

    fprintf('[projector bracket test] all PASS\n');
end
