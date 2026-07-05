function AAGreyScaleFullFieldNoiseFinal2026(flickerHz, stimFrames, refreshRate)
% AAGreyScaleFullFieldNoiseFinal2026
%
% Stage-VSS client/server.
%
% Full-field rectangle flickers BLACK <-> WHITE at flickerHz (square-wave).
% Right-side bar (rightmost 1/8) flickers BLUE <-> BLACK every frame.
%
% All arguments are optional. When called with no arguments, sensible
% defaults are used (standalone mode). When called from Experimenter5000,
% pass arguments explicitly.
%
% Inputs (all optional):
%   flickerHz   - flicker frequency in Hz           (default: 4)
%   stimFrames  - total number of stimulus frames    (default: 10 * refreshRate)
%   refreshRate - monitor refresh rate in Hz         (default: 60)
%
% All PropertyController callbacks use pure anonymous functions with
% precomputed lookup tables - no local subfunctions required for
% Stage client/server serialization compatibility.

    % ---- Defaults (allow standalone execution with no arguments) ----
    if nargin < 3 || isempty(refreshRate), refreshRate = 60;              end
    if nargin < 1 || isempty(flickerHz),   flickerHz   = 4;               end
    if nargin < 2 || isempty(stimFrames),  stimFrames  = 10 * refreshRate; end

    % ---- HARD REQUIREMENT: client/server pipeline ----
    client = stage.core.network.StageClient();
    client.connect(stageHost());
    canvasSize = client.getCanvasSize();
    fprintf('[AAGreyScaleFullFieldNoiseFinal2026] Connected. Canvas: %d x %d\n', canvasSize(1), canvasSize(2));

    import stage.core.*;
    import stage.builtin.stimuli.*;
    import stage.builtin.controllers.*;

    % ---- Display geometry (from server) ----
    W = canvasSize(1);
    H = canvasSize(2);

    % ---- Timing ----
    nBlackFrames  = 5;  % append black frames after stimulus
    totalFrames   = stimFrames + nBlackFrames;
    totalDuration = totalFrames / refreshRate;

    % ---- Flicker parameters ----
    framesPerHalfCycle = max(1, round(refreshRate / (2 * flickerHz)));

    % ---- Precompute ALL frame colors into a lookup table ----
    % fullFieldColors: totalFrames x 3 array
    fullFieldColors = zeros(totalFrames, 3);
    rightBarColors  = zeros(totalFrames, 3);

    for f = 1:stimFrames
        % Full field: square-wave flicker (greyscale: black <-> white)
        halfCycleIdx = floor((f - 1) / framesPerHalfCycle);
        if mod(halfCycleIdx, 2) == 0
            fullFieldColors(f, :) = [0 0 0];   % black
        else
            fullFieldColors(f, :) = [1 1 1];   % white
        end

        % Right bar: blue/black at stimulus flicker rate (sync signal)
        if mod(halfCycleIdx, 2) == 0
            rightBarColors(f, :) = [0 0 1];
        else
            rightBarColors(f, :) = [0 0 0];
        end
    end

    % ---- Gamma-correct all streamed colors for the LightCrafter -> linear light ----
    % (identity on the pure black/white/blue used here; applied for uniform
    %  correctness so any future intermediate level is displayed linearly)
    fullFieldColors = lcGammaCorrect(fullFieldColors);
    rightBarColors  = lcGammaCorrect(rightBarColors);

    % ---- Stimuli ----
    fullField = Rectangle();
    fullField.size     = [W, H];
    fullField.position = [W/2, H/2];
    fullField.color    = [0 0 0];

    rightBar = Rectangle();
    rightBar.size     = [W/8, H];
    rightBar.position = [W - W/16, H/2];
    rightBar.color    = [0 0 0];

    % ---- Controllers (pure anonymous functions - no subfunctions) ----
    fullFieldCtrl = PropertyController(fullField, 'color', ...
        @(s) fullFieldColors(min(max(floor(s.time * refreshRate) + 1, 1), totalFrames), :));

    rightBarCtrl = PropertyController(rightBar, 'color', ...
        @(s) rightBarColors(min(max(floor(s.time * refreshRate) + 1, 1), totalFrames), :));

    % ---- Log this trial to the per-day session manifest (paired to .abf by order) ----
    record = struct( ...
        'stimulus',        'AAGreyScaleFullFieldNoiseFinal2026', ...
        'stim_type',       'sq_wave', ...
        'cone_isolation',  'achromatic', ...
        'flicker_hz',      flickerHz, ...
        'refresh_rate_hz', refreshRate, ...
        'stim_frames',     stimFrames);
    manifestPath = writeStimManifest(pwd, record);
    fprintf('[AAGreyScaleFullFieldNoiseFinal2026] Logged trial -> %s\n', manifestPath);

    % ---- Presentation + player ----
    presentation = Presentation(totalDuration);
    presentation.addStimulus(fullField);
    presentation.addStimulus(rightBar);
    presentation.addController(fullFieldCtrl);
    presentation.addController(rightBarCtrl);

    player = stage.builtin.players.RealtimePlayer(presentation);
    fprintf('[AAGreyScaleFullFieldNoiseFinal2026] Playing presentation (%.1f sec)...\n', totalDuration);
    client.play(player);
    fprintf('[AAGreyScaleFullFieldNoiseFinal2026] Done.\n');
end