function results = test_AAGreyscaleFFNoise(durationSec, stimKind, refreshRate)
% test_AAGreyscaleFFNoise  Photodiode-free frame-drop / frame-sync test for the
% OpenGL (Stage-VSS) display, using Stage's OWN per-flip timing telemetry.
%
% WHY THIS EXISTS
%   You want to know whether the OpenGL renderer on the Stage server (192.168.0.51)
%   drops or duplicates frames -- the "frame sync" problem -- but you have no photodiode
%   or DAQ at home. You don't need one. The Stage server timestamps EVERY buffer swap
%   (vertical-retrace flip) with a high-resolution monotonic clock (glfwGetTime) inside
%   FlipTimer, RealtimePlayer returns those times in `info.flipDurations`, and the client
%   reads them back with client.getPlayInfo(). This function plays a long, deterministic
%   full-field noise stimulus down the REAL client/server pipeline, retrieves the flip
%   intervals, and reports dropped frames + cumulative drift. It is the renderer telling
%   you its own timing.
%
% THE PHYSICS (why a long run "goes off" if frames drop) -- confirmed from the Stage source
%   RealtimePlayer.play renders a FIXED number of frames: its loop is indexed by frame
%   number, not the wall clock  ->  `while frame/refresh < duration`. canvas.window.flip()
%   blocks until the next vertical retrace. So if the GPU cannot finish a frame within one
%   refresh period (~16.67 ms @ 60 Hz), that flip waits for the NEXT retrace: the frame is
%   HELD for 2 (or more) refreshes. The flip COUNT is unchanged -- so counting flips proves
%   nothing -- but:
%       * that one flip interval measures ~2x the period      -> per-frame drop detector
%       * the whole run finishes LATE by droppedFrames/refresh -> cumulative drift
%   Over a long run even a rare drop accumulates into a measurable offset. Exactly your
%   intuition. This function measures BOTH and they should agree.
%
% WHAT IT PROVES / DOES NOT PROVE
%   PROVES:  whether the OpenGL server renders every frame on time (no dropped / held /
%            duplicated frames), and quantifies render jitter. This IS the OpenGL "frame
%            sync" you asked about.
%   DOES NOT PROVE (that needs the photodiode/DAQ back at the rig): that the displayed
%            frames are time-aligned to the ephys / Clampex TTL clock. This tests the
%            DISPLAY side only.
%
% USAGE
%   test_AAGreyscaleFFNoise                  % 120 s, image (Gaussian-noise) path
%   test_AAGreyscaleFFNoise(600)             % stricter: 10-minute run
%   test_AAGreyscaleFFNoise(120, 'rect')     % square-wave Rectangle render path
%   r = test_AAGreyscaleFFNoise(...);        % returns a struct; also writes CSV+MAT+PNG
%
% Inputs (all optional):
%   durationSec - stimulus length in seconds  (default 120). LONGER = more sensitive to
%                 RARE drops: zero drops over N frames bounds the drop rate below ~1/N.
%   stimKind    - 'image' (default): full-field per-frame Image/imageMatrix texture upload
%                 -- the SAME OpenGL path as AASeededGaussianGreyScaleStimFinal2026 (the
%                 heavy path most likely to hitch). 'rect': Rectangle color-swap (light).
%   refreshRate - fallback refresh (Hz) if the server can't report one (default: rig_config
%                 refresh_rate_hz, else 60). The server's true rate is used when available.
%
% Output: results struct (also echoed to the console and saved under ./timing_tests/).
%
% NOTE: this is a DIAGNOSTIC -- it does NOT write a stimulus manifest (unlike the real
%       AA* stimulus functions), so it will not pollute the per-day trial log.

    % ---- Defaults ----
    if nargin < 1 || isempty(durationSec), durationSec = 120;                          end
    if nargin < 2 || isempty(stimKind),    stimKind    = 'image';                       end
    if nargin < 3 || isempty(refreshRate), refreshRate = loadRigConfig('refresh_rate_hz', 60); end

    % ---- Tunables ----
    longFactor   = 1.5;   % a flip longer than longFactor*period counts as a held/dropped frame
    warmupFlips  = 2;     % ignore the first few flips (texture preload / priority bump) for PASS/FAIL
    passDriftFrm = 1.0;   % steady-state net drift must be < this many frames to PASS
    seed         = 7;     % deterministic noise (repeatable test)
    poolSeconds  = 10;    % precompute this many seconds of distinct frames, then cycle (bounds memory)
    saveResults  = true;
    doPlot       = true;

    % ---- HARD REQUIREMENT: the real client/server pipeline ----
    client = stage.core.network.StageClient();
    client.connect(stageHost());
    canvasSize = client.getCanvasSize();
    W = canvasSize(1); H = canvasSize(2);
    fprintf('[test_AAGreyscaleFFNoise] Connected to %s.  Canvas: %d x %d\n', stageHost(), W, H);

    import stage.core.*;
    import stage.builtin.stimuli.*;
    import stage.builtin.controllers.*;
    import stage.builtin.players.*;

    % ---- Ask the SERVER for its true refresh rate (the LightCrafter's video-mode rate) ----
    refresh = double(refreshRate);
    try
        r = client.getMonitorRefreshRate();
        if ~isempty(r) && isfinite(r) && r > 1
            refresh = double(r);
        end
    catch
        % server didn't answer -> keep the rig_config / argument fallback
    end
    period        = 1 / refresh;
    totalFrames   = max(2, round(durationSec * refresh));
    totalDuration = totalFrames / refresh;   % using the server's own rate keeps totalFrames exact
    isImage       = strcmpi(stimKind, 'image');
    fprintf('[test_AAGreyscaleFFNoise] refresh=%.4f Hz (period %.3f ms)  %d frames  %.1f s  kind=%s\n', ...
            refresh, period*1000, totalFrames, totalDuration, stimKind);

    % ---- Precompute a bounded pool of per-frame content, then cycle it ----
    % (Content repetition is irrelevant to timing; the renderer still uploads/sets the
    %  property every frame. Cycling a pool keeps memory flat for arbitrarily long runs.)
    poolN    = max(1, min(totalFrames, round(poolSeconds * refresh)));
    rbColors = [0 0 0; 0 0 1];   % right-edge sync bar: black / blue, alternating each frame

    if isImage
        checksY = 1; checksX = 1;               % full-field greyscale = 1x1 (matches the real stim)
        stream  = RandStream('mt19937ar', 'Seed', seed);
        pool    = cell(poolN, 1);
        for k = 1:poolN
            % Seeded inverse-CDF Gaussian, clipped, gamma-corrected -- same recipe as the real stim.
            v = 0.5 + 0.3 .* (sqrt(2) .* erfinv(2 .* rand(stream, checksY, checksX) - 1));
            v = min(max(v, 0), 1);
            g = uint8(round(255 * lcGammaCorrect(v)));
            img = zeros(checksY, checksX, 3, 'uint8');
            img(:,:,1) = g; img(:,:,2) = g; img(:,:,3) = g;
            pool{k} = img;
        end
        blackRGB = zeros(checksY, checksX, 3, 'uint8');
    else
        pool = zeros(poolN, 3);                 % square-wave: alternate black/white every frame
        pool(2:2:end, :) = 1;
        pool = lcGammaCorrect(pool);            % identity on pure black/white, applied for correctness
    end

    % ---- Stimuli + per-frame controllers (pure anonymous fns, Stage-serialization safe) ----
    if isImage
        stim = Image(blackRGB);
        stim.position = [W/2, H/2];
        stim.size     = [W, H];
        stim.setMinFunction(GL.NEAREST);
        stim.setMagFunction(GL.NEAREST);
        stimCtrl = PropertyController(stim, 'imageMatrix', ...
            @(s) pool{mod(s.frame, poolN) + 1});
    else
        stim = Rectangle();
        stim.size     = [W, H];
        stim.position = [W/2, H/2];
        stim.color    = [0 0 0];
        stimCtrl = PropertyController(stim, 'color', ...
            @(s) pool(mod(s.frame, poolN) + 1, :));
    end

    rightBar = Rectangle();
    rightBar.size     = [W/8, H];
    rightBar.position = [W - W/16, H/2];
    rightBar.color    = [0 0 0];
    rightBarCtrl = PropertyController(rightBar, 'color', ...
        @(s) rbColors(mod(s.frame, 2) + 1, :));

    presentation = Presentation(totalDuration);
    presentation.addStimulus(stim);
    presentation.addStimulus(rightBar);
    presentation.addController(stimCtrl);
    presentation.addController(rightBarCtrl);

    player = RealtimePlayer(presentation);

    % ---- Play + capture timing --------------------------------------------------------
    fprintf('[test_AAGreyscaleFFNoise] Playing %.1f s ... (do not interrupt)\n', totalDuration);
    tPlay = tic;
    client.play(player);            % returns immediately: the server ACKs, then renders asynchronously
    info  = client.getPlayInfo();   % BLOCKS until the presentation completes -> the true playback time
    clientWall = toc(tPlay);        % client-side wall clock spanning play() + retrieval
    if ~isstruct(info) || ~isfield(info, 'flipDurations') || isempty(info.flipDurations)
        error('test_AAGreyscaleFFNoise:noTiming', ...
              'getPlayInfo returned no flipDurations -- cannot assess timing (Stage version?).');
    end
    d      = double(info.flipDurations(:));   % inter-flip intervals (s); length = nFlips-1
    nFlips = numel(d) + 1;                     % FlipTimer's first tick records no delta
    tStamp = cumsum(d);                        % wall time of each recorded flip (s from first flip)

    % ---- Analysis ---------------------------------------------------------------------
    heldMask      = d > longFactor * period;                 % flips that spanned >1 retrace
    heldIdx       = find(heldMask);
    droppedFrames = sum(max(round(d(heldMask) / period) - 1, 0));   % extra retraces held = frames lost

    lo         = min(warmupFlips + 1, numel(d));             % steady-state = drop the warm-up flips
    ss         = d(lo:end);
    ssHeld     = ss > longFactor * period;
    ssDropped  = sum(max(round(ss(ssHeld) / period) - 1, 0));
    ssDriftSec = sum(ss) - numel(ss) * period;               % measured minus ideal, steady state
    ssDriftFrm = ssDriftSec / period;

    driftSec = sum(d) - numel(d) * period;                   % full-run drift over recorded intervals
    driftFrm = driftSec / period;

    meanMs = mean(d) * 1000;  stdMs = std(d) * 1000;
    maxMs  = max(d)  * 1000;  minMs = min(d) * 1000;

    passed  = (ssDropped == 0) && (abs(ssDriftFrm) < passDriftFrm);
    verdict = 'FAIL';  if passed, verdict = 'PASS'; end

    % ---- Report -----------------------------------------------------------------------
    fprintf('\n================ FRAME-SYNC TEST: %s ================\n', verdict);
    fprintf('  stimulus path      : %s\n', stimKind);
    fprintf('  server refresh     : %.4f Hz   (period %.3f ms)\n', refresh, period*1000);
    fprintf('  frames requested   : %d  (%.1f s)\n', totalFrames, totalDuration);
    fprintf('  flips recorded     : %d', nFlips);
    if nFlips ~= totalFrames
        fprintf('   <-- WARNING: expected %d; server may have aborted early', totalFrames);
    end
    fprintf('\n');
    fprintf('  dropped frames     : %d  (steady-state %d, %d long-flip events)\n', ...
            droppedFrames, ssDropped, numel(heldIdx));
    fprintf('  cumulative drift   : %+.2f ms  = %+.3f frames (steady-state %+.3f frames)\n', ...
            driftSec*1000, driftFrm, ssDriftFrm);
    fprintf('  flip interval      : mean %.3f  sd %.3f  min %.3f  max %.3f  ms\n', ...
            meanMs, stdMs, minMs, maxMs);
    fprintf('  client wall clock  : %.3f s   (server flip span %.3f s; diff %+.1f ms = connect/teardown)\n', ...
            clientWall, sum(d), (clientWall - sum(d))*1000);

    if ~isempty(heldIdx)
        [sd, ord] = sort(d, 'descend');
        fprintf('  longest flips (frame / wall time / interval / xperiod):\n');
        for ii = 1:min(6, numel(d))
            j = ord(ii);
            fprintf('      frame %7d  @ %8.2f s   %6.2f ms  (%.2fx)\n', ...
                    j+1, tStamp(j), sd(ii)*1000, sd(ii)/period);
        end
    end

    if passed
        fprintf('  => No dropped frames and drift < %.1f frame. The OpenGL renderer kept sync\n', passDriftFrm);
        fprintf('     over %d frames (drop rate < ~1/%d). "Long enough" caught nothing.\n', totalFrames, totalFrames);
    else
        fprintf('  => Frames were dropped/held. The two signatures agree: %d dropped frames\n', ssDropped);
        fprintf('     ~ %.2f frames of drift. Re-run longer to bound the rate, and/or try\n', ssDriftFrm);
        fprintf('     ''rect'' to see if the Image/texture-upload path is the culprit.\n');
    end
    fprintf('=====================================================\n');

    % ---- Package results --------------------------------------------------------------
    results = struct( ...
        'passed',          passed, ...
        'stimKind',        stimKind, ...
        'refreshHz',       refresh, ...
        'periodMs',        period*1000, ...
        'durationSec',     totalDuration, ...
        'totalFrames',     totalFrames, ...
        'nFlips',          nFlips, ...
        'droppedFrames',   droppedFrames, ...
        'ssDroppedFrames', ssDropped, ...
        'longFlipEvents',  numel(heldIdx), ...
        'driftMs',         driftSec*1000, ...
        'driftFrames',     driftFrm, ...
        'ssDriftFrames',   ssDriftFrm, ...
        'meanMs',          meanMs, 'stdMs', stdMs, 'minMs', minMs, 'maxMs', maxMs, ...
        'clientWallSec',   clientWall, ...
        'serverSpanSec',   sum(d), ...
        'flipDurationsMs', d*1000);

    % ---- Persist (CSV of intervals + MAT of results + a timeline/histogram PNG) --------
    if saveResults
        outDir = fullfile(fileparts(mfilename('fullpath')), 'timing_tests');
        if ~exist(outDir, 'dir'), mkdir(outDir); end
        stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
        base  = fullfile(outDir, sprintf('fliptiming_%s_%s', stimKind, stamp));
        try
            writematrix(d*1000, [base '.csv']);   % flip intervals, one per row, in ms
        catch
            csvwrite([base '.csv'], d*1000);       % fallback for older MATLAB %#ok<CSVWT>
        end
        try
            save([base '.mat'], '-struct', 'results');
        catch
        end
        if doPlot
            try
                fig = figure('Visible', 'off', 'Position', [100 100 1000 720]);
                subplot(2,1,1);
                plot(tStamp, d*1000, '-', 'Color', [.2 .4 .8]); hold on;
                plot(xlim, [1 1]*period*1000,             'k:');
                plot(xlim, [1 1]*longFactor*period*1000,  'r--');
                if any(heldMask)
                    plot(tStamp(heldMask), d(heldMask)*1000, 'ro', 'MarkerFaceColor', 'r');
                end
                xlabel('time (s)'); ylabel('flip interval (ms)');
                title(sprintf('%s  |  %.4f Hz  |  dropped=%d  drift=%+.2f frm  |  %s', ...
                      stimKind, refresh, ssDropped, ssDriftFrm, verdict), 'Interpreter', 'none');
                subplot(2,1,2);
                histogram(d*1000, 80); hold on;
                yl = ylim;
                plot([1 1]*period*1000,            yl, 'k:');
                plot([1 1]*longFactor*period*1000, yl, 'r--');
                set(gca, 'YScale', 'log');
                xlabel('flip interval (ms)'); ylabel('count (log)');
                try
                    exportgraphics(fig, [base '.png'], 'Resolution', 120);
                catch
                    saveas(fig, [base '.png']);    % fallback for older MATLAB
                end
                close(fig);
            catch me
                fprintf('  (plot skipped: %s)\n', me.message);
            end
        end
        fprintf('  Saved: %s.{csv,mat,png}\n', base);
    end
end
