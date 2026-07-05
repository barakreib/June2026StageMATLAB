%% debugStimulus  —  ISOLATE subsystems to troubleshoot OpenGL + DLP linearization
%
% Run this to exercise the visual / OpenGL path WITHOUT the rest of the rig. Set
% Debug = true and flip the Call_* flags to turn each hardware subsystem on or off.
% With Clampex absent, keep Call_ClampEx = false so NO acquisition-trigger keystrokes
% are sent. Each flag maps to a runExperiment option, so this uses the exact same
% presentation path as a real session — just with pieces switched off. The script
% prints what is on/off so nothing is happening behind your back.
%
% Needs the Stage/OpenGL server reachable (local machine or the "Stage host" in
% rig_config.json). Gamma linearization (lcGammaCorrect) is applied INSIDE each
% stimulus, so whatever you present is already corrected — measure it with a photometer
% (see RIG_REMINDER.md §1).

%% ===== DEBUG FLAGS =====
Debug = true;

if Debug
    Call_OpenGL  = true;    % present the stimulus via Stage/OpenGL   (what you are testing)
    Call_ClampEx = false;   % trigger Clampex acquisition (SendKeys)  — OFF: Clampex not present
    Call_LED     = false;   % drive the NeitzLedRig LED driver
    Check_Server = true;    % pre-flight: verify the Stage server is reachable before running
else
    % Not debugging -> full rig, everything on (a normal runExperiment call).
    Call_OpenGL = true;  Call_ClampEx = true;  Call_LED = true;  Check_Server = true;  %#ok<UNRCH>
end

%% ===== WHAT TO SHOW =====   (args differ per stimulus — see its m-file header / stimRegistry.m)
stimulus = @AAGreyScaleFullFieldNoiseFinal2026;   % e.g. @AASeededGaussianGreyScaleStimFinal2026
stimArgs = {4, 600, 60};                          % (flickerHz, stimFrames, refreshRate)
nEpochs  = 1;

%% ===== RUN =====
fprintf('[debug] OpenGL=%d  Clampex=%d  LED=%d  preflight=%d   |   Stage host: %s\n', ...
        Call_OpenGL, Call_ClampEx, Call_LED, Check_Server, stageHost());

if ~Call_OpenGL
    fprintf('[debug] Call_OpenGL = false -> nothing to present. Set it true to test OpenGL.\n');  %#ok<UNRCH>
    return;
end

protocol = struct('stim', stimulus, 'args', {stimArgs}, 'epochs', nEpochs, 'label', 'debug');
opts = struct('triggerAcq', Call_ClampEx, ...   % false -> runExperiment sends NO keystrokes to Clampex
              'preflight',  Check_Server, ...
              'preStim', 0, 'postStim', 0, 'itp', 0, 'settle', 0);
opts.leds = struct('enabled', Call_LED);        % false -> LED driver is left untouched

runExperiment(protocol, opts);
