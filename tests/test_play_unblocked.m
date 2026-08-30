function test_play_unblocked()
% The presentation must no longer eat the event queue: a callback firing mid-presentation
% has to run DURING it, not after.
    td = tempname; mkdir(td);
    c = onCleanup(@() rmdir(td, 's'));

    nFrames = 120; refresh = 60; durS = nFrames / refresh;   % 2.0 s
    rec = struct('stimulus', 'FakeStim', 'stim_type', 'gaussian_noise', ...
                 'cone_isolation', 'achromatic', 'seed', 7, 'flicker_hz', 4, ...
                 'noise_update_hz', 8, 'stim_frames', nFrames, 'refresh_rate_hz', refresh);

    % ---- 1. a timer callback fires DURING the presentation ----
    fired = NaN;
    t = timer('StartDelay', 0.6, 'TimerFcn', @(~,~) markFired());
    cl = onCleanup(@() delete(t));
    fk = FakeStageClient(); fk.durationS = durS; fk.refresh = refresh;
    fk.flipDurations = repmat(1/refresh, nFrames - 1, 1);

    stimProgress('detach');
    start(t);
    tAll = tic;
    sync = playAndLogTrial(fk, [], td, rec, refresh, nFrames);
    el = toc(tAll);

    assert(~isnan(fired), 'the timer callback ran at all');
    assert(fired < 1.0, sprintf('it ran DURING the 2 s presentation, at %.2f s', fired));
    assert(el > durS * 0.95 && el < durS + 0.6, sprintf('total wall time still ~%.1f s (got %.2f)', durS, el));
    assert(fk.playCalled == 1 && fk.infoCalled == 1, 'played once, asked for telemetry once');
    assert(fk.infoBlockedFor < 0.35, ...
        sprintf('getPlayInfo returned promptly (%.2f s) -- the wait happened outside it', fk.infoBlockedFor));

    % ---- 2. frame-sync telemetry is unchanged by the reordering ----
    assert(sync.measured && sync.ok, 'clean telemetry still reads as OK');
    assert(sync.dropped_frames == 0 && sync.n_flips == nFrames, 'flip count / drop count preserved');
    assert(sync.client_wall_s > durS * 0.95, 'client_wall_s still spans the whole playback');

    % ---- 3. a dropped frame is still detected ----
    fk2 = FakeStageClient(); fk2.durationS = 0.3; fk2.refresh = refresh;
    fd = repmat(1/refresh, nFrames - 1, 1); fd(50) = 2.2 / refresh;   % one held frame
    fk2.flipDurations = fd;
    s2 = playAndLogTrial(fk2, [], td, rec, refresh, nFrames);
    assert(s2.measured && ~s2.ok && s2.dropped_frames == 1, ...
        sprintf('the held frame is still caught (dropped=%g)', s2.dropped_frames));

    % ---- 4. the manifest row is still written, once per trial ----
    ds = char(datetime('now', 'Format', 'yyyy_MM_dd'));
    tree = jsondecode(fileread(fullfile(td, [ds '_stim_manifest.json'])));
    cells = local_cells(tree.cells);
    blks  = local_cells(cells{1}.blocks);
    eps_  = local_cells(blks{1}.epochs);
    assert(numel(eps_) == 2, sprintf('two trials logged (got %d)', numel(eps_)));

    % ---- 5. progress reports reach an attached listener during the presentation ----
    got = {};
    stimProgress('attach', @(k, m) collect(k, m), @() []);
    cl2 = onCleanup(@() stimProgress('detach'));
    fk3 = FakeStageClient(); fk3.durationS = 0.5; fk3.refresh = refresh;
    fk3.flipDurations = repmat(1/refresh, 29, 1);
    playAndLogTrial(fk3, [], td, rec, refresh, 30);
    assert(numel(got) >= 5, sprintf('the presentation ticked the listener (%d reports)', numel(got)));
    assert(all(cellfun(@(m) strcmp(m.phase, 'presenting'), got)), 'all tagged "presenting"');
    el_ = cellfun(@(m) m.phaseElapsed, got);
    assert(issorted(el_) && el_(1) < 0.1 && abs(el_(end) - 0.5) < 0.05, ...
        'phaseElapsed climbs from 0 to the full duration');
    si = got{end}.stim;
    assert(si.flicker_hz == 4 && si.noise_update_hz == 8 && si.refresh_hz == refresh && ...
           si.stim_frames == nFrames && si.seed == 7, 'the stimulus frequencies are reported');

    fprintf('[play unblocked] all PASS\n');

    function markFired(), fired = toc(tAll); end
    function collect(kind, msg)
        if strcmp(kind, 'report'), got{end+1} = msg; end %#ok<AGROW>
    end
end

function c = local_cells(x)
    if isempty(x),      c = {};
    elseif iscell(x),   c = reshape(x, 1, []);
    elseif isstruct(x), c = num2cell(reshape(x, 1, []));
    else,               c = {x};
    end
end
