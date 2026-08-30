function test_phases()
% test_phases  The phase machinery around the generated scripts:
%   1. playAndLogTrial with a phase plan reports prestim -> presenting -> poststim to the
%      monitor and applies each phase's LED grid, in order, as its frames start.
%   2. runExperiment with a rendered phase plan skips its own pre/post waits, paints the
%      inter-stim backdrop between epochs (but not after the last), paints the end-of-run
%      backdrop once, and tears the LED rig down dark+closed when no final grid is set.
%   3. A final LED grid is applied and the rig HANDED OFF (left open, published as base
%      `rig`) instead of darkened+closed.
%
% RIG-SAFE: FakeStageClient injected via stageClientShared('set'), FakeLedRig through
% opts.ledFactory, preflight off, Clampex trigger off; tests/stageHost.m shadows the real
% host with 127.0.0.1 as a last-ditch net.

    here = fileparts(mfilename('fullpath'));
    repo = fileparts(here);
    addpath(repo, here);

    td = tempname;
    mkdir(td);
    cleanup = onCleanup(@() local_cleanup(td)); %#ok<NASGU>
    stimProgress('detach');
    ledSession('clear');

    mainGrid = [0 0 0.3; 0 0 0; 0 0 0; 0.2 0 0];
    preGrid  = [0.1 0 0; 0 0 0; 0 0 0; 0 0 0];

    % ---- 1. playAndLogTrial: phase reports + LED grid order ----
    reports = {};
    stimProgress('attach', @grab, @() []);
    fake = FakeStageClient();
    fake.durationS = 0.5;
    fake.flipDurations = repmat(1/60, 1, 29);
    rig = FakeLedRig('FAKE');
    ledSession('set', rig, mainGrid);
    plan = struct('name', {'prestim', 'presenting', 'poststim'}, ...
                  'durS', {0.15, 0.2, 0.15}, ...
                  'leds', {preGrid, mainGrid, zeros(4, 3)});
    rec = struct('stimulus', 'phase-test', 'stim_type', 'sq_wave', ...
                 'refresh_rate_hz', 60, 'stim_frames', 30);
    playAndLogTrial(fake, [], td, rec, 60, 30, plan);
    stimProgress('detach');

    seen = cellfun(@(r) r.phase, reports, 'UniformOutput', false);
    iPre  = find(strcmp(seen, 'prestim'), 1);
    iStim = find(strcmp(seen, 'presenting'), 1);
    iPost = find(strcmp(seen, 'poststim'), 1);
    assert(~isempty(iPre) && ~isempty(iStim) && ~isempty(iPost) && iPre < iStim && iStim < iPost, ...
        'phase reports arrive in order prestim -> presenting -> poststim');
    kPre = reports{iPre};
    assert(abs(kPre.phaseTotal - 0.15) < 1e-9, 'prestim reports its own phase length');
    assert(numel(rig.J.sets) == 36, 'three phase grids -> 36 LED writes (got %d)', numel(rig.J.sets));
    assert(abs(rig.J.sets(1).v - preGrid(1, 1)) < 1e-12 && ...
           abs(rig.J.sets(13).v - mainGrid(1, 1)) < 1e-12 && ...
           abs(rig.J.sets(25).v - 0) < 1e-12, 'LED grids applied in phase order');
    ledSession('clear');
    fprintf('  ok  playAndLogTrial: phase reports + per-phase LED grids in order\n');

    % ---- 2. runExperiment: iti between epochs, final once, dark+close teardown ----
    made = {};
    fake = FakeStageClient();
    fake.durationS = 0.01;
    stageClientShared('set', fake);
    protocol = struct('stim', {@(varargin) [], @(varargin) []}, 'args', {{}, {}}, ...
                      'epochs', {1, 1}, 'label', {'a', 'b'}, 'seedArg', {0, 0});
    opts = struct('preflight', false, 'triggerAcq', false, ...
                  'settle', 0, 'preStim', 5, 'postStim', 5, 'itp', 0.02);
    opts.leds = struct('enabled', true, 'port', 'FAKE', 'mode', 2, 'intensity', mainGrid);
    opts.ledFactory = @mkRig;
    opts.phases = struct('rendered', true, ...
        'pre',   struct('seconds', 5, 'rgb', [0 0 0], 'ledGrid', preGrid), ...
        'post',  struct('seconds', 5, 'rgb', [0 0 0], 'ledGrid', zeros(4, 3)), ...
        'iti',   struct('seconds', 0.02, 'rgb', [0.1 0.1 0.1], 'ledGrid', zeros(4, 3)), ...
        'final', struct('rgb', [0.2 0 0], 'ledGrid', []));
    t0 = tic;
    st = runExperiment(protocol, opts);
    el = toc(t0);
    assert(st.epochs == 2 && ~st.cancelled, 'both epochs ran');
    assert(el < 4, 'pre/post waits are skipped in a rendered run (took %.1f s with preStim=5)', el);
    assert(fake.playCalled == 2, 'one inter-stim hold + one end-of-run hold (got %d plays)', fake.playCalled);
    pIti = fake.players{1}.presentation;
    pFin = fake.players{2}.presentation;
    assert(abs(pIti.duration - 2/60) < 1e-12 && ...
           max(abs(pIti.stimuli{1}.color - lcGammaCorrect([0.1 0.1 0.1]))) < 1e-12, ...
        'inter-stim hold: 2 frames of the iti screen value');
    assert(max(abs(pFin.stimuli{1}.color - lcGammaCorrect([0.2 0 0]))) < 1e-12, ...
        'end-of-run hold: the final screen value');
    % the sync-bar column is excluded from every held full-screen value: a dark rect
    % covers the rightmost W/8, and the TOP segment sits on it SOLID blue -- the visible
    % "projector alive, frame held" marker (so the bar is present even on idle screens)
    W = fake.canvas(1);  H = fake.canvas(2);
    for pp = {pIti, pFin}
        s = pp{1}.stimuli;
        assert(numel(s) == 3, 'held screen = background + dark bar column + lit top segment');
        b = s{2};  t = s{3};
        assert(isequal(b.color, [0 0 0]) && ...
               max(abs(b.size - [W/8, H])) < 1e-9 && ...
               max(abs(b.position - [W - W/16, H/2])) < 1e-9, ...
            'held screens keep the sync-bar column dark, never painted over');
        assert(max(abs(t.color - lcGammaCorrect([0 0 1]))) < 1e-12 && ...
               max(abs(t.size - [W/8, H/3])) < 1e-9 && ...
               max(abs(t.position - [W - W/16, 5*H/6])) < 1e-9, ...
            'held screens light the top bar segment solid blue');
    end
    assert(isscalar(made), 'exactly one LED rig opened');
    J = made{1};
    assert(J.closed && J.modes(end) == 0, 'no final grid -> rig darkened + closed');
    % setup loads the main grid (12) + the iti grid after epoch 1 (12); final grid is []
    assert(numel(J.sets) == 24, 'main load + one iti grid = 24 LED writes (got %d)', numel(J.sets));
    assert(isempty(ledSession('rig')), 'ledSession cleared after the run');
    fprintf('  ok  runExperiment: skipped waits, iti/final backdrops, dark+close teardown\n');

    % ---- 3. final LED grid -> applied + handed off (rig left open as base `rig`) ----
    made = {};
    finalGrid = [0 0.5 0; 0 0 0; 0 0 0; 0 0 0];
    fake = FakeStageClient();
    fake.durationS = 0.01;
    stageClientShared('set', fake);
    opts.phases.final = struct('rgb', [0 0 0], 'ledGrid', finalGrid);
    st = runExperiment(protocol, opts);
    assert(st.epochs == 2, 'handoff run completed');
    J = made{1};
    assert(~J.closed, 'final grid -> rig left OPEN (handed off)');
    assert(abs(J.sets(end - 10).v - finalGrid(1, 2)) < 1e-12, ...
        'final grid was written (row 1 green = 0.5)');
    assert(J.modes(end) == 2, 'handed-off rig keeps its video mode (never darkened)');
    baseRig = evalin('base', 'rig');
    assert(isa(baseRig, 'FakeLedRig') && isvalid(baseRig), ...
        'handed-off rig published as base-workspace `rig`');
    evalin('base', 'clear rig');
    delete(baseRig);
    assert(J.closed && J.modes(end) == 0, 'clearing the handed-off rig darkens + closes it');
    fprintf('  ok  runExperiment: final LED grid applied + rig handed off as base `rig`\n');

    % ---- old callers: no phases -> no holds, LED session untouched ----
    fake = FakeStageClient();
    stageClientShared('set', fake);
    opts2 = struct('preflight', false, 'triggerAcq', false, ...
                   'settle', 0, 'preStim', 0.01, 'postStim', 0.01, 'itp', 0.01);
    st = runExperiment(protocol, opts2);
    assert(st.epochs == 2 && fake.playCalled == 0, ...
        'no phase plan -> no backdrops, exactly the old behavior');
    fprintf('  ok  runExperiment: without a phase plan nothing new happens\n');

    function grab(~, msg)
        if isstruct(msg) && isfield(msg, 'phase')
            reports{end + 1} = msg;
        end
    end

    function r = mkRig(port)
        r = FakeLedRig(port);
        made{end + 1} = r.J;     % keep the journal -- it outlives the rig's teardown
    end
end


function local_cleanup(td)
    stimProgress('detach');
    stageClientShared('set', []);
    ledSession('clear');
    try
        evalin('base', 'clear rig');
    catch
    end
    try
        rmdir(td, 's');
    catch
    end
end
