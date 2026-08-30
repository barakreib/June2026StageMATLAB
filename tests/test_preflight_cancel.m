function test_preflight_cancel()
% REGRESSION for: "stage.server did not respond within 10 seconds and the stimulusGUI did
% not handle it well. The cancel was not available on the new stimulus monitor window nor on
% the main. I had to close the stimulusGUI and restart."
%
% Sandboxed: this copy's rig_config points stage_host at 127.0.0.1, where a socket accepts
% the connection and never answers -- the exact failure, with the rig nowhere near it.
    fig = local_openWithBlock();
    c1 = onCleanup(@() local_shutdown()); %#ok<NASGU>
    runBtn  = findall(fig, 'Type', 'uibutton', 'Text', 'Run experiment');
    mainCan = findall(fig, 'Type', 'uibutton', 'Text', 'Cancel');
    ctrls   = findall(fig, '-property', 'Enable', '-not', 'Type', 'uilabel');
    before  = arrayfun(@(x) string(x.Enable), ctrls);

    % ---- 1. let the pre-flight time out: the failure must be visible + the GUI clean ----
    % (this first run also pays the one-off cost of building the monitor window)
    fprintf('>>> run 1 (let it time out)\n');
    tic; runBtn.ButtonPushedFcn(runBtn, []); elFail = toc;
    mf = local_monFig();
    assert(local_hasLabel(mf, 'RUN FAILED'), 'the monitor shows the failure, not a stale "Starting run..."');
    assert(local_hasLabel(mf, 'did not answer'), 'and the REASON, so the operator need not hunt for a dialog');
    after = arrayfun(@(x) string(x.Enable), ctrls);
    assert(isequal(before, after), 'every control is restored after the failed run');
    assert(strcmp(runBtn.Enable, 'on') && strcmp(mainCan.Enable, 'off'), 'Run live, Cancel dead');
    % Hooks deliberately OUTLIVE the run: the monitor keeps previewing the protocol after
    % it finishes. They are dropped when the window closes, not when the run ends.
    if isempty(findall(0, 'Type', 'figure', 'Name', 'Session monitor'))
        assert(~stimProgress('isAttached'), 'no monitor window -> no hooks');
    else
        assert(stimProgress('isAttached'), 'the monitor stays attached while its window is open');
    end
    fprintf('   run 1: timed out after %.1f s, GUI clean, failure shown in the monitor\n', elFail);

    % ---- 2. mid-pre-flight (monitor now built): BOTH Cancels live, monitor says CONNECTING ----
    snap = [];
    t = timer('StartDelay', 2.5, 'TimerFcn', @(~,~) sample());
    ct = onCleanup(@() delete(t)); %#ok<NASGU>
    start(t);
    fprintf('>>> run 2 (sample only, nobody presses Cancel)\n');
    tic; runBtn.ButtonPushedFcn(runBtn, []); elFail2 = toc;
    assert(~isempty(snap), 'the sampler ran during the pre-flight -- the GUI was not frozen');
    assert(snap.hasConnecting, 'the monitor says CONNECTING, not "Waiting for a run..."');
    assert(strcmp(snap.mainCancel, 'on'), 'the main window Cancel is live during the pre-flight');
    assert(strcmp(snap.monCancel, 'on'), 'the MONITOR Cancel is live during the pre-flight');
    fprintf('   run 2: CONNECTING + both Cancels live at 2.5 s (total %.1f s)\n', elFail2);

    % ---- 3. the MONITOR's Cancel aborts the pre-flight instead of waiting out the 10 s ----
    t2 = timer('StartDelay', 2.5, 'TimerFcn', @(~,~) pressMonitorCancel());
    ct2 = onCleanup(@() delete(t2)); %#ok<NASGU>
    start(t2);
    fprintf('>>> run 3 (monitor Cancel at 2.5 s)\n');
    tic; runBtn.ButtonPushedFcn(runBtn, []); elCancel = toc;
    assert(elCancel < elFail2 - 3, sprintf(['Cancel aborted the pre-flight (%.1f s) instead of ' ...
        'waiting out the full timeout (%.1f s)'], elCancel, elFail2));
    mf = local_monFig();
    assert(local_hasLabel(mf, 'Cancelled after 0 of'), 'the monitor reports a clean cancel');
    assert(~local_hasLabel(mf, 'RUN FAILED'), 'cancelling out of the pre-flight is not an error');
    assert(strcmp(runBtn.Enable, 'on'), 'the GUI is usable again after cancelling');
    fprintf('   run 3: monitor Cancel aborted in %.1f s (vs %.1f s timing out)\n', elCancel, elFail2);

    % ---- 4. the MAIN window's Cancel does the same ----
    t3 = timer('StartDelay', 2.5, 'TimerFcn', @(~,~) pressMainCancel());
    ct3 = onCleanup(@() delete(t3)); %#ok<NASGU>
    start(t3);
    fprintf('>>> run 4 (main Cancel at 2.5 s)\n');
    tic; runBtn.ButtonPushedFcn(runBtn, []); elCancel2 = toc;
    assert(elCancel2 < elFail2 - 3, sprintf('the main Cancel also aborts the pre-flight (%.1f s)', elCancel2));
    assert(isequal(arrayfun(@(x) string(x.Enable), ctrls), before), 'and the GUI is fully restored');
    fprintf('   run 4: main Cancel aborted in %.1f s\n', elCancel2);
    fprintf('[preflight cancel] all PASS\n');

    function sample()
        m = local_monFig();
        snap = struct('mainCancel', char(mainCan.Enable), ...
                      'monCancel',  char(local_monCancel(m).Enable), ...
                      'hasConnecting', local_hasLabel(m, 'CONNECTING'));
    end
    function pressMonitorCancel()
        b = local_monCancel(local_monFig());
        b.ButtonPushedFcn(b, []);
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

function f = local_monFig()
    f = findall(0, 'Type', 'figure', 'Name', 'Session monitor');
end
function b = local_monCancel(f)
    b = findall(f, 'Type', 'uibutton', 'Text', 'Cancel run');
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
