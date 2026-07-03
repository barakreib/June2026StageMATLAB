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
%   cone_isolation ('S' | 'achromatic'), stimulus (function name), etc. Two fields are
%   added automatically:
%     - `timestamp`      : local ISO-8601 time of the presentation.
%     - `stim_signature` : a hash of the record's DEFINING params. Repeated IDENTICAL
%                          stimuli (e.g. Experimenter5000_v2 running the same 2 Hz square
%                          wave 3x) get the SAME stim_signature, so the importer groups
%                          them as N epochs of ONE stimulus; different stimuli differ.
%                          Computed per call, so it works for the plain trial-loop
%                          (Experimenter5000_v2) and runExperiment alike, with no
%                          coordination between calls and no change to acquisition.
%
%   Append-only: called once per trial by each stimulus function, so a stimulus run
%   standalone (outside Experimenter5000) is still recorded. The seed is the source
%   of truth; the noise is regenerated downstream, never stored here.

    if nargin < 1 || isempty(outDir), outDir = pwd; end

    % Signature FIRST, from the pure defining params (before timestamp/signature exist),
    % so repeated identical stimuli hash identically.
    record.stim_signature = local_signature(record);
    record.timestamp = char(datetime('now', 'Format', 'yyyy-MM-dd''T''HH:mm:ss'));
    dateStr = char(datetime('now', 'Format', 'yyyy_MM_dd'));
    outPath = fullfile(outDir, [dateStr '_stim_manifest.jsonl']);

    fid = fopen(outPath, 'a');
    if fid < 0, error('writeStimManifest:cannotOpen', 'Cannot open %s for writing', outPath); end
    closer = onCleanup(@() fclose(fid));

    fprintf(fid, '%s\n', jsonencode(record));
end


function s = local_signature(rec)
% Deterministic 16-hex-char signature of a record's defining params. jsonencode
% preserves the struct's field order, so two identical records produce identical JSON
% (hence the same signature); any changed param changes it. Two independent 31-bit
% rolling hashes (kept < 2^53 so double arithmetic is exact) -> ~62-bit, pure MATLAB.
    b  = double(unicode2native(jsonencode(rec), 'UTF-8'));
    h1 = 0; h2 = 0;
    M  = 2^31 - 1;                          % Mersenne prime modulus
    for i = 1:numel(b)
        h1 = mod(h1 * 131      + b(i), M);
        h2 = mod(h2 * 16777619 + b(i), M);
    end
    s = lower([dec2hex(h1, 8), dec2hex(h2, 8)]);
end
