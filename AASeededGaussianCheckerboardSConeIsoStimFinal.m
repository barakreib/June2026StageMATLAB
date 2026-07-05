function AASeededGaussianCheckerboardSConeIsoStimFinal(seed, mu, sigma, flickerHz, stimFrames, refreshRate)
% AASeededGaussianCheckerboardSConeIsoStimFinal
%
% Stage-VSS client/server, checkerboard Image stimulus.
% S-cone iso Gaussian noise per-square: R=v, G=1-v, B=0
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
%   flickerHz   - noise update frequency in Hz        (default: 4)
%   stimFrames  - total number of stimulus frames     (default: 10 * refreshRate)
%   refreshRate - monitor refresh rate in Hz          (default: 60)
%
% All callbacks use pure anonymous functions with precomputed lookup
% tables for Stage serialization compatibility. No local subfunctions.

    % ---- Defaults (allow standalone execution with no arguments) ----
    if nargin < 6 || isempty(refreshRate), refreshRate = 60;              end
    if nargin < 1 || isempty(seed),        seed        = 2;               end
    if nargin < 2 || isempty(mu),          mu          = 0.5;             end
    if nargin < 3 || isempty(sigma),       sigma       = 0.3;             end
    if nargin < 4 || isempty(flickerHz),   flickerHz   = 4;               end
    if nargin < 5 || isempty(stimFrames),  stimFrames  = 10 * refreshRate; end

    % Convert flickerHz to frames between updates
    updateEveryNFrames = max(1, round(refreshRate / (2 * flickerHz)));

    % ---- HARD REQUIREMENT: client/server pipeline ----
    client = stage.core.network.StageClient();
    client.connect(stageHost());
    canvasSize = client.getCanvasSize();
    fprintf('[AASeededGaussianCheckerboardSConeIsoStimFinal] Connected. Canvas: %d x %d\n', canvasSize(1), canvasSize(2));

    import stage.core.*;
    import stage.builtin.stimuli.*;
    import stage.builtin.controllers.*;

    % ---- Display geometry ----
    W = canvasSize(1);
    H = canvasSize(2);

    % ---- Parameters ----
    checksX = 40;
    checksY = 32;

    nBlackFrames  = 5;  % append black frames after stimulus
    totalFrames   = stimFrames + nBlackFrames;
    totalDuration = totalFrames / refreshRate;
    nUpdates = ceil(stimFrames / updateEveryNFrames);

    % ---- Precompute noise ----
    stream = RandStream('mt19937ar', 'Seed', seed);
    % Inverse-CDF normals (not randn): uniform draws from mt19937ar rand() match
    % numpy's RandomState exactly, so this noise reproduces from the seed in the
    % Python analysis suite. Uses erfinv (base MATLAB), NOT norminv (Stats Toolbox):
    % sqrt(2)*erfinv(2*u-1) == norminv(u) exactly, so no toolbox is required.
    noiseVals = mu + sigma .* (sqrt(2) .* erfinv(2 .* rand(stream, checksY, checksX, nUpdates) - 1));
    noiseVals = min(max(noiseVals, 0), 1);

    % ---- Precompute per-update S-cone iso images ----
    rgbImages = cell(nUpdates, 1);
    for u = 1:nUpdates
        v = noiseVals(:, :, u);
        img = zeros(checksY, checksX, 3, 'uint8');
        img(:,:,1) = uint8(round(255 * lcGammaCorrect(v)));        % R = v     (gamma-corrected)
        img(:,:,2) = uint8(round(255 * lcGammaCorrect(1 - v)));    % G = 1 - v (gamma-corrected)
        img(:,:,3) = uint8(0);                                     % B = 0
        rgbImages{u} = img;
    end

    blackRGB = zeros(checksY, checksX, 3, 'uint8');

    % ---- Precompute imageMatrix for EVERY frame ----
    allFrameImages = cell(totalFrames, 1);
    for f = 1:stimFrames
        updateIdx = min(max(floor((f - 1) / updateEveryNFrames) + 1, 1), nUpdates);
        allFrameImages{f} = rgbImages{updateIdx};
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

    % ---- Log this trial to the per-day session manifest (seed + params only) ----
    % No per-cell values are stored: the Neitz_Analysis_Suite regenerates the exact
    % (checks_y x checks_x x n_updates) noise from `seed` via reproduce_noise, and the
    % per-channel gamma-corrected codes via gamma_adjust (S-iso: R=v, G=1-v, B=0).
    record = struct( ...
        'stimulus',              'AASeededGaussianCheckerboardSConeIsoStimFinal', ...
        'stim_type',             'checkerboard', ...
        'cone_isolation',        'S', ...
        'seed',                  seed, ...
        'mu',                    mu, ...
        'sigma',                 sigma, ...
        'checks_x',              checksX, ...
        'checks_y',              checksY, ...
        'n_updates',             nUpdates, ...
        'update_every_n_frames', updateEveryNFrames, ...
        'flicker_hz',            flickerHz, ...
        'noise_update_hz',       refreshRate / updateEveryNFrames, ...
        'refresh_rate_hz',       refreshRate, ...
        'stim_frames',           stimFrames, ...
        'gamma',                 loadRigConfig('gamma', 2.2056), ...
        'noise_method',          'mt19937ar+invCDF', ...
        'fill_order',            'F');
    manifestPath = writeStimManifest(pwd, record);
    fprintf('[AASeededGaussianCheckerboardSConeIsoStimFinal] Logged trial -> %s\n', manifestPath);

    % ---- Debug prints ----
    fprintf('\n--- Stage Checkerboard Gaussian S-Cone Isolation Stimulus ---\n');
    fprintf('Canvas: %d x %d, checks: %dx%d\n', W, H, checksX, checksY);
    fprintf('stimFrames: %d, totalDuration: %.2f s\n', stimFrames, totalDuration);
    fprintf('flickerHz: %d, updateEveryNFrames: %d, nUpdates: %d\n', flickerHz, updateEveryNFrames, nUpdates);
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
        @(s) allFrameImages{min(max(s.frame + 1, 1), totalFrames)});

    rightBarCtrl = PropertyController(rightBar, 'color', ...
        @(s) rightBarColors(min(max(s.frame + 1, 1), totalFrames), :));

    % ---- Presentation + player ----
    presentation = Presentation(totalDuration);
    presentation.addStimulus(checkerboard);
    presentation.addStimulus(rightBar);
    presentation.addController(imageCtrl);
    presentation.addController(rightBarCtrl);

    player = stage.builtin.players.RealtimePlayer(presentation);
    fprintf('[AASeededGaussianCheckerboardSConeIsoStimFinal] Playing (%.1f sec)...\n', totalDuration);
    client.play(player);
    fprintf('[AASeededGaussianCheckerboardSConeIsoStimFinal] Done.\n');
end