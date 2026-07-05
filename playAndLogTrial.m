function sync = playAndLogTrial(client, player, outDir, record, refreshRate, totalFrames)
% playAndLogTrial  Play one presentation, measure display frame-sync from Stage's OWN
% flip telemetry, and log ONE manifest row (with the frame-sync result) for the trial.
%
%   sync = playAndLogTrial(client, player, outDir, record, refreshRate, totalFrames)
%
% Drop-in replacement for the bare `writeStimManifest(pwd, record)` + `client.play(player)`
% pair in the AA* stimulus functions. It:
%   1. stamps record.timestamp BEFORE play -- the .abf pairing keys off acquisition time
%      (~play START, not play end), so the row is WRITTEN after play but carries the
%      pre-play time;
%   2. plays the presentation down the real client/server pipeline;
%   3. reads the server's per-flip timing via client.getPlayInfo() and reduces it to a
%      dropped-frame count + drift (full rationale in test_AAGreyscaleFFNoise.m);
%   4. attaches that as record.frame_sync and appends ONE manifest row (append-only; the
%      row is written even if play errored, then the error is rethrown); and
%   5. prints a one-line frame-sync summary -- loudly if any frame was dropped.
%
% record.frame_sync is EXCLUDED from the manifest stim_signature (see writeStimManifest),
% so a per-trial drop count never fragments the "N epochs of one stimulus" grouping.
%
% WHY THIS DETECTS DROPS: a dropped frame means the GPU missed a vertical retrace, so the
% frame was HELD for 2+ refreshes -- one flip interval measures ~2x the refresh period AND
% the run drifts late by droppedFrames/refresh. RealtimePlayer's render loop is
% frame-indexed, so the flip COUNT is unchanged: counting frames misses it, measuring flip
% DURATIONS catches it.

    % ---- (1) Pre-play timestamp (preserved through the post-play write) ----
    record.timestamp = char(datetime('now', 'Format', 'yyyy-MM-dd''T''HH:mm:ss'));

    % True refresh from the server (the LightCrafter's video-mode rate); fall back to arg.
    refresh = double(refreshRate);
    try
        r = client.getMonitorRefreshRate();
        if ~isempty(r) && isfinite(r) && r > 1, refresh = double(r); end
    catch
    end

    % ---- (2) Play, then retrieve timing (robustly) ----
    % client.play returns immediately (the server ACKs, THEN renders); the presentation's
    % wall time actually elapses inside getPlayInfo, which blocks until it completes.
    played  = false;
    playErr = [];
    info    = [];
    tPlay   = tic;
    try
        client.play(player);
        played = true;
    catch playErr
    end
    if played
        try
            info = client.getPlayInfo();   % BLOCKS until the presentation completes
        catch
            info = [];                     % telemetry unavailable; not a play failure
        end
    end
    clientWall = toc(tPlay);               % spans play() + retrieval = true playback wall time

    % ---- (3) Reduce the flip telemetry to a frame-sync record ----
    record.frame_sync = local_frameSync(info, refresh, totalFrames, clientWall, played);

    % ---- (4) Log exactly one row (append-only), even on a play error ----
    try
        outPath = writeStimManifest(outDir, record);
        fprintf('[playAndLogTrial] Logged trial -> %s\n', outPath);
    catch logErr
        fprintf(2, '[playAndLogTrial] WARNING: manifest write failed: %s\n', logErr.message);
    end

    % ---- (5) Report ----
    sync = record.frame_sync;
    local_report(sync, refresh);

    if ~played
        rethrow(playErr);   % surface the play failure -- AFTER the trial was logged
    end
end


function fs = local_frameSync(info, refresh, totalFrames, clientWall, played)
% Reduce a play-info struct's flipDurations (inter-flip deltas, seconds) to a compact
% per-trial frame-sync record. Best-effort: if telemetry is missing, measured=false and the
% numeric fields are NaN (-> null in the JSON) so the trial still logs.
    period = 1 / refresh;
    fs = struct( ...
        'measured',         false, ...
        'ok',               false, ...
        'dropped_frames',   NaN, ...
        'long_flip_events', NaN, ...
        'drift_frames',     NaN, ...
        'max_flip_ms',      NaN, ...
        'mean_flip_ms',     NaN, ...
        'n_flips',          NaN, ...
        'expected_frames',  totalFrames, ...
        'refresh_hz',       refresh, ...
        'client_wall_s',    clientWall);

    if ~played, return; end
    if ~isstruct(info) || ~isfield(info, 'flipDurations') || isempty(info.flipDurations)
        return;    % telemetry missing, or the server stored an exception instead of play-info
    end

    d    = double(info.flipDurations(:));    % inter-flip intervals (s); length = nFlips-1
    lo   = min(3, numel(d));                  % drop the first 2 flips (texture preload / priority)
    ss   = d(lo:end);
    held = ss > 1.5 * period;                 % a flip spanning >1 retrace = a held/dropped frame

    fs.measured         = true;
    fs.dropped_frames   = sum(max(round(ss(held) / period) - 1, 0));
    fs.long_flip_events = sum(held);
    fs.drift_frames     = (sum(ss) - numel(ss) * period) / period;
    fs.max_flip_ms      = max(d) * 1000;
    fs.mean_flip_ms     = mean(d) * 1000;
    fs.n_flips          = numel(d) + 1;
    fs.ok               = (fs.dropped_frames == 0) && (abs(fs.drift_frames) < 1.0);
end


function local_report(fs, refresh)
    if ~fs.measured
        fprintf('[frame-sync] telemetry unavailable (no flipDurations from the server).\n');
        return;
    end
    tag = 'OK';
    if ~fs.ok, tag = '*** CHECK ***'; end
    fprintf('[frame-sync] %s  dropped=%d  drift=%+.2f frm  maxflip=%.2f ms (period %.2f ms)  flips=%d/%d\n', ...
        tag, fs.dropped_frames, fs.drift_frames, fs.max_flip_ms, 1000 / refresh, fs.n_flips, fs.expected_frames);
    if ~fs.ok
        fprintf(2, '[frame-sync] WARNING: %d dropped frame(s); display timing drifted %+.2f frames this trial.\n', ...
            fs.dropped_frames, fs.drift_frames);
    end
end
