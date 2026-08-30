function test_monitor()
% Drive stimulusMonitor with the exact message shapes runExperiment / playAndLogTrial send.
    mon = stimulusMonitor();
    c = onCleanup(@() mon.close());
    fig = mon.fig;
    assert(isvalid(fig), 'the monitor window opened');

    lbl = @(txt) local_hasLabel(fig, txt);
    btn = findall(fig, 'Type', 'uibutton', 'Text', 'Cancel run');
    assert(~isempty(btn) && strcmp(btn.Enable, 'off'), 'Cancel is present, disabled before a run');

    % ---- begin: 2 blocks (3 + 2 epochs), 10 s stimulus, LEDs on ----
    plan = struct('cellName', 'cell A', 'nBlocks', 2, 'totalEpochs', 5, ...
        'triggerAcq', true, 'seedBase', 2, ...
        'timings', struct('settle', 1, 'preStim', 2, 'postStim', 1, 'itp', 3));
    plan.leds   = struct('enabled', true, 'mode', 2, 'port', 'COM3', ...
                         'intensity', [0.75 0 0; 0 0 1; 0 0 0; 1 0 0]);
    plan.blocks = struct('label', {'grey', 'grey2'}, 'stimName', {'AAFoo', 'AAFoo'}, ...
                         'epochs', {3, 2}, 'stimSeconds', {10, 10});
    mon.update('begin', plan);
    assert(strcmp(btn.Enable, 'on'), 'Cancel goes live when a run begins');
    assert(lbl('cell "cell A"') && lbl('5 epoch(s) in 2 block(s)') && lbl('Clampex ON'), ...
        'the header names the cell, the size of the run and the acquisition state');
    ax = findall(fig, 'Type', 'axes');
    np = numel(findall(ax, 'Type', 'patch'));
    assert(np == 5 * 5 + 1, sprintf('timeline drew 5 phases x 5 epochs + the progress overlay (got %d)', np));
    % 5 epochs x (1 settle + 2 pre + 10 stim + 1 post + 3 itp) = 85 s
    assert(lbl('planned total 01:25'), 'the planned session length is 1:25');

    % ---- an epoch starts ----
    mon.update('report', struct('epoch', 1, 'totalEpochs', 5, 'block', 1, 'nBlocks', 2, ...
        'epochInBlock', 1, 'epochsInBlock', 3, 'label', 'grey', 'stimName', 'AAFoo', ...
        'phase', 'settle', 'phaseElapsed', 0, 'phaseTotal', 0));
    assert(lbl('Epoch 1 of 5'), 'the headline names the epoch');
    assert(lbl('block 1 of 2') && lbl('epoch 1 of 3 in this block') && lbl('"grey"'), ...
        'and the block it belongs to');
    assert(lbl('settling'), 'the phase is shown');

    mon.update('report', struct('seed', 12));
    mon.update('report', struct('phase', 'trigger', 'phaseElapsed', 0, 'phaseTotal', 0));
    assert(lbl('TRIGGER'), 'the acquisition trigger is called out');
    assert(lbl('Epoch 1 of 5'), 'a partial report does not wipe the epoch identity');

    % ---- the presentation reports its own progress + frequencies ----
    si = struct('stimulus', 'AASeededGaussianGreyScaleStimFinal2026', 'stim_type', 'gaussian_noise', ...
                'cone_isolation', 'achromatic', 'seed', 12, 'flicker_hz', 4, ...
                'noise_update_hz', 8, 'refresh_hz', 60, 'stim_frames', 600, ...
                'total_frames', 605, 'duration_s', 10.0833);
    mon.update('report', struct('phase', 'presenting', 'phaseElapsed', 5, 'phaseTotal', 10.0833, 'stim', si));
    assert(lbl('PRESENTING'), 'the presenting phase is called out');
    tbl = findall(fig, 'Type', 'uitable');
    stimTbl = tbl(arrayfun(@(t) any(strcmp(t.Data(:, 1), 'flicker (Hz)')), tbl));
    d = stimTbl.Data;
    val = @(k) d{strcmp(d(:, 1), k), 2};
    assert(strcmp(val('flicker (Hz)'), '4') && strcmp(val('noise update (Hz)'), '8') && ...
           strcmp(val('refresh (Hz)'), '60'), 'the frequencies are on screen');
    assert(strcmp(val('seed'), '12') && strcmp(val('frames (stim/total)'), '600 / 605'), ...
        'seed and frame counts are on screen');
    assert(strcmp(val('cone isolation'), 'achromatic'), 'and the cone isolation');

    % the timeline was redrawn once against the TRUE duration (10.0833, not the planned 10)
    assert(lbl('planned total 01:25'), 'a 0.08 s correction is below the redraw threshold');

    % ---- LED state ----
    ledTbl = tbl(arrayfun(@(t) isequal(size(t.Data), [4 3]), tbl));
    assert(isequal(ledTbl.Data, [0.75 0 0; 0 0 1; 0 0 0; 1 0 0]), 'the LED grid is shown');
    assert(lbl('mode 2 (video RGB)') && lbl('COM3'), 'with its mode and port');

    % ---- finish ----
    mon.update('finish', struct('cancelled', true, 'epochs', 2, 'totalEpochs', 5, 'done', true));
    assert(lbl('CANCELLED') && lbl('Cancelled after 2 of 5 epoch(s).'), 'a cancelled run says so');
    assert(strcmp(btn.Enable, 'off'), 'Cancel goes dead once the run has stopped');

    % ---- a bigger duration correction DOES redraw the timeline ----
    mon2 = stimulusMonitor();
    c2 = onCleanup(@() mon2.close());
    mon2.update('begin', plan);
    si2 = si; si2.duration_s = 20;
    mon2.update('report', struct('phase', 'presenting', 'phaseElapsed', 0, 'phaseTotal', 20, 'stim', si2));
    % 5 x (1 + 2 + 20 + 1 + 3) = 135 s
    assert(local_hasLabel(mon2.fig, 'planned total 02:15'), ...
        'a real 10 s -> 20 s correction redraws the timeline');

    % ---- a listener that throws must not escape into the run ----
    stimProgress('attach', @(k, m) error('boom'), @() []);
    c3 = onCleanup(@() stimProgress('detach'));
    stimProgress('report', struct('phase', 'itp'));       % must not throw
    assert(~stimProgress('isAttached'), 'a broken listener is dropped, not propagated');

    fprintf('[monitor] all PASS\n');
end

function tf = local_hasLabel(fig, txt)
    L = findall(fig, 'Type', 'uilabel');
    tf = any(arrayfun(@(x) contains(char(x.Text), txt), L));
end
