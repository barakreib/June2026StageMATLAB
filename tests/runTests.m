function ok = runTests()
% runTests  The stimulusGUI / monitor / runExperiment regression suite.
%
%   cd .../June2026StageMATLAB/tests;  runTests
%
% Runs tiers 1 and 2 (below). Tier 3 needs a sandbox + a fake server and is run by hand --
% see README.md. Returns true if everything passed.
%
% RIG SAFETY (read this before adding a test):
%   NOTHING here may reach the real rig. rig_config.json's stage_host points at the actual
%   Stage server, and a GUI test that presses "Run experiment" WILL open a TCP connection to
%   it -- Stage is single-client, so that can disturb a live session. Two guards:
%     * tier 2 runs with tests/rigsafe/ FIRST on the path, so a stub runExperiment shadows
%       the real one and the GUI can never get near the network;
%     * tier 3 runs against a COPY of the repo whose rig_config says 127.0.0.1.
%   Never point a test at the real stage_host, and never run one with the LED driver or
%   Clampex acquisition enabled.
%
% ALSO: stimulusGUI saves its last session to prefdir -- the user's REAL MATLAB preferences
% directory. Tests must call guiStateGuard() (which moves it aside and restores it), never
% delete it.

    here = fileparts(mfilename('fullpath'));
    repo = fileparts(here);
    addpath(repo, here);

    % ---- tier 1: pure logic + headless GUI, no network, no stub needed ----
    tier1 = {@() stimulusGUI('__selftest__'), @test_cancel, @test_cancel_async, ...
             @test_protocol_complete, @test_play_unblocked, @test_monitor, ...
             @test_timeline_drift, @test_prep_landing, @test_gui_edits, @test_gui_smoke, ...
             @test_generator, @test_phases, @test_values_csv, ...
             @test_projector_state, @test_gamma_regime, @test_ensure_parse, ...
             @test_projector_bracket, @test_stage_agent};

    % ---- tier 2: drives the real Run button, so the stub runner MUST shadow the real one ----
    tier2 = {@test_gui_lock, @test_gui_runfail};

    ok = local_run('tier 1  (logic / monitor / GUI)', tier1, {repo, here});
    ok = local_run('tier 2  (Run button, rig-safe stub runner)', tier2, ...
                   {repo, here, fullfile(here, 'rigsafe')}) && ok;

    fprintf('\n');
    if ok
        fprintf('==== ALL PASS ====\n');
    else
        fprintf(2, '==== FAILURES ABOVE ====\n');
    end
    fprintf(['(tier 3, the Stage pre-flight timeout/cancel test, is run by hand -- ' ...
             'see tests/README.md)\n']);
end


function ok = local_run(title, fns, pathParts)
    fprintf('\n===== %s =====\n', title);
    old = path();
    restoreP = onCleanup(@() path(old)); %#ok<NASGU>
    for i = 1:numel(pathParts)           % addpath PREPENDS, so the last one added wins:
        addpath(pathParts{i});           % pass rigsafe/ last and it shadows the real runner
    end
    if any(contains(pathParts, 'rigsafe'))
        assert(contains(which('runExperiment'), 'rigsafe'), ...
            'RIG SAFETY: the stub runner must shadow the real runExperiment for these tests');
    end
    ok = true;
    for i = 1:numel(fns)
        name = func2str(fns{i});
        try
            fns{i}();
        catch err
            ok = false;
            fprintf(2, '  FAIL  %s: %s\n', name, err.message);
        end
    end
end
