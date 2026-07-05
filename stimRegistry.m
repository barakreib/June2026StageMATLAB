function reg = stimRegistry()
% stimRegistry  Single source of truth for the experiment GUI (stimulusGUI.m):
% which stimuli exist, their POSITIONAL arguments (name / default / type, IN CALL
% ORDER), and which argument is the auto-managed seed.
%
%   reg = stimRegistry()  ->  struct array, one entry per stimulus, fields:
%       .name    - display name shown in the GUI list.
%       .fn      - function name as a CHAR (resolved with str2func; never a raw handle,
%                  so saved experiments survive code edits/renames).
%       .params  - N x 3 cell, one row per positional argument: {name, default, type}.
%                  type:  'num'  -> numeric field
%                         'vec2' -> two numbers, e.g. rfCenter "570 456"
%                         'enum' -> a fixed choice (options in .choices)
%                         'seed' -> the seed; auto-incremented per epoch by runExperiment,
%                                   NOT edited in the GUI (its position becomes seedArg).
%       .choices - struct(paramName -> {options}) for any 'enum' params.
%
%   The .params rows MUST match each function's signature order exactly. stimulusGUI runs
%   a startup self-check asserting size(params,1) == nargin(@fn). To add or change a
%   stimulus, edit ONLY this file (see the `default:` comments in each stimulus header).

    reg = struct('name', {}, 'fn', {}, 'params', {}, 'choices', {});

    flick = {'flickerHz', 4, 'num'; 'stimFrames', 600, 'num'; 'refreshRate', 60, 'num'};
    reg(end+1) = entry('Greyscale full-field flicker',  'AAGreyScaleFullFieldNoiseFinal2026',  flick);
    reg(end+1) = entry('S-cone-iso full-field flicker', 'AASConeIsoFullFieldNoiseStimFinal2026', flick);

    % (seed, mu, sigma, flickerHz, stimFrames, refreshRate) -- seed auto-managed per epoch
    gauss = {'seed', 2, 'seed'; 'mu', 0.5, 'num'; 'sigma', 0.3, 'num'; ...
             'flickerHz', 4, 'num'; 'stimFrames', 600, 'num'; 'refreshRate', 60, 'num'};
    reg(end+1) = entry('Greyscale Gaussian noise (full field)', 'AASeededGaussianGreyScaleStimFinal2026', gauss);
    reg(end+1) = entry('S-cone-iso Gaussian noise (full field)', 'AASeededGaussianSConeIsoStimFinal2026', gauss);
    reg(end+1) = entry('Greyscale Gaussian checkerboard', 'AASeededGaussianCheckerboardGreyScaleStimFinal', gauss);
    reg(end+1) = entry('S-cone-iso Gaussian checkerboard', 'AASeededGaussianCheckerboardSConeIsoStimFinal', gauss);

    jit = entry('Jittering circle', 'AAJitteringCircleStimulusFinal', ...
        {'rfCenter', [570 456], 'vec2'; 'rfRadius', 80, 'num'; 'circleRadius', 150, 'num'; ...
         'walkSpeed', 50, 'num'; 'stimFrames', 600, 'num'; 'refreshRate', 60, 'num'; ...
         'colorMode', 'Greyscale', 'enum'});
    jit.choices = struct('colorMode', {{'Greyscale', 'S-Cone Isolating'}});
    reg(end+1) = jit;
end


function e = entry(name, fn, params)
    e = struct('name', name, 'fn', fn, 'params', {params}, 'choices', struct());
end
