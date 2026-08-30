function outPath = writeStimValuesCsv(outDir, stimName, seed, intendedByChannel)
% writeStimValuesCsv  Troubleshooting dump: what a seeded stimulus actually sends.
%
%   outPath = writeStimValuesCsv(outDir, stimName, seed, intendedByChannel)
%
% Writes one CSV row per (update, check, channel) with BOTH sides of the
% linearization:
%   seed, update, check_row, check_col, channel, intended_linear, sent_frac, sent_code
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
% Called by the AASeededGaussian* stimuli when rig_config.json has
% "debug_values_csv": true (loadRigConfig caches -- run `clear loadRigConfig`
% after flipping the flag). One timestamped file per trial, written next to the
% day's stim manifest. TROUBLESHOOTING ONLY: for analysis the values regenerate
% from the seed; leave the flag false in real experiments (a long checkerboard
% run makes millions of rows).

    if nargin < 1 || isempty(outDir), outDir = pwd; end
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
    writetable(T, outPath);
    fprintf('[writeStimValuesCsv] %d rows -> %s\n', height(T), outPath);
end
