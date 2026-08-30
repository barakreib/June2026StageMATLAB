function stimulusGUI(mode)
% stimulusGUI  Point-and-click builder for a stimulus session.
%
%   stimulusGUI            opens the GUI.
%   stimulusGUI('__selftest__')  runs the headless logic self-test (no window).
%
% Pick a stimulus (left), edit its parameters, set epochs + a label, and "Add block" to
% append it to the protocol, then "Run experiment" — which builds a protocol struct and
% hands it to runExperiment.m (same path as Experimenter5000). Save/Load store the protocol
% as human-readable JSON under June2026StageMATLAB/experiments/.
%
% Epochs and blocks are two views of one thing. The protocol table lists one row per EPOCH
% — "5 epochs" + Add block appends five rows of that stimulus — so what you see is exactly
% what will be presented, in order. Underneath, those five stay ONE block -- blocks group
% epochs that share one parameter set. A protocol holds a single stimulus
% TYPE (the same stimulus with different parameters is fine — that is another block);
% adding a different one offers to clear the protocol first.
%
% Epochs already in the table are EDITABLE, not just removable. Click one and its block
% loads back into the top window — stimulus, parameters, label, epoch count. Change what
% you want and press "Update epochs" to write it back onto those same rows (with nothing
% selected it targets the only block, or asks before touching them all). "Add block" is
% then only for genuinely appending more. Under the table, "Remove epoch" drops the
% selected row — and the block with its last epoch — and "Clear all" empties the protocol.
%
% Parameters carry a redundant "duration (s)" row alongside stimFrames. Type seconds and the
% frame count follows the refreshRate (and vice versa), so the presentation length stays
% consistent; seconds snap to whole frames, and the box then shows what will really run.
%
% "Cancel" stops a run started by mistake. It takes effect at the next clean epoch boundary
% — an epoch whose Clampex sweep is already triggered always finishes and is logged, so no
% .abf is ever left without its manifest row. The partly-run protocol still gets its
% Keep/Discard prompt, so a mistyped run can be thrown away on the spot.
%
% The "stimulus protocol complete" Keep/Discard dialog appears ONCE, at the end of the whole
% run — never between epochs, even when they carry different parameters. Discard removes
% every epoch of the run from the manifest and marks their .abf files to skip on import.
%
% Seeds are handled automatically: for the seeded Gaussian stimuli runExperiment advances
% the seed by 1 per epoch from "seedBase" (each seed recorded in the day's stim manifest),
% so repeated epochs are INDEPENDENT noise. To add or edit a stimulus, edit stimRegistry.m.

    if nargin >= 1 && ischar(mode) && strcmp(mode, '__selftest__')
        selftest();
        return;
    end

    reg      = stimRegistry();
    local_checkRegistry(reg);
    blocks   = local_emptyBlocks();
    curEntry = reg(1);
    presets  = local_loadPresets();      % LED value presets from rig_config.json
    expDir    = fullfile(fileparts(mfilename('fullpath')), 'experiments');
    if ~exist(expDir, 'dir'), mkdir(expDir); end
    stateFile = fullfile(prefdir, 'neitzStimulusGUI_lastSession.json');
    h = struct();
    rigConn = [];   % handle to the SHARED rig (same object as base-workspace `rig`; see quickRig)
    cancelRequested = false;   % set by the Cancel button, polled by runExperiment (see onCancel)
    suspendSelCb    = false;   % re-entrancy guard while the epoch table's Selection is set in code
    monitor         = [];      % the live "Session monitor" window (stimulusMonitor)

    buildUI();
    onSelectStim();
    loadState();        % restore the last-used settings + protocol, if any
    refreshProtocol();  % unconditional: with no saved state loadState returns early, and the
                        % table buttons would otherwise start enabled over an empty protocol

    % ================= nested callbacks (share reg / blocks / curEntry / h) =================
    function buildUI()
        h.fig = uifigure('Name', 'Neitz Stimulus GUI', 'Position', [80 60 1100 1010], ...
            'CloseRequestFcn', @(s,e) onClose());
        outer = uigridlayout(h.fig, [1 2]);
        outer.ColumnWidth = {250, '1x'};

        lp = uipanel(outer, 'Title', 'Stimuli');
        lg = uigridlayout(lp, [2 1]); lg.RowHeight = {'1x', 74};
        h.list = uilistbox(lg, 'Items', {reg.name}, 'ValueChangedFcn', @(s,e) onSelectStim());
        uilabel(lg, 'Text', sprintf(['%d stimuli. Pick one, set its parameters and how many ' ...
            'epochs, then Add block. One stimulus type per protocol.'], numel(reg)), ...
            'WordWrap', 'on', 'FontAngle', 'italic');

        rp = uigridlayout(outer, [14 1]);
        % Row 3 (the parameter table) is resized to its content by showEntry: exactly tall
        % enough that refreshRate is never scrolled out of sight -- it is half of the duration
        % relationship -- and no taller, so short stimuli hand the slack to the epoch table,
        % which is the row that flexes. Tight RowSpacing buys that table a few more rows.
        rp.RowHeight  = {28, 24, local_paramTableHeight(8), 40, 20, '1x', 34, 36, 26, 132, 34, 36, 30, 40};
        rp.RowSpacing = 4;
        h.rightGrid   = rp;

        % ----- Cell (patched cell) -- session identity for the nested manifest -----
        cr = uigridlayout(rp, [1 3]); cr.ColumnWidth = {'fit', 240, '1x'}; cr.Padding = [6 3 6 3];
        uilabel(cr, 'Text', 'Cell:', 'FontWeight', 'bold');
        h.cellName = uieditfield(cr, 'text', 'Value', '', ...
            'Tooltip', ['Name / ID of the patched cell. Recorded in the nested session manifest ' ...
                        '(day -> cell -> block -> epochs). Update it each time you patch a new cell.']);
        uilabel(cr, 'Text', 'patched cell -> nested manifest', 'FontAngle', 'italic', 'FontColor', [0.45 0.45 0.45]);

        h.paramTitle = uilabel(rp, 'Text', 'Parameters', 'FontWeight', 'bold');
        % CellEditCallback keeps the redundant "duration (s)" row and stimFrames in sync:
        % type seconds and the frame count follows refreshRate (and vice versa).
        h.paramTable = uitable(rp, 'ColumnName', {'Parameter', 'Value'}, ...
            'ColumnEditable', [false true], 'ColumnWidth', {180, 220}, 'RowName', {}, ...
            'CellEditCallback', @(s, e) onParamEdit(e));

        er = uigridlayout(rp, [1 6]); er.ColumnWidth = {60, 70, 55, '1x', 130, 130};
        er.Padding = [6 3 6 3];
        uilabel(er, 'Text', 'Epochs:');
        h.epochs = uieditfield(er, 'numeric', 'Value', 5, 'Limits', [1 Inf], 'RoundFractionalValues', 'on', ...
            'Tooltip', ['How many presentations "Add block" appends -- one table row per epoch. ' ...
                        'They run back-to-back as one block. Keep/Discard is asked once, at ' ...
                        'the end of the whole protocol.']);
        uilabel(er, 'Text', 'Label:');
        h.label = uieditfield(er, 'text', 'Value', '');
        h.addBtn = uibutton(er, 'Text', 'Add block  v', 'ButtonPushedFcn', @(s,e) onAddBlock(), ...
            'Tooltip', 'Append this stimulus, these parameters and this many epochs as a NEW block.');
        h.updateBtn = uibutton(er, 'Text', 'Update epochs  v', 'ButtonPushedFcn', @(s,e) onUpdateEpochs(), ...
            'Tooltip', ['Push these parameters, label and epoch count onto epochs ALREADY in the ' ...
                        'table, instead of adding more. Acts on the selected epoch''s block; with ' ...
                        'nothing selected it acts on the only block, or asks before touching all.']);

        nr = uigridlayout(rp, [1 2]); nr.ColumnWidth = {'1x', 'fit'}; nr.Padding = [6 0 6 0];
        h.seedNote  = uilabel(nr, 'Text', '', 'FontAngle', 'italic');
        h.protoNote = uilabel(nr, 'Text', local_protoSummary(local_emptyBlocks()), ...
            'FontAngle', 'italic', 'FontColor', [0.45 0.45 0.45], 'HorizontalAlignment', 'right');

        % One row per EPOCH, not per block: "5 epochs" + Add block appends 5 identical rows,
        % so the table shows exactly what will be presented. Blocks still exist underneath --
        % they group epochs that share one parameter set (see onProtocolComplete).
        h.protoTable = uitable(rp, 'ColumnName', {'Epoch #', 'Stimulus', 'Label', 'Params'}, ...
            'ColumnWidth', {70, 240, 120, '1x'}, 'RowName', {}, 'SelectionType', 'row', ...
            'Multiselect', 'on', 'SelectionChangedFcn', @(s,e) onSelectEpoch());

        % Row operations sit with the rows they act on, under the table.
        tb = uigridlayout(rp, [1 4]); tb.ColumnWidth = {140, 130, 110, '1x'};
        tb.Padding = [6 2 6 2]; tb.ColumnSpacing = 8;
        h.updSelBtn = uibutton(tb, 'Text', 'Update selected', 'ButtonPushedFcn', @(s,e) onUpdateSelected(), ...
            'Tooltip', ['Apply the parameters and label above to JUST the selected epoch(s) ' ...
                        '(shift/ctrl-click for several). Those epochs are split into their own ' ...
                        'block, so one epoch can differ from its neighbours. The run is not ' ...
                        'interrupted either way -- Keep/Discard is still asked once, at the end.']);
        h.removeBtn = uibutton(tb, 'Text', 'Remove epoch', 'ButtonPushedFcn', @(s,e) onRemoveEpoch(), ...
            'Tooltip', 'Drop the selected epoch. Removing a block''s last epoch removes the block.');
        h.clearBtn = uibutton(tb, 'Text', 'Clear all', 'ButtonPushedFcn', @(s,e) onClearAll(), ...
            'Tooltip', 'Empty the protocol and start over (asks first).');
        uilabel(tb, 'Text', 'Click an epoch to load it above, edit, then Update.', ...
            'FontAngle', 'italic', 'FontColor', [0.45 0.45 0.45]);

        % ----- LEDs (NeitzLedRig): one 4x3 intensity grid; a preset fills it -----
        lh = uigridlayout(rp, [1 10]);
        lh.ColumnWidth = {'fit', 'fit', 130, 'fit', 110, 'fit', 184, 'fit', 'fit', '1x'};
        lh.Padding = [6 4 6 4]; lh.ColumnSpacing = 8;
        uilabel(lh, 'Text', 'LEDs:', 'FontWeight', 'bold');
        uilabel(lh, 'Text', 'Mode');
        h.ledMode = uidropdown(lh, 'Items', {'off (0)', 'DC red (1)', 'video RGB (2)', 'video RGB + sync (3)'}, ...
            'ItemsData', [0 1 2 3], 'Value', 2);
        uilabel(lh, 'Text', 'Port');
        h.ledPort = uieditfield(lh, 'text', 'Value', char(loadRigConfig('led_port', 'COM3')), ...
            'Tooltip', ['LED-driver port (default: rig_config led_port -- hard-coded is fastest). ' ...
                        'Type AUTO to probe for the FPGA instead (slower), or a /dev/cu.* node on macOS.']);
        uilabel(lh, 'Text', 'Preset');
        h.ledPreset = uidropdown(lh, 'Items', local_presetNames(presets), 'ValueChangedFcn', @(s,e) onPreset(), ...
            'Tooltip', 'Fill the LED grid with a 12-value preset from rig_config.json.');
        h.ledSetNow = uibutton(lh, 'Text', 'Set now', 'ButtonPushedFcn', @(s,e) onLedSetNow(), ...
            'Tooltip', ['Quick set: push the LED grid and Mode to the rig immediately, ' ...
                        'without running an experiment -- for LED changes between runs.']);
        h.ledOffNow = uibutton(lh, 'Text', 'Off now', 'ButtonPushedFcn', @(s,e) onLedOffNow(), ...
            'Tooltip', 'Quick set: mode 0 (all LEDs dark) immediately. Grid values are kept.');

        % status line (LED quick-set feedback)
        sel = uigridlayout(rp, [1 1]); sel.Padding = [44 2 6 2];
        h.ledStatus  = uilabel(sel, 'Text', '', 'FontAngle', 'italic', ...
            'FontColor', [0.45 0.45 0.45], 'HorizontalAlignment', 'right');

        % one 4x3 intensity grid (LED 0..3 x R/G/B), applied during the run
        tg = uigridlayout(rp, [1 1]); tg.Padding = [6 0 6 0];
        h.ledGrid = local_ledTable(tg);

        % ----- Stage/OpenGL server host (blank = this machine; an IPv4 = remote) -----
        sr = uigridlayout(rp, [1 3]); sr.ColumnWidth = {'fit', 200, '1x'}; sr.Padding = [6 3 6 3];
        uilabel(sr, 'Text', 'Stage host (IPv4):');
        h.stageHost = uieditfield(sr, 'text', 'Value', char(loadRigConfig('stage_host', 'localhost')), ...
            'Tooltip', ['The Stage/OpenGL server computer. Blank / "localhost" = this machine; an ' ...
                        'IPv4 (e.g. 192.168.0.49) connects to that computer. Saved to rig_config on Run.']);
        uilabel(sr, 'Text', 'blank / localhost = this machine', 'FontAngle', 'italic', 'FontColor', [0.45 0.45 0.45]);

        og = uigridlayout(rp, [1 8]); og.ColumnWidth = {'fit', 58, 'fit', 58, 'fit', 58, 'fit', 58};
        og.Padding = [6 3 6 3];
        onPlanEdit = @(s, e) pushPreview();   % these set the shape of every epoch
        uilabel(og, 'Text', 'preStim (s)');  h.preStim  = uieditfield(og, 'numeric', 'Value', 2, 'Limits', [0 Inf], 'ValueChangedFcn', onPlanEdit);
        uilabel(og, 'Text', 'postStim (s)'); h.postStim = uieditfield(og, 'numeric', 'Value', 1, 'Limits', [0 Inf], 'ValueChangedFcn', onPlanEdit);
        uilabel(og, 'Text', 'itp (s)');      h.itp      = uieditfield(og, 'numeric', 'Value', 3, 'Limits', [0 Inf], 'ValueChangedFcn', onPlanEdit);
        uilabel(og, 'Text', 'seedBase');     h.seedBase = uieditfield(og, 'numeric', 'Value', 2, 'Limits', [0 Inf], 'RoundFractionalValues', 'on');

        % Two independent enables, ON by default. Unchecking one makes Run skip
        % exactly those lines: Clampex off -> no acquisition trigger; LED driver
        % off -> runExperiment never opens NeitzLedRig (LEDs left untouched).
        dr = uigridlayout(rp, [1 4]); dr.ColumnWidth = {230, 160, 200, '1x'};
        dr.Padding = [6 2 6 2]; dr.ColumnSpacing = 24;
        h.triggerAcq = uicheckbox(dr, 'Text', 'Clampex acquisition', 'Value', true, 'FontWeight', 'bold', ...
            'Tooltip', ['ON: Run triggers Clampex acquisition each epoch. OFF: present via the Stage ' ...
                        'host only, no Clampex keystrokes (local dry run / no rig).']);
        h.ledEnable = uicheckbox(dr, 'Text', 'LED driver', 'Value', true, 'FontWeight', 'bold', ...
            'Tooltip', ['ON: Run opens NeitzLedRig and applies the LED grids during the session. ' ...
                        'OFF: the LED driver is not touched by Run.']);
        h.showMonitor = uicheckbox(dr, 'Text', 'Session monitor', 'Value', true, 'FontWeight', 'bold', ...
            'ValueChangedFcn', @(s,e) onMonitorToggle(), ...
            'Tooltip', ['Live monitor window: the planned session timeline while you build the ' ...
                        'protocol, then epoch progress, phase clock, stimulus frequencies and ' ...
                        'LED state while it runs. It carries its own Cancel button.']);

        % "New" is gone: "Clear all" under the table does the same job, next to the rows it clears.
        bg = uigridlayout(rp, [1 5]); bg.ColumnWidth = {'1x', 120, 120, '1.4x', 110};
        bg.Padding = [6 4 6 4];
        uilabel(bg, 'Text', '');   % spacer -- keeps Run / Cancel over on the right
        h.saveBtn = uibutton(bg, 'Text', 'Save...', 'ButtonPushedFcn', @(s,e) onSave());
        h.loadBtn = uibutton(bg, 'Text', 'Load...', 'ButtonPushedFcn', @(s,e) onLoad());
        h.runBtn  = uibutton(bg, 'Text', 'Run experiment', 'ButtonPushedFcn', @(s,e) onRun(), ...
            'BackgroundColor', [0.20 0.55 0.30], 'FontColor', 'w', 'FontWeight', 'bold', ...
            'Interruptible', 'on');   % MUST stay 'on' -- it is what lets Cancel fire mid-run
        h.cancelBtn = uibutton(bg, 'Text', 'Cancel', 'ButtonPushedFcn', @(s,e) onCancel(), ...
            'BackgroundColor', [0.70 0.15 0.15], 'FontColor', 'w', 'FontWeight', 'bold', ...
            'Enable', 'off', 'BusyAction', 'queue', ...
            'Tooltip', ['Stop the run at the next clean epoch boundary. An epoch whose Clampex ' ...
                        'sweep is already triggered is always finished and logged, so no .abf is ' ...
                        'left without its manifest row.']);

        % Locked / restored wholesale by lockUI-unlockUI for the duration of a run.
        h.lockList  = gobjects(0);
        h.lockState = strings(0);
    end

    function onSelectStim()
        showEntry(reg(h.list.ValueIndex), struct());   % registry defaults
    end

    function showEntry(entry, ps)
        % Fill the top window from `entry` + a params struct ({} = registry defaults).
        curEntry = entry;
        h.paramTable.Data = local_paramRows(curEntry, ps);   % + the derived "duration (s)" row
        h.rightGrid.RowHeight{3} = local_paramTableHeight(size(h.paramTable.Data, 1));
        h.paramTitle.Text = ['Parameters for:  ' curEntry.name '   (' curEntry.fn ')'];
        if local_seedArgFor(curEntry) > 0
            h.seedNote.Text = 'Seed: +1 per epoch from seedBase, recorded per epoch in the manifest.';
        else
            h.seedNote.Text = 'Seed: not applicable to this stimulus.';
        end
    end

    function onSelectEpoch()
        % Clicking an epoch loads its block back into the top window -- stimulus, parameters,
        % label and epoch count -- so it can be edited and pushed back with "Update epochs".
        if suspendSelCb, return; end
        sel = h.protoTable.Selection;
        if isempty(sel), return; end
        b = local_blockOfEpoch(blocks, sel(1));
        if b == 0, return; end
        k = find(strcmp({reg.fn}, blocks(b).fnName), 1);
        if isempty(k), return; end
        h.list.ValueIndex = k;
        h.epochs.Value    = max(1, round(blocks(b).epochs));
        h.label.Value     = char(blocks(b).label);
        showEntry(reg(k), blocks(b).params);
    end

    function onParamEdit(evt)
        % "duration (s)" and stimFrames are two views of the same thing. Editing either
        % (or refreshRate) rewrites the other so the presentation length stays consistent:
        % seconds -> frames = round(seconds * refreshRate), then seconds is snapped back to
        % the whole-frame value that will ACTUALLY be presented.
        data = h.paramTable.Data;
        if isempty(evt.Indices) || ~local_hasDuration(curEntry), return; end
        name = data{evt.Indices(1), 1};
        if ~any(strcmp(name, {'stimFrames', 'refreshRate', local_durRowName()})), return; end
        try
            h.paramTable.Data = local_syncDuration(curEntry, data, name);
        catch err
            h.paramTable.Data = data;    % leave the typed text in place to be corrected
            uialert(h.fig, err.message, 'Invalid parameter');
        end
    end

    function onAddBlock()
        % ONE stimulus type per protocol. Mixing them is what let a session chain several
        % different experiments back-to-back; the same stimulus with different parameters
        % is still fine -- that is simply another block.
        if ~local_sameStimAs(blocks, curEntry.fn)
            choice = uiconfirm(h.fig, sprintf(['This protocol already uses "%s", and a protocol ' ...
                'may only contain one stimulus type.\n\nClear it and start over with "%s"?'], ...
                blocks(1).stimName, curEntry.name), 'One stimulus per protocol', ...
                'Options', {'Cancel', 'Clear and add'}, 'DefaultOption', 1, 'CancelOption', 1);
            if ~strcmp(choice, 'Clear and add'), return; end
            blocks = local_emptyBlocks();
        end
        try
            ps = local_paramsFromRows(curEntry, h.paramTable.Data);
            b  = struct('stimName', curEntry.name, 'fnName', curEntry.fn, 'params', ps, ...
                        'epochs', round(h.epochs.Value), 'label', char(h.label.Value));
            blocks(end + 1) = b;
            refreshProtocol();
        catch err
            uialert(h.fig, err.message, 'Invalid parameter');
        end
    end

    function updateTableButtons()
        % Nothing in the table means nothing to update, remove or clear.
        onOff = {'off', 'on'};
        e = onOff{1 + ~isempty(blocks)};
        h.updateBtn.Enable = e;
        h.updSelBtn.Enable = e;
        h.removeBtn.Enable = e;
        h.clearBtn.Enable  = e;
    end

    function pushPreview()
        % Publish the protocol as a PLANNED session, so the monitor draws its timeline before
        % anything runs -- and redraws it every time the protocol changes. The first epoch
        % brings the window up (unless the monitor is switched off); an empty protocol never
        % opens it, so just launching the GUI does not cost a second window.
        if h.showMonitor.Value && ~isempty(blocks), openMonitor(); end
        if isempty(monitor) || ~isfield(monitor, 'fig') || ~isvalid(monitor.fig), return; end
        stimProgress('preview', local_previewPlan(reg, blocks, gatherOpts(), ...
                                                  strtrim(char(h.cellName.Value))));
    end

    function onMonitorToggle()
        if h.showMonitor.Value
            openMonitor();
            pushPreview();
        else
            closeMonitor();
        end
    end

    function onUpdateSelected()
        % Per-EPOCH edits: apply the top window to just the selected rows. Epochs within a
        % block share one parameter set, so the selected ones are split into their own block
        % -- purely a grouping; the run still stops only once, at the end, to ask Keep/Discard.
        if isempty(blocks)
            uialert(h.fig, 'There are no epochs yet -- use "Add block" first.', 'Nothing to update');
            return;
        end
        rows = h.protoTable.Selection;
        if isempty(rows)
            uialert(h.fig, ['Select the epoch(s) to update in the table below first ' ...
                '(shift- or ctrl-click for several).'], 'Select epochs');
            return;
        end
        if ~strcmp(blocks(1).fnName, curEntry.fn)
            uialert(h.fig, sprintf(['The parameter panel is showing "%s", but this protocol is ' ...
                '"%s". Click an epoch to load it back up, or use "Clear all" to start over ' ...
                'with a different stimulus.'], curEntry.name, blocks(1).stimName), 'Different stimulus');
            return;
        end
        try
            ps     = local_paramsFromRows(curEntry, h.paramTable.Data);
            blocks = local_applyToEpochs(blocks, rows, ps, char(h.label.Value));
        catch err
            uialert(h.fig, err.message, 'Invalid parameter');
            return;
        end
        refreshProtocol(rows);
    end

    function onUpdateEpochs()
        % Edit epochs that are ALREADY in the table instead of appending more: rewrite their
        % parameters, label and epoch count from the top window.
        if isempty(blocks)
            uialert(h.fig, 'There are no epochs to update yet -- use "Add block" first.', ...
                'Nothing to update');
            return;
        end
        if ~strcmp(blocks(1).fnName, curEntry.fn)
            uialert(h.fig, sprintf(['The parameter panel is showing "%s", but this protocol is ' ...
                '"%s". Click an epoch to load it back up, or use "Clear all" to start over with ' ...
                'a different stimulus.'], curEntry.name, blocks(1).stimName), 'Different stimulus');
            return;
        end
        sel = h.protoTable.Selection;
        if ~isempty(sel)
            target = local_blockOfEpoch(blocks, sel(1));
        elseif isscalar(blocks)
            target = 1;
        else
            choice = uiconfirm(h.fig, sprintf(['Nothing is selected in the epoch table, and this ' ...
                'protocol has %d blocks.\n\nApply these parameters, this label and %d epoch(s) ' ...
                'to ALL of them?'], numel(blocks), round(h.epochs.Value)), 'Update which epochs?', ...
                'Options', {'Cancel', 'Update all'}, 'DefaultOption', 1, 'CancelOption', 1);
            if ~strcmp(choice, 'Update all'), return; end
            target = 1:numel(blocks);
        end
        if isempty(target) || any(target == 0), return; end
        try
            ps     = local_paramsFromRows(curEntry, h.paramTable.Data);
            blocks = local_updateBlocks(blocks, target, ps, char(h.label.Value), h.epochs.Value);
        catch err
            uialert(h.fig, err.message, 'Invalid parameter');
            return;
        end
        keep = [];
        if ~isempty(sel), keep = sel(1); end
        refreshProtocol(keep);
    end

    function onRemoveEpoch()
        % Rows are EPOCHS: drop one epoch from the block that owns the selected row, and
        % drop the block itself once its last epoch is gone.
        sel = h.protoTable.Selection;
        if isempty(sel), return; end
        row    = sel(1);
        blocks = local_removeEpoch(blocks, row);
        refreshProtocol(min(row, sum([blocks.epochs])));   % keep the cursor where it was
    end

    function onClearAll()
        if ~isempty(blocks)
            choice = uiconfirm(h.fig, sprintf('Clear all %d epoch(s) from the protocol?', ...
                sum([blocks.epochs])), 'Clear all', 'Options', {'Cancel', 'Clear all'}, ...
                'DefaultOption', 1, 'CancelOption', 1);
            if ~strcmp(choice, 'Clear all'), return; end
        end
        blocks = local_emptyBlocks();
        refreshProtocol();
    end

    function onRun()
        if isempty(blocks)
            uialert(h.fig, 'Add at least one block first.', 'Nothing to run'); return;
        end
        % Persist the Stage host to rig_config (only if changed) so the stimulus scripts'
        % client.connect(stageHost()) reaches it. blank/localhost = this machine.
        hostNow = strtrim(char(h.stageHost.Value));
        if ~strcmp(hostNow, strtrim(char(loadRigConfig('stage_host', 'localhost'))))
            try
                setRigConfig('stage_host', hostNow);
            catch err
                uialert(h.fig, ['Could not save Stage host to rig_config: ' err.message], 'rig_config');
                return;
            end
        end
        protocol = local_buildProtocol(reg, blocks);
        opts     = gatherOpts();
        opts.cellName = strtrim(char(h.cellName.Value));   % patched cell -> nested manifest (Run only)
        opts.onProtocolComplete = @onProtocolComplete;     % ONE dialog, at the end of the run
        % Cancel hook: runExperiment polls this between epochs and inside its waits, so a
        % click on Cancel stops the session without an error (see onCancel).
        % MUST be a handle to the NESTED isCancelledNow, not @() cancelRequested -- an
        % anonymous handle would capture the flag BY VALUE at this line and freeze it
        % false, so Cancel would silently do nothing.
        cancelRequested  = false;
        opts.isCancelled = @isCancelledNow;
        if opts.leds.enabled
            % runExperiment opens its OWN NeitzLedRig; free the quick-set connection first
            % or that open fails with "port in use". (LED driver not enabled: keep ours, so
            % quick-set values persist untouched through the run.)
            releaseQuickRig();
        end
        % Live monitor: runExperiment and playAndLogTrial publish through stimProgress, the
        % monitor draws, and its Cancel routes straight back to onCancel below. The hooks
        % stay attached after the run -- the window keeps previewing the protocol.
        if h.showMonitor.Value, openMonitor(); end
        setRunning(true);
        % Held only for its destructor: re-enables the UI on ANY exit (finish, error, Ctrl-C).
        restoreButtons = onCleanup(@() setRunning(false));
        try
            st = runExperiment(protocol, opts);
            if getfielddef(st, 'cancelled', false)
                uialert(h.fig, sprintf(['Run cancelled after %d epoch(s). Every epoch that was ' ...
                    'triggered finished and was logged, so the manifest still lines up with the ' ...
                    '.abf files.'], getfielddef(st, 'epochs', 0)), 'Cancelled', 'Icon', 'warning');
            else
                uialert(h.fig, sprintf('Experiment finished (%d block(s)).', numel(blocks)), 'Done', 'Icon', 'success');
            end
        catch err
            % Tell the monitor too, and raise the main window first: during a pre-flight the
            % monitor is the window in front, and an alert behind it never gets read.
            stimProgress('failed', struct('message', err.message));
            figure(h.fig);
            uialert(h.fig, err.message, 'runExperiment error');
        end
    end

    function tf = isCancelledNow()
        tf = cancelRequested;
    end

    function onCancel()
        % Runs AS AN INTERRUPT of the Run callback (uibutton Interruptible='on' + the waits
        % inside runExperiment let the event queue drain). Keep it short: just raise the flag.
        cancelRequested    = true;
        h.cancelBtn.Enable = 'off';
        h.cancelBtn.Text   = 'Cancelling';
        setLedStatus('Cancel requested -- stopping at the end of the current epoch.', [0.85 0.45 0.10]);
    end

    function setRunning(tf)
        % A run now keeps the event queue alive the whole way through (runExperiment waits in
        % slices, and playAndLogTrial waits out the presentation instead of blocking in
        % getPlayInfo), so EVERY control is live mid-run unless it is disabled. Lock the lot
        % -- one mistimed click on the stimulus list or the LED grid would otherwise land in
        % the middle of a sweep -- and leave exactly one thing clickable: Cancel.
        if tf
            lockUI();
        else
            unlockUI();
        end
        h.cancelBtn.Text = 'Cancel';
        drawnow;   % repaint before runExperiment takes the thread back
    end

    function lockUI()
        c = findall(h.fig, '-property', 'Enable', '-not', 'Type', 'uilabel');
        c = c(arrayfun(@(x) ~isequal(x, h.cancelBtn), c));
        h.lockList  = c;
        h.lockState = arrayfun(@(x) string(x.Enable), c);
        set(c, 'Enable', 'off');
        h.cancelBtn.Enable = 'on';     % the one live control during a run
    end

    function unlockUI()
        if isfield(h, 'lockList')
            for k = 1:numel(h.lockList)
                if isvalid(h.lockList(k))
                    h.lockList(k).Enable = char(h.lockState(k));
                end
            end
        end
        h.lockList         = gobjects(0);
        h.lockState        = strings(0);
        h.cancelBtn.Enable = 'off';
        updateTableButtons();   % the protocol may have emptied while the snapshot was held
    end

    function openMonitor()
        if isempty(monitor) || ~isfield(monitor, 'fig') || ~isvalid(monitor.fig)
            monitor = stimulusMonitor(h.fig);
        end
        % Hooks live as long as the WINDOW does, not just as long as a run -- that is what
        % lets the timeline preview the protocol while you are still building it.
        stimProgress('attach', @(kind, msg) monitor.update(kind, msg), @onCancel);
    end

    function closeMonitor()
        stimProgress('detach');
        if ~isempty(monitor) && isfield(monitor, 'fig') && isvalid(monitor.fig)
            delete(monitor.fig);
        end
        monitor = [];
    end

    function newCell = onProtocolComplete(nBlocks, nEpochs, cellName)
        % runExperiment fires this ONCE, when the whole protocol has finished -- never between
        % epochs, even when they carry different parameters (that only makes them separate
        % blocks, and every epoch's own parameters are in its manifest row regardless).
        % KEEP (optionally appending a suffix to the cell name) or DISCARD the whole run.
        % Manifest edits target `pwd` -- where the stimulus functions write the nested manifest
        % (they call playAndLogTrial(..., pwd, ...)). Returns the (possibly renamed) cell name.
        newCell = cellName;
        res = local_protocolCompleteDialog(h.fig, nBlocks, nEpochs, cellName);
        if strcmp(res.action, 'discard')
            try
                % nBlocks, not 1: a protocol with per-epoch parameters spans several blocks
                % and discarding it has to take all of them.
                finalizeStimBlock(pwd, 'discard', nBlocks);
            catch err
                uialert(h.fig, ['Could not discard the run in the manifest: ' err.message], 'Discard failed');
            end
        elseif ~isempty(res.suffix)
            try
                finalizeStimBlock(pwd, 'append', res.suffix);
                newCell = [char(cellName) res.suffix];
                h.cellName.Value = newCell;      % reflect the refined cell name in the GUI
            catch err
                uialert(h.fig, ['Could not rename the cell in the manifest: ' err.message], 'Rename failed');
            end
        end
    end

    function onSave()
        if isempty(blocks), uialert(h.fig, 'Nothing to save.', 'Empty'); return; end
        [f, p] = uiputfile('*.json', 'Save experiment', fullfile(expDir, 'experiment.json'));
        if isequal(f, 0), return; end
        txt = local_experimentToJson(blocks, gatherOpts());
        fid = fopen(fullfile(p, f), 'w'); fwrite(fid, txt, 'char'); fclose(fid);
        uialert(h.fig, ['Saved: ' f], 'Saved', 'Icon', 'success');
    end

    function onLoad()
        [f, p] = uigetfile('*.json', 'Load experiment', [expDir filesep]);
        if isequal(f, 0), return; end
        try
            [blocks, o] = local_jsonToExperiment(reg, fileread(fullfile(p, f)));
            h.preStim.Value  = getfielddef(o, 'preStim', 2);
            h.postStim.Value = getfielddef(o, 'postStim', 1);
            h.itp.Value      = getfielddef(o, 'itp', 3);
            h.seedBase.Value = getfielddef(o, 'seedBase', 2);
            if isfield(o, 'triggerAcq'), h.triggerAcq.Value = logical(o.triggerAcq); end
            applyLedsToUI(getfielddef(o, 'leds', struct()));
            refreshProtocol();
            % Point the stimulus list at what was just loaded, so the parameter table matches
            % the protocol and "Add block" extends it instead of tripping the one-stimulus rule.
            if ~isempty(blocks)
                k = find(strcmp({reg.fn}, blocks(1).fnName), 1);
                if ~isempty(k), h.list.ValueIndex = k; onSelectStim(); end
            end
            if local_mixedStims(blocks)
                uialert(h.fig, ['This saved experiment mixes several stimulus types. It will still ' ...
                    'run as saved, but new protocols are limited to one stimulus type -- adding a ' ...
                    'different stimulus will offer to clear the protocol first.'], ...
                    'Mixed stimuli', 'Icon', 'warning');
            end
        catch err
            uialert(h.fig, err.message, 'Load failed');
        end
    end

    function refreshProtocol(keepRow)
        % keepRow: re-select this epoch after the rebuild, so editing does not lose your place.
        % Guarded, because setting Selection can re-enter onSelectEpoch and clobber the top
        % window with the block's stored values.
        if nargin < 1, keepRow = []; end
        h.protoTable.Data = local_epochRows(reg, blocks);
        h.protoNote.Text  = local_protoSummary(blocks);
        updateTableButtons();
        pushPreview();      % the monitor's timeline tracks the protocol as you build it
        suspendSelCb = true;
        n    = size(h.protoTable.Data, 1);
        keep = keepRow(keepRow >= 1 & keepRow <= n);
        if ~isempty(keep)
            h.protoTable.Selection = keep;
        end
        suspendSelCb = false;
    end

    function o = gatherOpts()
        % The two checkboxes map straight through: triggerAcq -> Clampex acquisition,
        % o.leds.enabled -> LED driver (set in gatherLeds). Unchecked = Run skips it.
        o = struct('preStim', h.preStim.Value, 'postStim', h.postStim.Value, ...
                   'itp', h.itp.Value, 'seedBase', round(h.seedBase.Value), ...
                   'triggerAcq', logical(h.triggerAcq.Value));
        o.leds = gatherLeds();
    end

    % ----- remember the last-used session across GUI opens (in prefdir, not the repo) -----
    function onClose()
        if ~isempty(h.lockList)     % a run is in flight (lockUI populated it)
            % Always offer a way OUT. Refusing outright is how you end up killing MATLAB to
            % escape a run that will not stop; "Close anyway" drops the hooks and goes.
            choice = uiconfirm(h.fig, ['A run is in progress. Cancel it and let it stop at the ' ...
                'next epoch boundary, or close anyway (the run keeps going until it finishes ' ...
                'the current epoch).'], 'Run in progress', ...
                'Options', {'Stay open', 'Close anyway'}, 'DefaultOption', 1, 'CancelOption', 1);
            if ~strcmp(choice, 'Close anyway'), return; end
            cancelRequested = true;      % ask the run to stop on its way out
            stimProgress('detach');
        end
        closeMonitor();
        saveState();
        % The shared `rig` stays CONNECTED across GUI closes (it lives on in the
        % base workspace) -- scripts and the prompt keep using it without a
        % reconnect. `clear rig` at the prompt darkens + closes it when done.
        delete(h.fig);
    end

    function saveState()
        try
            o = struct('preStim', h.preStim.Value, 'postStim', h.postStim.Value, ...
                       'itp', h.itp.Value, 'seedBase', round(h.seedBase.Value), ...
                       'triggerAcq', logical(h.triggerAcq.Value), ...
                       'stimIndex', h.list.ValueIndex);
            o.leds = gatherLeds();
            fid = fopen(stateFile, 'w');
            if fid > 0
                fwrite(fid, local_experimentToJson(blocks, o), 'char');
                fclose(fid);
            end
        catch
            % never block closing on a save error
        end
    end

    function loadState()
        if ~exist(stateFile, 'file'), return; end
        try
            [blk, o] = local_jsonToExperiment(reg, fileread(stateFile));
        catch
            return;   % ignore a corrupt / outdated state file
        end
        h.preStim.Value    = getfielddef(o, 'preStim', 2);
        h.postStim.Value   = getfielddef(o, 'postStim', 1);
        h.itp.Value        = getfielddef(o, 'itp', 3);
        h.seedBase.Value   = getfielddef(o, 'seedBase', 2);
        h.triggerAcq.Value = logical(getfielddef(o, 'triggerAcq', true));
        applyLedsToUI(getfielddef(o, 'leds', struct()));
        si = round(getfielddef(o, 'stimIndex', 1));
        if si >= 1 && si <= numel(reg), h.list.ValueIndex = si; onSelectStim(); end
        blocks = blk;
        refreshProtocol();
    end

    function leds = gatherLeds()
        leds = struct('enabled', logical(h.ledEnable.Value), ...
                      'port', char(h.ledPort.Value), ...
                      'mode', double(h.ledMode.Value), ...
                      'intensity', local_coerce43(h.ledGrid.Data));   % runExperiment applies this grid
    end

    function onPreset()
        name = h.ledPreset.Value;
        k = find(strcmp({presets.name}, name), 1);
        if isempty(k), return; end     % the "(load preset...)" placeholder row
        h.ledGrid.Data = presets(k).values;
    end

    function applyLedsToUI(L)
        if ~isstruct(L), return; end
        h.ledEnable.Value = logical(getfielddef(L, 'enabled', true));   % LED driver ON by default
        p = char(getfielddef(L, 'port', ''));
        if isempty(p) || strcmpi(p, 'AUTO')   % legacy saved sessions: snap to the fast
            p = char(loadRigConfig('led_port', 'COM3'));   % configured port (type AUTO
        end                                                % in the field to re-probe)
        h.ledPort.Value = p;
        m = double(getfielddef(L, 'mode', 2));
        if ismember(m, [0 1 2 3]), h.ledMode.Value = m; end
        % single grid: prefer `intensity`; fall back to a legacy During grid, else zeros
        grid = getfielddef(L, 'intensity', getfielddef(L, 'during_epochs', zeros(4, 3)));
        h.ledGrid.Data = local_coerce43(grid);
    end

    % ----- LED quick-set: drive the rig NOW, between OpenGL runs (no experiment) -----
    function r = quickRig()
        % ONE shared rig per MATLAB session: reuse the GUI's live handle, else
        % ADOPT a connected `rig` from the base workspace (e.g. left by demoLedRig
        % or the prompt), else connect and PUBLISH the new rig to the base
        % workspace as `rig`. GUI, scripts and prompt share one open COM port --
        % no delete-and-rebuild, no reconnect cost, no "port in use" fights.
        if ~isempty(rigConn) && isvalid(rigConn) && rigConn.isConnected()
            r = rigConn; return;
        end
        rigConn = [];
        try
            wr = evalin('base', 'rig');
            if isa(wr, 'NeitzLedRig') && isvalid(wr) && wr.isConnected()
                rigConn = wr;
                r = rigConn;
                return;
            end
        catch
            % no usable `rig` in the base workspace -- connect below
        end
        if exist('NeitzLedRig', 'class') ~= 8   % same path shim as runExperiment
            addpath(fullfile(fileparts(mfilename('fullpath')), 'ml-uled'));
        end
        setLedStatus('Connecting to the LED driver...', [0.45 0.45 0.45]);
        rigConn = NeitzLedRig(strtrim(char(h.ledPort.Value)));   % 'AUTO' = probe
        assignin('base', 'rig', rigConn);   % publish: scripts + prompt reuse this rig
        r = rigConn;
    end

    function releaseQuickRig()
        % Fully release the shared COM pathway (used before an LED-enabled Run,
        % which opens its OWN connection). Deleting darkens (mode 0) + closes.
        if ~isempty(rigConn)
            try
                delete(rigConn);
            catch
            end
            rigConn = [];
        end
        try   % the same handle may live on as base `rig` -- remove that alias too
            evalin('base', ...
                'if exist(''rig'',''var'') && isa(rig,''NeitzLedRig''), delete(rig); clear(''rig''); end');
        catch
        end
    end

    function onLedSetNow()
        try
            r    = quickRig();
            vals = local_coerce43(h.ledGrid.Data);
            ok   = r.setMode(0);               % dark while the registers load (as runExperiment)
            cols = {'r', 'g', 'b'};
            for li = 1:4
                for ci = 1:3
                    ok = r.setIntensity(li - 1, cols{ci}, vals(li, ci)) && ok;
                end
            end
            md = h.ledMode.Value;
            ok = r.setMode(md) && ok;
            if ~ok
                setLedStatus('Sent, but not every write was ACKed -- check the rig.', [0.85 0.45 0.10]);
                return;
            end
            % Modes 2/3 are colour-field video: the LEDs stay DARK until the projector
            % (or setTtlDebug) drives i_RGB. Say so, so a "nothing lit" isn't mistaken
            % for a failure. Mode 1 (DC red) lights immediately from the grid's R column.
            if md == 2 || md == 3
                setLedStatus(sprintf(['Set: LED grid, mode %d (video) on %s -- LEDs light only while ' ...
                    'the projector drives i_RGB. Use mode 1 (DC red) to see them now.'], ...
                    md, char(r.Port)), [0.20 0.40 0.55]);
            else
                setLedStatus(sprintf('LEDs set now: LED grid, mode %d, on %s.', ...
                    md, char(r.Port)), [0.13 0.45 0.20]);
            end
        catch err
            onLedError(err);
        end
    end

    function onLedOffNow()
        try
            r = quickRig();
            if r.setMode(0)
                setLedStatus(sprintf('LEDs OFF (mode 0) on %s. Grid values kept.', char(r.Port)), [0.13 0.45 0.20]);
            else
                setLedStatus('Mode-0 write was not ACKed -- check the rig.', [0.85 0.45 0.10]);
            end
        catch err
            onLedError(err);
        end
    end

    function onLedError(err)
        % Loud, actionable failure feedback -- a popup (not just the small status
        % label) so a failed quick-set can't be mistaken for "nothing happened".
        releaseQuickRig();   % drop any half-open handle so the next click retries clean
        msg  = err.message;
        port = strtrim(char(h.ledPort.Value));
        low  = lower(msg);
        if contains(low, 'denied') || contains(low, 'in use') || contains(low, 'busy') || contains(low, 'portbusy')
            msg = sprintf(['%s is busy -- another program already holds it. Close the C# uLED GUI, ' ...
                'or run "clear rig" at the MATLAB prompt if a script left one open, then click again.'], port);
        elseif contains(low, 'no ') && contains(low, 'ack')
            msg = sprintf(['%s opened but the LED-driver FPGA did not answer. Check the board is ' ...
                'powered and on %s (Device Manager), or type AUTO in the Port field to re-probe.'], port, port);
        end
        setLedStatus(['LED error: ' msg], [0.75 0.15 0.15]);
        uialert(h.fig, msg, 'LED quick-set failed');
    end

    function setLedStatus(msg, rgb)
        h.ledStatus.Text      = msg;
        h.ledStatus.FontColor = rgb;
        h.ledStatus.Tooltip   = msg;    % full text on hover if the label clips
        drawnow limitrate
    end
end


% ===================== "stimulus protocol complete" dialog =====================
function res = local_protocolCompleteDialog(parentFig, nBlocks, nEpochs, cellName)
% Modal dialog shown ONCE, when the whole protocol has finished: KEEP the run (optionally
% appending a suffix to the cell name) or DISCARD it. Returns
% struct('action','keep'|'discard','suffix',<text>). Blocks via uiwait; closing the window ==
% Keep (the safe default). Purely a chooser -- the caller (onProtocolComplete) applies the
% choice to the manifest via finalizeStimBlock.
    res = struct('action', 'keep', 'suffix', '');
    pos = [500 400 470 220];
    try
        if ~isempty(parentFig) && isvalid(parentFig)
            pp = parentFig.Position;
            pos = [pp(1) + 140, pp(2) + 260, 470, 220];
        end
    catch
    end
    d = uifigure('Name', 'Stimulus protocol complete', 'Position', pos, 'Resize', 'off');
    g = uigridlayout(d, [5 2]);
    g.RowHeight   = {'fit', 'fit', 'fit', '1x', 'fit'};
    g.ColumnWidth = {'fit', '1x'};

    t = uilabel(g, 'Text', sprintf('Protocol finished on cell "%s":  %d epoch(s)%s.', ...
                    char(string(cellName)), nEpochs, local_blockSuffix(nBlocks)), ...
                'WordWrap', 'on', 'FontWeight', 'bold');
    t.Layout.Row = 1; t.Layout.Column = [1 2];

    l2 = uilabel(g, 'Text', 'Append to cell name:');
    l2.Layout.Row = 2; l2.Layout.Column = 1;
    ef = uieditfield(g, 'text', 'Value', '', ...
        'Tooltip', 'Optional suffix appended to this cell''s name in the manifest, e.g. "-ON".');
    ef.Layout.Row = 2; ef.Layout.Column = 2;

    hint = uilabel(g, 'Text', ['Keep saves the whole run (with any suffix). Discard removes ' ...
        'every epoch of it from the manifest and marks their .abf files to skip on import.'], ...
        'WordWrap', 'on', 'FontAngle', 'italic', 'FontColor', [0.45 0.45 0.45]);
    hint.Layout.Row = 3; hint.Layout.Column = [1 2];

    bdisc = uibutton(g, 'Text', 'Discard', 'BackgroundColor', [0.70 0.15 0.15], 'FontColor', 'w', ...
        'FontWeight', 'bold', 'ButtonPushedFcn', @(s, e) onChoice('discard'));
    bdisc.Layout.Row = 5; bdisc.Layout.Column = 1;
    bkeep = uibutton(g, 'Text', 'Keep', 'BackgroundColor', [0.20 0.55 0.30], 'FontColor', 'w', ...
        'FontWeight', 'bold', 'ButtonPushedFcn', @(s, e) onChoice('keep'));
    bkeep.Layout.Row = 5; bkeep.Layout.Column = 2;

    d.CloseRequestFcn = @(s, e) onChoice('keep');    % closing the window == Keep (safe default)
    uiwait(d);

    function onChoice(action)
        res.action = action;
        if strcmp(action, 'keep')
            res.suffix = strtrim(char(ef.Value));
        else
            res.suffix = '';
        end
        uiresume(d);
        delete(d);
    end
end


function s = local_blockSuffix(nBlocks)
% Only mention blocks when there is more than one -- they are an implementation detail of
% per-epoch parameters, not something the operator asked for.
    if nBlocks > 1
        s = sprintf(' in %d parameter block(s)', nBlocks);
    else
        s = '';
    end
end


% ===================== pure logic (shared by the GUI and the self-test) =====================
function b = local_emptyBlocks()
    b = struct('stimName', {}, 'fnName', {}, 'params', {}, 'epochs', {}, 'label', {});
end

function t = local_ledTable(parent)
    t = uitable(parent, 'Data', zeros(4, 3), 'ColumnName', {'R', 'G', 'B'}, ...
        'RowName', {'LED 0', 'LED 1', 'LED 2', 'LED 3'}, 'ColumnEditable', [true true true], ...
        'ColumnWidth', {52, 52, 52}, ...
        'Tooltip', 'Per-LED intensity (0..1 linear duty; pre-distort like lcGammaCorrect for eye-linear).');
end

function m = local_coerce43(v)
    if iscell(v), v = cell2mat(v); end
    v = double(v);
    if isequal(size(v), [4, 3]), m = v; else, m = zeros(4, 3); end
end

function p = local_loadPresets()
    raw = loadRigConfig('led_presets', []);
    if iscell(raw), items = raw; elseif isstruct(raw), items = num2cell(raw); else, items = {}; end
    p = struct('name', {}, 'values', {});
    for i = 1:numel(items)
        r = items{i};
        if isstruct(r) && isfield(r, 'name') && isfield(r, 'values')
            p(end + 1) = struct('name', char(string(r.name)), 'values', local_coerce43(r.values)); %#ok<AGROW>
        end
    end
    if isempty(p), p = struct('name', {'Off'}, 'values', {zeros(4, 3)}); end
end

function items = local_presetNames(presets)
    names = arrayfun(@(p) char(string(p.name)), presets(:)', 'UniformOutput', false);
    items = [{'(load preset...)'}, names];
end

function idx = local_editableParams(entry)
    idx = find(~strcmp(entry.params(:, 3), 'seed'))';
end


% ---------- redundant "duration (s)" <-> stimFrames (driven by refreshRate) ----------

function px = local_paramTableHeight(nRows)
% Height that fits a uitable header + nRows with no scrollbar. Kept in one place so the
% parameter table always shows every parameter -- clipping refreshRate would hide half of
% the duration <-> stimFrames relationship.
    px = 44 + 24 * max(1, nRows);
end

function n = local_durRowName()
% Display name of the DERIVED parameter row. Not an argument of any stimulus -- it is
% stripped before the args are built (local_paramsFromRows). The space + "(s)" keep it
% from ever colliding with a real parameter name.
    n = 'duration (s)';
end

function tf = local_isDerivedRow(name)
    tf = strcmp(name, local_durRowName());
end

function tf = local_hasDuration(entry)
% A stimulus gets the duration row only if seconds are actually convertible for it.
    tf = any(strcmp(entry.params(:, 1), 'stimFrames')) && any(strcmp(entry.params(:, 1), 'refreshRate'));
end

function [frames, dur] = local_framesFromDuration(dur, refreshRate)
% Seconds -> whole frames, and the seconds that will ACTUALLY be presented. Typing 5 s at
% 60 Hz gives 300 frames; a duration that is not a whole number of frames snaps to the
% nearest one, and the returned dur reports that -- the box never claims a length the
% projector cannot present.
    if ~isscalar(refreshRate) || ~isfinite(refreshRate) || refreshRate <= 0
        error('stimulusGUI:badRefresh', ...
              'refreshRate must be a positive number to convert seconds <-> frames (got %s).', ...
              num2str(refreshRate));
    end
    if ~isscalar(dur) || ~isfinite(dur) || dur < 0
        error('stimulusGUI:badDuration', 'duration (s) must be a number >= 0 (got %s).', num2str(dur));
    end
    frames = max(1, round(dur * refreshRate));
    dur    = frames / refreshRate;
end

function dur = local_durationFromFrames(frames, refreshRate)
% Frames -> seconds. NaN when refreshRate is not usable, so the row shows "NaN" rather
% than a made-up number.
    if ~isscalar(refreshRate) || ~isfinite(refreshRate) || refreshRate <= 0
        dur = NaN;
    else
        dur = double(frames) / double(refreshRate);
    end
end

function v = local_paramValue(entry, ps, name)
% Current value of a parameter: from ps if set, else the registry default.
    if isfield(ps, name)
        v = ps.(name);
    else
        r = find(strcmp(entry.params(:, 1), name), 1);
        if isempty(r), v = []; else, v = entry.params{r, 2}; end
    end
end

function data = local_paramRows(entry, ps)
% The parameter table's Nx2 {name, valueStr} rows: every editable argument, plus the
% derived "duration (s)" row inserted directly under stimFrames.
    idx  = local_editableParams(entry);
    data = cell(0, 2);
    addDur = local_hasDuration(entry);
    for k = 1:numel(idx)
        r    = idx(k);
        name = entry.params{r, 1};
        v    = local_paramValue(entry, ps, name);
        data(end + 1, :) = {name, local_valueStr(entry.params{r, 3}, v)}; %#ok<AGROW>
        if addDur && strcmp(name, 'stimFrames')
            rr = double(local_paramValue(entry, ps, 'refreshRate'));
            data(end + 1, :) = {local_durRowName(), ...
                local_valueStr('num', local_durationFromFrames(double(v), rr))}; %#ok<AGROW>
        end
    end
end

function data = local_syncDuration(entry, data, editedName)
% Re-derive whichever of duration / stimFrames the user did NOT just type. Returns the
% updated table rows; throws (with a message meant for a uialert) on unparseable input.
    dRow = local_rowIndex(data, local_durRowName());
    fRow = local_rowIndex(data, 'stimFrames');
    rRow = local_rowIndex(data, 'refreshRate');
    if any([dRow fRow rRow] == 0), return; end
    rr = local_parseValue('num', data{rRow, 2}, entry, 'refreshRate');
    if local_isDerivedRow(editedName)
        dur = local_parseValue('num', data{dRow, 2}, entry, local_durRowName());
        [frames, dur]  = local_framesFromDuration(dur, rr);
        data{fRow, 2}  = local_valueStr('num', frames);
        data{dRow, 2}  = local_valueStr('num', dur);
    else                                     % stimFrames or refreshRate typed: seconds follow
        frames = local_parseValue('num', data{fRow, 2}, entry, 'stimFrames');
        data{dRow, 2} = local_valueStr('num', local_durationFromFrames(frames, rr));
    end
end

function r = local_rowIndex(data, name)
    r = find(strcmp(data(:, 1), name), 1);
    if isempty(r), r = 0; end
end

function ps = local_paramsFromRows(entry, data)
% Parse the parameter table back into a params struct, DROPPING the derived duration row
% (it is not an argument -- it only ever drives stimFrames).
    ps = struct();
    for k = 1:size(data, 1)
        name = data{k, 1};
        if local_isDerivedRow(name), continue; end
        r = find(strcmp(entry.params(:, 1), name), 1);
        if isempty(r)
            error('stimulusGUI:unknownParam', '"%s" is not an argument of %s.', name, entry.fn);
        end
        ps.(name) = local_parseValue(entry.params{r, 3}, data{k, 2}, entry, name);
    end
end


% ---------- protocol table: one row per EPOCH (blocks are the run-time grouping) ----------

function rows = local_epochRows(reg, blocks)
% Expand the blocks into one display row per epoch: {epochNo, stimulus, label, params}.
% Epoch numbers are global across the protocol, matching the order runExperiment presents
% them (and therefore the order Clampex saves the .abf files).
    rows = cell(0, 4);
    n    = 0;
    for b = 1:numel(blocks)
        e = local_findEntry(reg, blocks(b).fnName);
        s = local_paramSummary(e, blocks(b).params);
        for k = 1:blocks(b).epochs
            n = n + 1;
            rows(n, :) = {n, blocks(b).stimName, blocks(b).label, s};
        end
    end
end

function b = local_blockOfEpoch(blocks, row)
% Which block owns display epoch `row` (1-based)? 0 when the row is out of range.
    b = 0;
    n = 0;
    for i = 1:numel(blocks)
        n = n + blocks(i).epochs;
        if row <= n, b = i; return; end
    end
end

function blocks = local_removeEpoch(blocks, row)
% Drop one epoch from the block owning `row`; drop the block when its last epoch goes.
    b = local_blockOfEpoch(blocks, row);
    if b == 0, return; end
    blocks(b).epochs = blocks(b).epochs - 1;
    if blocks(b).epochs < 1, blocks(b) = []; end
end

function blocks = local_applyToEpochs(blocks, rows, ps, label)
% Apply one parameter set + label to the given DISPLAY EPOCH rows only.
%
% Epochs inside a block share a single parameter set -- that is what makes them one block --
% so giving a subset different values means splitting them out. Expand to one entry per
% epoch, overwrite the selected ones, then re-collapse RUNS of identical neighbours back
% into blocks. The result is the fewest blocks that can express the edit, and untouched
% epochs keep the block structure they already had.
    flat = local_flattenEpochs(blocks);
    if isempty(flat), return; end
    rows = unique(round(rows(:)'));
    rows = rows(rows >= 1 & rows <= numel(flat));
    if isempty(rows), return; end
    for i = rows
        flat(i).params = ps;
        flat(i).label  = char(label);
    end
    blocks = local_collapseEpochs(flat);
end

function flat = local_flattenEpochs(blocks)
% One struct per epoch, in display order.
    flat = struct('stimName', {}, 'fnName', {}, 'params', {}, 'label', {});
    for b = 1:numel(blocks)
        for k = 1:blocks(b).epochs
            flat(end + 1) = struct('stimName', blocks(b).stimName, 'fnName', blocks(b).fnName, ...
                                   'params', blocks(b).params, 'label', blocks(b).label); %#ok<AGROW>
        end
    end
end

function blocks = local_collapseEpochs(flat)
% Inverse of local_flattenEpochs: consecutive epochs that agree on stimulus, parameters and
% label become one block again.
    blocks = local_emptyBlocks();
    for i = 1:numel(flat)
        f = flat(i);
        if ~isempty(blocks) && strcmp(blocks(end).fnName, f.fnName) && ...
                isequal(blocks(end).params, f.params) && strcmp(blocks(end).label, f.label)
            blocks(end).epochs = blocks(end).epochs + 1;
        else
            blocks(end + 1) = struct('stimName', f.stimName, 'fnName', f.fnName, ...
                                     'params', f.params, 'epochs', 1, 'label', f.label); %#ok<AGROW>
        end
    end
end

function plan = local_previewPlan(reg, blocks, opts, cellName)
% The same plan shape runExperiment publishes, built from the protocol as it stands, so the
% monitor can draw the session BEFORE it is run.
    pb = struct('label', {}, 'stimName', {}, 'epochs', {}, 'stimSeconds', {});
    nEp = 0;
    for b = 1:numel(blocks)
        e = local_findEntry(reg, blocks(b).fnName);
        pb(b) = struct('label', blocks(b).label, 'stimName', blocks(b).fnName, ...
                       'epochs', blocks(b).epochs, ...
                       'stimSeconds', local_blockSeconds(e, blocks(b).params));
        nEp = nEp + blocks(b).epochs;
    end
    plan = struct('cellName', char(cellName), 'nBlocks', numel(blocks), 'totalEpochs', nEp, ...
                  'triggerAcq', logical(getfielddef(opts, 'triggerAcq', true)), ...
                  'seedBase', getfielddef(opts, 'seedBase', 2), ...
                  'timings', struct('settle', 1, ...
                                    'preStim',  getfielddef(opts, 'preStim', 2), ...
                                    'postStim', getfielddef(opts, 'postStim', 1), ...
                                    'itp',      getfielddef(opts, 'itp', 3)), ...
                  'leds', getfielddef(opts, 'leds', struct('enabled', false)));
    plan.blocks = pb;
end

function blocks = local_updateBlocks(blocks, target, ps, label, epochs)
% Rewrite the parameters, label and epoch count of the given block indices in place. Used by
% "Update epochs": the epochs already in the table change, none are appended.
    for i = reshape(target, 1, [])
        blocks(i).params = ps;
        blocks(i).label  = char(label);
        blocks(i).epochs = max(1, round(epochs));
    end
end

function secs = local_blockSeconds(entry, ps)
% stimFrames / refreshRate for one block, or NaN when the stimulus has no such pair.
    if ~local_hasDuration(entry), secs = NaN; return; end
    secs = local_durationFromFrames(double(local_paramValue(entry, ps, 'stimFrames')), ...
                                    double(local_paramValue(entry, ps, 'refreshRate')));
    if ~isfinite(secs) || secs <= 0, secs = NaN; end
end

function tf = local_sameStimAs(blocks, fnName)
% True when adding fnName keeps the protocol to a single stimulus type.
    tf = isempty(blocks) || all(strcmp({blocks.fnName}, fnName));
end

function tf = local_mixedStims(blocks)
% True for a (legacy / hand-edited) protocol that chains more than one stimulus type.
    tf = ~isempty(blocks) && numel(unique({blocks.fnName})) > 1;
end

function s = local_protoSummary(blocks)
    if isempty(blocks)
        s = 'No epochs yet.';
        return;
    end
    s = sprintf('%d epoch(s) in %d parameter block(s)  -  Keep/Discard asked once, at the end.', ...
                sum([blocks.epochs]), numel(blocks));
end

function k = local_seedArgFor(entry)
    k = find(strcmp(entry.params(:, 3), 'seed'), 1);
    if isempty(k), k = 0; end
end

function args = local_argsFor(entry, ps)
    P = entry.params; n = size(P, 1); args = cell(1, n);
    for i = 1:n
        name = P{i, 1}; typ = P{i, 3};
        if strcmp(typ, 'seed'), args{i} = []; continue; end   % auto-managed per epoch
        if isfield(ps, name), v = ps.(name); else, v = P{i, 2}; end
        if strcmp(typ, 'vec2'), v = reshape(double(v), 1, []); end
        args{i} = v;
    end
end

function v = local_parseValue(typ, str, entry, name)
    str = strtrim(char(str));
    switch typ
        case 'num'
            v = str2double(str);
            if isnan(v), error('stimulusGUI:badNum', 'Parameter "%s" must be a number (got "%s").', name, str); end
        case 'vec2'
            v = sscanf(str, '%f')';
            if numel(v) ~= 2, error('stimulusGUI:badVec', 'Parameter "%s" needs two numbers, e.g. "570 456" (got "%s").', name, str); end
        case 'enum'
            opts = entry.choices.(name);
            if ~any(strcmp(str, opts)), error('stimulusGUI:badEnum', 'Parameter "%s" must be one of: %s (got "%s").', name, strjoin(opts, ', '), str); end
            v = str;
        otherwise
            v = str;
    end
end

function s = local_valueStr(typ, v)
    switch typ
        case 'vec2', s = strtrim(sprintf('%g ', v));
        case 'enum', s = char(v);
        otherwise,   s = num2str(v);
    end
end

function s = local_paramSummary(entry, ps)
    idx   = local_editableParams(entry);
    parts = cell(1, numel(idx));
    for k = 1:numel(idx)
        r = idx(k); name = entry.params{r, 1};
        if isfield(ps, name), v = ps.(name); else, v = entry.params{r, 2}; end
        parts{k} = [name '=' local_valueStr(entry.params{r, 3}, v)];
    end
    s = strjoin(parts, ', ');
end

function e = local_findEntry(reg, fnName)
    k = find(strcmp({reg.fn}, fnName), 1);
    if isempty(k), error('stimulusGUI:unknownStim', 'Stimulus "%s" is not in stimRegistry.', fnName); end
    e = reg(k);
end

function protocol = local_buildProtocol(reg, blocks)
    protocol = struct('stim', {}, 'args', {}, 'epochs', {}, 'label', {}, 'seedArg', {});
    for b = 1:numel(blocks)
        e = local_findEntry(reg, blocks(b).fnName);
        protocol(b).stim    = str2func(blocks(b).fnName);
        protocol(b).args    = local_argsFor(e, blocks(b).params);
        protocol(b).epochs  = blocks(b).epochs;
        protocol(b).label   = blocks(b).label;
        protocol(b).seedArg = local_seedArgFor(e);
        % Planned presentation length -- what stimulusMonitor draws its timeline from before
        % anything has run. The stimuli append a few black frames, so the true duration is a
        % touch longer; playAndLogTrial reports the exact value once the first epoch plays.
        protocol(b).stimSeconds = local_blockSeconds(e, blocks(b).params);
    end
end

function txt = local_experimentToJson(blocks, opts)
    jb = cell(1, numel(blocks));
    for i = 1:numel(blocks)
        jb{i} = struct('stim', blocks(i).fnName, 'params', blocks(i).params, ...
                       'epochs', blocks(i).epochs, 'label', blocks(i).label);
    end
    exp        = struct('format', 'neitz-experiment/1');
    exp.opts   = opts;
    exp.blocks = jb;
    txt = jsonencode(exp, 'PrettyPrint', true);
end

function [blocks, opts] = local_jsonToExperiment(reg, txt)
    exp    = jsondecode(txt);
    opts   = getfielddef(exp, 'opts', struct());
    raw    = local_asCell(getfielddef(exp, 'blocks', {}));
    blocks = local_emptyBlocks();
    for i = 1:numel(raw)
        r = raw{i};
        if ~isfield(r, 'stim') || isempty(r.stim)
            error('stimulusGUI:badExperiment', 'Experiment block %d has no "stim" field.', i);
        end
        e = local_findEntry(reg, r.stim);
        % Optional fields default via getfielddef, so a hand-edited/older JSON that omits
        % params / epochs / label still loads instead of throwing a raw field error.
        blocks(i) = struct('stimName', e.name, 'fnName', e.fn, ...
                           'params', getfielddef(r, 'params', struct()), ...
                           'epochs', double(getfielddef(r, 'epochs', 1)), ...
                           'label',  char(string(getfielddef(r, 'label', ''))));
    end
end

function c = local_asCell(x)
    if iscell(x), c = x; elseif isstruct(x), c = num2cell(x); else, c = {x}; end
end

function v = getfielddef(s, f, d)
    if isstruct(s) && isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end

function local_checkRegistry(reg)
    for i = 1:numel(reg)
        want = nargin(reg(i).fn);
        got  = size(reg(i).params, 1);
        assert(want < 0 || want == got, ...
            'stimRegistry drift: %s takes %d args but the registry lists %d.', reg(i).fn, want, got);
    end
end


% ================================= headless self-test =================================
function selftest()
    reg = stimRegistry();
    local_checkRegistry(reg);
    fprintf('[selftest] registry: %d stimuli, nargin matches params for all\n', numel(reg));

    g  = local_findEntry(reg, 'AASeededGaussianGreyScaleStimFinal2026');
    ps = struct('mu', 0.5, 'sigma', 0.3, 'flickerHz', 4, 'stimFrames', 600, 'refreshRate', 60);
    assert(isequal(local_argsFor(g, ps), {[], 0.5, 0.3, 4, 600, 60}), 'argsFor gaussian (seed slot [])');
    assert(local_seedArgFor(g) == 1, 'gaussian seedArg == 1');

    f = local_findEntry(reg, 'AAGreyScaleFullFieldNoiseFinal2026');
    assert(local_seedArgFor(f) == 0, 'flicker has no seed');

    j  = local_findEntry(reg, 'AAJitteringCircleStimulusFinal');
    pj = struct('rfCenter', [570 456], 'rfRadius', 80, 'circleRadius', 150, ...
                'walkSpeed', 50, 'stimFrames', 600, 'refreshRate', 60, 'colorMode', 'Greyscale');
    aj = local_argsFor(j, pj);
    assert(isequal(aj{1}, [570 456]) && strcmp(aj{7}, 'Greyscale'), 'argsFor jitter (vec2 + enum)');

    assert(local_parseValue('num', '4', f, 'flickerHz') == 4, 'parse num');
    assert(isequal(local_parseValue('vec2', '570 456', j, 'rfCenter'), [570 456]), 'parse vec2');
    assert(strcmp(local_parseValue('enum', 'Greyscale', j, 'colorMode'), 'Greyscale'), 'parse enum');
    ok = false;
    try
        local_parseValue('enum', 'Purple', j, 'colorMode');
    catch
        ok = true;
    end
    assert(ok, 'parse enum rejects an invalid choice');

    % ---- redundant duration (s) <-> stimFrames, tied together by refreshRate ----
    assert(all(arrayfun(@local_hasDuration, reg)), 'every registered stimulus has stimFrames + refreshRate');
    [fr5, d5] = local_framesFromDuration(5, 60);
    assert(fr5 == 300 && abs(d5 - 5) < 1e-12, '5 s at 60 Hz -> 300 frames');
    [frx, dx] = local_framesFromDuration(5.004, 60);     % not a whole number of frames
    assert(frx == 300 && abs(dx - 5) < 1e-12, 'duration snaps back to the frame count actually presented');
    assert(local_framesFromDuration(0, 60) == 1, 'a zero duration still presents one frame');
    assert(abs(local_durationFromFrames(600, 60) - 10) < 1e-12, '600 frames at 60 Hz -> 10 s');
    for badRR = [0 -60 Inf]
        bad = false;
        try
            local_framesFromDuration(5, badRR);
        catch
            bad = true;
        end
        assert(bad, 'an unusable refreshRate is rejected instead of dividing by zero');
    end
    assert(isnan(local_durationFromFrames(600, 0)), 'frames -> seconds reports NaN, not a made-up number');

    rows = local_paramRows(g, ps);
    dRow = find(strcmp(rows(:, 1), local_durRowName()), 1);
    fRow = find(strcmp(rows(:, 1), 'stimFrames'), 1);
    assert(~isempty(dRow) && dRow == fRow + 1, 'the duration row sits directly under stimFrames');
    assert(strcmp(rows{dRow, 2}, '10'), 'duration row shows 600 frames / 60 Hz = 10 s');
    assert(isequal(local_paramsFromRows(g, rows), ps), ...
        'the derived duration row is dropped when the rows are parsed back to arguments');

    r2 = local_syncDuration(g, rows, local_durRowName());          % defaults unchanged: 10 s
    assert(strcmp(r2{fRow, 2}, '600'), 'editing duration rewrites stimFrames');
    rows{dRow, 2} = '5';
    r3 = local_syncDuration(g, rows, local_durRowName());           % user typed 5 seconds
    assert(strcmp(r3{fRow, 2}, '300') && strcmp(r3{dRow, 2}, '5'), '5 s typed -> stimFrames 300');
    r3{fRow, 2} = '900';
    r4 = local_syncDuration(g, r3, 'stimFrames');                   % user typed frames instead
    assert(strcmp(r4{dRow, 2}, '15'), 'editing stimFrames rewrites duration');
    rRow = find(strcmp(r4(:, 1), 'refreshRate'), 1);
    r4{rRow, 2} = '90';
    r5 = local_syncDuration(g, r4, 'refreshRate');                  % same frames, faster refresh
    assert(strcmp(r5{dRow, 2}, '10'), 'a new refreshRate re-derives duration from stimFrames');
    ps5 = local_paramsFromRows(g, r5);
    assert(ps5.stimFrames == 900 && ps5.refreshRate == 90, 'the synced frame count is what gets run');
    fprintf('[selftest] duration <-> stimFrames stay redundant through refreshRate\n');

    blocks    = local_emptyBlocks();
    blocks(1) = struct('stimName', g.name, 'fnName', g.fn, 'params', ps, 'epochs', 5, 'label', 'grey gauss');
    blocks(2) = struct('stimName', j.name, 'fnName', j.fn, 'params', pj, 'epochs', 3, 'label', 'jit');
    opts = struct('preStim', 2, 'postStim', 1, 'itp', 3, 'seedBase', 7, ...
                  'triggerAcq', false, 'stimIndex', 3);
    opts.leds = struct('enabled', true, 'port', 'AUTO', 'mode', 2, ...
                       'intensity', [0.75 0 0; 0 0.5 0; 0 0 0; 0 0 0.125]);
    [b2, o2] = local_jsonToExperiment(reg, local_experimentToJson(blocks, opts));
    assert(numel(b2) == 2 && strcmp(b2(1).fnName, g.fn) && b2(1).epochs == 5, 'json round-trip blocks');
    assert(isequal(local_argsFor(local_findEntry(reg, b2(1).fnName), b2(1).params), {[], 0.5, 0.3, 4, 600, 60}), ...
        'json round-trip rebuilds gaussian args');
    assert(o2.seedBase == 7, 'json round-trip opts');
    assert(o2.leds.enabled && o2.leds.mode == 2, 'json round-trip LED scalars');
    assert(isequal(size(o2.leds.intensity), [4, 3]) && abs(o2.leds.intensity(1, 1) - 0.75) < 1e-9, ...
        'json round-trip LED grid');
    assert(o2.stimIndex == 3 && o2.triggerAcq == false, ...
        'session-state round-trip (stimIndex / triggerAcq)');

    % ---- protocol table lists one row per EPOCH; blocks stay the run-time grouping ----
    eRows = local_epochRows(reg, blocks);                 % 5 gaussian epochs + 3 jitter epochs
    assert(isequal(size(eRows), [8 4]), '5 + 3 epochs -> 8 rows of {Epoch #, Stimulus, Label, Params}');
    assert(isequal(eRows{1, 1}, 1) && isequal(eRows{8, 1}, 8), 'epoch numbering is global and 1-based');
    assert(strcmp(eRows{5, 2}, g.name) && strcmp(eRows{6, 2}, j.name), 'each row carries its block''s stimulus');
    assert(strcmp(eRows{2, 4}, eRows{3, 4}), 'epochs of one block repeat identical parameters');
    assert(local_blockOfEpoch(blocks, 5) == 1 && local_blockOfEpoch(blocks, 6) == 2, 'epoch -> owning block');
    assert(local_blockOfEpoch(blocks, 9) == 0 && local_blockOfEpoch(local_emptyBlocks(), 1) == 0, ...
        'an out-of-range epoch maps to no block');
    b3 = local_removeEpoch(blocks, 6);
    assert(numel(b3) == 2 && b3(1).epochs == 5 && b3(2).epochs == 2, ...
        'removing an epoch decrements only its own block');
    b4 = blocks; b4(2).epochs = 1;
    b4 = local_removeEpoch(b4, 6);
    assert(numel(b4) == 1 && strcmp(b4(1).fnName, g.fn), 'removing a block''s last epoch drops the block');
    assert(local_sameStimAs(local_emptyBlocks(), g.fn) && local_sameStimAs(blocks(1), g.fn), ...
        'an empty / single-stimulus protocol accepts that stimulus');
    assert(~local_sameStimAs(blocks(1), j.fn), 'a second stimulus type is refused');
    assert(local_mixedStims(blocks) && ~local_mixedStims(blocks(1)) && ~local_mixedStims(local_emptyBlocks()), ...
        'legacy mixed-stimulus protocols are detected on load');
    assert(contains(local_protoSummary(blocks), '8 epoch') && ...
           contains(local_protoSummary(blocks), '2 parameter block') && ...
           contains(local_protoSummary(blocks), 'once, at the end'), ...
        'the table summary counts epochs + parameter blocks, and says Keep/Discard is asked once');

    % ---- "Update epochs": edit rows already in the table instead of appending more ----
    ps2 = ps; ps2.sigma = 0.9; ps2.stimFrames = 300;
    b5  = local_updateBlocks(blocks, 1, ps2, 'retuned', 4);
    assert(numel(b5) == 2, 'updating adds no blocks');
    assert(b5(1).params.sigma == 0.9 && b5(1).params.stimFrames == 300 && ...
           strcmp(b5(1).label, 'retuned') && b5(1).epochs == 4, 'the targeted block took the new values');
    assert(b5(2).epochs == 3 && ~isfield(b5(2).params, 'sigma'), 'other blocks are untouched');
    assert(size(local_epochRows(reg, b5), 1) == 7, '5 epochs -> 4 shrinks the table to 7 rows');
    b6 = local_updateBlocks(blocks, 1:2, ps2, 'all', 2);
    assert(all([b6.epochs] == 2) && all(strcmp({b6.label}, 'all')), '"Update all" reaches every block');
    b7 = local_updateBlocks(blocks, 1, ps2, 'zero', 0);
    assert(b7(1).epochs == 1, 'a block can never be updated down to zero epochs');
    fprintf('[selftest] Update epochs rewrites existing rows (params / label / count) in place\n');
    fprintf('[selftest] protocol table = one row per epoch; one stimulus type per protocol\n');

    pr = local_loadPresets();                       % presets read from rig_config.json
    assert(numel(pr) >= 2 && any(strcmp({pr.name}, 'Off')) && any(strcmp({pr.name}, 'macaque s-iso')), ...
        'presets load with friendly names preserved (spaces survive jsondecode)');
    kk = find(strcmp({pr.name}, 'macaque s-iso'), 1);
    assert(isequal(size(pr(kk).values), [4, 3]) && abs(pr(kk).values(4, 1) - 1.0) < 1e-9 ...
        && abs(pr(kk).values(2, 3) - 1.0) < 1e-9, 'macaque s-iso values (LED3 R=1, LED1 B=1)');
    assert(numel(local_presetNames(pr)) == numel(pr) + 1, 'preset dropdown includes the placeholder');
    fprintf('[selftest] LED grid round-trip + presets (Off / macaque s-iso) from rig_config\n');

    proto = local_buildProtocol(reg, blocks);
    assert(numel(proto) == 2 && proto(1).seedArg == 1 && proto(2).seedArg == 0, 'buildProtocol seedArg per block');
    assert(isa(proto(1).stim, 'function_handle'), 'buildProtocol resolves the handle');

    sample = fullfile(fileparts(mfilename('fullpath')), 'experiments', 'example_grey_flicker_and_gaussian.json');
    if exist(sample, 'file')
        [bs, os] = local_jsonToExperiment(reg, fileread(sample));
        assert(numel(bs) == 2 && os.seedBase == 2, 'tracked sample experiment loads via the real loader');
        assert(isequal(local_argsFor(local_findEntry(reg, bs(1).fnName), bs(1).params), {2, 600, 60}), 'sample block 1 args');
        fprintf('[selftest] tracked sample experiment loads: %d blocks\n', numel(bs));
    end

    % ---- nested manifest writer: day -> cell -> block -> epoch (2 cells) round-trip ----
    td = tempname; mkdir(td);
    restoreCtx = onCleanup(@() local_cleanupNestedTest(td));   % rmdir + clear ctx on any exit
    assignin('base', 'neitzSessionContext', struct('cell_name', 'cell A', 'block_index', 1, ...
        'block_label', 'grey', 'leds', struct('enabled', true, 'mode', 2, ...
        'intensity', [0.5 0 0; 0 0 0; 0 0 0; 0 0 0])));
    recG = struct('stimulus', 'AASeededGaussianGreyScaleStimFinal2026', 'stim_type', 'gaussian_noise', ...
        'cone_isolation', 'achromatic', 'seed', 2, 'mu', 0.5, 'sigma', 0.3, ...
        'stim_frames', 600, 'refresh_rate_hz', 60, 'timestamp', '2026-07-16T09:00:00');
    writeStimManifest(td, recG);
    recG.seed = 3; recG.timestamp = '2026-07-16T09:01:00'; writeStimManifest(td, recG);
    assignin('base', 'neitzSessionContext', struct('cell_name', 'cell B', 'block_index', 1, ...
        'block_label', 'grey', 'leds', struct('enabled', false)));
    recG.seed = 4; recG.timestamp = '2026-07-16T09:02:00'; writeStimManifest(td, recG);
    evalin('base', 'clear neitzSessionContext');
    ds   = char(datetime('now', 'Format', 'yyyy_MM_dd'));
    tree = jsondecode(fileread(fullfile(td, [ds '_stim_manifest.json'])));
    assert(strcmp(tree.format, 'neitz-stim-manifest/2'), 'nested: format tag');
    cells = local_asCellsTest(tree.cells);
    assert(numel(cells) == 2 && strcmp(cells{1}.cell_name, 'cell A') && strcmp(cells{2}.cell_name, 'cell B'), ...
        'nested: two cells in patch order');
    blA = local_asCellsTest(cells{1}.blocks);
    epA = local_asCellsTest(blA{1}.epochs);
    assert(numel(blA) == 1 && numel(epA) == 2 && epA{1}.seed == 2 && epA{2}.seed == 3, ...
        'nested: block epochs + per-epoch seeds');
    assert(blA{1}.leds.enabled == true && abs(blA{1}.leds.intensity(1, 1) - 0.5) < 1e-9, ...
        'nested: LED grid logged on the block');
    % the legacy flat .jsonl dual-write was DROPPED -- only the nested .json is written now
    assert(~exist(fullfile(td, [ds '_stim_manifest.jsonl']), 'file'), ...
        'nested: legacy flat .jsonl is no longer written');

    % ---- finalizeStimBlock: append a suffix to the current cell, then discard a block ----
    finalizeStimBlock(td, 'append', '-ON');                       % refine cell B -> "cell B-ON"
    t2 = jsondecode(fileread(fullfile(td, [ds '_stim_manifest.json'])));
    c2 = local_asCellsTest(t2.cells);
    assert(strcmp(c2{end}.cell_name, 'cell B-ON'), 'finalize: append renamed the last cell');

    finalizeStimBlock(td, 'discard');                             % discard cell B-ON's only block
    t3 = jsondecode(fileread(fullfile(td, [ds '_stim_manifest.json'])));
    c3 = local_asCellsTest(t3.cells);
    assert(numel(c3) == 1 && strcmp(c3{1}.cell_name, 'cell A'), ...
        'finalize: discard dropped the emptied cell (cell B-ON)');
    disc = local_asCellsTest(t3.discarded);
    assert(numel(disc) == 1 && disc{1}.seed == 4 && strcmp(disc{1}.cell_name, 'cell B-ON'), ...
        'finalize: discarded epoch moved to discarded[] with its seed + context');

    % ---- discarding a MULTI-BLOCK run: per-epoch parameters span several blocks, and the
    % ---- one end-of-run Discard has to take all of them (and only them).
    assignin('base', 'neitzSessionContext', struct('cell_name', 'cell A', 'block_index', 2, ...
        'block_label', 'hi-sigma', 'leds', struct('enabled', false)));
    recG.sigma = 0.9; recG.seed = 20; recG.timestamp = '2026-07-16T10:00:00'; writeStimManifest(td, recG);
    assignin('base', 'neitzSessionContext', struct('cell_name', 'cell A', 'block_index', 3, ...
        'block_label', 'lo-sigma', 'leds', struct('enabled', false)));
    recG.sigma = 0.1; recG.seed = 21; recG.timestamp = '2026-07-16T10:01:00'; writeStimManifest(td, recG);
    evalin('base', 'clear neitzSessionContext');
    t4 = jsondecode(fileread(fullfile(td, [ds '_stim_manifest.json'])));
    tmpCells = local_asCellsTest(t4.cells);
    b4 = local_asCellsTest(tmpCells{1}.blocks);
    assert(numel(b4) == 3, 'differing parameters made three blocks under one cell');

    finalizeStimBlock(td, 'discard', 2);                          % the 2-block run just added
    t5 = jsondecode(fileread(fullfile(td, [ds '_stim_manifest.json'])));
    c5 = local_asCellsTest(t5.cells);
    b5 = local_asCellsTest(c5{1}.blocks);
    assert(numel(c5) == 1 && numel(b5) == 1 && strcmp(b5{1}.label, 'grey'), ...
        'finalize: a 2-block discard took both, and left the earlier block alone');
    d5 = local_asCellsTest(t5.discarded);
    assert(numel(d5) == 3 && d5{2}.seed == 20 && d5{3}.seed == 21, ...
        'finalize: both blocks'' epochs moved to discarded[], oldest first');

    finalizeStimBlock(td, 'discard', 99);                         % never eat more than exists
    t6 = jsondecode(fileread(fullfile(td, [ds '_stim_manifest.json'])));
    assert(isempty(local_asCellsTest(local_getfieldTest(t6, 'cells', {}))), ...
        'finalize: an over-large discard is clamped, not an error');
    fprintf('[selftest] nested manifest writer + finalizeStimBlock (append / multi-block discard)\n');

    fprintf('[selftest] args / parse / json round-trip / buildProtocol all PASS\n');
end


function v = local_getfieldTest(s, f, d)
    if isstruct(s) && isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end


function c = local_asCellsTest(x)
% Normalize jsondecode output (struct | struct array | cell) to a row cell array (test aid).
    if isempty(x),        c = {};
    elseif iscell(x),     c = reshape(x, 1, []);
    elseif isstruct(x),   c = num2cell(reshape(x, 1, []));
    else,                 c = {x};
    end
end


function local_cleanupNestedTest(td)
% Best-effort cleanup for the nested-writer self-test: clear the context, remove the temp dir.
    try
        evalin('base', 'clear neitzSessionContext');
    catch
    end
    try
        rmdir(td, 's');
    catch
    end
end
