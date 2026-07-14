function result = calibrateDlpResponse(inputFraction, output, varargin)
% calibrateDlpResponse  Fit the LightCrafter's measured code->light response and
% (optionally) install it as THE linearization in rig_config.json.
%
%   result = calibrateDlpResponse(inputFraction, output)
%   result = calibrateDlpResponse(..., 'write', true)    % install in rig_config.json
%   result = calibrateDlpResponse(..., 'plot', false)    % skip the diagnostic figure
%
% WHY THIS EXISTS: the LightCrafter 4500's video-mode "de-gamma" is a proprietary
% TI LUT, and the measured response (July 2026 sweeps) is NOT a pure power law:
% its local log-log slope runs ~1.4 through the low-mid codes, ~3 through the
% middle, and compresses hard above ~90 % code. No small monotone parametric
% family (power, Hill/Naka-Rushton, Weibull, two-power mix) can follow that
% S-shape, so the linearization is stored as the measured curve itself -- a
% monotone shape-preserving (pchip) LUT that lcGammaCorrect inverts. The
% parametric fits are still computed and reported, both as documentation and as
% a guard: if a re-measured curve IS clean power-law again (max |rel err| <= 5 %),
% the power model is chosen instead.
%
% Inputs:
%   inputFraction - code fractions actually displayed (code/255, as the
%                   measureDlpGamma* sweeps send and print). Values are snapped
%                   to the exact 8-bit grid round(255*x)/255. Duplicates are fine
%                   (up/down sweeps average per level). MUST include 1.0 (code
%                   255), which anchors the normalization.
%   output        - measured light at each inputFraction (any linear unit, e.g.
%                   Thorlabs uW), EXTINCTION-SUBTRACTED (tare at the black hold,
%                   or subtract your extinction reading). Must be > 0 and
%                   strictly increasing after per-level averaging.
%
% Options:
%   'write' (default false) - persist the result to rig_config.json:
%       gamma_model          = 'lut-pchip' (or 'power' if that fit sufficed)
%       dlp_lut_codes        = [0 8 16 ... 255]      (8-bit codes, exact)
%       dlp_lut_output_norm  = [0 ... 1]             (measured output / output at 255)
%       gamma                = equivalent power-law exponent (LEGACY summary; the
%                              per-trial manifests keep recording this scalar)
%       gamma_source / gamma_calibrated_on = provenance
%     Run `clear loadRigConfig` afterwards to drop the config cache.
%   'plot'  (default true)  - diagnostic figure (response linear + log-log +
%       residuals), also saved as dlp_response_fit_<date>.png next to this file.
%
% Output `result`: struct with the LUT, every candidate fit (params, R^2 in log
% space, max |relative error|, AICc), the pchip leave-one-out errors, the chosen
% model, and the equivalent gamma.
%
% The LUT is used by lcGammaCorrect (inverse direction: desired linear light ->
% code fraction). Codes between the measured ones follow the shape-preserving
% pchip through the measured points, anchored at (0,0) [extinction-subtracted
% zero]; (255,1) is exact by construction.
%
% Example (July 2026 white-channel measurement):
%   x = [0.03125 0.0625 0.125 0.25 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1];
%   w = [0.733 4.74 12.8 34.52 170 219 285.4 376.25 426.67 503 579.5 670.6 702 753 767];
%   calibrateDlpResponse(x, w, 'write', true);

    p = inputParser;
    addParameter(p, 'write', false, @(v) islogical(v) || isnumeric(v));
    addParameter(p, 'plot',  true,  @(v) islogical(v) || isnumeric(v));
    parse(p, varargin{:});

    % ---- Clean, snap to the 8-bit grid, average duplicate levels ----
    x = double(inputFraction(:));  y = double(output(:));
    if numel(x) ~= numel(y)
        error('calibrateDlpResponse:sizeMismatch', 'inputFraction and output must match in length.');
    end
    keep = isfinite(x) & isfinite(y);
    x = x(keep);  y = y(keep);
    if any(x < 0 | x > 1)
        error('calibrateDlpResponse:badInput', 'inputFraction values must lie in [0,1].');
    end
    drop = (x == 0);                       % the dark reading is the tare, not a data point
    if any(drop)
        fprintf('calibrateDlpResponse: dropping %d point(s) at input 0 (dark is the LUT anchor).\n', sum(drop));
        x = x(~drop);  y = y(~drop);
    end
    codes = round(255 * x);                % snap: the sweep displayed EXACT 8-bit codes
    [uCodes, ~, grp] = unique(codes);
    uy = accumarray(grp, y, [], @mean);    % average up/down-sweep repeats per level
    n  = numel(uCodes);
    if n < 4
        error('calibrateDlpResponse:tooFewPoints', 'Need >= 4 distinct levels (got %d).', n);
    end
    if uCodes(end) ~= 255
        error('calibrateDlpResponse:noTopAnchor', ...
              'Need a 100 %% (code 255) measurement to normalize against.');
    end
    if any(uy <= 0)
        error('calibrateDlpResponse:nonPositive', ...
              'All outputs must be > 0 after extinction subtraction (check the tare).');
    end
    if any(diff(uy) <= 0)
        bad = uCodes(find(diff(uy) <= 0) + 1);
        error('calibrateDlpResponse:notMonotone', ...
              ['Averaged output is not strictly increasing at code(s) %s -- re-measure ' ...
               'those levels (a monotone curve is required for an invertible LUT).'], mat2str(bad(:).'));
    end

    ux = uCodes / 255;                     % exact displayed fractions
    Rn = uy / uy(end);                     % normalized response, Rn(end) = 1

    % ---- Candidate parametric models, fit by least squares on log(output) ----
    % (relative error is what matters across a ~3-decade range)
    ly   = log(uy);
    sst  = sum((ly - mean(ly)).^2);
    mdl  = struct('name', {}, 'K', {}, 'params', {}, 'yhat', {}, 'R2log', {}, 'maxRelPct', {}, 'AICc', {});

    % power: y = gain * x^gamma  (the OLD model; analytic in log-log)
    c = polyfit(log(ux), ly, 1);
    gammaEq = c(1);  gainEq = exp(c(2));
    mdl(end+1) = local_metrics('power', 2, [gainEq gammaEq], gainEq * ux.^gammaEq, uy, ly, sst);

    % Hill / Naka-Rushton: y = A * x^n / (x^n + s^n)
    f_hill = @(t, x) exp(t(1)) .* x.^exp(t(2)) ./ (x.^exp(t(2)) + exp(t(3)).^exp(t(2)));
    t = local_fit(f_hill, [log(1.5*uy(end)) log(3) log(0.8)], ux, ly);
    mdl(end+1) = local_metrics('hill', 3, [exp(t(1)) exp(t(2)) exp(t(3))], f_hill(t, ux), uy, ly, sst);

    % Weibull CDF: y = A * (1 - exp(-(x/lam)^k))
    f_wbl = @(t, x) exp(t(1)) .* (1 - exp(-(x ./ exp(t(3))).^exp(t(2))));
    t = local_fit(f_wbl, [log(1.2*uy(end)) log(2.3) log(0.7)], ux, ly);
    mdl(end+1) = local_metrics('weibull', 3, [exp(t(1)) exp(t(2)) exp(t(3))], f_wbl(t, ux), uy, ly, sst);

    % Two-power mix: y = A * (a*x^p + (1-a)*x^q)
    f_mix = @(t, x) exp(t(1)) .* (1./(1+exp(-t(2))) .* x.^exp(t(3)) + (1 - 1./(1+exp(-t(2)))) .* x.^exp(t(4)));
    t = local_fit(f_mix, [log(uy(end)) -2.2 log(1.4) log(3.2)], ux, ly);
    mdl(end+1) = local_metrics('two-power mix', 4, [exp(t(1)) 1/(1+exp(-t(2))) exp(t(3)) exp(t(4))], f_mix(t, ux), uy, ly, sst);

    % ---- The measured-LUT alternative: monotone pchip through the points ----
    lutCodes = [0; uCodes(:)];
    lutR     = [0; Rn(:)];
    % Leave-one-out: drop each measured level (except the code-255 anchor), predict it
    % from the pchip through the rest -> an honest noise/undersampling estimate.
    looPct = nan(n-1, 1);
    for i = 1:n-1
        keepIdx = setdiff(1:n, i);
        Rhat = interp1([0; ux(keepIdx)], [0; Rn(keepIdx)], ux(i), 'pchip');
        looPct(i) = 100 * (Rhat / Rn(i) - 1);
    end

    % ---- Report ----
    fprintf('\ncalibrateDlpResponse: %d distinct levels (codes %s)\n', n, mat2str(uCodes(:).'));
    fprintf('%-14s %-3s %-10s %-14s %-10s  %s\n', 'model', 'K', 'R2(log)', 'max|rel err|', 'AICc', 'params');
    for m = 1:numel(mdl)
        fprintf('%-14s %-3d %-10.4f %-13.1f%% %-10.1f  %s\n', mdl(m).name, mdl(m).K, ...
            mdl(m).R2log, mdl(m).maxRelPct, mdl(m).AICc, mat2str(round(mdl(m).params, 4)));
    end
    fprintf('%-14s %-3s exact at the %d measured levels; LOO median %.1f%%, max %.1f%%\n', ...
        'lut-pchip', '--', n, median(abs(looPct)), max(abs(looPct)));

    % ---- Choose: parametric only if it fits within realistic meter noise ----
    [bestErr, bestIdx] = min([mdl.maxRelPct]);
    if bestErr <= 5
        chosen = mdl(bestIdx).name;
        fprintf('\nCHOSEN: %s (max |rel err| %.1f%% <= 5%% -- a clean parametric fit).\n', chosen, bestErr);
    else
        chosen = 'lut-pchip';
        fprintf(['\nCHOSEN: lut-pchip. Best parametric (%s) still leaves %.0f%% errors -- the\n' ...
                 'response is not a simple curve (TI''s proprietary de-gamma LUT), so the\n' ...
                 'measured monotone LUT itself is the linearization.\n'], mdl(bestIdx).name, bestErr);
    end
    fprintf('Equivalent power-law exponent (legacy summary): gamma = %.4f (old config: 2.2056)\n', gammaEq);

    % ---- Diagnostic figure (saved next to this file) ----
    pngPath = '';
    if p.Results.plot
        try
            pngPath = local_plot(ux, uy, lutCodes, lutR, mdl, looPct);
        catch plotErr
            warning('calibrateDlpResponse:plot', 'Plot skipped: %s', plotErr.message);
        end
    end

    % ---- Persist to rig_config.json ----
    if p.Results.write
        cfgPath = fullfile(fileparts(mfilename('fullpath')), 'rig_config.json');
        if exist(cfgPath, 'file')
            cfg = jsondecode(fileread(cfgPath));
        else
            cfg = struct('schema', 'neitz.rig-config/1');
        end
        cfg.gamma               = round(gammaEq, 4);            % legacy scalar (manifests log it)
        cfg.gamma_model         = chosen;
        cfg.dlp_lut_codes       = lutCodes(:).';
        cfg.dlp_lut_output_norm = round(lutR(:).', 8);
        cfg.gamma_source        = sprintf(['calibrateDlpResponse %s: %d levels; pchip LUT (LOO med %.1f%%, ' ...
                                           'max %.1f%%); best parametric %s max err %.0f%%; equiv gamma %.3f'], ...
                                          char(datetime('now', 'Format', 'yyyy-MM-dd')), n, ...
                                          median(abs(looPct)), max(abs(looPct)), mdl(bestIdx).name, bestErr, gammaEq);
        cfg.gamma_calibrated_on = char(datetime('now', 'Format', 'yyyy-MM-dd'));
        fid = fopen(cfgPath, 'w');
        if fid < 0, error('calibrateDlpResponse:cannotWrite', 'Cannot write %s', cfgPath); end
        closer = onCleanup(@() fclose(fid));
        fprintf(fid, '%s', jsonencode(cfg, 'PrettyPrint', true));
        fprintf('calibrateDlpResponse: wrote %s model to %s\n', chosen, cfgPath);
        fprintf('                      -> run `clear loadRigConfig` to drop the config cache.\n');
    end

    result = struct('chosen_model', chosen, 'gamma_equiv', gammaEq, 'gain_equiv', gainEq, ...
                    'lut_codes', lutCodes(:).', 'lut_output_norm', lutR(:).', ...
                    'models', mdl, 'loo_pct', looPct(:).', 'png', pngPath);
end


function t = local_fit(modelFn, t0, ux, ly)
% Least squares on log(output) via fminsearch (no toolboxes), with one restart.
    obj = @(t) local_sse(t, modelFn, ux, ly);
    opt = optimset('MaxFunEvals', 2e4, 'MaxIter', 2e4, 'TolFun', 1e-12, 'TolX', 1e-10, 'Display', 'off');
    t = fminsearch(obj, t0, opt);
    t = fminsearch(obj, t,  opt);          % polish from the first optimum
end


function sse = local_sse(t, modelFn, ux, ly)
    yhat = modelFn(t, ux);
    if any(~isfinite(yhat)) || any(yhat <= 0)
        sse = Inf;
        return;
    end
    sse = sum((log(yhat) - ly).^2);
end


function m = local_metrics(name, K, params, yhat, uy, ly, sst)
% R^2 in log space, worst relative error, and small-sample AIC.
    yhat = yhat(:);
    sse  = sum((log(yhat) - ly).^2);
    n    = numel(uy);
    m = struct('name', name, 'K', K, 'params', params, 'yhat', yhat, ...
               'R2log', 1 - sse/sst, ...
               'maxRelPct', 100 * max(abs(yhat ./ uy - 1)), ...
               'AICc', n*log(sse/n) + 2*K + 2*K*(K+1) / max(n - K - 1, 1));
end


function pngPath = local_plot(ux, uy, lutCodes, lutR, mdl, looPct)
% Three-panel diagnostic: response (linear), response (log-log), residuals.
    xx  = linspace(0, 1, 1001).';
    Rxx = interp1(lutCodes/255, lutR, xx, 'pchip');
    top = uy(end);

    fig = figure('Name', 'DLP code->light response', 'Color', 'w', 'Position', [80 80 1500 420]);

    subplot(1, 3, 1); hold on;
    plot(xx, Rxx * top, '-', 'LineWidth', 1.5);
    for m = 1:numel(mdl), plot(ux, mdl(m).yhat, '--'); end
    plot(ux, uy, 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 5);
    grid on; xlabel('input code fraction (code/255)'); ylabel('measured output');
    title('DLP response (linear axes)');
    legend([{'lut-pchip'}, {mdl.name}, {'measured'}], 'Location', 'northwest');

    subplot(1, 3, 2); hold on;
    ok = xx > 1/512;
    plot(log10(xx(ok)), log10(Rxx(ok) * top), '-', 'LineWidth', 1.5);
    for m = 1:numel(mdl), plot(log10(ux), log10(mdl(m).yhat), '--'); end
    plot(log10(ux), log10(uy), 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 5);
    grid on; xlabel('log_{10} code fraction'); ylabel('log_{10} output');
    title('log-log (a pure gamma would be a straight line)');

    subplot(1, 3, 3); hold on;
    for m = 1:numel(mdl), plot(ux, 100*(mdl(m).yhat ./ uy - 1), '--o', 'MarkerSize', 4); end
    plot(ux(1:numel(looPct)), looPct, 'k-s', 'MarkerFaceColor', 'k', 'MarkerSize', 4);
    yline(0); grid on; xlabel('input code fraction'); ylabel('error vs measured (%)');
    title('fit residuals (black: LUT leave-one-out)');
    legend([{mdl.name}, {'lut-pchip LOO'}], 'Location', 'northwest');

    pngPath = fullfile(fileparts(mfilename('fullpath')), ...
                       sprintf('dlp_response_fit_%s.png', char(datetime('now', 'Format', 'yyyy-MM-dd'))));
    exportgraphics(fig, pngPath, 'Resolution', 150);
    fprintf('calibrateDlpResponse: diagnostic figure saved -> %s\n', pngPath);
end
