%% ===== Experimenter5000_v2 =====
% Same as Experimenter5000 but passes all parameters explicitly to
% stimulus functions. No resolveParam.m dependency required.
%
% SETUP: Uncomment the stimulus you want to run in the trial loop below.
%        Adjust parameters in this section to control the experiment.

%% ===== EXPERIMENT PARAMETERS =====
stim_dur    = 10;       % stimulus duration (seconds)
pre_stim    = 2;        % pre-stimulus window (seconds)
itp         = 3;        % inter-trial pause (seconds)
nTrials     = 5;        % number of trials
refreshRate = 60;       % monitor refresh rate (Hz) - always 60

% Derived timing
stimFrames = stim_dur * refreshRate;   % total stimulus frames

% Stimulus flicker rate (how fast the stimulus content changes)
flickerHz = 4;          % stimulus update frequency (Hz)


%% ===== TRIAL LOOP =====
for ind = 1:nTrials

    pause(1)
    % Trigger key to start Clampex acquisition
    NET.addAssembly('System.Windows.Forms');
    if ind == 1
        System.Windows.Forms.SendKeys.SendWait('%{TAB}');
    end
    pause(0.01);
    System.Windows.Forms.SendKeys.SendWait('^+{1}');

    pause(pre_stim); % pre-stimulus window

    % Auto-increment the seed per trial so repeated seeded-noise trials are INDEPENDENT
    % noise realizations (each seed is recorded in the day's stim manifest). Only the
    % seeded-Gaussian lines below use `seed`; the flicker/jitter lines ignore it.
    seed = 2 + (ind - 1);

    % ===== UNCOMMENT ONE STIMULUS =====
    AAGreyScaleFullFieldNoiseFinal2026(flickerHz, stimFrames, refreshRate);
%   AASConeIsoFullFieldNoiseStimFinal2026(flickerHz, stimFrames, refreshRate);
%   AASeededGaussianGreyScaleStimFinal2026(seed, [], [], flickerHz, stimFrames, refreshRate);
%   AASeededGaussianSConeIsoStimFinal2026(seed, [], [], flickerHz, stimFrames, refreshRate);
%   AASeededGaussianCheckerboardGreyScaleStimFinal(seed, [], [], flickerHz, stimFrames, refreshRate);
%   AASeededGaussianCheckerboardSConeIsoStimFinal(seed, [], [], flickerHz, stimFrames, refreshRate);
%   AAJitteringCircleStimulusFinal([], [], [], [], stimFrames, refreshRate, []);

    pause(stim_dur+1);
    pause(itp)
    sprintf('Trial %d done!', ind)
end
sprintf('Experiment done!')
