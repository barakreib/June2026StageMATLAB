function AASeededGaussianSConeIsoStimFinal2026(seed, mu, sigma, flickerHz, stimFrames, refreshRate)
% AASeededGaussianSConeIsoStimFinal2026
%
% Stage-VSS client/server, full-field Image stimulus.
% Full-field: seeded Gaussian noise -> R=v, G=1-v, B=0 (S-cone iso)
% Implemented as a 1x1 Image with imageMatrix controller.
%
% Right-side bar (1/8 width) flickers BLUE <-> BLACK every frame.
%
% All arguments are optional. When called with no arguments, sensible
% defaults are used (standalone mode). When called from Experimenter5000,
% pass arguments explicitly.
%
% Inputs (all optional):
%   seed        - RNG seed for reproducibility        (default: 2)
%   mu          - Gaussian mean                       (default: 0.5)
%   sigma       - Gaussian standard deviation         (default: 0.3)
%   flickerHz   - noise update rate in Hz             (default: 4)
%   stimFrames  - total number of stimulus frames     (default: 10 * refreshRate)
%   refreshRate - monitor refresh rate in Hz          (default: 60)
%
% All callbacks use pure anonymous functions with precomputed lookup
% tables for Stage serialization compatibility.

    % ---- Defaults (allow standalone execution with no arguments) ----
    if nargin < 6 || isempty(refreshRate), refreshRate = 60;              end
    if nargin < 1 || isempty(seed),        seed        = 2;               end
    if nargin < 2 || isempty(mu),          mu          = 0.5;             end
    if nargin < 3 || isempty(sigma),       sigma       = 0.3;             end
    if nargin < 4 || isempty(flickerHz),   flickerHz   = 4;               end
    if nargin < 5 || isempty(stimFrames),  stimFrames  = 10 * refreshRate; end

    % ---- HARD REQUIREMENT: client/server pipeline ----
    client = stage.core.network.StageClient();
    client.connect();
    canvasSize = client.getCanvasSize();
    fprintf('[AASeededGaussianSConeIsoStimFinal2026] Connected. Canvas: %d x %d\n', canvasSize(1), canvasSize(2));

    import stage.core.*;
    import stage.builtin.stimuli.*;
    import stage.builtin.controllers.*;

    % ---- Display geometry ----
    W = canvasSize(1);
    H = canvasSize(2);

    % ---- Parameters ----
    checksX = 1;
    checksY = 1;

    updateEveryNFrames = max(1, round(refreshRate / (2 * flickerHz)));

    nBlackFrames  = 5;  % append black frames after stimulus
    totalFrames   = stimFrames + nBlackFrames;
    totalDuration = totalFrames / refreshRate;
    nUpdates = ceil(stimFrames / updateEveryNFrames);

    % ---- Precompute noise ----
    stream = RandStream('mt19937ar', 'Seed', seed);
    noiseVals = mu + sigma .* randn(stream, checksY, checksX, nUpdates);
    noiseVals = min(max(noiseVals, 0), 1);

    % ---- Precompute imageMatrix for EVERY frame ----
    blackRGB = zeros(checksY, checksX, 3, 'uint8');
    allFrameImages = cell(totalFrames, 1);

    for f = 1:stimFrames
        updateIdx = min(max(floor((f - 1) / updateEveryNFrames) + 1, 1), nUpdates);
        v = noiseVals(:, :, updateIdx);
        img = zeros(checksY, checksX, 3, 'uint8');
        img(:,:,1) = uint8(round(255 * lcGammaCorrect(v)));        % R = v     (gamma-corrected)
        img(:,:,2) = uint8(round(255 * lcGammaCorrect(1 - v)));    % G = 1 - v (gamma-corrected)
        img(:,:,3) = uint8(0);                                     % B = 0
        allFrameImages{f} = img;
    end

    % ---- Append post-stimulus black frames ----
    for f = stimFrames+1:totalFrames
        allFrameImages{f} = blackRGB;
    end

    % ---- Precompute right bar colors (flickers at noise update rate) ----
    rightBarColors = zeros(totalFrames, 3);
    for f = 1:stimFrames
        updateIdx = floor((f - 1) / updateEveryNFrames);
        if mod(updateIdx, 2) == 0
            rightBarColors(f,:) = [0 0 1];
        else
            rightBarColors(f,:) = [0 0 0];
        end
    end

    % ---- Write stimulus log CSV (linear values + gamma-adjusted values sent) ----
    % S-iso: R=v, G=1-v, B=0. Correction is per channel, so R_adj+G_adj != 1
    % (codes do not sum to 255) -- that is required to keep the EMITTED light
    % linear, i.e. R_light+G_light = 1 for every v.
    logData = zeros(stimFrames, 8);
    for f = 1:stimFrames
        updateIdx = min(max(floor((f - 1) / updateEveryNFrames) + 1, 1), nUpdates);
        v   = noiseVals(1, 1, updateIdx);
        rgb = [v, 1 - v, 0];
        adj = lcGammaCorrect(rgb);
        logData(f, :) = [f - 1, (f - 1) / refreshRate, rgb, adj];
    end
    logHeader = {'frame', 'time_s', 'R', 'G', 'B', 'R_adj', 'G_adj', 'B_adj'};
    logMeta = { ...
        'stimulus',              'AASeededGaussianSConeIsoStimFinal2026'; ...
        'color_mode',            's-cone-iso'; ...
        'seed',                  seed; ...
        'mu',                    mu; ...
        'sigma',                 sigma; ...
        'flicker_update_hz',     flickerHz; ...
        'update_every_n_frames', updateEveryNFrames; ...
        'refresh_rate_hz',       refreshRate; ...
        'stim_frames',           stimFrames; ...
        'stim_duration_s',       stimFrames / refreshRate; ...
        'checks_x',              checksX; ...
        'checks_y',              checksY; ...
        'gamma',                 2.2056; ...
        'adj_scale',             'normalized_0to1_code_is_round255xadj'; ...
        'row_cadence',           'per_frame'; ...
        'created',               datestr(now, 'yyyy-mm-dd HH:MM:SS'); ...
        'data_start_row',        0 };
    logPath = writeStimLog(pwd, logMeta, logHeader, logData);
    fprintf('[AASeededGaussianSConeIsoStimFinal2026] Wrote stimulus log: %s\n', logPath);

    % ---- Debug prints ----
    fprintf('\n--- Stage Full-Field Gaussian S-Cone Isolation Stimulus ---\n');
    fprintf('Canvas: %d x %d, refreshRate: %d Hz\n', W, H, refreshRate);
    fprintf('stimFrames: %d, totalDuration: %.2f s\n', stimFrames, totalDuration);
    fprintf('updateEveryNFrames: %d, nUpdates: %d\n', updateEveryNFrames, nUpdates);
    fprintf('seed: %d, mu: %.3f, sigma: %.3f\n', seed, mu, sigma);

    % ---- Stimuli ----
    checkerboard = Image(blackRGB);
    checkerboard.position = [W/2, H/2];
    checkerboard.size = [W, H];
    checkerboard.setMinFunction(GL.NEAREST);
    checkerboard.setMagFunction(GL.NEAREST);

    rightBar = Rectangle();
    rightBar.size     = [W/8, H];
    rightBar.position = [W - W/16, H/2];
    rightBar.color    = [0 0 0];

    % ---- Controllers (pure anonymous functions - NO subfunctions) ----
    imageCtrl = PropertyController(checkerboard, 'imageMatrix', ...
        @(s) allFrameImages{min(max(floor(s.time * refreshRate) + 1, 1), totalFrames)});

    rightBarCtrl = PropertyController(rightBar, 'color', ...
        @(s) rightBarColors(min(max(floor(s.time * refreshRate) + 1, 1), totalFrames), :));

    % ---- Presentation + player ----
    presentation = Presentation(totalDuration);
    presentation.addStimulus(checkerboard);
    presentation.addStimulus(rightBar);
    presentation.addController(imageCtrl);
    presentation.addController(rightBarCtrl);

    player = stage.builtin.players.RealtimePlayer(presentation);
    fprintf('[AASeededGaussianSConeIsoStimFinal2026] Playing (%.1f sec)...\n', totalDuration);
    client.play(player);
    fprintf('[AASeededGaussianSConeIsoStimFinal2026] Done.\n');
end