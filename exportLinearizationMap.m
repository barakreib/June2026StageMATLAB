function T = exportLinearizationMap(outPath)
% exportLinearizationMap  CSV of the CURRENT intended->sent linearization mapping.
%
%   T = exportLinearizationMap()          % writes dlp_linearization_map_<date>.csv here
%   T = exportLinearizationMap(outPath)   % explicit destination
%
% One row per intended 8-bit level k = 0..255 (i.e. intended linear k/255):
%   intended_code    - the level you would naively send (0..255)
%   intended_linear  - the desired linear light fraction, k/255
%   sent_frac        - lcGammaCorrect(intended_linear): what a stimulus actually
%                      hands the display so the light comes out linear
%   sent_code        - round(255 * sent_frac): the 8-bit code that reaches the DLP
%
% Example row: intended (128,128,128) -> sent (168,168,168) under the 2026-07-14
% measured LUT. The DLP applies the same de-gamma to R, G and B, so this single
% mapping applies per channel: greyscale (k,k,k) and single-channel (k,0,0) use
% the same k -> sent_code mapping.
%
% Reflects rig_config.json's CURRENT gamma_model (via lcGammaCorrect /
% loadRigConfig, which caches -- `clear loadRigConfig` after recalibrating).
% Re-export after any recalibration; the filename carries the export date.

    if nargin < 1 || isempty(outPath)
        outPath = fullfile(fileparts(mfilename('fullpath')), ...
            sprintf('dlp_linearization_map_%s.csv', char(datetime('now', 'Format', 'yyyy-MM-dd'))));
    end
    intended_code   = (0:255).';
    intended_linear = intended_code / 255;
    sent_frac       = lcGammaCorrect(intended_linear);
    sent_code       = round(255 * sent_frac);
    T = table(intended_code, intended_linear, sent_frac, sent_code);
    writetable(T, outPath);
    fprintf('exportLinearizationMap: gamma_model=%s -> %s (%d rows)\n', ...
        char(string(loadRigConfig('gamma_model', 'power'))), outPath, height(T));
end
