%% ===== Experimenter5000_v2 =====
% Same as Experimenter5000 but passes all parameters explicitly to
% stimulus functions. No resolveParam.m dependency required.
%
% SETUP: Uncomment the stimulus you want to run in the trial loop below.
%        Adjust parameters in this section to control the experiment.

%% ===== EXPERIMENT PARAMETERS =====
stim_dur    = 600;       % stimulus duration (seconds)
pre_stim    = 2;        % pre-stimulus window (seconds)
itp         = 3;        % inter-trial pause (seconds)
nTrials     = 1;        % number of trials
refreshRate = 60;       % monitor refresh rate (Hz) - always 60

% Derived timing
stimFrames = stim_dur * refreshRate;   % total stimulus frames

% Stimulus flicker rate (how fast the stimulus content changes)
flickerHz = 0.1;          % stimulus update frequency (Hz)


if ~(exist('rig','var') && isa(rig,'NeitzLedRig') && isvalid(rig) && rig.isConnected())
    clear rig                                   % drop any stale handle, then connect:
    rig = NeitzLedRig('COM3');                  % this rig's port (rig_config led_port)
    % rig = NeitzLedRig();                      % AUTO-probe fallback (slower)
    % rig = NeitzLedRig('/dev/cu.usbserial-1101');   % macOS node
end
valLED = 0.1;
rig.setIntensity(0,'r',valLED);        % LED0 Red = 100%
rig.setIntensity(1,'r',valLED);         % LED1 Red = 0
rig.setIntensity(2,'r',valLED);         % LED2 Red = 0
rig.setIntensity(3,'r',valLED);         % LED3 Red = 0
rig.setIntensity(0,'g',valLED);        % LED0 Grn = 0
rig.setIntensity(1,'g',valLED);         % LED1 Grn = 0.5
rig.setIntensity(2,'g',valLED);         % LED2 Grn = 0
rig.setIntensity(3,'g',valLED);         % LED3 Grn = 0
rig.setIntensity(0,'b',valLED);        % LED0 Blu = 0
rig.setIntensity(1,'b',valLED);         % LED1 Blu = 0
rig.setIntensity(2,'b',valLED);         % LED2 Blu = 0
rig.setIntensity(3,'b',valLED);         % LED3 Blu = 0.125

rig.setMode(3);                      % (1) video mode


%% ===== TRIAL LOOP =====
for ind = 1:nTrials
    
    %pause(1)
    % Trigger key to start Clampex acquisition
    %NET.addAssembly('System.Windows.Forms');
    %if ind == 1
    %    System.Windows.Forms.SendKeys.SendWait('%{TAB}');
    %end
    %pause(0.01);
    %System.Windows.Forms.SendKeys.SendWait('^+{1}');

    %pause(pre_stim); % pre-stimulus window

    % Auto-increment the seed per trial so repeated seeded-noise trials are INDEPENDENT
    % noise realizations (each seed is recorded in the day's stim manifest). Only the
    % seeded-Gaussian lines below use `seed`; the flicker/jitter lines ignore it.
    seed = 5;

    % ===== UNCOMMENT ONE STIMULUS =====
    %AAGreyScaleFullFieldNoiseFinal2026(flickerHz, stimFrames, refreshRate);
%   AASConeIsoFullFieldNoiseStimFinal2026(flickerHz, stimFrames, refreshRate);
    AASeededGaussianGreyScaleStimFinal2026(seed, [], [], flickerHz, stimFrames, refreshRate);
%   AASeededGaussianSConeIsoStimFinal2026(seed, [], [], flickerHz, stimFrames, refreshRate);
%   AASeededGaussianCheckerboardGreyScaleStimFinal(seed, [], [], flickerHz, stimFrames, refreshRate);
%   AASeededGaussianCheckerboardSConeIsoStimFinal(seed, [], [], flickerHz, stimFrames, refreshRate);
%   AAJitteringCircleStimulusFinal([], [], [], [], stimFrames, refreshRate, []);

    pause(stim_dur+1);
    pause(itp)
    sprintf('Trial %d done!', ind)
end
sprintf('Experiment done!')

rig.setMode(0);                      % (1) video mode