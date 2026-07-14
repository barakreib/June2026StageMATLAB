%% ===== measureDlpGammaManualRGBW =====
% Same SELF-PACED manual-ranging sweep as measureDlpGammaManual.m, plus a
% grayscale option: the channel prompt is R / G / B / W, where W sends
% R=G=B at every level (e.g. (191,191,191)) so you can measure the DLP's
% composite white transfer function alongside the per-channel ones.
%
% Every level waits for YOU: each step paints a full-screen solid color on
% the DLP and then HOLDS it there indefinitely (the fullscreen Stage window
% keeps its last frame between presentations) while you set the Thorlabs
% meter's range by hand, let it settle, and note the wattage. Press Enter to
% advance. Nothing is timed.
%
% WHAT IT DOES
%   1. Sets the external LED driver (NeitzLedRig) to ONE fixed intensity on
%      all 4 LEDs x R/G/B and leaves it there for the whole sweep. The LED is
%      then a constant scale factor, so every wattage change you see on the
%      meter is the DLP's own code->light transfer function -- the thing we
%      are measuring.
%   2. Asks which projector channel to test: R, G, B, or W (W = grayscale,
%      all three channels driven together at the same code).
%   3. Forces the DLP to full black and HOLDS it at (0,0,0) at the "Meter
%      ready" prompt for as long as you need: LEDs lit + every mirror off =
%      the extinction light. Zero/tare the Thorlabs meter on it (or note the
%      value to subtract by hand) -- this is also your dark reading -- THEN
%      press Enter to show the first level.
%   4. Steps a full-screen solid color through the levels_pct list LOW ->
%      HIGH, then the same list back down (every level shown twice; the top
%      level twice back-to-back at the turnaround). Each level HOLDS until
%      you press Enter. For the red channel the codes sent are (32,0,0) ...
%      (255,0,0); for W they are (32,32,32) ... (255,255,255); etc.
%   5. Before the final step (the second pass at the dimmest level) it parks
%      the DLP at (0,0,0) again so you can RE-ZERO the meter after the bright
%      half of the sweep (rezero_before_steps adds holds before other steps).
%   No sync bar, no manifest row: the whole screen must be the test color
%   (the meter integrates everything), and this is a calibration sweep, not a
%   recorded trial.
%
% !!! RAW CODES ON PURPOSE -- NO lcGammaCorrect() IN THIS SCRIPT !!!
%   The point is to measure the projector's native gamma, so levels are sent
%   as raw code fractions (code/255), exactly like the pre-linearization days.
%   Adding the usual lcGammaCorrect() pre-distortion here would flatten the
%   very curve we are trying to measure.
%
% AFTERWARDS (re-deriving the linearization equation)
%   Note the meter wattage at each step (the console prints + beeps exactly
%   when each level comes up). Then fit with the existing tool:
%       watts = [ ...readings, display order... ];      % extinction-corrected (tare, or subtract)
%       calibrateDlpResponse(seq_frac, watts)                % compare models + build LUT
%       calibrateDlpResponse(seq_frac, watts, 'write', true) % ...and install in rig_config.json
%   (seq_frac is left in the workspace by this script, and it also offers the
%   fit interactively at the end.) lcGammaCorrect reads the linearization --
%   the measured LUT, or the legacy power law -- from rig_config.json, so
%   'write' IS the redo of the linearization equation.
%   NOTE on W: white is the SUM of the R+G+B field outputs, so its curve only
%   matches the per-channel curves if all three channels share one shape. Fit
%   the W sweep as a cross-check against the per-channel fits, and only
%   consider installing a W-derived curve if R, G and B individually agree.

%% ===== PARAMETERS =====
% Scripts run in the base workspace, where last run's variables survive: a
% typo'd assignment below (e.g. a misspelled levels_pct) would otherwise be
% masked by the stale value from the previous run. Clear the sweep parameters
% up front so mistakes fail LOUDLY. (rig/client are deliberately NOT cleared
% -- the LED-driver connection is reused across runs.)
clear channel led_level step_dur_s levels_pct seq_pct seq_code seq_frac nSteps rezero_before_steps
channel     = '';      % 'R' | 'G' | 'B' | 'W' -- leave '' to be prompted at run time
led_level   = [];      % fixed LED-driver duty, 0..1 -- leave [] to be prompted (Enter = 0.125)
step_dur_s  = 1;       % seconds the transition presentation runs; the level then HOLDS
                       % indefinitely at the prompt, so this only paces the changeover
%levels_pct  = [100 75 50 25 12.5 6.25 3.125 1.5625];   % linear code levels, percent of 255
%levels_pct  = [100 75 50 25 12.5];   % linear code levels, percent of 255
%levels_pct  = [100 95 90 85 80 75 70 65 60 55 50 25 12.5];   % linear code levels, percent of 255
levels_pct  = [100 95 90 85 80 75 70 65 60 55 50 25 12.5 6.25 3.125];   % linear code levels, percent of 255


% LOW -> HIGH first, then the same list back down (the top level runs twice
% in a row at the turnaround; the beep/console line marks the boundary).
seq_pct  = [fliplr(levels_pct), levels_pct];
seq_code = round(255 * seq_pct / 100);   % exact 8-bit codes, e.g. 32 64 128 191 255 ...
seq_frac = seq_code / 255;               % what Stage sends AND the x-axis of the gamma fit
nSteps   = numel(seq_code);

% Steps that get a RE-ZERO hold before they display: the sweep parks the DLP
% at (0,0,0) and waits for Enter so you can re-zero/tare the meter (zero
% drift check after the bright top of the sweep). Default = the final step,
% i.e. the second pass at the dimmest level. Add indices to hold before more
% of the dim tail, e.g. nSteps-2:nSteps. [] = no holds.
rezero_before_steps = nSteps;

%% ===== INTERACTIVE SELECTIONS =====
okChan = @(c) (ischar(c) || isstring(c)) && any(strcmpi(strtrim(char(c)), {'R','G','B','W'}));
while ~okChan(channel)
    channel = input('Projector channel to test, R / G / B / W (W = grayscale R=G=B): ', 's');
end
channel = upper(strtrim(char(channel)));
if channel == 'W'
    chanMask = [1 1 1];                  % grayscale: drive R, G and B together
else
    chanMask = double(channel == 'RGB'); % one-hot column of the Stage [r g b] triple
end

while isempty(led_level) || ~isnumeric(led_level) || ~isscalar(led_level) ...
        || ~isfinite(led_level) || led_level < 0 || led_level > 1
    led_level = input('Fixed LED-driver level, 0..1 [Enter = 0.125]: ');
    if isempty(led_level), led_level = 0.125; end
end

%% ===== LED DRIVER: FIXED FOR THE WHOLE SWEEP =====
% Same session-shared `rig` lifecycle as Experimenter5000_v2_jktest.m: reuse a
% live rig, rebuild a stale one, `clear rig` when done closes the port.
if isempty(which('NeitzLedRig'))         % ml-uled lives next to this file
    addpath(fullfile(fileparts(mfilename('fullpath')), 'ml-uled'));
end
if ~(exist('rig','var') && isa(rig,'NeitzLedRig') && isvalid(rig) && rig.isConnected())
    clear rig                            % drop any stale handle, then connect:
    rig = NeitzLedRig(char(loadRigConfig('led_port', 'COM3')));
end

% All 12 channels (4 LEDs x r/g/b) to the SAME fixed level -- the LED driver
% does NOT change during the measurement.
for led = 0:3
    for c = 'rgb'
        rig.setIntensity(led, c, led_level);
    end
end
rig.setMode(3);                          % video RGB w/ sync -- projector i_RGB picks the field

%% ===== STAGE: CONNECT =====
client = stage.core.network.StageClient();
client.connect(stageHost());             % stage_host from rig_config.json
canvasSize = client.getCanvasSize();
W = canvasSize(1);  H = canvasSize(2);
fprintf('[measureDlpGammaManualRGBW] Connected to Stage at %s. Canvas: %d x %d\n', stageHost(), W, H);

%% ===== SWEEP (SELF-PACED) =====
fprintf('\nChannel %s | LED driver fixed at %.4g | %d steps, self-paced (Enter advances)\n', ...
    channel, led_level, nSteps);
fprintf('%-5s  %-9s  %-5s  %-9s\n', 'step', 'percent', 'code', 'code/255');
for k = 1:nSteps
    mark = '';
    if ismember(k, rezero_before_steps), mark = '   <- re-zero hold before this step'; end
    fprintf('%-5d  %-9.4f  %-5d  %-9.6f%s\n', k, seq_pct(k), seq_code(k), seq_frac(k), mark);
end

% ---- Extinction hold: force (0,0,0) and wait as long as you need ----
% After a presentation completes the fullscreen Stage window HOLDS its last
% frame, so this short black presentation leaves the DLP sitting at (0,0,0)
% indefinitely while you sit at the prompt. The LEDs are already lit at
% led_level, so the meter is now reading exactly the extinction light --
% zero/tare the meter on it, or write the value down (this is also your dark
% reading, on the meter's most sensitive range).
local_showSolid(client, W, H, [0 0 0], 1);
input(sprintf(['\nMeter ready?  The DLP is now holding (0,0,0) -- take all the time you\n' ...
               'need to zero/tare the meter on this extinction reading (or note it to\n' ...
               'subtract by hand). Press Enter to show step 1/%d (%.4f %%, code %d)...'], ...
              nSteps, seq_pct(1), seq_code(1)), 's');

try
    t0 = tic;
    for k = 1:nSteps
        if ismember(k, rezero_before_steps)
            local_showSolid(client, W, H, [0 0 0], 1);   % park at (0,0,0): extinction again
            beep;
            input(sprintf(['\nRE-ZERO hold: the DLP is holding (0,0,0) -- re-zero/tare the meter,\n' ...
                           'then press Enter to show step %d/%d (%.4f %%, code %d)...'], ...
                          k, nSteps, seq_pct(k), seq_code(k)), 's');
        end
        colorVec   = seq_frac(k) * chanMask;   % RAW code fraction -- deliberately NOT lcGammaCorrect'ed
        codeTriple = seq_code(k) * chanMask;   % e.g. R at 75% -> (191,0,0); W -> (191,191,191)
        beep;
        fprintf('[%s] step %2d/%2d   %8.4f %%   code %3d   -> (%d,%d,%d)\n', ...
            char(datetime('now','Format','HH:mm:ss')), k, nSteps, seq_pct(k), seq_code(k), codeTriple);
        local_showSolid(client, W, H, colorVec, step_dur_s);   % paints the level; it then HOLDS
        if k < nSteps
            input(sprintf(['    Level is up and HOLDING -- set the range, note the reading, then\n' ...
                           '    press Enter for step %d/%d (%.4f %%, code %d)...'], ...
                          k+1, nSteps, seq_pct(k+1), seq_code(k+1)), 's');
        else
            input('    Level is up and HOLDING -- note the final reading, then press Enter to finish...', 's');
        end
    end

    local_showSolid(client, W, H, [0 0 0], 2);   % leave the projector dark
    rig.setMode(0);                              % LEDs off
    fprintf('\n===== SWEEP DONE (%.1f s incl. your holds) =====\n', toc(t0));
catch sweepErr
    try, rig.setMode(0); catch, end              % never leave the LEDs lit on an error
    rethrow(sweepErr);
end

%% ===== FIT THE BUILT-IN GAMMA =====
fprintf('Input fractions in display order (kept in the workspace as seq_frac):\n');
fprintf('  seq_frac = %s;\n\n', mat2str(seq_frac, 6));
fprintf(['To fit later (use readings as-is if you tared at the extinction hold;\n' ...
         'otherwise subtract your extinction watts from each one first):\n' ...
         '  watts = [ ...your %d meter readings, display order... ];\n' ...
         '  calibrateDlpResponse(seq_frac, watts)                 %% compare models + build LUT\n' ...
         '  calibrateDlpResponse(seq_frac, watts, ''write'', true)  %% ...and install in rig_config.json\n\n'], nSteps);

watts = input(sprintf(['Or enter the %d readings now as a vector (an expression is fine,\n' ...
                       'e.g. [w1 w2 ...] - extinctionW), or press Enter to skip: '], nSteps));
if ~isempty(watts)
    watts = watts(:).';
    if numel(watts) == nSteps
        calibrateDlpResponse(seq_frac, watts);   % model comparison + monotone LUT (repeats averaged)
        fprintf('Looks right? Install it with:  calibrateDlpResponse(seq_frac, watts, ''write'', true)\n');
    else
        fprintf(2, 'Expected %d readings, got %d -- not fitting. (Kept in workspace as `watts`.)\n', ...
            nSteps, numel(watts));
    end
end

%% ===== local functions (scripts allow these at end-of-file) =====
function local_showSolid(client, W, H, colorVec, durS)
% One full-screen solid-color presentation, blocking until it finishes.
% client.play returns immediately (server ACKs, THEN renders); the wall time
% elapses inside getPlayInfo, which blocks until the presentation completes.
% The window then HOLDS the last frame until the next play -- that hold is
% what lets every level (and the black parks) wait for the user.
    fullField          = stage.builtin.stimuli.Rectangle();
    fullField.size     = [W, H];
    fullField.position = [W/2, H/2];
    fullField.color    = colorVec;

    presentation = stage.core.Presentation(durS);
    presentation.addStimulus(fullField);

    player = stage.builtin.players.RealtimePlayer(presentation);
    client.play(player);
    try
        client.getPlayInfo();          % BLOCKS for durS while the server renders
    catch
        pause(durS + 0.5);             % telemetry failed -> keep the changeover paced anyway
    end
end
