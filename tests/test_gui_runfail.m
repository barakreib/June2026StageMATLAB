function test_gui_runfail()
% REGRESSION: a run that FAILS (e.g. the Stage pre-flight timing out) must leave the GUI
% fully usable. Reported symptom: after "Stage server did not respond within 10 seconds"
% the window stayed locked, Cancel did nothing, and the GUI had to be closed and restarted.
    global RIGSAFE_CALLS RIGSAFE_THROW %#ok<GVMIS>
    RIGSAFE_CALLS = {}; RIGSAFE_THROW = true;
    assert(contains(which('runExperiment'), 'rigsafe'), 'rig-safe stub must shadow the real runner');

    stateGuard = guiStateGuard(); %#ok<NASGU>  % keep the user's saved session
    stimulusGUI();
    fig = findall(0, 'Type', 'figure', 'Name', 'Neitz Stimulus GUI');
    c = onCleanup(@() local_shutdown()); %#ok<NASGU>

    lst = findall(fig, 'Type', 'uilistbox');
    lst.Value = 'Greyscale full-field flicker';
    lst.ValueChangedFcn(lst, []);
    add = findall(fig, 'Type', 'uibutton', 'Text', 'Add block  v');
    add.ButtonPushedFcn(add, []);

    runBtn = findall(fig, 'Type', 'uibutton', 'Text', 'Run experiment');
    ctrls  = findall(fig, '-property', 'Enable', '-not', 'Type', 'uilabel');
    before = arrayfun(@(x) string(x.Enable), ctrls);

    runBtn.ButtonPushedFcn(runBtn, []);          % the run throws
    delete(findall(0, 'Type', 'figure', '-depth', 0, '-regexp', 'Name', 'runExperiment'));

    after = arrayfun(@(x) string(x.Enable), ctrls);
    stuck = ctrls(before ~= after);
    assert(isempty(stuck), sprintf(['%d control(s) left in the wrong state after a FAILED run ' ...
        '-- the GUI is stuck and has to be restarted (first: %s "%s")'], numel(stuck), ...
        local_kind(stuck), local_txt(stuck)));
    assert(strcmp(runBtn.Enable, 'on'), 'Run is clickable again after a failed run');
    % Hooks deliberately OUTLIVE the run: the monitor keeps previewing the protocol after
    % it finishes. They are dropped when the window closes, not when the run ends.
    if isempty(findall(0, 'Type', 'figure', 'Name', 'Session monitor'))
        assert(~stimProgress('isAttached'), 'no monitor window -> no hooks');
    else
        assert(stimProgress('isAttached'), 'the monitor stays attached while its window is open');
    end
    fprintf('[run-fail] GUI fully restored after a failed run -- PASS\n');
end

function s = local_kind(c)
    if isempty(c), s = ''; else, s = class(c(1)); end
end
function s = local_txt(c)
    s = '';
    try, s = char(string(c(1).Text)); catch, end
end
function local_shutdown()
    stimProgress('detach');
    delete(findall(0, 'Type', 'figure'));
end
