function test_preflight_cancel()
% REGRESSION for: "stage.server did not respond within 10 seconds and the stimulusGUI did
% not handle it well. The cancel was not available... I had to close the stimulusGUI and
% restart."   (Since the single-window rework there is ONE Cancel button -- the main
% window's -- and the Session monitor is an embedded panel in the same window.)
%
% Sandboxed: this copy's rig_config points stage_host at 127.0.0.1, where a socket accepts
% the connection and never answers -- the exact failure, with the rig nowhere near it.
    fig = local_openWithBlock();
    c1 = onCleanup(@() local_shutdown()); %#ok<NASGU>
    runBtn  = findall(fig, 'Type', 'uibutton', 'Text', 'Run experiment');
    mainCan = findall(fig, 'Type', 'uibutton', 'Text', 'Cancel');
    assert(isscalar(mainCan), 'exactly ONE Cancel button in the whole UI');
    ctrls   = findall(fig, '-property', 'Enable', '-not', 'Type', 'uilabel');
    before  = arrayfun(@(x) string(x.Enable), ctrls);

    % ---- 1. let the pre-flight time out: the failure must be visible + the GUI clean ----
    fprintf('>>> run 1 (let it time out)\n');
    tic; runBtn.ButtonPushedFcn(runBtn, []); elFail = toc;
    assert(local_hasLabel(fig, 'RUN FAILED'), 'the monitor panel shows the failure, not a stale "Starting run..."');
    assert(local_hasLabel(fig, 'did not answer'), 'and the REASON, so the operator need not hunt for a dialog');
    after = arrayfun(@(x) string(x.Enable), ctrls);
    assert(isequal(before, after), 'every control is restored after the failed run');
    assert(strcmp(runBtn.Enable, 'on') && strcmp(mainCan.Enable, 'off'), 'Run live, Cancel dead');
    assert(stimProgress('isAttached'), 'the embedded monitor stays attached after the failure');
    fprintf('   run 1: timed out after %.1f s, GUI clean, failure shown in the monitor panel\n', elFail);

    % ---- 2. mid-pre-flight: Cancel live, the monitor panel says CONNECTING ----
    snap = [];
    t = timer('StartDelay', 2.5, 'TimerFcn', @(~,~) sample());
    ct = onCleanup(@() delete(t)); %#ok<NASGU>
    start(t);
    fprintf('>>> run 2 (sample only, nobody presses Cancel)\n');
    tic; runBtn.ButtonPushedFcn(runBtn, []); elFail2 = toc;
    assert(~isempty(snap), 'the sampler ran during the pre-flight -- the GUI was not frozen');
    assert(snap.hasConnecting, 'the monitor panel says CONNECTING, not "Waiting for a run..."');
    assert(strcmp(snap.mainCancel, 'on'), 'Cancel is live during the pre-flight');
    fprintf('   run 2: CONNECTING + Cancel live at 2.5 s (total %.1f s)\n', elFail2);

    % ---- 3. Cancel aborts the pre-flight instead of waiting out the 10 s ----
    t2 = timer('StartDelay', 2.5, 'TimerFcn', @(~,~) pressMainCancel());
    ct2 = onCleanup(@() delete(t2)); %#ok<NASGU>
    start(t2);
    fprintf('>>> run 3 (Cancel at 2.5 s)\n');
    tic; runBtn.ButtonPushedFcn(runBtn, []); elCancel = toc;
    assert(elCancel < elFail2 - 3, sprintf(['Cancel aborted the pre-flight (%.1f s) instead of ' ...
        'waiting out the full timeout (%.1f s)'], elCancel, elFail2));
    assert(local_hasLabel(fig, 'Cancelled after 0 of'), 'the monitor panel reports a clean cancel');
    assert(~local_hasLabel(fig, 'RUN FAILED'), 'cancelling out of the pre-flight is not an error');
    assert(strcmp(runBtn.Enable, 'on'), 'the GUI is usable again after cancelling');
    assert(isequal(arrayfun(@(x) string(x.Enable), ctrls), before), 'and the GUI is fully restored');
    fprintf('   run 3: Cancel aborted in %.1f s (vs %.1f s timing out)\n', elCancel, elFail2);
    fprintf('[preflight cancel] all PASS\n');

    function sample()
        snap = struct('mainCancel', char(mainCan.Enable), ...
                      'hasConnecting', local_hasLabel(fig, 'CONNECTING'));
    end
    function pressMainCancel()
        mainCan.ButtonPushedFcn(mainCan, []);
    end
end

function fig = local_openWithBlock()
    stateGuard = guiStateGuard(); %#ok<NASGU>  % keep the user's saved session
    stimulusGUI();
    fig = findall(0, 'Type', 'figure', 'Name', 'Neitz Stimulus GUI');
    lst = findall(fig, 'Type', 'uilistbox');
    lst.Value = 'Greyscale full-field flicker';
    lst.ValueChangedFcn(lst, []);
    add = findall(fig, 'Type', 'uibutton', 'Text', 'Add block  v');
    add.ButtonPushedFcn(add, []);
    set(findall(fig, 'Type', 'uicheckbox', 'Text', 'LED driver'), 'Value', false);
    set(findall(fig, 'Type', 'uicheckbox', 'Text', 'Clampex acquisition'), 'Value', false);
end

function tf = local_hasLabel(fig, txt)
% A uilabel's Text may be a cell of lines (multi-line messages), so compare as a string array.
    L = findall(fig, 'Type', 'uilabel');
    tf = false;
    for k = 1:numel(L)
        if any(contains(string(L(k).Text), txt)), tf = true; return; end
    end
end
function local_shutdown()
    stimProgress('detach');
    delete(findall(0, 'Type', 'figure'));
end
