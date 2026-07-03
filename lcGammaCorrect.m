function c = lcGammaCorrect(L)
% lcGammaCorrect  Gamma-correct a desired LINEAR intensity for the LightCrafter 4500.
%
%   c = lcGammaCorrect(L)
%
%   The TI LightCrafter 4500, running in "Video" mode, does NOT emit light
%   linearly in the digital value it is sent. Its measured transfer function
%   (rig calibration measurements.xlsx -> sheet "DLP power function", chart
%   fitted with Excel) is a pure power law:
%
%       relativeOutput(x) = x ^ gamma ,   gamma = 2.2056     (power fit, R^2 = 1)
%
%   where x = value/255 is the normalized 8-bit code actually sent to the
%   projector. This is the standard ~2.2 video gamma; the "13.835" prefactor
%   in the spreadsheet trendline is only the absolute-output scaling and
%   cancels once we work in normalized [0,1] terms.
%
%   To make the light that actually reaches the eye LINEAR in the intended
%   value L, we pre-distort by the INVERSE of that curve before sending:
%
%       c = L ^ (1/gamma)
%
%   Sending round(255*c) then yields output(c) = c^gamma = L, i.e. true
%   linear light output. L = 0 and L = 1 are fixed points, so full black,
%   full white and the pure primaries are unchanged; only intermediate
%   grey/colour levels (e.g. the Gaussian-noise stimuli) are remapped
%   (for example intended L = 0.5 -> code 186 rather than 128).
%
%   The noise/contrast in the stimulus scripts is therefore defined in
%   LINEAR light space: the Gaussian value is the desired linear intensity,
%   and this function converts it to the DAC value that realises it.
%
%   Inputs:
%     L  - desired linear intensity, scalar or array, in [0,1]
%          (fraction of the channel's maximum light output). Values outside
%          [0,1] are clamped.
%
%   Output:
%     c  - gamma-corrected value in [0,1] to hand to the display. For an
%          8-bit imageMatrix use uint8(round(255*c)); for a Stage .color
%          property (already normalized [0,1]) use c directly.
%
%   The projector applies the same transfer function to each of R, G and B
%   in Video mode, so this correction is applied independently per channel.
%
%   SINGLE SOURCE OF TRUTH: gamma is read from rig_config.json (via loadRigConfig);
%   re-derive it from measurements with calibrateGamma.m. Falls back to 2.2056 if the
%   config is absent. loadRigConfig caches, so this stays fast in the per-frame loops.

    GAMMA = loadRigConfig('gamma', 2.2056);   % rig_config.json -> single source of truth

    L = min(max(L, 0), 1);      % clamp to the valid linear range
    c = L .^ (1 / GAMMA);
end
