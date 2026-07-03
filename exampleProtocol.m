%% exampleProtocol.m -- define a session and run it via runExperiment.
%
% Edit the blocks below, then run this file. Each block runs its stimulus for `epochs`
% presentations; Clampex is triggered once per epoch and each presentation writes a row
% to the day's stim manifest (YYYY_MM_DD_stim_manifest.jsonl), paired to the .abf files
% by trial order in the Analysis Suite. This replaces Experimenter5000's uncomment-one
% workflow -- list as many blocks as you like and they run in sequence.

refreshRate = 60;
flickerHz   = 4;
stimFrames  = 10 * refreshRate;    % 10 s per epoch

% Each column below is one block: {stimulus handle}, {arg cell}, {#epochs}, {label}.
% (Gaussian stimuli take (seed, mu, sigma, flickerHz, stimFrames, refreshRate); [] = default.)
protocol = struct( ...
    'stim',   {@AASeededGaussianGreyScaleStimFinal2026, ...
               @AASeededGaussianSConeIsoStimFinal2026}, ...
    'args',   {{[], [], [], flickerHz, stimFrames, refreshRate}, ...
               {[], [], [], flickerHz, stimFrames, refreshRate}}, ...
    'epochs', {5, 5}, ...
    'label',  {'greyscale noise', 's-cone-iso noise'});

% opts is optional; defaults: preStim 2, postStim 1, itp 3, triggerAcq true, preflight true.
runExperiment(protocol);
