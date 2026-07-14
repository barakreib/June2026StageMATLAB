function [gamma, gain, R2] = calibrateGamma(inputFraction, output, varargin)
% calibrateGamma  Fit the LightCrafter's power-law gamma from measured light output.
%
%   NOTE (2026-07): the measured LightCrafter response turned out NOT to be a
%   pure power law (TI's proprietary de-gamma LUT) -- calibrateDlpResponse.m is
%   now the PRIMARY calibration tool (measured monotone LUT + model comparison).
%   This power fit remains for quick checks and legacy configs. Beware that
%   'write' here sets gamma_model='power', switching lcGammaCorrect BACK to the
%   power model and off the measured LUT.
%
%   [gamma, gain, R2] = calibrateGamma(inputFraction, output)
%   [gamma, gain, R2] = calibrateGamma()                    % rig reference points -> 2.2056
%   [gamma, gain, R2] = calibrateGamma(..., 'write', true)  % also update rig_config.json
%
%   Fits  output = gain * inputFraction .^ gamma  (least squares in log-log space). The
%   fitted `gamma` is what lcGammaCorrect inverts (code = L^(1/gamma)); `gain` is the
%   absolute-output scaling and cancels in normalized terms. So `2.2056` is not a magic
%   number: re-run this on fresh measurements to re-derive it and (optionally) persist it
%   to rig_config.json, from where lcGammaCorrect and the stimulus manifest both read it.
%
%   Inputs:
%     inputFraction - normalized input in (0,1]  (i.e. code/255)
%     output        - measured light output (any linear unit: luminance / integrated power)
%   With no data args, the rig calibration reference points are used
%   ('DLP power function' sheet, normalized input vs integrated output).
%
%   Options:
%     'write' (logical, default false) - overwrite gamma in rig_config.json with the fit
%                                        (preserving the file's other fields)
%
%   Example (re-derive from new measurements and persist):
%     calibrateGamma([1 0.5 0.25 0.125], [13.831 3.060 0.625 0.144], 'write', true);

    if nargin < 2 || isempty(inputFraction) || isempty(output)
        % Rig calibration reference points ('DLP power function' sheet, N16:O19)
        inputFraction = [1, 0.5, 0.25, 0.125];
        output        = [13.8314489, 3.06044049, 0.62507362, 0.14375798];
    end

    p = inputParser;
    addParameter(p, 'write', false, @(x) islogical(x) || isnumeric(x));
    parse(p, varargin{:});

    x = inputFraction(:);  y = output(:);
    good = (x > 0) & (y > 0);          % log-log fit needs strictly positive values
    x = x(good);  y = y(good);
    if numel(x) < 2
        error('calibrateGamma:tooFewPoints', 'Need >= 2 positive (input, output) pairs.');
    end

    coeffs = polyfit(log(x), log(y), 1);   % log(y) = gamma*log(x) + log(gain)
    gamma  = coeffs(1);
    gain   = exp(coeffs(2));

    yhat  = gain .* x .^ gamma;
    ssres = sum((y - yhat).^2);
    sstot = sum((y - mean(y)).^2);
    R2    = 1 - ssres / sstot;

    fprintf('calibrateGamma: gamma = %.4f, gain = %.4f, R^2 = %.6f (n = %d)\n', ...
            gamma, gain, R2, numel(x));

    if p.Results.write
        cfgPath = fullfile(fileparts(mfilename('fullpath')), 'rig_config.json');
        if exist(cfgPath, 'file')
            cfg = jsondecode(fileread(cfgPath));
        else
            cfg = struct('schema', 'neitz.rig-config/1');
        end
        cfg.gamma               = gamma;
        cfg.gamma_model         = 'power';
        cfg.gamma_source        = sprintf('calibrateGamma power fit, R^2=%.4f, n=%d', R2, numel(x));
        cfg.gamma_calibrated_on = char(datetime('now', 'Format', 'yyyy-MM-dd'));
        fid = fopen(cfgPath, 'w');
        if fid < 0, error('calibrateGamma:cannotWrite', 'Cannot write %s', cfgPath); end
        closer = onCleanup(@() fclose(fid));
        fprintf(fid, '%s', jsonencode(cfg, 'PrettyPrint', true));
        fprintf('calibrateGamma: wrote gamma = %.4f to %s (run `clear loadRigConfig`)\n', gamma, cfgPath);
    end
end
