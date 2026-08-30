function outPath = writeStimManifest(outDir, record)
% writeStimManifest  Append one trial's stimulus metadata to the per-day NESTED session log.
%
%   outPath = writeStimManifest(outDir, record)
%
%   Writes ONE document per day, <outDir>/YYYY_MM_DD_stim_manifest.json, mirroring how a
%   session is organized:
%           day -> cells[] (patched cell) -> blocks[] (stimulus + label + params + LEDs)
%               -> epochs[] (each with its seed + timestamp + frame_sync).
%   Session/block/epoch context (which cell, which block, the LED grid) comes from a
%   base-workspace struct `neitzSessionContext` that runExperiment/stimulusGUI publish
%   (see local_sessionContext). A standalone stimulus run with no context logs under cell
%   "(standalone)" (or a base-workspace `cellName`). The whole tree is written atomically
%   (temp file + rename), so a crash mid-write never leaves a half-written manifest.
%   outPath (returned) is this .json file.
%
%   This is the ONE format the Neitz_Analysis_Suite imports (stim_io.build_import_plan): it
%   pairs the epochs to the Clampex .abf files BY TIMESTAMP (not blind order, so a false
%   start with no .abf or a discarded block doesn't mislabel data) and regenerates the exact
%   noise from record.seed -- so NO per-frame values are stored. The legacy flat
%   `*_stim_manifest.jsonl` dual-write was DROPPED (both sides now speak nested .json).
%
%   `record` is a struct of metadata: seed, mu, sigma, checks_x, checks_y,
%   n_updates, update_every_n_frames, refresh_rate_hz, stim_frames, gamma,
%   stim_type ('gaussian_noise' | 'checkerboard' | 'sq_wave' | 'jitter'),
%   cone_isolation ('S' | 'achromatic'), stimulus (function name), etc. Three fields
%   are added automatically:
%     - `timestamp`      : local ISO-8601 time of the presentation (the .abf pairing key).
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
%
%   Append-only: called once per trial by each stimulus function, so a stimulus run
%   standalone (outside Experimenter5000) is still recorded. The seed is the source
%   of truth; the noise is regenerated downstream, never stored here.
%
%   See finalizeStimBlock.m for the post-hoc edits the stimulusGUI "protocol complete"
%   dialog applies to this document (append a suffix to the current cell name, or DISCARD
%   the just-finished block -> its epochs move to a top-level `discarded[]` skip list).

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
    outPath = fullfile(outDir, [dateStr '_stim_manifest.json']);

    % Single source of truth: the NESTED day -> cell -> block -> epoch document, written
    % atomically. (The legacy flat .jsonl dual-write was dropped -- the Analysis Suite now
    % imports the nested .json directly, pairing epochs to .abf files by timestamp.)
    local_writeNested(outDir, record, dateStr);
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
    % gamma (live rig state, already in `rig`), the metadata / post-hoc fields
    % (timestamp, rig, stim_signature, frame_sync), and generated_script (the per-run
    % generated file carries a timestamped name, but an identical protocol regenerated
    % tomorrow is still the same stimulus) -- so repeated epochs of one protocol hash
    % identically regardless of WHEN they ran or how many frames the display dropped.
    % (On the standalone path these fields are absent at hash time, so it is a no-op there.)
    for f = {'seed', 'gamma', 'timestamp', 'rig', 'stim_signature', 'frame_sync', 'generated_script'}
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


% ============================ nested (hierarchical) manifest ============================
function local_writeNested(outDir, record, dateStr)
% Insert one trial into the day's nested day->cell->block->epoch document, appending to the
% CURRENT (last) cell/block so document order stays acquisition order, and write the whole
% tree back atomically. `record` already carries stim_signature, rig and timestamp.
    nestedPath = fullfile(outDir, [dateStr '_stim_manifest.json']);
    ctx = local_sessionContext();

    % ---- load or initialize the tree (a corrupt file is rebuilt; flat .jsonl is the net) ----
    if exist(nestedPath, 'file')
        try
            tree = jsondecode(fileread(nestedPath));
        catch
            tree = local_newTree(record, dateStr);
        end
    else
        tree = local_newTree(record, dateStr);
    end
    if ~isfield(tree, 'rig') && isfield(record, 'rig'), tree.rig = record.rig; end
    cells = local_asCellArray(local_getfield(tree, 'cells', {}));

    % Deep-normalize EVERY collection to a cell array up front. jsondecode collapses a
    % single-element JSON array to a struct; without this, an untouched single-epoch block
    % (or single-block cell) would re-encode as a JSON object instead of an array, making
    % the output shape inconsistent. Cell arrays always jsonencode as arrays.
    for ii = 1:numel(cells)
        bl = local_asCellArray(local_getfield(cells{ii}, 'blocks', {}));
        for jj = 1:numel(bl)
            bl{jj}.epochs = local_asCellArray(local_getfield(bl{jj}, 'epochs', {}));
        end
        cells{ii}.blocks = bl;
    end

    % ---- find-or-append the cell: match the LAST cell by name, else start a new one ----
    if ~isempty(cells) && strcmp(local_getfield(cells{end}, 'cell_name', ''), ctx.cell_name)
        ci = numel(cells);
    else
        cells{end+1} = struct('cell_name', ctx.cell_name, 'blocks', {{}});
        ci = numel(cells);
    end
    blocks = local_asCellArray(local_getfield(cells{ci}, 'blocks', {}));

    % ---- find-or-append the block: match the cell's LAST block by index + signature ----
    sig = local_getfield(record, 'stim_signature', '');
    if ~isempty(blocks) && local_sameBlock(blocks{end}, ctx.block_index, sig)
        bi = numel(blocks);
    else
        blocks{end+1} = local_newBlock(record, ctx);
        bi = numel(blocks);
    end

    % ---- append the epoch (index derived from what is already there) ----
    epochs = local_asCellArray(local_getfield(blocks{bi}, 'epochs', {}));
    epochs{end+1} = local_epochNode(record, numel(epochs) + 1);

    blocks{bi}.epochs = epochs;
    cells{ci}.blocks  = blocks;
    tree.cells        = cells;

    local_atomicWrite(nestedPath, jsonencode(tree, 'PrettyPrint', true));
end


function t = local_newTree(record, dateStr)
    t = struct('format', 'neitz-stim-manifest/2', 'date', strrep(dateStr, '_', '-'));
    if isfield(record, 'rig'), t.rig = record.rig; end
    t.cells = {};
end


function b = local_newBlock(record, ctx)
% A new block node: identity + label + LED grid + the params constant across its epochs.
    b = struct();
    if ~isempty(ctx.block_index), b.block_index = ctx.block_index; end
    b.label          = ctx.block_label;
    b.stimulus       = local_getfield(record, 'stimulus', '');
    b.stim_type      = local_getfield(record, 'stim_type', '');
    b.cone_isolation = local_getfield(record, 'cone_isolation', '');
    b.stim_signature = local_getfield(record, 'stim_signature', '');
    L = ctx.leds;
    b.leds   = struct('enabled',   logical(local_getfield(L, 'enabled', false)), ...
                      'mode',      double(local_getfield(L, 'mode', 0)), ...
                      'intensity', local_getfield(L, 'intensity', zeros(4, 3)));
    b.params = local_blockParams(record);
    b.epochs = {};
end


function p = local_blockParams(record)
% Everything in the record that DEFINES the block and is constant across its epochs:
% the record minus block identity, the per-epoch fields, and the session `rig`.
    p = record;
    for f = {'stimulus', 'stim_type', 'cone_isolation', 'stim_signature', ...
             'seed', 'timestamp', 'frame_sync', 'rig', 'epoch'}
        if isfield(p, f{1}), p = rmfield(p, f{1}); end
    end
end


function e = local_epochNode(record, n)
% One epoch: only what varies per presentation (seed, timestamp, frame-sync telemetry).
    e = struct('epoch', n);
    if isfield(record, 'seed'),       e.seed       = record.seed;       end
    e.timestamp = local_getfield(record, 'timestamp', '');
    if isfield(record, 'frame_sync'), e.frame_sync = record.frame_sync; end
end


function tf = local_sameBlock(block, blockIndex, sig)
% Same block as the incoming epoch? Same signature, and (when both known) same block index,
% so two consecutive identical-protocol GUI blocks stay separate nodes.
    tf = strcmp(local_getfield(block, 'stim_signature', ''), sig);
    if tf && ~isempty(blockIndex) && isfield(block, 'block_index')
        tf = isequal(block.block_index, blockIndex);
    end
end


function ctx = local_sessionContext()
% Read the session context runExperiment/stimulusGUI publish, with a standalone fallback.
    ctx = struct('cell_name', '', 'block_index', [], 'block_label', '', ...
                 'leds', struct('enabled', false));
    try
        c = evalin('base', 'neitzSessionContext');
        if isstruct(c)
            ctx.cell_name   = char(string(local_getfield(c, 'cell_name', '')));
            ctx.block_index = local_getfield(c, 'block_index', []);
            ctx.block_label = char(string(local_getfield(c, 'block_label', '')));
            ctx.leds        = local_getfield(c, 'leds', struct('enabled', false));
        end
    catch
        % no context published -> standalone run
    end
    if isempty(ctx.cell_name)
        try
            cn = evalin('base', 'cellName');
            if ~isempty(cn), ctx.cell_name = char(string(cn)); end
        catch
        end
    end
    if isempty(ctx.cell_name), ctx.cell_name = '(standalone)'; end
end


function c = local_asCellArray(x)
% Normalize whatever jsondecode produced (struct, struct array, or cell array) into a row
% cell array of nodes. jsondecode collapses a 1-element JSON array to a struct and an
% equal-field array to a struct array; a cell array survives -- this unifies all three.
    if isempty(x)
        c = {};
    elseif iscell(x)
        c = reshape(x, 1, []);
    elseif isstruct(x)
        c = num2cell(reshape(x, 1, []));
    else
        c = {x};
    end
end


function v = local_getfield(s, f, d)
    if isstruct(s) && isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end


function local_atomicWrite(path, text)
% Write text to a temp file next to `path`, then rename over it -- so a crash mid-write
% never leaves a half-written manifest (the reader always sees a complete document).
    tmp = [path '.tmp'];
    fid = fopen(tmp, 'w');
    if fid < 0, error('writeStimManifest:cannotOpenNested', 'Cannot open %s for writing', tmp); end
    fwrite(fid, text, 'char');
    fclose(fid);
    movefile(tmp, path, 'f');
end
