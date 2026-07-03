function outPath = writeStimManifest(outDir, record)
% writeStimManifest  Append one trial's stimulus metadata to a per-day session log.
%
%   outPath = writeStimManifest(outDir, record)
%
%   Writes one JSON object per line (JSON Lines) to
%       <outDir>/YYYY_MM_DD_stim_manifest.jsonl
%   i.e. one row per trial, in trial order. The Neitz_Analysis_Suite pairs each row
%   with the Clampex .abf recorded for that trial BY ORDER (cross-checked by the
%   timestamp), then regenerates the exact stimulus noise from record.seed via
%   reproduce_noise -- so NO per-frame stimulus values need to be stored or shipped.
%
%   `record` is a struct of metadata: seed, mu, sigma, checks_x, checks_y,
%   n_updates, update_every_n_frames, refresh_rate_hz, stim_frames, gamma,
%   stim_type ('gaussian_noise' | 'checkerboard' | 'sq_wave' | 'jitter'),
%   cone_isolation ('S' | 'achromatic'), stimulus (function name), etc. A local
%   ISO-8601 `timestamp` field is added automatically.
%
%   Append-only: called once per trial by each stimulus function, so a stimulus run
%   standalone (outside Experimenter5000) is still recorded. The seed is the source
%   of truth; the noise is regenerated downstream, never stored here.

    if nargin < 1 || isempty(outDir), outDir = pwd; end

    record.timestamp = char(datetime('now', 'Format', 'yyyy-MM-dd''T''HH:mm:ss'));
    dateStr = char(datetime('now', 'Format', 'yyyy_MM_dd'));
    outPath = fullfile(outDir, [dateStr '_stim_manifest.jsonl']);

    fid = fopen(outPath, 'a');
    if fid < 0, error('writeStimManifest:cannotOpen', 'Cannot open %s for writing', outPath); end
    closer = onCleanup(@() fclose(fid));

    fprintf(fid, '%s\n', jsonencode(record));
end
