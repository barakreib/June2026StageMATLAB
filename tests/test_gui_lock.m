function test_gui_lock()
% The GUI must be dead to every control except Cancel while a run is in flight, and fully
% restored afterwards.
%
% RIG SAFETY: this drives the real Run button, but with a STUB runExperiment shadowing the
% real one on the path (scratchpad/rigsafe). Nothing here can reach the Stage server, the
% LED driver or Clampex -- the GUI never gets near the network.
    global RIGSAFE_CALLS RIGSAFE_SAMPLER %#ok<GVMIS>
    RIGSAFE_CALLS = {};
    assert(contains(which('runExperiment'), 'rigsafe'), ...
        'the rig-safe stub must shadow the real runExperiment before this test runs');

    stateGuard = guiStateGuard(); %#ok<NASGU>  % keep the user's saved session
    % Run now writes the generated stimulus script into <pwd>/generated_stimuli -- do that
    % in a scratch dir, not in tests/.
    td = tempname; mkdir(td); oldPwd = pwd; cd(td);
    pwdGuard = onCleanup(@() local_restorePwd(oldPwd, td)); %#ok<NASGU>
    stimulusGUI();
    fig = findall(0, 'Type', 'figure', 'Name', 'Neitz Stimulus GUI');
    c = onCleanup(@() local_shutdown()); %#ok<NASGU>

    lst = findall(fig, 'Type', 'uilistbox');
    lst.Value = 'Greyscale full-field flicker';
    lst.ValueChangedFcn(lst, []);
    add = findall(fig, 'Type', 'uibutton', 'Text', 'Add block  v');
    add.ButtonPushedFcn(add, []);

    % the Session monitor is EMBEDDED (one window): its panel exists, and there is
    % exactly ONE Cancel button anywhere
    assert(~isempty(findall(fig, 'Type', 'uipanel', 'Title', 'Session monitor')), ...
        'the Session monitor panel is embedded in the main window');
    cancelBtn = findall(fig, 'Type', 'uibutton', 'Text', 'Cancel');
    assert(isscalar(cancelBtn), 'exactly one Cancel button in the whole UI');
    runBtn    = findall(fig, 'Type', 'uibutton', 'Text', 'Run experiment');
    ctrls     = findall(fig, '-property', 'Enable', '-not', 'Type', 'uilabel');
    before    = arrayfun(@(x) string(x.Enable), ctrls);
    assert(numel(ctrls) > 10, sprintf('found the controls to lock (%d)', numel(ctrls)));

    snap = [];
    RIGSAFE_SAMPLER = @() grab();
    runBtn.ButtonPushedFcn(runBtn, []);
    RIGSAFE_SAMPLER = [];

    % ---- what the GUI handed the runner ----
    assert(isscalar(RIGSAFE_CALLS), 'Run called the runner exactly once');
    o = RIGSAFE_CALLS{1}.opts;
    assert(isa(o.isCancelled, 'function_handle'), 'the cancel hook was passed through');
    p = RIGSAFE_CALLS{1}.protocol;
    assert(isfield(p, 'stimSeconds') && abs(p(1).stimSeconds - 10) < 1e-9, ...
        'the planned presentation seconds (600/60) go with the protocol, for the timeline');

    % ---- locked state, sampled from inside the run ----
    assert(~isempty(snap), 'the sampler ran while the run held the thread');
    live = snap.ctrls(strcmp(snap.enable, 'on'));
    assert(isscalar(live) && isequal(live, cancelBtn), ...
        sprintf('exactly ONE control was live mid-run, and it was Cancel (got %d)', numel(live)));
    assert(strcmp(snap.monAttached, 'yes'), 'the monitor was attached to stimProgress for the run');

    % ---- and everything restored afterwards ----
    after = arrayfun(@(x) string(x.Enable), ctrls);
    assert(isequal(before, after), 'every control is restored to its previous state');
    assert(strcmp(runBtn.Enable, 'on') && strcmp(cancelBtn.Enable, 'off'), 'Run live, Cancel dead again');
    % Hooks deliberately OUTLIVE the run: the embedded monitor keeps previewing the
    % protocol after it finishes. They are dropped when the window closes.
    assert(stimProgress('isAttached'), 'the embedded monitor stays attached after the run');

    fprintf('[gui lock] %d controls locked to Cancel only, all restored -- PASS\n', numel(ctrls));

    function grab()
        snap = struct('ctrls', ctrls, ...
                      'enable', {arrayfun(@(x) string(x.Enable), ctrls)}, ...
                      'monAttached', local_yn(stimProgress('isAttached')));
    end
end

function s = local_yn(tf)
    if tf, s = 'yes'; else, s = 'no'; end
end

function local_shutdown()
    stimProgress('detach');
    delete(findall(0, 'Type', 'figure'));
end

function local_restorePwd(oldPwd, td)
    cd(oldPwd);
    ws = warning('off', 'MATLAB:rmpath:DirNotFound');
    try
        rmpath(fullfile(td, 'generated_stimuli'));
    catch
    end
    warning(ws);
    try
        rmdir(td, 's');
    catch
    end
end
