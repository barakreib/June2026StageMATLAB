function test_prep_landing()
% (2) "the graph line fully pauses on the purple portions, and then jumps [past the
% stimulus]". The pause is unavoidable -- nothing in MATLAB can repaint while blk.stim is
% precomputing frames and uploading the presentation. What must NOT happen is the jump
% landing in the wrong band: when the presentation starts, the marker has to sit exactly at
% the start of the STIMULUS segment.
    T = struct('settle', 0.5, 'preStim', 0.9, 'postStim', 0.4, 'itp', 0.6);
    STIM = 1.2; NEP = 4;
    PREP = [2.2 0.8 0.8 0.8];      % epoch 1 is much slower (first connect, cold caches)

    mon = stimulusMonitor();
    c = onCleanup(@() mon.close()); %#ok<NASGU>
    plan = struct('cellName', 'x', 'nBlocks', 1, 'totalEpochs', NEP, 'triggerAcq', true, ...
                  'seedBase', 2, 'timings', T);
    plan.leds   = struct('enabled', false);
    plan.blocks = struct('label', {'b'}, 'stimName', {'AAFoo'}, 'epochs', {NEP}, 'stimSeconds', {STIM});
    mon.update('begin', plan);

    err = zeros(1, NEP);
    for e = 1:NEP
        mon.update('report', struct('epoch', e, 'totalEpochs', NEP, 'block', 1, 'nBlocks', 1, ...
            'epochInBlock', e, 'epochsInBlock', NEP, 'label', 'b', 'stimName', 'AAFoo', ...
            'phase', 'settle', 'phaseElapsed', 0, 'phaseTotal', 0));
        tick(mon, 'settle', T.settle);
        mon.update('report', struct('phase', 'trigger', 'phaseElapsed', 0, 'phaseTotal', 0));
        tick(mon, 'prestim', T.preStim);

        % runExperiment announces the setup, then MATLAB goes dark for its duration
        mon.update('report', struct('phase', 'prep', 'phaseElapsed', 0, 'phaseTotal', 0));
        frozen = local_marker(mon.fig);
        pause(PREP(e));
        assert(abs(local_marker(mon.fig) - frozen) < 1e-9, ...
            'the marker holds still while nothing can repaint (expected, not a bug)');

        % first frame on the projector: the marker must resume ON the stimulus band
        si = struct('stimulus', 'AAFoo', 'cone_isolation', 'achromatic', 'seed', e, ...
                    'flicker_hz', 4, 'noise_update_hz', 8, 'refresh_hz', 60, ...
                    'stim_frames', 600, 'total_frames', 605, 'duration_s', STIM);
        mon.update('report', struct('phase', 'presenting', 'phaseElapsed', 0, ...
                                    'phaseTotal', STIM, 'stim', si));
        err(e) = local_marker(mon.fig) - local_stimStart(mon.fig, e);
        fprintf('   epoch %d: prep %.1f s -> marker lands %+.2f s from the stimulus band\n', ...
                e, PREP(e), err(e) * 60);
        assert(abs(err(e)) * 60 < 0.35, sprintf(['epoch %d: the marker resumed %+.2f s away ' ...
            'from the start of the stimulus band'], e, err(e) * 60));

        tick(mon, 'presenting', STIM, si);
        pause(0.15);
        tick(mon, 'poststim', T.postStim);
        tick(mon, 'itp', T.itp);
    end
    fprintf('[prep landing] worst landing error %.2f s -- PASS\n', max(abs(err)) * 60);
end

function tick(mon, ph, d, si)
% DEADLINE-based, exactly like runExperiment's waitFn: the phase lasts d seconds in total,
% with the redraws happening INSIDE that window rather than on top of it. A pause-per-tick
% harness would make every phase run long and the landing test would be measuring its own
% overhead instead of the monitor.
    t0 = tic;
    while true
        el = toc(t0);
        if el >= d, break; end
        m = struct('phase', ph, 'phaseElapsed', el, 'phaseTotal', d);
        if nargin >= 4, m.stim = si; end
        mon.update('report', m);
        pause(min(0.03, d - el));
    end
end

function x = local_marker(fig)
    ax = findall(fig, 'Type', 'axes');
    L  = findall(ax, 'Type', 'constantline');
    L  = L(arrayfun(@(o) o.LineWidth > 1, L));
    x  = L.Value;
end

function x = local_stimStart(fig, e)
% Left edge of epoch e's STIMULUS patch (the green one), in axis units.
    ax = findall(fig, 'Type', 'axes');
    P  = findall(ax, 'Type', 'patch');
    green = [];
    for k = 1:numel(P)
        if isequal(round(P(k).FaceColor, 3), [0.200 0.550 0.300])
            green(end + 1) = min(P(k).XData); %#ok<AGROW>
        end
    end
    green = sort(green);
    assert(numel(green) >= e, 'found a stimulus band for every epoch');
    x = green(e);
end
