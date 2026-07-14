%% ===== measureDlpGamma =====
% Measure the LightCrafter 4500's BUILT-IN (native video-mode) gamma, one
% projector channel (R / G / B) at a time, with the Thorlabs power meter in
% the optical path. Companion to Experimenter5000_v2_jktest.m: same LED-rig
% lifecycle and Stage client/server pipeline, but instead of an experiment it
% steps a full-screen solid color through fixed code levels so you can read
% wattage off the meter at each level.
%
% WHAT IT DOES
%   1. Sets the external LED driver (NeitzLedRig) to ONE fixed intensity on
%      all 4 LEDs x R/G/B and leaves it there for the whole sweep. The LED is
%      then a constant scale factor, so every wattage change you see on the
%      meter is the DLP's own code->light transfer function -- the thing we
%      are measuring.
%   2. Asks which projector channel to test (R, G or B) if not preset below.
%   3. Forces the DLP to full black and HOLDS it at (0,0,0) at the "Meter
%      ready" prompt for as long as you need: LEDs lit + every mirror off =
%      the extinction light. Zero/tare the Thorlabs meter on it (or note the
%      value to subtract by hand), THEN press Enter to start the sweep.
%   4. Shows a full-screen solid color on the DLP via Stage (stage_host in
%      rig_config.json), stepping through
%          1.5625  3.125  6.25  12.5  25  50  75  100   percent
%      LOW -> HIGH (so the radiometer's auto-range walks up from its most
%      sensitive range instead of sitting coarse and reading 0.000 at the dim
%      end), then the same list back high -> low. Every level is shown twice;
%      the top level runs twice back-to-back at the turnaround. Each level
%      holds for step_dur_s (default 5 s). For the red channel the codes sent
%      are (4,0,0), (8,0,0), (16,0,0), ... (255,0,0), then back down.
%   5. Pauses BEFORE the final step (the second pass at 1.5625 %) with the
%      DLP parked at (0,0,0) so you can RE-ZERO the meter after the bright
%      half of the sweep, then shows that last level when you press Enter
%      (rezero_before_steps adds holds before other steps too).
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
%       watts = [ ...16 readings, display order... ];  % extinction-corrected (tare, or subtract)
%       calibrateDlpResponse(seq_frac, watts)                % compare models + build LUT
%       calibrateDlpResponse(seq_frac, watts, 'write', true) % ...and install in rig_config.json
%   (seq_frac is left in the workspace by this script, and it also offers the
%   fit interactively at the end.) lcGammaCorrect reads the linearization --
%   the measured LUT, or the legacy power law -- from rig_config.json, so
%   'write' IS the redo of the linearization equation.
%   If R, G and B come back with meaningfully different curves, that is the
%   cue to extend rig_config/lcGammaCorrect to per-channel LUTs.

%% ===== PARAMETERS =====
% Scripts run in the base workspace, where last run's variables survive: a
% typo'd assignment below (e.g. a misspelled levels_pct) would otherwise be
% masked by the stale value from the previous run. Clear the sweep parameters
% up front so mistakes fail LOUDLY. (rig/client are deliberately NOT cleared
% -- the LED-driver connection is reused across runs.)
clear channel led_level step_dur_s dark_lead_s levels_pct seq_pct seq_code seq_frac nSteps rezero_before_steps
channel     = '';      % 'R' | 'G' | 'B' -- leave '' to be prompted at run time
led_level   = [];      % fixed LED-driver duty, 0..1 -- leave [] to be prompted (Enter = 0.125)
step_dur_s  = 5;       % seconds each level is held on screen
dark_lead_s = 5;       % seconds of full black at sweep start -- a ZERO CHECK: after taring
                       % at the extinction hold the meter should read ~0 here (0 = skip)
levels_pct  = [100 75 50 25 12.5 6.25 3.125 1.5625];   % linear code levels, percent of 255

% LOW -> HIGH first -- the radiometer's auto-range walks up from its most
% sensitive range (starting bright left it stuck on a coarse range, reading
% 0.000 at the dim end) -- then the same list back down (the top level runs
% twice in a row at the turnaround; the beep/console line marks the boundary).
seq_pct  = [fliplr(levels_pct), levels_pct];
seq_code = round(255 * seq_pct / 100);   % exact 8-bit codes: 4 8 16 32 64 128 191 255 ...
seq_frac = seq_code / 255;               % what Stage sends AND the x-axis of the gamma fit
nSteps   = numel(seq_code);

% Steps that get a RE-ZERO hold before they display: the sweep parks the DLP
% at (0,0,0) and waits for Enter so you can re-zero/tare the meter (auto-range
% recovery after the bright top of the sweep). Default = the final step, i.e.
% the second pass at 1.5625 %. Add indices to hold before more of the dim
% tail, e.g. nSteps-2:nSteps. [] = no holds.
rezero_before_steps = nSteps;

%% ===== INTERACTIVE SELECTIONS =====
okChan = @(c) (ischar(c) || isstring(c)) && any(strcmpi(strtrim(char(c)), {'R','G','B'}));
while ~okChan(channel)
    channel = input('Projector channel to test, R / G / B: ', 's');
end
channel = upper(strtrim(char(channel)));
chanIdx = find(channel == 'RGB');        % column in the Stage [r g b] color triple

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
fprintf('[measureDlpGamma] Connected to Stage at %s. Canvas: %d x %d\n', stageHost(), W, H);

%% ===== SWEEP =====
fprintf('\nChannel %s | LED driver fixed at %.4g | %d steps x %g s (+%g s dark check) = ~%.0f s + re-zero holds\n', ...
    channel, led_level, nSteps, step_dur_s, dark_lead_s, nSteps*step_dur_s + dark_lead_s + 2);
fprintf('%-5s  %-9s  %-5s  %-9s\n', 'step', 'percent', 'code', 'code/255');
for k = 1:nSteps
    mark = '';
    if ismember(k, rezero_before_steps), mark = '   <- re-zero hold before this step'; end
    fprintf('%-5d  %-9.4f  %-5d  %-9.6f%s\n', k, seq_pct(k), seq_code(k), seq_frac(k), mark);
end
% ---- Extinction hold: force (0,0,0) and wait as long as you need ----
% After a presentation completes the fullscreen Stage window HOLDS its last
% frame (the same behavior the AA* stimuli lean on when they append black
% end-frames to finish dark), so this 1 s black presentation leaves the DLP
% sitting at (0,0,0) indefinitely while you sit at the prompt. The LEDs are
% already lit at led_level, so the meter is now reading exactly the
% extinction light -- zero/tare the meter on it, or write the value down.
local_showSolid(client, W, H, [0 0 0], 1);
input(['\nMeter ready?  The DLP is now holding (0,0,0) -- take all the time you\n' ...
       'need to zero/tare the meter on this extinction reading (or note it to\n' ...
       'subtract by hand). Press Enter to start the sweep...'], 's');

try
    if dark_lead_s > 0
        beep;
        fprintf('[%s] DARK check (%g s) -- after the tare this should read ~0\n', ...
            char(datetime('now','Format','HH:mm:ss')), dark_lead_s);
        local_showSolid(client, W, H, [0 0 0], dark_lead_s);
    end

    t0 = tic;
    for k = 1:nSteps
        if ismember(k, rezero_before_steps)
            local_showSolid(client, W, H, [0 0 0], 1);   % park at (0,0,0): extinction again
            beep;
            input(sprintf(['\nRE-ZERO hold: the DLP is holding (0,0,0) -- re-zero/tare the meter,\n' ...
                           'then press Enter to show step %d/%d (%.4f %%, code %d)...'], ...
                          k, nSteps, seq_pct(k), seq_code(k)), 's');
        end
        colorVec = [0 0 0];
        colorVec(chanIdx) = seq_frac(k);   % RAW code fraction -- deliberately NOT lcGammaCorrect'ed
        codeTriple = double(channel == 'RGB') * seq_code(k);   % e.g. R at 75% -> [191 0 0]
        beep;
        fprintf('[%s] step %2d/%2d   %8.4f %%   code %3d   -> (%d,%d,%d)\n', ...
            char(datetime('now','Format','HH:mm:ss')), k, nSteps, seq_pct(k), seq_code(k), codeTriple);
        local_showSolid(client, W, H, colorVec, step_dur_s);
    end

    local_showSolid(client, W, H, [0 0 0], 2);   % leave the projector dark
    rig.setMode(0);                              % LEDs off
    fprintf('\n===== SWEEP DONE (%.1f s) =====\n', toc(t0));
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
% elapses inside getPlayInfo, which blocks until the presentation completes
% (same convention as playAndLogTrial).
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
        pause(durS + 0.5);             % telemetry failed -> keep the sweep paced anyway
    end
end
