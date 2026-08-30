function outPath = writeStimValuesCsv(outDir, stimName, seed, intendedByChannel, ledGrid)
% writeStimValuesCsv  Troubleshooting dump: what a seeded stimulus actually sends.
%
%   outPath = writeStimValuesCsv(outDir, stimName, seed, intendedByChannel, ledGrid)
%
% The file opens with '#'-comment header lines -- the stimulus name, the seed, the
% linearization in force, and the 4x3 LED grid (rows LED1..LED4, columns projector
% channel R/G/B) driving the projector during the stimulus frames -- followed by one
% CSV row per (update, check, channel) with BOTH sides of the linearization:
%   seed, update, check_row, check_col, channel, intended_linear, sent_frac, sent_code
% Read it with readtable(p, 'CommentStyle', '#') (or pandas read_csv(p, comment='#')).
% The seed column is constant down the file (and repeated in the file name): the CSV is
% self-describing even after a rename, and joins trivially against the manifest's
% per-epoch seeds. intended_linear is the stimulus's desired LINEAR intensity (the clamped
% Gaussian draw), sent_frac = lcGammaCorrect(intended_linear) is the linearized
% value handed to the display, and sent_code = uint8(round(255*sent_frac)) is
% the 8-bit code written into the imageMatrix. These are the SAME expressions
% the stimulus builders use, so the CSV is exactly what went to the projector.
%
% intendedByChannel: struct, one field per displayed channel, each a
% checksY x checksX x nUpdates array of intended linear values:
%   struct('grey', noiseVals)                     % greyscale: R=G=B
%   struct('R', noiseVals, 'G', 1 - noiseVals)    % S-cone iso (B constant 0)
%
% ledGrid (optional): the 4x3 LED duty grid in force DURING the stimulus frames.
% Generated scripts pass their baked stimLeds; when omitted (the standalone AA*
% scripts) the grid falls back to ledSession('current') -- whatever the LEDs were
% loaded with when the stimulus was built -- and the header says so. No grid at
% all is recorded as "none".
%
% Called by the AASeededGaussian* stimuli when rig_config.json has
% "debug_values_csv": true (loadRigConfig caches -- run `clear loadRigConfig`
% after flipping the flag). One timestamped file per trial, written next to the
% day's stim manifest. TROUBLESHOOTING ONLY: for analysis the values regenerate
% from the seed; leave the flag false in real experiments (a long checkerboard
% run makes millions of rows).

    if nargin < 1 || isempty(outDir), outDir = pwd; end
    if nargin < 5, ledGrid = []; end
    ledGrid = local_grid(ledGrid);
    ledNote = '';
    if isempty(ledGrid)                  % standalone AA* call: best effort from the session
        ledGrid = local_grid(ledSession('current'));
        if ~isempty(ledGrid), ledNote = ' (from ledSession: the grid loaded when the stimulus was built)'; end
    end

    chans = fieldnames(intendedByChannel);
    T = table();
    for ci = 1:numel(chans)
        v = intendedByChannel.(chans{ci});
        [ny, nx, nu] = size(v);
        sentFrac = lcGammaCorrect(v);                  % same call as the stimulus builders
        sentCode = uint8(round(255 * sentFrac));       % same quantization as the imageMatrix
        [r, c, u] = ndgrid(1:ny, 1:nx, 1:nu);
        T = [T; table(repmat(double(seed), numel(v), 1), ...
                      u(:), r(:), c(:), repmat(string(chans{ci}), numel(v), 1), ...
                      v(:), sentFrac(:), double(sentCode(:)), 'VariableNames', ...
                      {'seed', 'update', 'check_row', 'check_col', 'channel', ...
                       'intended_linear', 'sent_frac', 'sent_code'})]; %#ok<AGROW>
    end
    T = sortrows(T, {'update', 'check_row', 'check_col', 'channel'});
    if height(T) > 2e6
        warning('writeStimValuesCsv:big', ...
                '%d rows -- expect a large file and a slow write (troubleshooting flag left on?).', height(T));
    end
    outPath = fullfile(outDir, sprintf('%s_%s_seed%g_values.csv', ...
        char(datetime('now', 'Format', 'yyyy_MM_dd_HHmmss')), stimName, seed));

    fid = fopen(outPath, 'w');
    if fid < 0
        error('writeStimValuesCsv:cannotWrite', 'Cannot write %s', outPath);
    end
    fprintf(fid, '# %s troubleshooting dump -- intended vs sent, one row per (update, check, channel)\n', stimName);
    fprintf(fid, '# seed: %g\n', seed);
    fprintf(fid, '# written: %s\n', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
    fprintf(fid, '# linearization: %s (calibrated %s); sent_frac = lcGammaCorrect(intended_linear), sent_code = uint8(round(255*sent_frac))\n', ...
        char(string(loadRigConfig('gamma_model', 'unknown'))), ...
        char(string(loadRigConfig('gamma_calibrated_on', 'unknown'))));
    if isempty(ledGrid)
        fprintf(fid, '# led_grid: none -- no grid passed and no LED rig registered in this session\n');
    else
        fprintf(fid, '# led_grid%s: rows LED1..LED4, cols projector channel R,G,B, duty 0..1, in force during the stimulus frames\n', ledNote);
        for li = 1:4
            fprintf(fid, '# LED%d: R=%.6g G=%.6g B=%.6g\n', li, ledGrid(li, 1), ledGrid(li, 2), ledGrid(li, 3));
        end
    end
    fprintf(fid, '%s\n', strjoin(T.Properties.VariableNames, ','));
    fclose(fid);
    writetable(T, outPath, 'WriteMode', 'append', 'WriteVariableNames', false);
    fprintf('[writeStimValuesCsv] %d rows -> %s\n', height(T), outPath);
end


function g = local_grid(v)
% Accept a 4x3 numeric grid; anything else (including []) means "no grid".
    if iscell(v), v = cell2mat(v); end
    g = [];
    if isnumeric(v) && isequal(size(v), [4 3]) && all(isfinite(v(:)))
        g = double(v);
    end
end
