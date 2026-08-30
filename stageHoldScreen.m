function stageHoldScreen(client, rgb, refreshRate)
% stageHoldScreen  Put a full-screen color on the projector and LEAVE it there.
%
%   stageHoldScreen(client, rgb)                % rgb = [r g b], linear intent 0..1
%   stageHoldScreen(client, rgb, refreshRate)
%
% The Stage server has no "set background" command -- but when a presentation ends, the
% window simply stops flipping and the display HOLDS the last rendered frame (see
% RealtimePlayer.play: the loop exits after the final flip and nothing clears it). So a
% held background is made by playing a tiny two-frame presentation of the wanted color;
% the projector then shows that color until the next presentation starts.
%
% This is what paints the inter-stim (between epochs), end-of-run and GUI-startup screens.
% The color is linearized through lcGammaCorrect, same as every streamed stimulus color,
% so the value is linear light at the eye. Blocks for ~2 frames + a short telemetry read;
% the client is free for the next command when it returns.
%
% THE SYNC-BAR COLUMN (rightmost W/8) IS EXCLUDED from the full-screen value: that region
% belongs to the photodiode sync bar at all times. On a held screen the TOP segment is
% SOLID blue -- the visible "projector alive, frame held" marker (a photodiode reads DC,
% unmistakable against the frame clock's square wave during a presentation) -- and the
% middle/bottom segments are dark: no stimulus updates, stimulus OFF.

    if nargin < 3 || isempty(refreshRate) || ~isscalar(refreshRate) ...
            || ~isfinite(refreshRate) || refreshRate <= 0
        refreshRate = 60;
    end
    rgb = double(reshape(rgb, 1, []));
    if numel(rgb) ~= 3 || any(~isfinite(rgb))
        error('stageHoldScreen:badColor', 'rgb must be three finite numbers (linear 0..1).');
    end
    rgb = min(max(rgb, 0), 1);
    col = lcGammaCorrect(rgb);

    canvasSize = client.getCanvasSize();
    W = canvasSize(1); H = canvasSize(2);

    rect          = stage.builtin.stimuli.Rectangle();
    rect.size     = [W, H];
    rect.position = [W/2, H/2];
    rect.color    = col;

    % the sync-bar column, drawn OVER the background: middle/bottom dark, top solid blue
    bar          = stage.builtin.stimuli.Rectangle();
    bar.size     = [W/8, H];
    bar.position = [W - W/16, H/2];
    bar.color    = [0 0 0];

    topSeg          = stage.builtin.stimuli.Rectangle();
    topSeg.size     = [W/8, H/3];
    topSeg.position = [W - W/16, 5*H/6];
    topSeg.color    = lcGammaCorrect([0 0 1]);

    durS = 2 / refreshRate;
    presentation = stage.core.Presentation(durS);
    presentation.addStimulus(rect);
    presentation.addStimulus(bar);
    presentation.addStimulus(topSeg);

    client.play(stage.builtin.players.RealtimePlayer(presentation));
    % Wait the (tiny) duration out, then collect the play info so the connection is not
    % left mid-transaction for the next caller. Asking after completion returns promptly.
    pause(durS + 0.05);
    try
        client.getPlayInfo();
    catch
    end
end
