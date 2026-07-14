function c = lcGammaCorrect(L)
% lcGammaCorrect  Linearize a desired LINEAR intensity for the LightCrafter 4500.
%
%   c = lcGammaCorrect(L)
%
%   The TI LightCrafter 4500, running in "Video" mode, does NOT emit light
%   linearly in the digital value it is sent. It applies a proprietary
%   "de-gamma" LUT, and the July 2026 radiometer sweeps (measureDlpGamma*)
%   showed the response is NOT a pure power law: its local log-log slope runs
%   ~1.4 through the low-mid codes, ~3 through the middle, and compresses hard
%   above ~90 % code. So the linearization is model-driven from rig_config.json
%   (single source of truth), with two supported models:
%
%   gamma_model = 'lut-pchip'  (CURRENT -- measured curve)
%       rig_config holds the measured response itself:
%           dlp_lut_codes       : the 8-bit codes measured, with a 0 anchor
%           dlp_lut_output_norm : measured output normalized to code 255 = 1
%       This function inverts it: c = pchipInterp(outputNorm -> code/255, L).
%       The shape-preserving (pchip) interpolant through strictly-increasing
%       measurements is monotone, so the inverse lookup is well-defined; L = 0
%       and L = 1 map exactly to code 0 and code 255 (fixed points, as before).
%       Between measured codes the curve is the pchip's smooth monotone guess.
%
%   gamma_model = 'power'  (LEGACY -- pre-July-2026)
%       The old pure power law: c = L .^ (1/gamma), gamma from rig_config
%       (2.2056 fallback). calibrateGamma.m writes this model; it remains so
%       old configs and quick power-fit experiments still work.
%
%   The noise/contrast in the stimulus scripts is defined in LINEAR light
%   space: the Gaussian value is the desired linear intensity, and this
%   function converts it to the value that realises it on screen.
%
%   Inputs:
%     L  - desired linear intensity, scalar or array, in [0,1] (fraction of
%          the channel's maximum light output). Clamped to [0,1].
%
%   Output:
%     c  - linearized value in [0,1], same size as L, to hand to the display.
%          For an 8-bit imageMatrix use uint8(round(255*c)); for a Stage
%          .color property (already normalized [0,1]) use c directly.
%
%   The projector applies the same de-gamma to each of R, G and B in Video
%   mode, so this single curve is applied independently per channel. (If the
%   per-channel sweeps ever disagree, extend rig_config to per-channel LUTs.)
%
%   SINGLE SOURCE OF TRUTH: the model and its data come from rig_config.json
%   (via loadRigConfig, which caches -- run `clear loadRigConfig` after
%   recalibrating). Re-derive with calibrateDlpResponse.m (measured LUT,
%   primary) or calibrateGamma.m (legacy power fit).

    model = char(string(loadRigConfig('gamma_model', 'power')));
    L = min(max(L, 0), 1);      % clamp to the valid linear range

    if strncmpi(model, 'lut', 3)
        codes = loadRigConfig('dlp_lut_codes', []);
        Rn    = loadRigConfig('dlp_lut_output_norm', []);
        if isempty(codes) || isempty(Rn) || numel(codes) ~= numel(Rn)
            error('lcGammaCorrect:noLut', ...
                  ['rig_config.json says gamma_model=%s but dlp_lut_codes / ' ...
                   'dlp_lut_output_norm are missing or mismatched. Re-run ' ...
                   'calibrateDlpResponse(..., ''write'', true).'], model);
        end
        % Inverse lookup: desired normalized output -> code fraction.
        c = reshape(interp1(Rn(:), codes(:) / 255, L(:), 'pchip'), size(L));
    else
        GAMMA = loadRigConfig('gamma', 2.2056);
        c = L .^ (1 / GAMMA);
    end
end
