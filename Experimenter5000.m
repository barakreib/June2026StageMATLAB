%% ===== Experimenter5000 — session entry point =====
% Define the protocol below, then run this file. It builds a protocol and hands it to
% runExperiment.m, which pre-flights the Stage server, triggers Clampex once per epoch
% (triggerAcquisition.m), presents each stimulus, and lets each stimulus append its row
% to the day's stim manifest (YYYY_MM_DD_stim_manifest.jsonl, paired to the .abf files
% by trial order). This replaces the old hand-rolled trial loop and Experimenter5000_v2.

%% ----- parameters -----
refreshRate = 60;
flickerHz   = 4;
stim_dur    = 10;                          % seconds per epoch
stimFrames  = stim_dur * refreshRate;
nTrials     = 5;                           % epochs per block

%% ----- protocol: one column per block  {stimulus, args, #epochs, label} -----
% Flicker args        = (flickerHz, stimFrames, refreshRate).
% Gaussian-noise args = (seed, mu, sigma, flickerHz, stimFrames, refreshRate); [] = default.
protocol = struct( ...
    'stim',   {@AAGreyScaleFullFieldNoiseFinal2026}, ...
    'args',   {{flickerHz, stimFrames, refreshRate}}, ...
    'epochs', {nTrials}, ...
    'label',  {'greyscale full-field flicker'});

% --- Run several stimuli in one session by adding columns, e.g.: ---
% For a SEEDED stimulus, set .seedArg to the position of the seed argument (1 for the
% Gaussian stimuli); runExperiment then auto-increments the seed per epoch (independent
% noise, each seed recorded in the manifest). Use 0 for non-seeded stimuli (flicker/jitter).
% protocol = struct( ...
%     'stim',    {@AAGreyScaleFullFieldNoiseFinal2026,        @AASeededGaussianSConeIsoStimFinal2026}, ...
%     'args',    {{flickerHz, stimFrames, refreshRate},       {[], [], [], flickerHz, stimFrames, refreshRate}}, ...
%     'epochs',  {nTrials,                                    nTrials}, ...
%     'seedArg', {0,                                          1}, ...
%     'label',   {'greyscale flicker',                        's-cone-iso noise'});

%% ----- timing (see runExperiment.m for all opts) -----
opts = struct('preStim', 2, 'postStim', 1, 'itp', 3);

%% ----- run -----
runExperiment(protocol, opts);
