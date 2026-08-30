function sync = playAndLogTrial(client, player, outDir, record, refreshRate, totalFrames, phases)
% playAndLogTrial  Play one presentation, measure display frame-sync from Stage's OWN
% flip telemetry, and log ONE manifest row (with the frame-sync result) for the trial.
%
%   sync = playAndLogTrial(client, player, outDir, record, refreshRate, totalFrames)
%   sync = playAndLogTrial(..., phases)
%
% `phases` (optional) describes how the presentation's timeline divides into phases --
% the generated stimulus scripts pass {prestim, presenting, poststim} with their baked
% durations and per-phase LED grids:
%     struct array: .name (char, a stimulusMonitor phase name), .durS (seconds >= 0),
%                   .leds (4x3 LED duty grid to load as the phase starts, or [] = leave)
% While the presentation renders remotely, the wait loop below applies each phase's LED
% grid (through ledSession -- a no-op unless runExperiment registered the run's rig) as
% its frames begin, and reports the CURRENT phase to the session monitor instead of one
% long 'presenting'. LED grids are applied whether or not a monitor is attached. Omitted
% or empty => the whole presentation reports as 'presenting', exactly as before.
%
% Drop-in replacement for the bare `writeStimManifest(pwd, record)` + `client.play(player)`
% pair in the AA* stimulus functions. It:
%   1. stamps record.timestamp BEFORE play -- the .abf pairing keys off acquisition time
%      (~play START, not play end), so the row is WRITTEN after play but carries the
%      pre-play time;
%   2. plays the presentation down the real client/server pipeline, then waits out its
%      KNOWN duration in interruptible slices rather than blocking in getPlayInfo -- which
%      is what keeps the GUI alive (and its Cancel button clickable) mid-presentation, and
%      what feeds the live stimulusMonitor readout via stimProgress;
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

    if nargin < 7, phases = []; end

    % ---- (1) Pre-play timestamp (preserved through the post-play write) ----
    record.timestamp = char(datetime('now', 'Format', 'yyyy-MM-dd''T''HH:mm:ss'));

    % True refresh from the server (the LightCrafter's video-mode rate); fall back to arg.
    refresh = double(refreshRate);
    try
        r = client.getMonitorRefreshRate();
        if ~isempty(r) && isfinite(r) && r > 1, refresh = double(r); end
    catch
    end

    % ---- (2) Play, wait out the presentation, then retrieve timing (robustly) ----
    % client.play returns as soon as the SERVER ACKs -- the presentation then renders
    % remotely while this MATLAB sits idle. getPlayInfo blocks until the presentation
    % completes, so calling it straight after play (as this did) is what made the whole
    % presentation's wall time elapse inside one un-interruptible socket read: no drawnow,
    % no event queue, so the GUI froze and a Cancel click was not seen until afterwards.
    %
    % Instead, wait out the KNOWN duration here, in a loop that services the event queue and
    % reports progress; getPlayInfo is then asked for telemetry the server already has, and
    % returns promptly. Nothing about the presentation itself changes -- it renders on the
    % server either way, and the telemetry is stored there until the next play, so asking
    % LATE is always safe (asking EARLY is what blocks).
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
        local_awaitPresentation(double(totalFrames) / refresh, record, refresh, totalFrames, phases);
        try
            info = client.getPlayInfo();   % the presentation has finished: returns promptly
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


function local_awaitPresentation(durS, record, refresh, totalFrames, phases)
% Wait out a presentation that is rendering on the Stage server, keeping this MATLAB
% responsive: short pause() slices against a DEADLINE (so the total keeps plain-pause
% accuracy) with a progress report each tick. The pause is what lets the GUI repaint and
% run its Cancel callback -- the whole point of not blocking in getPlayInfo.
%
% With a phase plan, each slice also resolves WHICH phase the elapsed time falls in:
% entering a phase applies its LED grid (ledSession -- best-effort, no-op without a rig)
% and the tick reports that phase's own name/elapsed/total to the monitor. The LED
% switching runs even with no monitor attached -- it is rig behavior, not display sugar.
%
% Cancelling does NOT cut a presentation short. It is already playing on the server and its
% Clampex sweep is already recording, so it always runs to completion and is logged; the
% cancel is acted on at runExperiment's next epoch boundary.
    if ~isfinite(durS) || durS <= 0, return; end
    ph       = local_normalizePhases(phases, durS);
    attached = stimProgress('isAttached');
    info     = [];
    if attached
        info = local_stimInfo(record, refresh, totalFrames, durS);
    end

    lastIdx = 0;
    t0 = tic;
    while true
        el = toc(t0);
        idx = local_phaseAt(ph, min(el, durS));
        if idx > lastIdx
            % Entering a new phase (possibly skipping zero-length ones): apply the LED
            % grid of every phase crossed, in order, so none is silently dropped.
            for k = lastIdx+1:idx
                ledSession('apply', ph(k).leds);
            end
            lastIdx = idx;
        end
        if el >= durS, break; end
        if attached
            % 'leds' = the grid in force for THIS phase ([] = left alone), so the
            % monitor's LED readout follows the phases instead of freezing on the
            % run-level grid. Display only -- the application above is unconditional.
            stimProgress('report', struct('phase', ph(idx).name, ...
                'phaseElapsed', el - ph(idx).startS, 'phaseTotal', ph(idx).durS, ...
                'stim', info, 'leds', ph(idx).leds));
        end
        pause(min(0.05, durS - el));
    end
    if attached
        stimProgress('report', struct('phase', ph(end).name, ...
            'phaseElapsed', ph(end).durS, 'phaseTotal', ph(end).durS, ...
            'stim', info, 'leds', ph(end).leds));
    end
end


function ph = local_normalizePhases(phases, durS)
% Reduce the caller's phase plan to {name, startS, durS, leds} rows covering [0, durS].
% No plan (the AA* scripts) => one 'presenting' phase spanning everything, i.e. the
% pre-phase behavior. The last phase is stretched to absorb rounding so lookups at
% el == durS always land inside the plan.
    ph = struct('name', {}, 'startS', {}, 'durS', {}, 'leds', {});
    if isstruct(phases)
        t = 0;
        for i = 1:numel(phases)
            d = 0;
            if isfield(phases(i), 'durS') && ~isempty(phases(i).durS)
                d = max(0, double(phases(i).durS));
            end
            leds = [];
            if isfield(phases(i), 'leds'), leds = phases(i).leds; end
            nm = 'presenting';
            if isfield(phases(i), 'name') && ~isempty(phases(i).name)
                nm = char(string(phases(i).name));
            end
            ph(end+1) = struct('name', nm, 'startS', t, 'durS', d, 'leds', leds); %#ok<AGROW>
            t = t + d;
        end
    end
    if isempty(ph)
        ph = struct('name', 'presenting', 'startS', 0, 'durS', durS, 'leds', []);
    else
        ph(end).durS = max(ph(end).durS, durS - ph(end).startS);
    end
end


function idx = local_phaseAt(ph, el)
% Index of the LAST non-zero-length phase containing `el` (zero-length phases are crossed,
% never dwelt in). Clamps into [1, numel(ph)].
    idx = 1;
    for i = 1:numel(ph)
        if el >= ph(i).startS && (ph(i).durS > 0 || i == numel(ph))
            idx = i;
        end
        if el < ph(i).startS + ph(i).durS
            idx = i;
            break;
        end
    end
end


function si = local_stimInfo(record, refresh, totalFrames, durS)
% The stimulus's own numbers, for the monitor window: what is on screen and how fast.
    g = @(f, d) local_field(record, f, d);
    si = struct( ...
        'stimulus',       g('stimulus', ''), ...
        'stim_type',      g('stim_type', ''), ...
        'cone_isolation', g('cone_isolation', ''), ...
        'seed',           g('seed', NaN), ...
        'flicker_hz',     g('flicker_hz', NaN), ...
        'noise_update_hz', g('noise_update_hz', NaN), ...
        'refresh_hz',     refresh, ...
        'stim_frames',    g('stim_frames', NaN), ...
        'total_frames',   totalFrames, ...
        'duration_s',     durS);
end


function v = local_field(s, f, d)
    if isstruct(s) && isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
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
