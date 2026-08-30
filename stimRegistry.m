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
%       .kind    - which stimulus core generateStimScript.m emits for this entry:
%                  'sq' (full-field square-wave flicker), 'gauss' (seeded Gaussian noise
%                  Image), or 'jitter' (random-walk circle). The GUI "Run" no longer calls
%                  .fn directly -- it generates a per-run script that reproduces .fn's
%                  presentation exactly, wrapped in the configured pre/post-stim phases.
%                  The AA* files stay untouched and runnable standalone.
%       .iso     - true for the S-cone-isolating variant of the core (R=v, G=1-v),
%                  false for greyscale. ('jitter' takes it from its colorMode arg.)
%       .checks  - noise grid for 'gauss' cores: [1 1] = full field; anything else means a
%                  checkerboard with checksX = checks(1) and checksY DERIVED at run time
%                  so the checks are SQUARE ON THE WALL (the diamond-pixel DMD lands each
%                  canvas pixel ~2x wider than tall; see generateStimScript / pixel_aspect).
%
%   The .params rows MUST match each function's signature order exactly. stimulusGUI runs
%   a startup self-check asserting size(params,1) == nargin(@fn). To add or change a
%   stimulus, edit ONLY this file (see the `default:` comments in each stimulus header).

    reg = struct('name', {}, 'fn', {}, 'params', {}, 'choices', {}, ...
                 'kind', {}, 'iso', {}, 'checks', {});

    flick = {'flickerHz', 4, 'num'; 'stimFrames', 600, 'num'; 'refreshRate', 60, 'num'};
    reg(end+1) = entry('Greyscale full-field flicker',  'AAGreyScaleFullFieldNoiseFinal2026',  flick, 'sq', false, [1 1]);
    reg(end+1) = entry('S-cone-iso full-field flicker', 'AASConeIsoFullFieldNoiseStimFinal2026', flick, 'sq', true, [1 1]);

    % (seed, mu, sigma, flickerHz, stimFrames, refreshRate) -- seed auto-managed per epoch
    gauss = {'seed', 2, 'seed'; 'mu', 0.5, 'num'; 'sigma', 0.3, 'num'; ...
             'flickerHz', 4, 'num'; 'stimFrames', 600, 'num'; 'refreshRate', 60, 'num'};
    reg(end+1) = entry('Greyscale Gaussian noise (full field)', 'AASeededGaussianGreyScaleStimFinal2026', gauss, 'gauss', false, [1 1]);
    reg(end+1) = entry('S-cone-iso Gaussian noise (full field)', 'AASeededGaussianSConeIsoStimFinal2026', gauss, 'gauss', true, [1 1]);
    reg(end+1) = entry('Greyscale Gaussian checkerboard', 'AASeededGaussianCheckerboardGreyScaleStimFinal', gauss, 'gauss', false, [40 32]);
    reg(end+1) = entry('S-cone-iso Gaussian checkerboard', 'AASeededGaussianCheckerboardSConeIsoStimFinal', gauss, 'gauss', true, [40 32]);

    jit = entry('Jittering circle', 'AAJitteringCircleStimulusFinal', ...
        {'rfCenter', [570 456], 'vec2'; 'rfRadius', 80, 'num'; 'circleRadius', 150, 'num'; ...
         'walkSpeed', 50, 'num'; 'stimFrames', 600, 'num'; 'refreshRate', 60, 'num'; ...
         'colorMode', 'Greyscale', 'enum'}, 'jitter', false, [1 1]);
    jit.choices = struct('colorMode', {{'Greyscale', 'S-Cone Isolating'}});
    reg(end+1) = jit;
end


function e = entry(name, fn, params, kind, iso, checks)
    e = struct('name', name, 'fn', fn, 'params', {params}, 'choices', struct(), ...
               'kind', kind, 'iso', logical(iso), 'checks', checks);
end
