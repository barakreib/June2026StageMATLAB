function AAJitteringCircleStimulusFinal(rfCenter, rfRadius, circleRadius, walkSpeed, stimFrames, refreshRate, colorMode)
% AAJitteringCircleStimulusFinal
%
% Stage-VSS stimulus: A single circle performing a random walk (jitter)
% around a target Receptive Field (RF) center.
%
% Parameters are resolved in 3-tier priority:
%   1. Explicit function arguments
%   2. Base workspace variables (set by Experimenter5000 or user)
%   3. Hard-coded defaults
%
% Workspace variables consumed:
%   rfCenter      - [x, y] in pixels
%   rfRadius      - radius in pixels (used for scaling/reference)
%   circleRadius  - stimulus circle radius in pixels
%   walkSpeed     - speed of jitter in pixels/second
%   stim_dur      - converted to stimFrames (stim_dur * refreshRate)
%   refreshRate   - display refresh rate (Hz)
%   colorMode     - 'Greyscale' or 'S-Cone Isolating'
%
% All PropertyController callbacks use pure anonymous functions with
% precomputed lookup tables for Stage serialization compatibility.

    % ---- Resolve parameters: explicit arg > workspace > default ----
    refreshRate  = resolveParam('refreshRate', nargin >= 6, refreshRate, 60);
    stim_dur_ws  = resolveParam('stim_dur', false, [], 10);
    stimFrames   = resolveParam('stimFrames', nargin >= 5, stimFrames, stim_dur_ws * refreshRate);
    walkSpeed    = resolveParam('walkSpeed', nargin >= 4, walkSpeed, 50);
    circleRadius = resolveParam('circleRadius', nargin >= 3, circleRadius, 150);
    rfRadius     = resolveParam('rfRadius', nargin >= 2, rfRadius, 80);
    rfCenter     = resolveParam('rfCenter', nargin >= 1, rfCenter, [570, 456]);
    colorMode    = resolveParam('colorMode', nargin >= 7, colorMode, 'Greyscale');

    % ---- HARD REQUIREMENT: client/server pipeline ----
    client = stage.core.network.StageClient();
    client.connect(stageHost());
    canvasSize = client.getCanvasSize();
    fprintf('[AAJitteringCircle] Connected. Canvas: %d x %d\n', canvasSize(1), canvasSize(2));

    import stage.core.*;
    import stage.builtin.stimuli.*;
    import stage.builtin.controllers.*;

    W = canvasSize(1);
    H = canvasSize(2);

    % ---- Timing ----
    totalFrames = stimFrames;
    totalDuration = totalFrames / refreshRate;

    % ---- Precompute Jitter (Random Walk) ----
    % The circle jitters via an Ornstein-Uhlenbeck process:
    % Step size per frame = walkSpeed / refreshRate * N(0,1)
    % A small spring constant pulls it back toward rfCenter to prevent drift.

    posX = zeros(totalFrames, 1);
    posY = zeros(totalFrames, 1);

    curX = rfCenter(1);
    curY = rfCenter(2);

    % Step standard deviation
    stepSigma = walkSpeed / refreshRate;
    % Spring constant (0.02 means it pulls back 2% of the distance to center each frame)
    k = 0.02;

    % Seed the walk for reproducibility
    stream = RandStream('mt19937ar', 'Seed', 2);

    for f = 1:totalFrames
        % Update position with random walk + spring back to center.
        % Inverse-CDF normals (not randn) so the walk reproduces from the seed in
        % Python. Uses erfinv (base MATLAB), NOT norminv (Stats Toolbox):
        % sqrt(2)*erfinv(2*u-1) == norminv(u) exactly.
        dx = stepSigma * sqrt(2) * erfinv(2 * rand(stream) - 1);
        dy = stepSigma * sqrt(2) * erfinv(2 * rand(stream) - 1);

        curX = curX + dx - k * (curX - rfCenter(1));
        curY = curY + dy - k * (curY - rfCenter(2));

        posX(f) = curX;
        posY(f) = curY;
    end

    % ---- Precompute Right Bar Colors ----
    rightBarColors = zeros(totalFrames, 3);
    for f = 1:totalFrames
        if mod(f, 2) == 1
            rightBarColors(f,:) = [0 0 1];
        else
            rightBarColors(f,:) = [0 0 0];
        end
    end

    % ---- Determine Color ----
    if strcmpi(colorMode, 'S-Cone Isolating')
        % S-Cone: R=1, G=0, B=0 (following logic from other S-cone scripts)
        circColor = [1 0 0];
    else
        % Greyscale: White
        circColor = [1 1 1];
    end

    % ---- Gamma-correct all streamed colors for the LightCrafter -> linear light ----
    % (identity on the pure primaries used here; applied for uniform correctness)
    circColor      = lcGammaCorrect(circColor);
    rightBarColors = lcGammaCorrect(rightBarColors);

    % ---- Debug prints ----
    fprintf('\n--- Stage Jittering Circle Stimulus ---\n');
    fprintf('RF Center: (%.1f, %.1f), Radius: %.1f px\n', rfCenter(1), rfCenter(2), rfRadius);
    fprintf('Circle Radius: %.1f px, Walk Speed: %.1f px/s\n', circleRadius, walkSpeed);
    fprintf('Stim Frames: %d, Total Duration: %.2f s\n', stimFrames, totalDuration);
    fprintf('Color Mode: %s\n', colorMode);

    % ---- Stimuli ----
    % Background
    background = Rectangle();
    background.size = [W, H];
    background.position = [W/2, H/2];
    background.color = [0 0 0]; % Black background

    % The Jittering Circle
    circle = Ellipse();
    circle.radiusX = circleRadius;
    circle.radiusY = circleRadius;
    circle.color   = circColor;
    circle.position = rfCenter;

    % Sync Bar
    rightBar = Rectangle();
    rightBar.size     = [W/8, H];
    rightBar.position = [W - W/16, H/2];
    rightBar.color    = [0 0 0];

    % ---- Controllers ----
    posCtrl = PropertyController(circle, 'position', ...
        @(s) [posX(min(max(s.frame + 1, 1), totalFrames)), ...
              posY(min(max(s.frame + 1, 1), totalFrames))]);

    rightBarCtrl = PropertyController(rightBar, 'color', ...
        @(s) rightBarColors(min(max(s.frame + 1, 1), totalFrames), :));

    % ---- Log this trial to the per-day session manifest (paired to .abf by order) ----
    % Walk is an OU process; seed 2 + these params + the inverse-CDF draw order let
    % the analysis reproduce the exact trajectory (mt19937ar rand() matches numpy).
    if strcmpi(colorMode, 'S-Cone Isolating'), coneIso = 'S'; else, coneIso = 'achromatic'; end
    record = struct( ...
        'stimulus',        'AAJitteringCircleStimulusFinal', ...
        'stim_type',       'jitter', ...
        'cone_isolation',  coneIso, ...
        'seed',            2, ...
        'walk_speed',      walkSpeed, ...
        'spring_k',        k, ...
        'circle_radius',   circleRadius, ...
        'rf_center_x',     rfCenter(1), ...
        'rf_center_y',     rfCenter(2), ...
        'rf_radius',       rfRadius, ...
        'refresh_rate_hz', refreshRate, ...
        'stim_frames',     stimFrames, ...
        'noise_method',    'mt19937ar+invCDF', ...
        'fill_order',      'F');
    % Manifest logged AFTER play (with frame-sync telemetry) by playAndLogTrial, below.

    % ---- Presentation ----
    presentation = Presentation(totalDuration);
    presentation.addStimulus(background);
    presentation.addStimulus(circle);
    presentation.addStimulus(rightBar);

    presentation.addController(posCtrl);
    presentation.addController(rightBarCtrl);

    player = stage.builtin.players.RealtimePlayer(presentation);
    fprintf('[AAJitteringCircle] Playing...\n');
    playAndLogTrial(client, player, pwd, record, refreshRate, totalFrames);
    fprintf('[AAJitteringCircle] Done.\n');
end
