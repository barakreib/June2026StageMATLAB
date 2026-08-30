function test_timeline_drift()
% REGRESSION: "the progress line finished travelling all the way to the right after just 4
% epochs and the 5th epoch still had not displayed."
%
% Replays a realistic report stream in REAL time (short phases, but genuine wall-clock gaps
% -- the monitor measures overhead off the clock, so it cannot be simulated faster). Each
% epoch spends real time inside blk.stim BEFORE the presentation (connect + precompute every
% frame + serialise the presentation to the server) and after it (telemetry + manifest
% write). The plan cannot know that, so the monitor has to measure it and reflow the
% timeline -- and the marker must never pin at the right-hand edge.
    PREP = 1.0;  WRAP = 0.3;          % the per-epoch overhead the plan does NOT model
    T    = struct('settle', 0.3, 'preStim', 0.5, 'postStim', 0.3, 'itp', 0.6);
    STIM = 1.5;  NEP = 5;
    naive = NEP * (T.settle + T.preStim + STIM + T.postStim + T.itp);
    real_ = NEP * (T.settle + T.preStim + PREP + STIM + WRAP + T.postStim + T.itp);

    mon = stimulusMonitor();
    c = onCleanup(@() mon.close()); %#ok<NASGU>
    plan = struct('cellName', 'drift', 'nBlocks', 1, 'totalEpochs', NEP, ...
                  'triggerAcq', true, 'seedBase', 2, 'timings', T);
    plan.leds   = struct('enabled', false);
    plan.blocks = struct('label', {'b'}, 'stimName', {'AAFoo'}, 'epochs', {NEP}, 'stimSeconds', {STIM});
    mon.update('begin', plan);

    planned0 = local_total(mon.fig);
    assert(abs(planned0 - naive) < 0.5, sprintf('the plan starts naive at %.1f s (got %.1f)', naive, planned0));

    frac = zeros(1, NEP); mark = zeros(1, NEP);
    tSession = tic;
    for e = 1:NEP
        mon.update('report', struct('epoch', e, 'totalEpochs', NEP, 'block', 1, 'nBlocks', 1, ...
            'epochInBlock', e, 'epochsInBlock', NEP, 'label', 'b', 'stimName', 'AAFoo', ...
            'phase', 'settle', 'phaseElapsed', 0, 'phaseTotal', 0));
        local_run(mon, 'settle',  T.settle);
        mon.update('report', struct('phase', 'trigger', 'phaseElapsed', 0, 'phaseTotal', 0));
        local_run(mon, 'prestim', T.preStim);
        pause(PREP);                                  % <-- unmodelled: setup + upload
        local_present(mon, STIM);
        pause(WRAP);                                  % <-- unmodelled: telemetry + manifest
        local_run(mon, 'poststim', T.postStim);
        local_run(mon, 'itp',      T.itp);
        [frac(e), mark(e)] = local_markerFrac(mon.fig);
        fprintf('   after epoch %d: marker at %3.0f%% of the timeline (model %.1f s)\n', ...
                e, 100 * frac(e), local_total(mon.fig));
    end

    elapsed = toc(tSession);

    % THE BUG: the marker hit the right edge at epoch 4 and stayed pinned there while epoch
    % 5 had not even been presented.
    assert(all(frac(1:NEP-1) < 0.92), sprintf(['no epoch before the last may push the marker ' ...
        'to the right-hand edge (worst was %.0f%%)'], 100 * max(frac(1:NEP-1))));
    assert(all(diff(mark) > 0), 'the marker always advances in absolute time, never pins');
    assert(frac(NEP) > 0.85, sprintf('and it does reach the end on the last epoch (%.0f%%)', 100 * frac(NEP)));

    % The model must land near the session that ACTUALLY happened -- not the naive plan, and
    % not the paper arithmetic, which ignores this harness's own per-tick cost.
    planned1 = local_total(mon.fig);
    assert(planned1 > planned0 + 0.3 * (real_ - naive), 'the timeline grew towards the real length');
    assert(abs(planned1 - elapsed) < 0.18 * elapsed, ...
        sprintf('the model (%.1f s) tracks the real session (%.1f s)', planned1, elapsed));
    fprintf(['[timeline drift] naive plan %.1f s -> model %.1f s; session really took %.1f s ' ...
             '-- PASS\n'], planned0, planned1, elapsed);
end

function local_run(mon, phase, dur)
    n = max(2, round(dur * 12));
    for i = 0:n
        mon.update('report', struct('phase', phase, 'phaseElapsed', dur * i / n, 'phaseTotal', dur));
        pause(dur / n);
    end
end

function local_present(mon, dur)
    si = struct('stimulus', 'AAFoo', 'cone_isolation', 'achromatic', 'seed', 2, ...
                'flicker_hz', 4, 'noise_update_hz', 8, 'refresh_hz', 60, ...
                'stim_frames', 600, 'total_frames', 605, 'duration_s', dur);
    n = max(2, round(dur * 12));
    for i = 0:n
        mon.update('report', struct('phase', 'presenting', 'phaseElapsed', dur * i / n, ...
                                    'phaseTotal', dur, 'stim', si));
        pause(dur / n);
    end
end

function t = local_total(fig)
% The modelled session length, read straight off the axis (minutes -> seconds).
    ax = findall(fig, 'Type', 'axes');
    t  = ax.XLim(2) * 60;
end

function [f, x] = local_markerFrac(fig)
% The "now" marker is the thick red constantline; the thin grey ones are epoch boundaries.
    ax = findall(fig, 'Type', 'axes');
    L  = findall(ax, 'Type', 'constantline');
    L  = L(arrayfun(@(o) o.LineWidth > 1, L));
    assert(isscalar(L), 'found exactly one "now" marker');
    x  = L.Value;
    f  = x / ax.XLim(2);
end
