function AASConeIsoFullFieldNoiseStimFinal2026(flickerHz, stimFrames, refreshRate)
% AASConeIsoFullFieldNoiseStimFinal2026
%
% Stage-VSS client/server.
%
% Full-field rectangle flickers RED <-> GREEN at flickerHz (square-wave).
% Right-side bar (rightmost 1/8) flickers BLUE <-> BLACK every frame.
%
% All arguments are optional. When called with no arguments, sensible
% defaults are used (standalone mode). When called from Experimenter5000,
% pass arguments explicitly.
%
% Inputs (all optional):
%   flickerHz   - stimulus flicker frequency in Hz   (default: 4)
%   stimFrames  - total number of stimulus frames     (default: 10 * refreshRate)
%   refreshRate - monitor refresh rate in Hz          (default: 60)
%
% All PropertyController callbacks use pure anonymous functions with
% precomputed lookup tables - no local subfunctions.

    % ---- Defaults (allow standalone execution with no arguments) ----
    if nargin < 3 || isempty(refreshRate), refreshRate = 60;              end
    if nargin < 1 || isempty(flickerHz),   flickerHz   = 4;               end
    if nargin < 2 || isempty(stimFrames),  stimFrames  = 10 * refreshRate; end

    % ---- HARD REQUIREMENT: client/server pipeline ----
    client = stage.core.network.StageClient();
    client.connect();
    canvasSize = client.getCanvasSize();
    fprintf('[AASConeIsoFullFieldNoiseStimFinal2026] Connected. Canvas: %d x %d\n', canvasSize(1), canvasSize(2));

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

    % ---- Precompute ALL frame colors ----
    fullFieldColors = zeros(totalFrames, 3);
    rightBarColors  = zeros(totalFrames, 3);

    for f = 1:stimFrames
        % Full field: square-wave flicker (S-cone iso: red <-> green)
        halfCycleIdx = floor((f - 1) / framesPerHalfCycle);
        if mod(halfCycleIdx, 2) == 0
            fullFieldColors(f, :) = [1 0 0];   % red
        else
            fullFieldColors(f, :) = [0 1 0];   % green
        end

        % Right bar: blue/black at stimulus flicker rate (sync signal)
        if mod(halfCycleIdx, 2) == 0
            rightBarColors(f, :) = [0 0 1];
        else
            rightBarColors(f, :) = [0 0 0];
        end
    end

    % ---- Stimuli ----
    fullField = Rectangle();
    fullField.size     = [W, H];
    fullField.position = [W/2, H/2];
    fullField.color    = [0 0 0];

    rightBar = Rectangle();
    rightBar.size     = [W/8, H];
    rightBar.position = [W - W/16, H/2];
    rightBar.color    = [0 0 0];

    % ---- Controllers (pure anonymous functions) ----
    fullFieldCtrl = PropertyController(fullField, 'color', ...
        @(s) fullFieldColors(min(max(floor(s.time * refreshRate) + 1, 1), totalFrames), :));

    rightBarCtrl = PropertyController(rightBar, 'color', ...
        @(s) rightBarColors(min(max(floor(s.time * refreshRate) + 1, 1), totalFrames), :));

    % ---- Presentation + player ----
    presentation = Presentation(totalDuration);
    presentation.addStimulus(fullField);
    presentation.addStimulus(rightBar);
    presentation.addController(fullFieldCtrl);
    presentation.addController(rightBarCtrl);

    player = stage.builtin.players.RealtimePlayer(presentation);
    fprintf('[AASConeIsoFullFieldNoiseStimFinal2026] Playing presentation (%.1f sec)...\n', totalDuration);
    client.play(player);
    fprintf('[AASConeIsoFullFieldNoiseStimFinal2026] Done.\n');
end