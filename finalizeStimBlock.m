function tree = finalizeStimBlock(outDir, action, varargin)
% finalizeStimBlock  Post-hoc edit the day's NESTED stim manifest for the JUST-FINISHED block.
%
%   tree = finalizeStimBlock(outDir, 'append', suffix)
%   tree = finalizeStimBlock(outDir, 'discard')          the last block
%   tree = finalizeStimBlock(outDir, 'discard', nBlocks) the last nBlocks (one whole run)
%   tree = finalizeStimBlock(outDir, 'warn', entry)      flag a data-quality problem
%
%   The stimulusGUI "stimulus protocol complete" dialog calls this ONCE, when the whole
%   protocol has finished:
%
%   'append', suffix : append `suffix` to the CURRENT (last) cell's name -- refine the
%       patched-cell label after seeing the block's response (e.g. append "-ON"). Renames the
%       last cell node in place. The caller should also carry the new name forward (update
%       neitzSessionContext.cell_name / the GUI field) so later blocks stay under the renamed
%       cell.
%
%   'discard' : DISCARD the just-finished run -- remove the LAST cell's last nBlocks (default
%       1) and move their epochs to a top-level `discarded[]` array. nBlocks exists because a
%       protocol whose epochs do not all share one parameter set spans several blocks (the
%       GUI's "Update selected" splits them), and discarding that protocol has to take all of
%       them, not just the last. That array is the SKIP MARKER the
%       Analysis Suite reads (neitz.io.stim.build_import_plan): any .abf whose acquisition
%       time matches a discarded epoch's `timestamp` is skipped on import instead of surfacing
%       as an unsorted recording. If the cell is left with no blocks, the cell node is dropped.
%
%   'warn', entry : append `entry` (a struct; a .type field names the problem, e.g.
%       'projector_gamma_reverted' -> runExperiment's end-of-run projector check) to a
%       top-level `data_quality_warnings[]` array, stamped with a timestamp and the current
%       cell's name. Additive, like `discarded[]`: the Analysis Suite ignores it until
%       taught otherwise, but the flag lives WITH the data it questions.
%
%   Operates ONLY on <outDir>/YYYY_MM_DD_stim_manifest.json (today's), written back atomically.
%   NEVER touches the Clampex .abf files (Clampex owns those; "discard" only edits the manifest
%   + marks those abfs to skip). A no-op (warns) if today's manifest is absent. Returns the
%   updated tree (empty [] on no-op).

    if nargin < 1 || isempty(outDir), outDir = pwd; end
    dateStr    = char(datetime('now', 'Format', 'yyyy_MM_dd'));
    nestedPath = fullfile(outDir, [dateStr '_stim_manifest.json']);
    tree = [];
    if ~exist(nestedPath, 'file')
        fprintf(2, '[finalizeStimBlock] no manifest at %s -- nothing to %s.\n', nestedPath, action);
        return;
    end
    tree  = jsondecode(fileread(nestedPath));
    cells = local_asCellArray(local_getfield(tree, 'cells', {}));
    % Deep-normalize every collection to a cell array (so a single-element array re-encodes as
    % a JSON array, not an object) -- same guard as writeStimManifest.local_writeNested.
    for ii = 1:numel(cells)
        bl = local_asCellArray(local_getfield(cells{ii}, 'blocks', {}));
        for jj = 1:numel(bl)
            bl{jj}.epochs = local_asCellArray(local_getfield(bl{jj}, 'epochs', {}));
        end
        cells{ii}.blocks = bl;
    end
    if isempty(cells)
        fprintf(2, '[finalizeStimBlock] manifest has no cells -- nothing to %s.\n', action);
        return;
    end

    switch lower(char(action))
        case 'append'
            suffix = '';
            if ~isempty(varargin), suffix = char(string(varargin{1})); end
            if ~isempty(suffix)
                cur = char(string(local_getfield(cells{end}, 'cell_name', '')));
                cells{end}.cell_name = [cur suffix];
            end

        case 'discard'
            nBlocks = 1;
            if ~isempty(varargin) && isnumeric(varargin{1}) && isscalar(varargin{1})
                nBlocks = max(1, round(varargin{1}));
            end
            blocks = local_asCellArray(local_getfield(cells{end}, 'blocks', {}));
            if isempty(blocks)
                fprintf(2, '[finalizeStimBlock] last cell has no block to discard.\n');
            else
                nBlocks = min(nBlocks, numel(blocks));    % never eat an earlier run's blocks
                disc    = local_asCellArray(local_getfield(tree, 'discarded', {}));
                % Oldest-first, so `discarded[]` keeps acquisition order for the importer.
                for bi = numel(blocks) - nBlocks + 1 : numel(blocks)
                    blk = blocks{bi};
                    eps = local_asCellArray(local_getfield(blk, 'epochs', {}));
                    for k = 1:numel(eps)
                        e = eps{k};                      % keep the epoch + block context for the importer
                        e.cell_name      = local_getfield(cells{end}, 'cell_name', '');
                        e.block_label    = local_getfield(blk, 'label', '');
                        e.stim_signature = local_getfield(blk, 'stim_signature', '');
                        disc{end+1} = e; %#ok<AGROW>
                    end
                end
                tree.discarded = disc;
                blocks(end - nBlocks + 1 : end) = [];     % remove the discarded blocks
                if isempty(blocks)
                    cells(end) = [];                      % cell had only these -> drop the cell
                else
                    cells{end}.blocks = blocks;
                end
            end

        case 'warn'
            entry = struct();
            if ~isempty(varargin) && isstruct(varargin{1}), entry = varargin{1}; end
            if ~isfield(entry, 'type'), entry.type = 'unspecified'; end
            entry.timestamp = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
            entry.cell_name = local_getfield(cells{end}, 'cell_name', '');
            warns = local_asCellArray(local_getfield(tree, 'data_quality_warnings', {}));
            warns{end + 1} = entry;
            tree.data_quality_warnings = warns;

        otherwise
            error('finalizeStimBlock:badAction', ...
                  'action must be ''append'', ''discard'' or ''warn'' (got ''%s'').', char(action));
    end

    tree.cells = cells;
    local_atomicWrite(nestedPath, jsonencode(tree, 'PrettyPrint', true));
end


function c = local_asCellArray(x)
% Normalize jsondecode output (struct | struct array | cell) into a row cell array of nodes.
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
% Write to a temp file next to `path`, then rename over it -- a crash mid-write never leaves a
% half-written manifest (the reader always sees a complete document).
    tmp = [path '.tmp'];
    fid = fopen(tmp, 'w');
    if fid < 0, error('finalizeStimBlock:cannotOpen', 'Cannot open %s for writing', tmp); end
    fwrite(fid, text, 'char');
    fclose(fid);
    movefile(tmp, path, 'f');
end
