function outPath = writeStimManifest(outDir, record)
% writeStimManifest  Append one trial's stimulus metadata to a per-day session log.
%
%   outPath = writeStimManifest(outDir, record)
%
%   Writes one JSON object per line (JSON Lines) to
%       <outDir>/YYYY_MM_DD_stim_manifest.jsonl
%   i.e. one row per trial, in trial order. The Neitz_Analysis_Suite pairs each row
%   with the Clampex .abf recorded for that trial BY ORDER (and refuses to pair when the
%   row and recording counts disagree), then regenerates the exact stimulus noise from
%   record.seed via reproduce_noise -- so NO per-frame stimulus values need to be stored
%   or shipped. (The `timestamp` below is also an order cross-check: the suite's
%   apply_session_manifest compares each row's time to the paired .abf's recorded time,
%   catching an equal-count-but-shifted pairing, not just a count mismatch.)
%
%   `record` is a struct of metadata: seed, mu, sigma, checks_x, checks_y,
%   n_updates, update_every_n_frames, refresh_rate_hz, stim_frames, gamma,
%   stim_type ('gaussian_noise' | 'checkerboard' | 'sq_wave' | 'jitter'),
%   cone_isolation ('S' | 'achromatic'), stimulus (function name), etc. Three fields
%   are added automatically:
%     - `timestamp`      : local ISO-8601 time of the presentation.
%     - `rig`            : the rig hardware/calibration state from rig_config.json
%                          (projector, projector_mode, gamma + the full linearization
%                          model/LUT, channel_to_led, ...), so each recording is
%                          self-describing for the importer. Stamped AFTER the
%                          signature, so it does not affect stimulus identity.
%     - `stim_signature` : a hash of the record's DEFINING params EXCLUDING the seed
%                          (the seed varies per epoch for independent noise). Repeated
%                          epochs of the same PROTOCOL therefore share a stim_signature,
%                          so the importer groups them as N epochs of ONE stimulus; any
%                          protocol change (type/cone/mu/sigma/checks/...) differs.
%                          Computed per call, so it works for the plain trial-loop
%                          (Experimenter5000_v2) and runExperiment alike, with no
%                          coordination between calls and no change to acquisition.
%
%   Append-only: called once per trial by each stimulus function, so a stimulus run
%   standalone (outside Experimenter5000) is still recorded. The seed is the source
%   of truth; the noise is regenerated downstream, never stored here.

    if nargin < 1 || isempty(outDir), outDir = pwd; end

    % Signature FIRST, from the pure defining params (before signature/rig/timestamp
    % exist) so repeated identical stimuli hash identically regardless of rig or time.
    record.stim_signature = local_signature(record);
    % Then stamp the rig hardware/calibration state so every row is self-describing.
    % Deliberately AFTER the signature: the stimulus identity is independent of the rig.
    record.rig = local_rig_state();
    % Honor a pre-set timestamp: playAndLogTrial stamps it BEFORE play (acquisition time)
    % and writes the row AFTER play (to include frame_sync), so the .abf pairing still sees
    % ~play-start time. Stamp `now` only when the caller didn't (the standalone path).
    if ~isfield(record, 'timestamp') || isempty(record.timestamp)
        record.timestamp = char(datetime('now', 'Format', 'yyyy-MM-dd''T''HH:mm:ss'));
    end
    dateStr = char(datetime('now', 'Format', 'yyyy_MM_dd'));
    outPath = fullfile(outDir, [dateStr '_stim_manifest.jsonl']);

    fid = fopen(outPath, 'a');
    if fid < 0, error('writeStimManifest:cannotOpen', 'Cannot open %s for writing', outPath); end
    closer = onCleanup(@() fclose(fid));

    fprintf(fid, '%s\n', jsonencode(record));
end


function s = local_signature(rec)
% Deterministic 16-hex-char signature of a record's DEFINING params, EXCLUDING the seed
% and gamma. The seed varies per epoch (independent noise realizations) and gamma is live
% rig-calibration state (already captured in the `rig` block), so both are dropped before
% hashing: N epochs of the same PROTOCOL then share a signature and group as "N epochs of
% one stimulus" -- even across a mid-session recalibration -- while any protocol change
% (type/cone/mu/sigma/checks/...) changes it. jsonencode preserves struct field order, so
% identical protocols hash identically. Two independent 31-bit rolling hashes (kept < 2^53
% so double arithmetic is exact).
    % Drop everything that is NOT stimulus identity before hashing: seed (varies per epoch),
    % gamma (live rig state, already in `rig`), and the metadata / post-hoc fields
    % (timestamp, rig, stim_signature, frame_sync) -- so repeated epochs of one protocol
    % hash identically regardless of WHEN they ran or how many frames the display dropped.
    % (On the standalone path these fields are absent at hash time, so it is a no-op there.)
    for f = {'seed', 'gamma', 'timestamp', 'rig', 'stim_signature', 'frame_sync'}
        if isfield(rec, f{1}), rec = rmfield(rec, f{1}); end
    end
    b  = double(unicode2native(jsonencode(rec), 'UTF-8'));
    h1 = 0; h2 = 0;
    M  = 2^31 - 1;                          % Mersenne prime modulus
    for i = 1:numel(b)
        h1 = mod(h1 * 131      + b(i), M);
        h2 = mod(h2 * 16777619 + b(i), M);
    end
    s = lower([dec2hex(h1, 8), dec2hex(h2, 8)]);
end


function r = local_rig_state()
% The rig hardware/calibration state stamped into every manifest row (from
% rig_config.json via loadRigConfig), so each recording is self-describing for the
% importer: which projector + mode, the gamma that was inverted, and the
% projector-channel -> external-LED map. Missing fields are simply omitted.
    cfg = loadRigConfig();
    r = struct();
    for f = {'projector', 'projector_mode', 'gamma', 'gamma_model', 'gamma_source', ...
             'gamma_calibrated_on', 'dlp_lut_codes', 'dlp_lut_output_norm', ...
             'channel_to_led', 'led_spectra_file'}
        if isstruct(cfg) && isfield(cfg, f{1}), r.(f{1}) = cfg.(f{1}); end
    end
end
