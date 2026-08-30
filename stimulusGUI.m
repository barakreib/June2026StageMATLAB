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
% Epochs already in the table are EDITABLE, not just removable. Every column is live:
% Label, this epoch's seed (seeded stimuli), and every parameter has its own column —
% type in a cell and just that epoch changes (it splits out of its block; edit it back and
% it re-merges). For bulk edits, click a row to load its block into the top window, change
% the parameters there, select the target rows and press "Apply params to selected".
% Under the table, "Remove epoch" drops the selected row — and the block with its last
% epoch — and "Clear all" empties the protocol.
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
% Run does NOT call the AA* stimulus files. It writes ONE generated m-file for the run
% (generateStimScript.m -> <data dir>/generated_stimuli/) that reproduces the chosen
% stimulus exactly and renders the configured phases around it, then hands that to
% runExperiment. The PHASES panel (right) sets, for pre-stim / post-stim / inter-stim and
% the end of the run: a full-screen RGB value (linear 0..1, linearized like every stimulus
% color) and an LED state ("(main grid)" = the LED grid below, "Off" = dark, or any LED
% preset from rig_config.json). Pre/post are rendered inside the epoch's presentation
% (frame-locked, sync bar dark), inter-stim/end are held on the projector between epochs.
% The generated file stays on disk next to the day's manifest as the exact record of what
% ran; the AA* files remain untouched and standalone-runnable.
%
% QUICK LOAD (top right) gives ten assignable slots for your most common experiments:
% click a slot to load its saved experiment; "Assign slot..." binds the current protocol
% (or any saved .json) to a slot. Assignments live in experiments/quickload_slots.json.
%
% THE SYNC BAR (rightmost W/8) is a permanent instrument: no full-screen value ever covers
% it. During a presentation it shows three photodiode segments -- top: the projector FRAME
% CLOCK (toggles every frame); middle: the STIMULUS UPDATE CLOCK (the legacy sync pattern,
% dark outside the stimulus); bottom: the STIMULUS ENVELOPE (solid while stimulus frames
% are on screen). On held screens (inter-stim / run end) the bar is dark -- a held frame
% is static, so there are no frame updates to report.
%
% ON LAUNCH the GUI touches NOTHING on the network -- no Stage-server probe, no LED
% writes. The first contact with the Stage server is Run's own pre-flight. (An earlier
% launch-time probe was removed at the user's request: it added a failure mode at boot
% and the rig state belongs to Run / quick-set, not to opening a window.)
%
% The "stimulus protocol complete" Keep/Discard dialog appears ONCE, at the end of the whole
% run — never between epochs, even when they carry different parameters. Discard removes
% every epoch of the run from the manifest and marks their .abf files to skip on import.
%
% Seeds are PER EPOCH: every Gaussian epoch carries its own seed (auto-assigned as a
% fresh RANDOM integer in [1, 1e6], distinct from every seed already in the protocol;
% editable in the table's seed column), so repeated epochs are INDEPENDENT noise. Each
% epoch's seed is recorded in the day's stim manifest and in the values CSV when the
% debug dump is on. To add or edit a stimulus, edit stimRegistry.m.
%
% The SESSION MONITOR is embedded in this window (right panel) — epoch progress, phase
% clock, stimulus numbers, LED state, and the whole-session timeline. ONE window, ONE
% Cancel button (bottom middle).
%
% The SCREENS & LEDS band (bottom) sets, per phase — pre-stim | stimulus | post-stimulus |
% inter-stim | end of stim — each LED's R/G duty (preset dropdown to fill it) and, for
% every phase but the stimulus itself, the RGBval column (a one-column table: R, G, B
% rows + a click-to-pick swatch cell, aligned row-for-row with the LED table). The B
% channel is GLOBAL: the far-right B column drives every phase's B (it carries the
% sync/photodiode light, so it never varies by phase). LED row names show once, on the
% pre-stim table; DOUBLE-CLICK a row name to rename that LED everywhere (saved to
% rig_config `led_names`). "link values" (top left of the band): press it, click phase
% sections to toggle them into or out of the ONE linked set (they highlight while
% linking), then press "done linking" — linked sections share BOTH the LED R/G grid and
% the full-screen RGBval (editing any one edits them all; a section joining the set
% adopts its values), and a line under the band shows which sections are linked.
% "Set now"/"Off now" beside the stimulus title push that grid (+ global B) to the rig
% immediately. Stimulus parameters are remembered PER STIMULUS TYPE (last-used values
% come back when a stimulus is re-selected, and across sessions via the saved state).
% An all-dark "end of stim" grid = the classic dark+close LED teardown; anything lit
% there stays ON after the run (driver handed off as base `rig`).

    if nargin >= 1 && ischar(mode) && strcmp(mode, '__selftest__')
        selftest();
        return;
    end

    reg      = stimRegistry();
    local_checkRegistry(reg);
    blocks   = local_emptyBlocks();
    curEntry = reg(1);
    presets  = local_loadPresets();      % LED value presets from rig_config.json
    ledNames = local_ledNames();         % user-editable LED row names (rig_config led_names)
    expDir    = fullfile(fileparts(mfilename('fullpath')), 'experiments');
    if ~exist(expDir, 'dir'), mkdir(expDir); end
    stateFile = fullfile(prefdir, 'neitzStimulusGUI_lastSession.json');
    qlFile    = fullfile(expDir, 'quickload_slots.json');
    qlSlots   = local_loadQuickSlots(qlFile);   % the 10 assignable experiment slots
    h = struct();
    rigConn = [];   % handle to the SHARED rig (same object as base-workspace `rig`; see quickRig)
    cancelRequested = false;   % set by the Cancel button, polled by runExperiment (see onCancel)
    suspendSelCb    = false;   % re-entrancy guard while the epoch table's Selection is set in code
    monitor         = [];      % the live "Session monitor" window (stimulusMonitor)
    linkOn   = struct('pre', false, 'post', false, 'iti', false, 'final', false);  % the ONE linked set
    linkMode = false;          % true while "link values" is armed (clicks toggle membership)
    lastParams = struct();     % per-stimulus last-used parameters (fn name -> params struct)
    suppressRemember = false;  % set while loadState drives the list, so restoring never clobbers

    buildUI();
    openMonitor();      % the embedded Session monitor (right panel) + its stimProgress hooks
    onSelectStim();
    loadState();        % restore the last-used settings + protocol, if any
    refreshProtocol();  % unconditional: with no saved state loadState returns early, and the
                        % table buttons would otherwise start enabled over an empty protocol
    % NO network activity at launch (no Stage probe, no LED writes) -- Run's pre-flight
    % makes the first contact with the Stage server.

    % ================= nested callbacks (share reg / blocks / curEntry / h) =================
    function buildUI()
        % ONE window: builder (middle), embedded Session monitor (right), and the
        % screens-&-LEDs band along the bottom. One Cancel button, on this window.
        h.fig = uifigure('Name', 'Neitz Stimulus GUI', 'Position', [30 40 1580 1010], ...
            'CloseRequestFcn', @(s,e) onClose());
        outer = uigridlayout(h.fig, [2 1]);
        outer.RowHeight  = {'1x', 300};
        outer.Padding    = [6 6 6 6];
        outer.RowSpacing = 6;
        top = uigridlayout(outer, [1 3]);
        top.ColumnWidth   = {235, '1x', 480};
        top.Padding       = [0 0 0 0];
        top.ColumnSpacing = 8;

        % ---------------- left: stimulus list (+ Save/Load) + quick-load slots ----------------
        lc = uigridlayout(top, [2 1]);
        lc.RowHeight  = {'1x', 330};
        lc.Padding    = [0 0 0 0];
        lc.RowSpacing = 6;
        lp = uipanel(lc, 'Title', 'Stimuli');
        lg = uigridlayout(lp, [1 1]);
        h.list = uilistbox(lg, 'Items', {reg.name}, 'ValueChangedFcn', @(s,e) onSelectStim());
        buildQuickLoad(lc);

        % ---------------- middle: the protocol builder ----------------
        rp = uigridlayout(top, [8 1]);
        % Row 3 (the parameter table) is resized to its content by showEntry: exactly tall
        % enough that refreshRate is never scrolled out of sight -- it is half of the duration
        % relationship -- and no taller, so short stimuli hand the slack to the epoch table,
        % which is the row that flexes. Tight RowSpacing buys that table a few more rows.
        % Row 4 is the checkerboard auto-checks checkbox; showEntry collapses it to 0 px
        % for stimuli without checksX/checksY.
        rp.RowHeight  = {28, 24, local_paramTableHeight(8), 22, 40, 20, '1x', 34};
        rp.RowSpacing = 4;
        rp.Padding    = [0 0 0 0];
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

        % Checkerboards only (showEntry hides it otherwise): keep checksX x checksY
        % square-on-the-wall -- edit either direction and the other follows.
        ar = uigridlayout(rp, [1 1]); ar.Padding = [6 0 6 0];
        h.autoChecks = uicheckbox(ar, 'Text', 'Auto-derive the other checks direction (square checks fill the screen)', ...
            'Value', false, 'ValueChangedFcn', @(s,e) onAutoChecks(), ...
            'Tooltip', ['When ticked, editing checksX rewrites checksY (and vice versa) so the ' ...
                        'checks stay SQUARE ON THE WALL and tile the whole screen: ' ...
                        'checksY = round(checksX * (H/W) / pixel_aspect) on the 912 x 1140 ' ...
                        'diamond DMD (40 -> 25 at pixel_aspect 2). Applies in this panel and ' ...
                        'to checksX / checksY cells typed in the epoch table below.']);

        er = uigridlayout(rp, [1 5]); er.ColumnWidth = {60, 70, 55, '1x', 130};
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
        % ("Update epochs" is gone: rows in the table are edited directly, and bulk edits
        %  go through "Apply params to selected" -- which sits under the rows it changes.)

        nr = uigridlayout(rp, [1 2]); nr.ColumnWidth = {'1x', 'fit'}; nr.Padding = [6 0 6 0];
        h.seedNote  = uilabel(nr, 'Text', '', 'FontAngle', 'italic');
        h.protoNote = uilabel(nr, 'Text', local_protoSummary(local_emptyBlocks()), ...
            'FontAngle', 'italic', 'FontColor', [0.45 0.45 0.45], 'HorizontalAlignment', 'right');

        % One row per EPOCH, not per block: "5 epochs" + Add block appends 5 identical rows,
        % so the table shows exactly what will be presented. Blocks still exist underneath --
        % they group epochs that share one parameter set (see onProtocolComplete). Every
        % parameter gets ITS OWN column (plus Label, plus this epoch's seed for seeded
        % stimuli) and the cells are EDITABLE -- typing in a cell rewrites just that epoch.
        % refreshProtocol() rebuilds the columns to match the protocol's stimulus type.
        h.protoTable = uitable(rp, 'ColumnName', {'Epoch #', 'Label'}, ...
            'ColumnWidth', {64, '1x'}, 'RowName', {}, 'SelectionType', 'row', ...
            'Multiselect', 'on', 'SelectionChangedFcn', @(s,e) onSelectEpoch(), ...
            'CellEditCallback', @(s, e) onEpochCellEdit(e));

        % Row operations sit with the rows they act on, under the table.
        tb = uigridlayout(rp, [1 6]); tb.ColumnWidth = {170, 130, 110, '1x', 88, 88};
        tb.Padding = [6 2 6 2]; tb.ColumnSpacing = 8;
        h.updSelBtn = uibutton(tb, 'Text', 'Apply params to selected', 'ButtonPushedFcn', @(s,e) onUpdateSelected(), ...
            'Tooltip', ['Apply the parameters and label above to JUST the selected epoch(s) ' ...
                        '(shift/ctrl-click for several). Those epochs are split into their own ' ...
                        'block, so one epoch can differ from its neighbours. The run is not ' ...
                        'interrupted either way -- Keep/Discard is still asked once, at the end.']);
        h.removeBtn = uibutton(tb, 'Text', 'Remove epoch', 'ButtonPushedFcn', @(s,e) onRemoveEpoch(), ...
            'Tooltip', 'Drop the selected epoch. Removing a block''s last epoch removes the block.');
        h.clearBtn = uibutton(tb, 'Text', 'Clear all', 'ButtonPushedFcn', @(s,e) onClearAll(), ...
            'Tooltip', 'Empty the protocol and start over (asks first).');
        uilabel(tb, 'Text', 'Edit cells directly, or select rows + apply above.', ...
            'FontAngle', 'italic', 'FontColor', [0.45 0.45 0.45]);
        h.saveBtn = uibutton(tb, 'Text', 'Save...', 'ButtonPushedFcn', @(s,e) onSave());
        h.loadBtn = uibutton(tb, 'Text', 'Load...', 'ButtonPushedFcn', @(s,e) onLoad());

        % ---------------- right: the Session monitor + Run/Cancel under it ----------------
        rc = uigridlayout(top, [2 1]);
        rc.RowHeight  = {'1x', 46};
        rc.Padding    = [0 0 0 0];
        rc.RowSpacing = 4;
        h.monPanel = uipanel(rc, 'Title', 'Session monitor');
        rb = uigridlayout(rc, [1 2]); rb.ColumnWidth = {'1x', 120};
        rb.Padding = [0 0 0 0]; rb.ColumnSpacing = 8;
        h.runBtn  = uibutton(rb, 'Text', 'Run experiment', 'ButtonPushedFcn', @(s,e) onRun(), ...
            'BackgroundColor', [0.20 0.55 0.30], 'FontColor', 'w', 'FontWeight', 'bold', ...
            'Interruptible', 'on');   % MUST stay 'on' -- it is what lets Cancel fire mid-run
        % THE one and only Cancel button (the embedded monitor has none).
        h.cancelBtn = uibutton(rb, 'Text', 'Cancel', 'ButtonPushedFcn', @(s,e) onCancel(), ...
            'BackgroundColor', [0.70 0.15 0.15], 'FontColor', 'w', 'FontWeight', 'bold', ...
            'Enable', 'off', 'BusyAction', 'queue', ...
            'Tooltip', ['Stop the run at the next clean epoch boundary. An epoch whose Clampex ' ...
                        'sweep is already triggered is always finished and logged, so no .abf is ' ...
                        'left without its manifest row.']);

        % ---------------- bottom: screens & LEDs band + the Settings panel ----------------
        bot = uigridlayout(outer, [1 2]);
        bot.ColumnWidth   = {'1x', 480};
        bot.Padding       = [0 0 0 0];
        bot.ColumnSpacing = 8;
        buildPhaseBand(bot);
        buildSettings(bot);

        % Locked / restored wholesale by lockUI-unlockUI for the duration of a run.
        h.lockList  = gobjects(0);
        h.lockState = strings(0);
    end

    function buildQuickLoad(parent)
        % Quick load: 10 assignable slots for the most common experiments.
        qp = uipanel(parent, 'Title', 'Quick load');
        qg = uigridlayout(qp, [2 1]);
        qg.RowHeight   = {264, 'fit'};
        qg.Padding     = [6 4 6 4];
        qg.RowSpacing  = 4;
        h.qlGroup = uibuttongroup(qg, 'BorderType', 'none', ...
            'SelectionChangedFcn', @(s, e) onQuickLoad());
        % A hidden "none" radio, created FIRST so it takes the group's default selection:
        % a uibuttongroup cannot have SelectedObject = [], and no slot should light up
        % until one is actually loaded. Selecting it programmatically = "no slot".
        h.qlNone = uiradiobutton(h.qlGroup, 'Text', '', 'Position', [-200 -200 10 10], ...
            'Visible', 'off', 'UserData', 0);
        h.qlRadio = gobjects(1, 10);
        for qi = 1:10
            h.qlRadio(qi) = uiradiobutton(h.qlGroup, 'Text', local_quickLabel(qi, qlSlots(qi)), ...
                'Position', [8, 264 - 26 * qi, 200, 22], 'UserData', qi);
        end
        h.qlGroup.SelectedObject = h.qlNone;   % nothing loaded yet -> no slot lit
        h.qlAssign = uibutton(qg, 'Text', 'Assign slot...', 'ButtonPushedFcn', @(s,e) onAssignSlot(), ...
            'Tooltip', ['Bind a slot to the current protocol (saved as a .json under experiments/) ' ...
                        'or to an existing saved experiment. Slots live in experiments/quickload_slots.json. ' ...
                        'Click a slot to load that experiment.']);
    end

    function buildSettings(parent)
        % Session-wide switches and addresses, bottom right (same width as the monitor):
        % Stage host, the Clampex / LED-driver enables, and the LED driver's mode + port.
        sp = uipanel(parent, 'Title', 'Settings');
        sg = uigridlayout(sp, [5 2]);
        sg.RowHeight   = {30, 26, 26, 30, 30};
        sg.ColumnWidth = {150, '1x'};
        sg.Padding     = [8 6 8 6];
        sg.RowSpacing  = 6;
        uilabel(sg, 'Text', 'Stage host (IPv4):');
        h.stageHost = uieditfield(sg, 'text', 'Value', char(loadRigConfig('stage_host', 'localhost')), ...
            'Tooltip', ['The Stage/OpenGL server computer. Blank / "localhost" = this machine; an ' ...
                        'IPv4 (e.g. 192.168.0.49) connects to that computer. Saved to rig_config on Run.']);
        % Two independent enables, ON by default. Unchecking one makes Run skip exactly
        % those lines: Clampex off -> no acquisition trigger; LED driver off ->
        % runExperiment never opens NeitzLedRig (LEDs left untouched).
        h.triggerAcq = uicheckbox(sg, 'Text', 'Clampex acquisition', 'Value', true, 'FontWeight', 'bold', ...
            'Tooltip', ['ON: Run triggers Clampex acquisition each epoch. OFF: present via the Stage ' ...
                        'host only, no Clampex keystrokes (local dry run / no rig).']);
        h.triggerAcq.Layout.Column = [1 2];
        h.ledEnable = uicheckbox(sg, 'Text', 'LED driver', 'Value', true, 'FontWeight', 'bold', ...
            'Tooltip', ['ON: Run opens NeitzLedRig and applies the LED grids during the session. ' ...
                        'OFF: the LED driver is not touched by Run.']);
        h.ledEnable.Layout.Column = [1 2];
        uilabel(sg, 'Text', 'LED driver mode:');
        h.ledMode = uidropdown(sg, 'Items', {'off (0)', 'DC red (1)', 'video RGB (2)', 'video RGB + sync (3)'}, ...
            'ItemsData', [0 1 2 3], 'Value', 2);
        uilabel(sg, 'Text', 'LED driver port:');
        h.ledPort = uieditfield(sg, 'text', 'Value', char(loadRigConfig('led_port', 'COM3')), ...
            'Tooltip', ['LED-driver port (default: rig_config led_port -- hard-coded is fastest). ' ...
                        'Type AUTO to probe for the FPGA instead (slower), or a /dev/cu.* node on macOS.']);
    end

    function buildPhaseBand(parent)
        % The screens-&-LEDs band: one section per phase -- pre-stim | stimulus |
        % post-stimulus | inter-stim | end of stim -- each with a preset dropdown, its
        % R/G LED duty table, and (except "stimulus", whose screen IS the stimulus) the
        % RGBval column. The far right holds the GLOBAL B column, which drives every
        % phase's B channel. "link values" (top left) links whole sections: while
        % linking, click sections to toggle them in and out of the linked set; a line
        % under the band shows which sections are linked (they share LED R/G AND RGBval;
        % editing any one edits them all).
        band = uipanel(parent, 'Title', ...
            'Screens & LEDs  (LED duty + screen RGB are linear 0..1; screens exclude the sync bar)');
        bgl = uigridlayout(band, [3 1]);
        bgl.RowHeight  = {26, '1x', 22};
        bgl.Padding    = [6 2 6 2];
        bgl.RowSpacing = 2;

        % --- strip: the link-mode button + the status line ---
        st = uigridlayout(bgl, [1 2]);
        st.ColumnWidth = {110, '1x'};
        st.Padding = [0 0 0 0]; st.ColumnSpacing = 8;
        h.linkBtn = uibutton(st, 'Text', 'link values', 'ButtonPushedFcn', @(s, e) onLinkMode(), ...
            'Tooltip', ['Link phase sections so they share ONE set of values (LED R/G and the ' ...
                        'full-screen RGBval): press, click sections to toggle them into or out ' ...
                        'of the linked set, then press "done linking". The line under the band ' ...
                        'shows what is linked.']);
        h.ledStatus = uilabel(st, 'Text', '', 'FontAngle', 'italic', ...
            'FontColor', [0.45 0.45 0.45], 'HorizontalAlignment', 'right');
        % (The B channel is ALWAYS global -- the far-right B column drives every phase.)

        % --- the five phase sections + the master B column ---
        sc = uigridlayout(bgl, [1 7]);
        sc.ColumnWidth   = {'fit', 'fit', 'fit', 'fit', 'fit', 'fit', '1x'};
        sc.Padding       = [0 0 0 0];
        sc.ColumnSpacing = 8;
        % Grid children never report a usable Position in uifigures, so each section
        % hands back its fixed width + LED-table center and the band accumulates the
        % x of every table -- that is where the link line puts its dots.
        x = 0;
        for kk = {{'pre', 'pre-stim', 2}, {'stim', 'stimulus', []}, ...
                  {'post', 'post-stimulus', 1}, {'iti', 'inter-stim', 3}, ...
                  {'final', 'end of stim', []}}
            [secW, tblCx] = buildPhaseSection(sc, kk{1}{1}, kk{1}{2}, kk{1}{3});
            h.linkX.(kk{1}{1}) = x + tblCx;
            x = x + secW + sc.ColumnSpacing;
        end
        buildMasterB(sc);

        % --- the link line: drawn under the linked sections (absolutely-positioned
        %     mini-panels in a plain container -- no axes coordinate quirks) ---
        h.linkStrip = uipanel(bgl, 'BorderType', 'none', 'AutoResizeChildren', 'off');

        % duration aliases: the rest of the GUI (gatherOpts, loaders, the monitor plan)
        % keeps its long-standing handle names
        h.preStim  = h.phDur.pre;
        h.postStim = h.phDur.post;
        h.itp      = h.phDur.iti;
    end

    function [secW, tblCx] = buildPhaseSection(parent, key, ttl, durDefault)
        % Each section, top to bottom: title (+duration; the stimulus section carries
        % the Set now / Off now quick-set buttons there), preset dropdown, then the LED
        % table -- R and G only (B is GLOBAL, the far-right column). Every phase but
        % the stimulus also gets an RGBval column: a one-column TABLE (rows 1-3 = the
        % full-screen R/G/B, row 4 = the color-picker swatch cell), so its header and
        % rows align pixel-for-pixel with the LED table's. LED row names show ONCE, on
        % the pre-stim table (double-click a name there to rename that LED everywhere).
        hasScreen = ~strcmp(key, 'stim');
        hasNames  = strcmp(key, 'pre');
        sg = uigridlayout(parent, [3 1]);
        sg.RowHeight  = {26, 24, 124};
        sg.Padding    = [0 0 0 0];
        sg.RowSpacing = 2;
        % title (+ its duration, for the phases that have one; quick-set for stimulus)
        if hasScreen
            tr = uigridlayout(sg, [1 4]);
            tr.ColumnWidth = {'fit', '1x', 'fit', 52};
            tr.Padding = [2 0 2 0]; tr.ColumnSpacing = 4;
            uilabel(tr, 'Text', ttl, 'FontWeight', 'bold');
            uilabel(tr, 'Text', '');
            if ~isempty(durDefault)
                uilabel(tr, 'Text', 's:');
                h.phDur.(key) = uieditfield(tr, 'numeric', 'Value', durDefault, 'Limits', [0 Inf], ...
                    'ValueChangedFcn', @(s, e) pushPreview(), ...
                    'Tooltip', sprintf('Duration of the %s phase in seconds.', ttl));
            end
        else
            tr = uigridlayout(sg, [1 3]);
            tr.ColumnWidth = {'fit', '1x', 108};   % header must not out-grow the table
                                                   % below, or the 'fit' section widens
                                                   % and the link line's x math drifts
            tr.Padding = [2 0 2 0]; tr.ColumnSpacing = 4;
            uilabel(tr, 'Text', ttl, 'FontWeight', 'bold');
            uilabel(tr, 'Text', '');
            qs = uigridlayout(tr, [1 2]); qs.Padding = [0 0 0 0]; qs.ColumnSpacing = 3;
            h.ledSetNow = uibutton(qs, 'Text', 'Set now', 'FontSize', 10, ...
                'ButtonPushedFcn', @(s,e) onLedSetNow(), ...
                'Tooltip', ['Quick set: push THIS stimulus grid (R/G below + the global B ' ...
                            'column) and the Settings mode to the rig immediately, without ' ...
                            'running an experiment.']);
            h.ledOffNow = uibutton(qs, 'Text', 'Off now', 'FontSize', 10, ...
                'ButtonPushedFcn', @(s,e) onLedOffNow(), ...
                'Tooltip', 'Quick set: mode 0 (all LEDs dark) immediately. Grid values are kept.');
        end
        h.phPreset.(key) = uidropdown(sg, 'Items', local_presetNames(presets), ...
            'Tag', ['phPreset_' key], 'ValueChangedFcn', @(s, e) onPhasePreset(key), ...
            'Tooltip', 'Fill this LED grid from a rig_config.json preset (its B column fills the global B).');
        % Widths are chosen so the WHOLE band fits its panel: an overflowing
        % uigridlayout silently shrinks every fixed column, which both squeezes the
        % tables and breaks the link line's analytic x positions.
        if hasNames, tw = 170; else, tw = 112; end     % pre carries the LED-name gutter
        secW  = tw + 3 + 64;                           % table + spacing + RGBval column
        tblCx = tw / 2;                                % the LED table's center within the section
        if hasScreen
            cg = uigridlayout(sg, [1 2]);
            cg.ColumnWidth = {tw, 64};
            cg.Padding = [0 0 0 0]; cg.ColumnSpacing = 3;
        else
            cg = uigridlayout(sg, [1 1]);
            cg.ColumnWidth = {tw + 3 + 64};   % table EXPANDS over the (absent) RGBval slot
            cg.Padding = [0 0 0 0];
        end
        if hasNames, rn = ledNames; else, rn = {}; end
        h.phGrid.(key) = uitable(cg, 'Data', zeros(4, 2), 'ColumnName', {'R', 'G'}, ...
            'RowName', rn, 'ColumnEditable', [true true], ...
            'ColumnWidth', {'1x', '1x'}, 'CellEditCallback', @(s, e) onPhaseGridEdit(key, e), ...
            'DoubleClickedFcn', @(s, e) onLedNameDblClick(e), ...
            'ClickedFcn', @(s, e) onPhaseTableClick(key), ...
            'Tag', ['phGrid_' key], ...
            'Tooltip', sprintf('%s: per-LED duty (0..1) on the R/G timing channels (B: far-right global column).', ttl));
        if hasScreen
            % RGBval as a one-column TABLE: same widget as the LED grid, so the header
            % and all four rows align identically (R~LED row 1, G~2, B~3, swatch~4).
            h.phScrTbl.(key) = uitable(cg, 'Data', {0; 0; 0; ''}, 'ColumnName', {'RGBval'}, ...
                'RowName', {}, 'ColumnEditable', true, 'ColumnWidth', {'1x'}, ...
                'CellEditCallback', @(s, e) onScreenCellEdit(key, e), ...
                'ClickedFcn', @(s, e) onScreenClick(key, e), ...
                'Tag', ['phScr_' key], ...
                'Tooltip', sprintf(['Full-screen value during %s (linear 0..1): rows are R, G, B; ' ...
                                    'the bottom cell shows the color -- click it to pick.'], ttl));
            updateSwatch(key);
        end
    end

    function buildMasterB(parent)
        % The GLOBAL B column, always on the far right: one duty per LED, driving the B
        % channel of EVERY phase (it carries the sync/photodiode light, which never
        % varies by phase). The table sits in a fixed-width cell exactly as wide as its
        % one column, so there is no dead black strip to its right.
        mg = uigridlayout(parent, [3 1]);
        mg.RowHeight  = {26, 24, 124};
        mg.Padding    = [0 0 0 0];
        mg.RowSpacing = 2;
        uilabel(mg, 'Text', 'B (all phases)', 'FontWeight', 'bold', ...
            'Tooltip', 'Global B column: one duty per LED, used during every phase.');
        uilabel(mg, 'Text', '');
        ig = uigridlayout(mg, [1 1]);
        ig.ColumnWidth = {62};
        ig.Padding = [0 0 0 0];
        h.masterB = uitable(ig, 'Data', zeros(4, 1), 'ColumnName', {'B'}, ...
            'RowName', {}, 'ColumnEditable', true, ...
            'ColumnWidth', {'1x'}, 'Tag', 'masterB', ...
            'CellEditCallback', @(s, e) onMasterBEdit(e));
    end

    function onSelectStim()
        % Remember the panel for the stimulus being LEFT, then show the newly picked
        % stimulus with its last-used values (registry defaults only the first time).
        rememberParams();
        e = reg(h.list.ValueIndex);
        showEntry(e, getfielddef(lastParams, e.fn, struct()));
    end

    function rememberParams()
        % Keep the panel's current values per stimulus TYPE, so re-selecting it (now or
        % next session -- saved with the session state) starts from the last-used
        % values, not the registry defaults. A half-typed invalid value is skipped.
        if suppressRemember, return; end
        try
            lastParams.(curEntry.fn) = local_paramsFromRows(curEntry, h.paramTable.Data);
        catch
        end
    end

    function showEntry(entry, ps)
        % Fill the top window from `entry` + a params struct ({} = registry defaults).
        curEntry = entry;
        h.paramTable.Data = local_paramRows(curEntry, ps);   % + the derived "duration (s)" row
        h.rightGrid.RowHeight{3} = local_paramTableHeight(size(h.paramTable.Data, 1));
        h.paramTitle.Text = ['Parameters for:  ' curEntry.name '   (' curEntry.fn ')'];
        % the auto-checks row exists only for stimuli with checksX/checksY (checkerboards)
        hasChecks = local_hasChecksXY(curEntry);
        h.autoChecks.Visible = hasChecks;
        h.rightGrid.RowHeight{4} = 22 * double(hasChecks);
        if local_seedArgFor(curEntry) > 0
            h.seedNote.Text = 'Seeds: one per epoch, assigned at random -- editable in the seed column.';
        else
            h.seedNote.Text = 'Seed: not applicable to this stimulus.';
        end
    end

    function onSelectEpoch()
        % Clicking an epoch loads its block back into the top window -- stimulus, parameters,
        % label and epoch count -- for bulk edits via "Apply params to selected".
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
        rememberParams();      % the loaded block's values become this stimulus's last-used
    end

    function onParamEdit(evt)
        % "duration (s)" and stimFrames are two views of the same thing. Editing either
        % (or refreshRate) rewrites the other so the presentation length stays consistent:
        % seconds -> frames = round(seconds * refreshRate), then seconds is snapped back to
        % the whole-frame value that will ACTUALLY be presented. Every successful edit is
        % remembered per stimulus type (see rememberParams).
        data = h.paramTable.Data;
        if isempty(evt.Indices), return; end
        name = data{evt.Indices(1), 1};
        if local_hasDuration(curEntry) && ...
                any(strcmp(name, {'stimFrames', 'refreshRate', local_durRowName()}))
            try
                h.paramTable.Data = local_syncDuration(curEntry, data, name);
            catch err
                h.paramTable.Data = data;    % leave the typed text in place to be corrected
                uialert(h.fig, err.message, 'Invalid parameter');
                return;
            end
        end
        if h.autoChecks.Value && local_hasChecksXY(curEntry) && ...
                any(strcmp(name, {'checksX', 'checksY'}))
            try
                h.paramTable.Data = local_syncChecks(curEntry, h.paramTable.Data, name);
            catch err
                h.paramTable.Data = data;    % leave the typed text in place to be corrected
                uialert(h.fig, err.message, 'Invalid parameter');
                return;
            end
        end
        rememberParams();
    end

    function onAutoChecks()
        % Ticking the box squares the CURRENT pair up immediately (checksX drives
        % checksY); from then on each edit re-derives the other direction. Unticking
        % just stops the coupling -- the values stay as shown.
        if ~h.autoChecks.Value || ~local_hasChecksXY(curEntry), return; end
        try
            h.paramTable.Data = local_syncChecks(curEntry, h.paramTable.Data, 'checksX');
            rememberParams();
        catch
            % a half-typed checksX stays put; the cell-edit callback reports it when touched
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
            n  = round(h.epochs.Value);
            b  = struct('stimName', curEntry.name, 'fnName', curEntry.fn, 'params', ps, ...
                        'epochs', n, 'label', char(h.label.Value), ...
                        'seeds', local_nextSeeds(blocks, n, local_seedArgFor(curEntry) > 0));
            blocks(end + 1) = b;
            lastParams.(curEntry.fn) = ps;
            refreshProtocol();
        catch err
            uialert(h.fig, err.message, 'Invalid parameter');
        end
    end

    function onEpochCellEdit(evt)
        % A protocol-table cell was typed into: rewrite JUST that epoch (Label, its seed,
        % or one parameter). The epoch splits out of its block if it no longer matches its
        % neighbours; identical neighbours re-merge. Bad input rolls the table back.
        if isempty(evt.Indices), return; end
        row = evt.Indices(1);
        col = evt.Indices(2);
        [~, ~, ~, keys] = local_epochTableSpec(reg, blocks);
        if col > numel(keys) || strcmp(keys{col}, 'epoch') || strcmp(keys{col}, 'readonly')
            refreshProtocol(row);
            return;
        end
        try
            blocks = local_applyCellEdit(reg, blocks, row, keys{col}, evt.NewData);
            if h.autoChecks.Value    % keep that epoch's checks square-on-the-wall too
                blocks = local_autoChecksEpoch(reg, blocks, row, keys{col});
            end
        catch err
            uialert(h.fig, err.message, 'Invalid value');
        end
        refreshProtocol(row);
    end

    function updateTableButtons()
        % Nothing in the table means nothing to update, remove or clear.
        onOff = {'off', 'on'};
        e = onOff{1 + ~isempty(blocks)};
        h.updSelBtn.Enable = e;
        h.removeBtn.Enable = e;
        h.clearBtn.Enable  = e;
    end

    function pushPreview()
        % Publish the protocol as a PLANNED session, so the embedded monitor draws its
        % timeline before anything runs -- and redraws it every time the protocol changes.
        if isempty(monitor) || ~isfield(monitor, 'fig') || ~isvalid(monitor.fig), return; end
        stimProgress('preview', local_previewPlan(reg, blocks, gatherOpts(), ...
                                                  strtrim(char(h.cellName.Value))));
    end

    % ============== screens & LEDs band (per-phase grids + screen colors) ==============
    function g = phaseGrid43(key)
        % A phase's full 4x3 grid: R,G from its own table + the GLOBAL B column.
        d = h.phGrid.(key).Data;
        g = local_coerce43([double(d(:, 1:2)), double(h.masterB.Data(:))]);
    end

    function onPhaseGridEdit(key, evt)
        % Keep every cell a clamped number (the tables carry R and G only; B is global),
        % then mirror the whole grid to any tables linked with this one. A hand-edited
        % grid is no longer the assigned preset's values, so the assignment clears.
        d = h.phGrid.(key).Data;
        if isempty(evt.Indices), return; end
        v = double(evt.NewData);
        if ~isscalar(v) || ~isfinite(v), v = 0; end
        d(evt.Indices(1), evt.Indices(2)) = min(max(v, 0), 1);
        h.phGrid.(key).Data = d;
        setPhasePresetName(key, '');
        syncLinked(key);
    end

    function onPhasePreset(key)
        % Fill this phase's R/G from the preset; the preset's B column goes to the
        % GLOBAL B (B never varies by phase, so loading a preset sets it everywhere).
        % The dropdown keeps showing the name: that IS the phase's preset assignment,
        % saved with experiments/state and re-resolved against rig_config on load.
        name = h.phPreset.(key).Value;
        k = find(strcmp({presets.name}, name), 1);
        if isempty(k), return; end     % the "(load preset...)" placeholder row
        vals = local_coerce43(presets(k).values);
        h.phGrid.(key).Data = vals(:, 1:2);
        h.masterB.Data      = vals(:, 3);
        syncLinked(key);
    end

    function nm = phasePresetName(key)
        % This phase's preset assignment: the dropdown's name, '' when unassigned.
        nm = char(h.phPreset.(key).Value);
        if strcmp(nm, local_noPresetItem()), nm = ''; end
    end

    function setPhasePresetName(key, nm)
        % Point the dropdown at `nm` without firing its callback; anything not in the
        % current preset list (including '') shows as unassigned.
        nm = char(string(nm));
        if ~isempty(nm) && any(strcmp(h.phPreset.(key).Items, nm))
            h.phPreset.(key).Value = nm;
        else
            h.phPreset.(key).Value = local_noPresetItem();
        end
    end

    % ------ LED-table links: ONE linked set of sections sharing LED R/G + RGBval ------
    function ks = linkMembers()
        all = {'pre', 'post', 'iti', 'final'};
        ks  = all(cellfun(@(k) linkOn.(k), all));
    end

    function syncLinked(key)
        % Mirror `key`'s LED grid, its RGBval screen AND its preset assignment to every
        % linked section (no-op when key is unlinked, and for the stimulus grid, which
        % has none of the three).
        if ~isfield(linkOn, key) || ~linkOn.(key), return; end
        d  = h.phGrid.(key).Data;
        v  = phaseScreenRGB(key);
        nm = phasePresetName(key);
        for m = linkMembers()
            if ~strcmp(m{1}, key)
                h.phGrid.(m{1}).Data = d;
                setPhaseScreenRGB(m{1}, v);
                setPhasePresetName(m{1}, nm);
            end
        end
    end

    function paintLinkStyles()
        % While linking: members get the green wash, the rest a dim "eligible" tint.
        % Outside link mode nothing is painted. The RGBval swatch cell is re-applied
        % after every removeStyle (cell styles stack on top of table styles).
        for kk = {'pre', 'post', 'iti', 'final'}
            key = kk{1};
            removeStyle(h.phGrid.(key));
            if linkMode
                if linkOn.(key), c = [0.25 0.42 0.20]; else, c = [0.36 0.33 0.14]; end
                addStyle(h.phGrid.(key), uistyle('BackgroundColor', c));
            end
            updateSwatch(key);
        end
    end

    function drawLinkLine()
        % The line under the band connecting the linked sections (dot on each member).
        try
            delete(h.linkStrip.Children);
            ks = linkMembers();
            if numel(ks) < 2, return; end
            % h.linkX holds each LED table's center, computed from the band's fixed
            % widths at build time (grid children report no usable Position).
            xs = cellfun(@(k) h.linkX.(k), ks);
            xs = sort(xs);
            c  = [0.30 0.65 0.35];
            uipanel(h.linkStrip, 'BorderType', 'none', 'BackgroundColor', c, ...
                    'Position', [xs(1), 5, max(2, xs(end) - xs(1)), 3]);
            for i = 1:numel(xs)
                uipanel(h.linkStrip, 'BorderType', 'none', 'BackgroundColor', c, ...
                        'Position', [xs(i) - 4, 2, 9, 9]);          % the square
                uipanel(h.linkStrip, 'BorderType', 'none', 'BackgroundColor', c, ...
                        'Position', [xs(i) - 1, 11, 3, 11]);        % tick UP toward its table
            end
        catch
            % the line is a decoration -- never let it break the band
        end
    end

    function onLinkMode()
        if ~linkMode
            linkMode = true;
            h.linkBtn.Text = 'done linking';
            % read-only while linking: an editable cell swallows clicks (click ->
            % select, click again -> editor opens and ClickedFcn never fires), which
            % made toggling feel unreliable
            for kk = {'pre', 'post', 'iti', 'final'}
                h.phGrid.(kk{1}).ColumnEditable   = [false false];
                h.phScrTbl.(kk{1}).ColumnEditable = false;
            end
            paintLinkStyles();
            setLedStatus(['Linking: click sections to toggle them into/out of the linked set, ' ...
                          'then press "done linking".'], [0.45 0.45 0.45]);
        else
            linkMode = false;
            h.linkBtn.Text = 'link values';
            for kk = {'pre', 'post', 'iti', 'final'}
                h.phGrid.(kk{1}).ColumnEditable   = [true true];
                h.phScrTbl.(kk{1}).ColumnEditable = true;
            end
            if numel(linkMembers()) < 2      % a set of one is no link at all
                for kk = {'pre', 'post', 'iti', 'final'}, linkOn.(kk{1}) = false; end
            end
            paintLinkStyles();
            drawLinkLine();
            ks = linkMembers();
            if isempty(ks)
                setLedStatus('No sections linked.', [0.45 0.45 0.45]);
            else
                setLedStatus(sprintf('Linked: %s (shared LED R/G + RGBval).', strjoin(ks, ' + ')), ...
                    [0.13 0.45 0.20]);
            end
        end
    end

    function onPhaseTableClick(key)
        % While "link values" is armed, clicking a section toggles its membership in
        % the linked set; a section joining the set ADOPTS the set's current values.
        if ~linkMode || ~isfield(linkOn, key), return; end
        if linkOn.(key)
            linkOn.(key) = false;
        else
            others = linkMembers();
            linkOn.(key) = true;
            if ~isempty(others)              % adopt the group's values on joining
                src = others{1};
                h.phGrid.(key).Data = h.phGrid.(src).Data;
                setPhaseScreenRGB(key, phaseScreenRGB(src));
                setPhasePresetName(key, phasePresetName(src));
            end
        end
        h.phGrid.(key).Selection   = [];    % no lingering cell selection between toggles
        h.phScrTbl.(key).Selection = [];
        paintLinkStyles();
        drawLinkLine();
        drawnow;                            % instant feedback -- a toggle must be visible NOW
    end

    % -------- the RGBval column (a one-column table: R, G, B rows + a swatch cell) --------
    function v = phaseScreenRGB(key)
        d = h.phScrTbl.(key).Data;
        v = [0 0 0];
        for ci = 1:3
            x = d{ci};
            if isnumeric(x) && isscalar(x) && isfinite(x), v(ci) = x; end
        end
        v = min(max(double(v), 0), 1);
    end

    function setPhaseScreenRGB(key, v)
        v = min(max(double(reshape(v, 1, [])), 0), 1);
        d = h.phScrTbl.(key).Data;
        for ci = 1:3
            d{ci} = v(ci);
        end
        d{4} = '';
        h.phScrTbl.(key).Data = d;
        updateSwatch(key);
    end

    function updateSwatch(key)
        % The bottom cell IS the swatch: its background is painted the actual color, so
        % it is theme-independent by construction. Re-applies the link-mode wash first
        % (cell styles stack on top of table styles).
        t = h.phScrTbl.(key);
        removeStyle(t);
        if linkMode
            if linkOn.(key), c = [0.25 0.42 0.20]; else, c = [0.36 0.33 0.14]; end
            addStyle(t, uistyle('BackgroundColor', c));
        end
        addStyle(t, uistyle('BackgroundColor', phaseScreenRGB(key)), 'cell', [4 1]);
    end

    function onScreenCellEdit(key, evt)
        if isempty(evt.Indices), return; end
        r = evt.Indices(1);
        d = h.phScrTbl.(key).Data;
        if r == 4                              % the swatch cell holds no text
            d{4} = '';
            h.phScrTbl.(key).Data = d;
            return;
        end
        v = str2double(string(evt.NewData));
        if isnumeric(evt.NewData) && isscalar(evt.NewData), v = double(evt.NewData); end
        if ~isscalar(v) || ~isfinite(v), v = 0; end
        d{r} = min(max(v, 0), 1);
        h.phScrTbl.(key).Data = d;
        updateSwatch(key);
        syncLinked(key);
    end

    function onScreenClick(key, evt)
        % While "link values" is armed, a click anywhere on the RGBval table toggles
        % this section's membership; otherwise a click on the bottom (swatch) cell
        % opens the color picker.
        if linkMode
            onPhaseTableClick(key);
            return;
        end
        try
            if evt.InteractionInformation.Row ~= 4, return; end
        catch
            return;
        end
        c = uisetcolor(phaseScreenRGB(key), 'Phase screen color');
        if isscalar(c), return; end            % dialog cancelled
        setPhaseScreenRGB(key, c);
        syncLinked(key);
    end

    function onMasterBEdit(evt)
        % The global B column: clamp the value; every phase reads it live (phaseGrid43).
        d = h.masterB.Data;
        if ~isempty(evt.Indices)
            v = double(evt.NewData);
            if ~isscalar(v) || ~isfinite(v), v = 0; end
            d(evt.Indices(1)) = min(max(v, 0), 1);
            h.masterB.Data = d;
        end
    end

    function ps = gatherPhaseSpec()
        % The band as data (version 2): explicit 4x3 LED grids + screen RGB per phase,
        % plus the B-lock state. This is exactly what is saved into experiments/state --
        % no symbolic preset references, so a saved experiment always reproduces the
        % light it was saved with, even if rig_config presets change later.
        % Grids are stored as full 4x3 (R,G from each phase table + the GLOBAL B column),
        % so saved experiments, resolution and the run pipeline are format-unchanged.
        % Each phase ALSO records its preset assignment (the dropdown name, '' when
        % unassigned): on load an assigned phase re-fills from TODAY's rig_config preset
        % (recalibrations flow into old experiments), with the explicit grid as the
        % fallback when the preset no longer exists.
        ps = struct('version', 2);
        ps.pre   = struct('seconds', h.preStim.Value,  'rgb', phaseScreenRGB('pre'), ...
                          'grid', phaseGrid43('pre'),   'preset', phasePresetName('pre'));
        ps.stim  = struct('grid', phaseGrid43('stim'),  'preset', phasePresetName('stim'));
        ps.post  = struct('seconds', h.postStim.Value, 'rgb', phaseScreenRGB('post'), ...
                          'grid', phaseGrid43('post'),  'preset', phasePresetName('post'));
        ps.iti   = struct('seconds', h.itp.Value,      'rgb', phaseScreenRGB('iti'), ...
                          'grid', phaseGrid43('iti'),   'preset', phasePresetName('iti'));
        ps.final = struct('rgb', phaseScreenRGB('final'), ...
                          'grid', phaseGrid43('final'), 'preset', phasePresetName('final'));
        ps.syncB   = true;                     % B is always global now
        ps.masterB = double(h.masterB.Data(:)');
        ps.links = struct('pre', 0, 'post', 0, 'iti', 0, 'final', 0);
        for lk = linkMembers(), ps.links.(lk{1}) = 1; end   % the linked set (0 = unlinked)
    end

    function applyPhasesToUI(spec)
        % Fill the band from a saved spec. Handles: v2 (explicit grids), the short-lived
        % v1 (symbolic mode/preset -- converted against today's presets), and nothing at
        % all (defaults that reproduce the pre-overhaul behavior).
        def = local_defaultPhaseSpec(h.preStim.Value, h.postStim.Value, h.itp.Value);
        % The stimulus grid's default is what applyLedsToUI just loaded (opts.leds), NOT
        % zeros -- otherwise a pre-band experiment file would wipe its LED grid on load,
        % and a v1 spec's "(main grid)" phases would convert to darkness.
        def.stim.grid = phaseGrid43('stim');
        def.masterB   = double(h.masterB.Data(:)');
        spec = local_normalizePhaseSpec(spec, presets, def);
        h.preStim.Value  = spec.pre.seconds;
        h.postStim.Value = spec.post.seconds;
        h.itp.Value      = spec.iti.seconds;
        % B is GLOBAL now: specs saved with the old per-phase lock OFF carry a B column
        % per grid -- the stimulus phase's B (the one that mattered during epochs) wins.
        if isfield(spec, 'syncB') && logical(spec.syncB(1))
            h.masterB.Data = spec.masterB(:);
        else
            h.masterB.Data = spec.stim.grid(:, 3);
        end
        h.phGrid.stim.Data = spec.stim.grid(:, 1:2);
        for kk = {'pre', 'post', 'iti', 'final'}
            key = kk{1};
            h.phGrid.(key).Data = spec.(key).grid(:, 1:2);
            setPhaseScreenRGB(key, spec.(key).rgb);
        end
        % Preset assignments: restore each dropdown, and AUTO-POPULATE assigned phases
        % from TODAY's rig_config presets -- exactly as if the operator re-picked them
        % left to right (R/G to the phase, the preset's B column to the global B; with
        % several assigned presets the rightmost one's B wins, as it does by hand). A
        % preset that has vanished from rig_config keeps the saved explicit grid.
        gone = {};
        for kk = {'pre', 'stim', 'post', 'iti', 'final'}
            key = kk{1};
            nm  = spec.(key).preset;
            setPhasePresetName(key, nm);
            if isempty(nm), continue; end
            pk = find(strcmp({presets.name}, nm), 1);
            if isempty(pk)
                gone{end + 1} = sprintf('%s: "%s"', key, nm);   %#ok<AGROW>
                setPhasePresetName(key, '');
            else
                vals = local_coerce43(presets(pk).values);
                h.phGrid.(key).Data = vals(:, 1:2);
                h.masterB.Data      = vals(:, 3);
            end
        end
        if ~isempty(gone)
            setLedStatus(sprintf(['Preset(s) no longer in rig_config -- kept the values ' ...
                'saved with the experiment: %s.'], strjoin(gone, ', ')), [0.72 0.45 0.12]);
        end
        linkMode = false;
        h.linkBtn.Text = 'link values';
        for kk = {'pre', 'post', 'iti', 'final'}
            linkOn.(kk{1}) = spec.links.(kk{1}) > 0;   % old multi-group saves merge into one set
        end
        if numel(linkMembers()) < 2
            for kk = {'pre', 'post', 'iti', 'final'}, linkOn.(kk{1}) = false; end
        end
        paintLinkStyles();
        drawLinkLine();
    end

    % ================= Quick load: 10 assignable experiment slots =================
    function onQuickLoad()
        r = h.qlGroup.SelectedObject;
        if isempty(r) || r == h.qlNone, return; end
        i = r.UserData;
        if isempty(qlSlots(i).file)
            h.qlGroup.SelectedObject = h.qlNone;
            uialert(h.fig, sprintf(['Slot %d is empty. Use "Assign slot..." to bind a saved ' ...
                'experiment to it.'], i), 'Empty slot');
            return;
        end
        p = local_slotPath(expDir, qlSlots(i).file);
        if ~exist(p, 'file')
            h.qlGroup.SelectedObject = h.qlNone;
            uialert(h.fig, sprintf('Slot %d points at "%s", which no longer exists.', i, p), ...
                'Missing file');
            return;
        end
        loadExperimentFile(p);
    end

    function refreshQuickUI()
        for i = 1:10
            h.qlRadio(i).Text = local_quickLabel(i, qlSlots(i));
        end
    end

    function onAssignSlot()
        % Small modal chooser: which slot, what name, and where the experiment comes from
        % (the protocol as it stands, or an existing saved .json). Also clears a slot.
        selIdx = find(cellfun(@isempty, {qlSlots.file}), 1);
        if isempty(selIdx), selIdx = 1; end
        % The group's SelectedObject is NEVER empty: with no slot chosen it is the
        % HIDDEN "none" radio, whose UserData is 0 -- feeding that into the dropdown
        % (valid values 1..10) aborted the dialog build half-way, leaving an empty,
        % unclickable window. Only a REAL slot (UserData >= 1) may override.
        if ~isempty(h.qlGroup.SelectedObject) && h.qlGroup.SelectedObject.UserData >= 1
            selIdx = h.qlGroup.SelectedObject.UserData;
        end

        pp  = h.fig.Position;
        d   = uifigure('Name', 'Assign quick-load slot', 'Resize', 'off', ...
                       'Position', [pp(1) + 320, pp(2) + 380, 470, 235]);
        g   = uigridlayout(d, [5 2]);
        g.RowHeight   = {'fit', 'fit', 'fit', 'fit', 'fit'};
        g.ColumnWidth = {110, '1x'};
        uilabel(g, 'Text', 'Slot:');
        slotItems = arrayfun(@(i) local_quickLabel(i, qlSlots(i)), 1:10, 'UniformOutput', false);
        sd = uidropdown(g, 'Items', slotItems, 'ItemsData', 1:10, 'Value', selIdx);
        uilabel(g, 'Text', 'Name:');
        nf = uieditfield(g, 'text', 'Value', qlSlots(selIdx).name, ...
            'Tooltip', 'Shown on the slot''s button. Blank = the experiment file''s name.');
        hint = uilabel(g, 'Text', ['"Bind current protocol" saves what is in the table now as a ' ...
            '.json under experiments/ and points the slot at it. "Bind existing file..." points ' ...
            'the slot at an experiment you already saved.'], 'WordWrap', 'on', ...
            'FontAngle', 'italic', 'FontColor', [0.45 0.45 0.45]);
        hint.Layout.Column = [1 2];
        b1 = uibutton(g, 'Text', 'Bind current protocol', 'ButtonPushedFcn', @(s, e) doBindCurrent(), ...
            'BackgroundColor', [0.20 0.55 0.30], 'FontColor', 'w', 'FontWeight', 'bold');
        b1.Layout.Column = 1;
        b2 = uibutton(g, 'Text', 'Bind existing file...', 'ButtonPushedFcn', @(s, e) doBindExisting());
        b2.Layout.Column = 2;
        b3 = uibutton(g, 'Text', 'Clear slot', 'ButtonPushedFcn', @(s, e) doClear());
        b3.Layout.Column = 1;
        b4 = uibutton(g, 'Text', 'Cancel', 'ButtonPushedFcn', @(s, e) delete(d));
        b4.Layout.Column = 2;

        function doBindCurrent()
            if isempty(blocks)
                uialert(d, 'The protocol table is empty -- add epochs first.', 'Nothing to bind');
                return;
            end
            i  = sd.Value;
            nm = strtrim(char(nf.Value));
            if isempty(nm), nm = sprintf('quick slot %d', i); end
            file = [local_safeFileName(nm) '.json'];
            full = fullfile(expDir, file);
            if exist(full, 'file')
                choice = uiconfirm(d, sprintf('"%s" already exists. Overwrite it?', file), ...
                    'Overwrite', 'Options', {'Cancel', 'Overwrite'}, 'DefaultOption', 1, 'CancelOption', 1);
                if ~strcmp(choice, 'Overwrite'), return; end
            end
            fid = fopen(full, 'w');
            if fid < 0
                uialert(d, ['Cannot write ' full], 'Save failed');
                return;
            end
            fwrite(fid, local_experimentToJson(blocks, gatherOpts()), 'char');
            fclose(fid);
            commitSlot(i, nm, file);
        end

        function doBindExisting()
            [f, p] = uigetfile('*.json', 'Choose a saved experiment', [expDir filesep]);
            if isequal(f, 0), return; end
            i  = sd.Value;
            nm = strtrim(char(nf.Value));
            if isempty(nm), [~, nm] = fileparts(f); end
            if strcmp(local_stripSep(p), local_stripSep(expDir))
                file = f;                    % keep experiments/ slots portable
            else
                file = fullfile(p, f);
            end
            commitSlot(i, nm, file);
        end

        function doClear()
            i = sd.Value;
            qlSlots(i).name = '';
            qlSlots(i).file = '';
            local_saveQuickSlots(qlFile, qlSlots);
            refreshQuickUI();
            if ~isempty(h.qlGroup.SelectedObject) && h.qlGroup.SelectedObject.UserData == i
                h.qlGroup.SelectedObject = h.qlNone;
            end
            delete(d);
        end

        function commitSlot(i, nm, file)
            qlSlots(i).name = nm;
            qlSlots(i).file = file;
            local_saveQuickSlots(qlFile, qlSlots);
            refreshQuickUI();
            delete(d);
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
            lastParams.(curEntry.fn) = ps;
        catch err
            uialert(h.fig, err.message, 'Invalid parameter');
            return;
        end
        refreshProtocol(rows);
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
        opts = gatherOpts();
        % ---- every Gaussian epoch should have its OWN seed: warn about duplicates ----
        allSeeds = [blocks.seeds];
        allSeeds = allSeeds(isfinite(allSeeds));
        if numel(unique(allSeeds)) < numel(allSeeds)
            choice = uiconfirm(h.fig, ['Two or more epochs share the same seed, so their ' ...
                'noise will be IDENTICAL, not independent. Run anyway?'], 'Duplicate seeds', ...
                'Options', {'Cancel', 'Run anyway'}, 'DefaultOption', 1, 'CancelOption', 1);
            if ~strcmp(choice, 'Run anyway'), return; end
        end
        % ---- resolve the band + write this run's generated stimulus script ----
        % Run never calls the AA* files: it generates ONE m-file per stimulus type in the
        % protocol (normally exactly one) that renders pre-stim + stimulus + post-stim as a
        % single presentation with the configured screens/LED grids, and executes that. The
        % file lands in <data dir>/generated_stimuli/ as the exact record of what ran.
        phRun = local_resolvePhaseSpec(opts.phases);
        if opts.leds.enabled
            stimGrid = local_coerce43(opts.leds.intensity);
        else
            stimGrid = [];
        end
        genDir = fullfile(pwd, 'generated_stimuli');
        genMap = struct();
        try
            uf = unique({blocks.fnName});
            for gi = 1:numel(uf)
                genMap.(uf{gi}) = generateStimScript(local_findEntry(reg, uf{gi}), ...
                                                     phRun, stimGrid, genDir);
            end
        catch err
            uialert(h.fig, sprintf('Could not write the generated stimulus script:\n%s', ...
                err.message), 'Generate failed');
            return;
        end
        protocol = local_buildProtocol(reg, blocks);
        for bi = 1:numel(protocol)
            protocol(bi).stim = str2func(genMap.(blocks(bi).fnName));
        end
        opts.phases   = phRun;                             % resolved grids + .rendered=true
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
        % The embedded monitor: runExperiment and playAndLogTrial publish through
        % stimProgress and it draws. Re-attach in case the hooks were ever dropped.
        openMonitor();
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
        % The embedded Session monitor is read-only display: leave it LIVE, or the whole
        % right panel (timeline, phase/progress text, LED readout) greys out mid-run --
        % exactly when the operator needs to read it. Run/Cancel sit OUTSIDE h.monPanel.
        mon = findall(h.monPanel, '-property', 'Enable');
        c = c(arrayfun(@(x) ~isequal(x, h.cancelBtn) && ~any(mon == x), c));
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
        % The Session monitor lives INSIDE this window (right panel) -- one window, and
        % the main Cancel button is the only Cancel. Built once, at startup; the hooks
        % live as long as the window does, so the timeline previews the protocol while
        % you are still building it.
        if isempty(monitor)
            monitor = stimulusMonitor(h.monPanel);
        end
        stimProgress('attach', @(kind, msg) monitor.update(kind, msg), @onCancel);
    end

    function closeMonitor()
        stimProgress('detach');
        monitor = [];    % its widgets die with the window; nothing separate to delete
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
        h.qlGroup.SelectedObject = h.qlNone;   % loaded by hand -> no quick-load slot is "current"
        loadExperimentFile(fullfile(p, f));
    end

    function loadExperimentFile(fp)
        % Load one saved experiment (Load... button and the quick-load slots share this).
        try
            [blocks, o] = local_jsonToExperiment(reg, fileread(fp));
            h.preStim.Value  = getfielddef(o, 'preStim', 2);
            h.postStim.Value = getfielddef(o, 'postStim', 1);
            h.itp.Value      = getfielddef(o, 'itp', 3);
            if isfield(o, 'triggerAcq'), h.triggerAcq.Value = logical(o.triggerAcq); end
            applyLedsToUI(getfielddef(o, 'leds', struct()));
            applyPhasesToUI(getfielddef(o, 'phases', []));   % after the flat fields: it wins
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
        % window with the block's stored values. The columns are rebuilt to match the
        % protocol's stimulus type: Label + seed + one column per parameter, all editable.
        if nargin < 1, keepRow = []; end
        [cols, widths, editable] = local_epochTableSpec(reg, blocks);
        h.protoTable.ColumnName     = cols;
        h.protoTable.ColumnWidth    = widths;
        h.protoTable.ColumnEditable = editable;
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
        % o.phases is the band's data (v2: explicit grids + screen colors). The flat
        % preStim/postStim/itp mirror the phase durations for the monitor plan and for
        % older experiment files. (seedBase is gone: every epoch carries its own seed in
        % the protocol table.)
        o = struct('preStim', h.preStim.Value, 'postStim', h.postStim.Value, ...
                   'itp', h.itp.Value, 'triggerAcq', logical(h.triggerAcq.Value));
        o.leds   = gatherLeds();
        o.phases = gatherPhaseSpec();
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
                       'itp', h.itp.Value, 'triggerAcq', logical(h.triggerAcq.Value), ...
                       'stimIndex', h.list.ValueIndex, ...
                       'autoChecks', logical(h.autoChecks.Value));
            o.leds   = gatherLeds();
            o.phases = gatherPhaseSpec();
            rememberParams();               % capture the panel as shown right now
            o.last_params = lastParams;     % per-stimulus last-used parameters
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
        h.triggerAcq.Value = logical(getfielddef(o, 'triggerAcq', true));
        h.autoChecks.Value = logical(getfielddef(o, 'autoChecks', false));
        applyLedsToUI(getfielddef(o, 'leds', struct()));
        applyPhasesToUI(getfielddef(o, 'phases', []));
        lastParams = local_coerceLastParams(reg, getfielddef(o, 'last_params', struct()));
        si = round(getfielddef(o, 'stimIndex', 1));
        if si >= 1 && si <= numel(reg)
            suppressRemember = true;        % restoring must not clobber the restored map
            h.list.ValueIndex = si;
            onSelectStim();
            suppressRemember = false;
        end
        blocks = blk;
        refreshProtocol();
    end

    function leds = gatherLeds()
        leds = struct('enabled', logical(h.ledEnable.Value), ...
                      'port', char(h.ledPort.Value), ...
                      'mode', double(h.ledMode.Value), ...
                      'intensity', phaseGrid43('stim'));   % runExperiment applies this grid
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
        % single grid: prefer `intensity`; fall back to a legacy During grid, else zeros.
        % R/G land on the stimulus table, the B column on the global B (applyPhasesToUI,
        % which runs after this on load, may override both from the saved band spec).
        grid = local_coerce43(getfielddef(L, 'intensity', getfielddef(L, 'during_epochs', zeros(4, 3))));
        h.phGrid.stim.Data = grid(:, 1:2);
        h.masterB.Data     = grid(:, 3);
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
            vals = phaseGrid43('stim');
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
% .seeds: one seed per epoch for seeded stimuli ([] otherwise) -- every Gaussian epoch has
% its OWN seed, shown and editable in the protocol table and recorded per epoch in the
% manifest (and the values CSV).
    b = struct('stimName', {}, 'fnName', {}, 'params', {}, 'epochs', {}, 'label', {}, 'seeds', {});
end

function s = local_nextSeeds(blocks, n, seeded)
% n fresh RANDOM seeds (user request: not a guessable n+1 sequence), uniform over
% [1, 1e6], each distinct from every seed already in the protocol and from each other,
% so every epoch is an INDEPENDENT noise realization. Reproducibility is unchanged --
% the seed that actually ran is recorded per epoch in the manifest (and in the values
% CSV), and analysis regenerates the noise from it. Drawn from a private time-seeded
% stream: the global RNG is untouched, and a fresh MATLAB session does not deal the
% default global sequence (which would repeat seeds across sessions). Pass seeded=false
% (a stimulus with no seed argument) to get [].
    persistent rs
    if isempty(rs)
        rs = RandStream('mt19937ar', 'Seed', ...
                        mod(round(posixtime(datetime('now')) * 1e3), 2^31));
    end
    if nargin >= 3 && ~seeded
        s = [];
        return;
    end
    used = [];
    for b = 1:numel(blocks)
        used = [used, double(reshape(getfielddef(blocks(b), 'seeds', []), 1, []))]; %#ok<AGROW>
    end
    used = used(isfinite(used));
    s = zeros(1, n);
    for i = 1:n
        v = randi(rs, 1e6);
        while any(v == used) || any(v == s(1:i-1))
            v = randi(rs, 1e6);
        end
        s(i) = v;
    end
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
    items = [{local_noPresetItem()}, names];
end

function s = local_noPresetItem()
% The preset dropdowns' placeholder row = "this phase is not assigned to a preset".
    s = '(load preset...)';
end

function n = local_ledNames()
% User-editable LED row names from rig_config `led_names` (double-click a row name on
% the pre-stim table to rename). Always a 1x4 cellstr; anything missing -> 'LED i'.
    n = local_coerceLedNames(loadRigConfig('led_names', []));
end

function n = local_coerceLedNames(raw)
    n = {'LED 0', 'LED 1', 'LED 2', 'LED 3'};
    if isstring(raw), raw = cellstr(raw); end
    if ~iscell(raw), return; end
    for i = 1:min(4, numel(raw))
        try
            v = strtrim(char(string(raw{i})));
        catch
            v = '';
        end
        if ~isempty(v) && (ischar(raw{i}) || isstring(raw{i})), n{i} = v; end
    end
end

function lp = local_coerceLastParams(reg, raw)
% Saved per-stimulus last-used params -> a clean map: only registry stimuli survive, and
% numeric fields come back as ROWS (jsondecode hands back columns for vec2 params).
    lp = struct();
    if ~isstruct(raw), return; end
    fns = fieldnames(raw);
    for i = 1:numel(fns)
        if ~any(strcmp({reg.fn}, fns{i})), continue; end
        ps = raw.(fns{i});
        if ~isstruct(ps), continue; end
        pf = fieldnames(ps);
        for k = 1:numel(pf)
            if isnumeric(ps.(pf{k}))
                ps.(pf{k}) = double(reshape(ps.(pf{k}), 1, []));
            end
        end
        lp.(fns{i}) = ps;
    end
end

function out = local_askString(parentFig, ttl, prompt, current)
% Small modal text prompt (uifigure-native; inputdlg mixes figure types). Returns the
% trimmed string, or '' on cancel/empty.
    out = '';
    pp = parentFig.Position;
    d  = uifigure('Name', ttl, 'Resize', 'off', ...
                  'Position', [pp(1) + 500, pp(2) + 450, 360, 130]);
    g  = uigridlayout(d, [3 2]);
    g.RowHeight   = {'fit', 'fit', 'fit'};
    g.ColumnWidth = {'1x', '1x'};
    lb = uilabel(g, 'Text', prompt, 'WordWrap', 'on');
    lb.Layout.Column = [1 2];
    ef = uieditfield(g, 'text', 'Value', current);
    ef.Layout.Column = [1 2];
    uibutton(g, 'Text', 'OK', 'ButtonPushedFcn', @(s, e) done(true));
    uibutton(g, 'Text', 'Cancel', 'ButtonPushedFcn', @(s, e) done(false));
    d.CloseRequestFcn = @(s, e) done(false);
    uiwait(d);
    function done(ok)
        if ok, out = strtrim(char(ef.Value)); end
        delete(d);
    end
end


function d = local_defaultPhaseSpec(preS, postS, itiS)
% The spec that reproduces the pre-overhaul behavior: black screens, every phase grid
% dark, all-dark end state (= the classic dark + close teardown).
    d = struct('version', 2, ...
        'pre',   struct('seconds', preS,  'rgb', [0 0 0], 'grid', zeros(4, 3), 'preset', ''), ...
        'stim',  struct('grid', zeros(4, 3), 'preset', ''), ...
        'post',  struct('seconds', postS, 'rgb', [0 0 0], 'grid', zeros(4, 3), 'preset', ''), ...
        'iti',   struct('seconds', itiS,  'rgb', [0 0 0], 'grid', zeros(4, 3), 'preset', ''), ...
        'final', struct('rgb', [0 0 0], 'grid', zeros(4, 3), 'preset', ''));
    d.syncB   = false;
    d.masterB = zeros(1, 4);
    d.links   = struct('pre', 0, 'post', 0, 'iti', 0, 'final', 0);   % LED-table link groups
end

function spec = local_normalizePhaseSpec(spec, presets, def)
% Overlay a saved spec onto the defaults, tolerating jsondecode's shapes (columns for
% vectors) and both generations of the format: v2 stores explicit 4x3 grids + screen RGB
% per phase; the short-lived v1 stored a symbolic LED choice ({mode, preset}) per phase --
% converted here against today's presets ('main' = the default's stimulus grid).
    out = def;
    if ~isstruct(spec), spec = struct(); end
    isV1 = isfield(spec, 'pre') && isstruct(spec.pre) && isfield(spec.pre, 'leds');
    for kk = {'pre', 'stim', 'post', 'iti', 'final'}
        key = kk{1};
        if ~isfield(spec, key) || ~isstruct(spec.(key)), continue; end
        src = spec.(key);
        dst = out.(key);
        if isfield(dst, 'seconds') && isfield(src, 'seconds')
            s = double(src.seconds);
            if isscalar(s) && isfinite(s) && s >= 0, dst.seconds = s; end
        end
        if isfield(dst, 'rgb') && isfield(src, 'rgb')
            v = double(reshape(src.rgb, 1, []));
            if numel(v) == 3 && all(isfinite(v)), dst.rgb = min(max(v, 0), 1); end
        end
        if isfield(src, 'grid')
            dst.grid = local_coerce43(src.grid);
        elseif isV1 && isfield(src, 'leds')
            dst.grid = local_v1Grid(src.leds, presets, out.stim.grid);
        end
        if isfield(src, 'preset')       % pre-preset-memory saves simply stay unassigned
            try
                dst.preset = strtrim(char(string(src.preset)));
            catch
                dst.preset = '';
            end
        end
        out.(key) = dst;
    end
    if isfield(spec, 'syncB') && ~isempty(spec.syncB)
        v = spec.syncB;
        if islogical(v) || isnumeric(v)          % jsondecode gives a logical; never
            out.syncB = logical(v(1));           % string-convert it (string(false) is
        end                                      % 'false' -> str2double NaN -> "true")
    end
    if isfield(spec, 'masterB')
        m = double(reshape(spec.masterB, 1, []));
        if numel(m) == 4 && all(isfinite(m)), out.masterB = min(max(m, 0), 1); end
    end
    if isfield(spec, 'links') && isstruct(spec.links)
        for kk = {'pre', 'post', 'iti', 'final'}
            if isfield(spec.links, kk{1})
                v = double(spec.links.(kk{1}));
                if isscalar(v) && isfinite(v) && v >= 0, out.links.(kk{1}) = round(v); end
            end
        end
        % a "group" with a single member is no link at all
        ids = structfun(@(x) x, out.links);
        for kk = {'pre', 'post', 'iti', 'final'}
            g = out.links.(kk{1});
            if g > 0 && sum(ids == g) < 2, out.links.(kk{1}) = 0; end
        end
    end
    spec = out;
end

function g = local_v1Grid(ls, presets, mainGrid)
% v1 symbolic LED choice -> a concrete grid: '(main grid)' = the stimulus grid, 'off' =
% all dark, a preset = its current rig_config values (a vanished preset -> dark).
    g = zeros(4, 3);
    mode = char(string(getfielddef(ls, 'mode', 'main')));
    switch mode
        case 'main'
            g = mainGrid;
        case 'preset'
            k = find(strcmp({presets.name}, char(string(getfielddef(ls, 'preset', '')))), 1);
            if ~isempty(k), g = presets(k).values; end
    end
end

function phases = local_resolvePhaseSpec(spec)
% Band spec (v2) -> the plan runExperiment/generateStimScript consume: per phase
% {seconds, rgb, ledGrid} plus .rendered = true. An ALL-DARK "end of stim" grid means the
% classic teardown (dark + close the driver); any lit value there is applied and left
% RUNNING after the run (the driver is handed off as base-workspace `rig`).
    phases = struct('rendered', true);
    phases.pre  = struct('seconds', spec.pre.seconds,  'rgb', spec.pre.rgb,  'ledGrid', spec.pre.grid);
    phases.post = struct('seconds', spec.post.seconds, 'rgb', spec.post.rgb, 'ledGrid', spec.post.grid);
    phases.iti  = struct('seconds', spec.iti.seconds,  'rgb', spec.iti.rgb,  'ledGrid', spec.iti.grid);
    g = spec.final.grid;
    if ~any(g(:)), g = []; end
    phases.final = struct('rgb', spec.final.rgb, 'ledGrid', g);
end


% ---------- Quick load: 10 assignable experiment slots ----------

function s = local_loadQuickSlots(file)
% experiments/quickload_slots.json -> 1x10 struct('name','file'). Missing/corrupt file or
% short slot list -> empty slots (never an error at GUI startup).
    s = repmat(struct('name', '', 'file', ''), 1, 10);
    try
        if ~exist(file, 'file'), return; end
        raw   = jsondecode(fileread(file));
        items = local_asCell(getfielddef(raw, 'slots', {}));
        for i = 1:min(10, numel(items))
            r = items{i};
            if isstruct(r)
                s(i).name = char(string(getfielddef(r, 'name', '')));
                s(i).file = char(string(getfielddef(r, 'file', '')));
            end
        end
    catch
    end
end

function local_saveQuickSlots(file, slots)
    doc = struct('format', 'neitz-quickload/1');
    doc.slots = arrayfun(@(x) struct('name', x.name, 'file', x.file), slots(:)', ...
                         'UniformOutput', false);
    fid = fopen(file, 'w');
    if fid < 0
        error('stimulusGUI:quickSave', 'Cannot write %s', file);
    end
    fwrite(fid, jsonencode(doc, 'PrettyPrint', true), 'char');
    fclose(fid);
end

function t = local_quickLabel(i, slot)
    if isempty(slot.file)
        nm = '(empty)';
    else
        nm = slot.name;
        if isempty(nm), [~, nm] = fileparts(slot.file); end
    end
    t = sprintf('%d:  %s', i, nm);
end

function p = local_slotPath(expDir, file)
% Slot files saved under experiments/ are stored relative (portable across machines);
% anything else is an absolute path used as-is.
    if isempty(fileparts(file))
        p = fullfile(expDir, file);
    else
        p = file;
    end
end

function s = local_stripSep(p)
    s = char(p);
    while ~isempty(s) && (s(end) == '/' || s(end) == '\')
        s = s(1:end-1);
    end
end

function f = local_safeFileName(name)
% A filesystem-safe stem for "Bind current protocol": keep word characters and dashes,
% everything else becomes '_'.
    f = regexprep(char(string(name)), '[^\w\-]', '_');
    if isempty(f), f = 'experiment'; end
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


% ---------- optional checksX <-> checksY auto-derivation (square on the wall) ----------
% The checkerboards' 40 x 25 default is the square-on-the-wall pair at pixel_aspect 2 on
% the 912 x 1140 diamond DMD. With the auto-checks box ticked, editing either direction
% re-derives the other from the same rule the generated scripts document:
%   checksY = round(checksX * (H/W) / pixel_aspect)

function tf = local_hasChecksXY(entry)
% Only the checkerboards expose both checks directions as parameters.
    tf = any(strcmp(entry.params(:, 1), 'checksX')) && any(strcmp(entry.params(:, 1), 'checksY'));
end

function r = local_checksRatio()
% checksY per checksX for square-on-the-wall checks tiling the full canvas.
    cs = loadRigConfig('canvas_size', [912 1140]);
    r  = (double(cs(2)) / double(cs(1))) / double(loadRigConfig('pixel_aspect', 2));
end

function y = local_checksYFromX(x)
    y = max(1, round(double(x) * local_checksRatio()));
end

function x = local_checksXFromY(y)
    x = max(1, round(double(y) / local_checksRatio()));
end

function data = local_syncChecks(entry, data, editedName)
% Re-derive whichever checks direction the user did NOT just type. Returns the updated
% table rows; throws (with a uialert-ready message) on unparseable input.
    xRow = local_rowIndex(data, 'checksX');
    yRow = local_rowIndex(data, 'checksY');
    if any([xRow yRow] == 0), return; end
    if strcmp(editedName, 'checksY')
        y = local_parseValue('num', data{yRow, 2}, entry, 'checksY');
        data{xRow, 2} = local_valueStr('num', local_checksXFromY(y));
    else
        x = local_parseValue('num', data{xRow, 2}, entry, 'checksX');
        data{yRow, 2} = local_valueStr('num', local_checksYFromX(x));
    end
end

function blocks = local_autoChecksEpoch(reg, blocks, row, key)
% Epoch-table twin of local_syncChecks: after a checksX/checksY cell edit, rewrite the
% OTHER direction of that same epoch. A no-op for every other column.
    if ~any(strcmp(key, {'p:checksX', 'p:checksY'})), return; end
    flat = local_flattenEpochs(blocks);
    if row < 1 || row > numel(flat), return; end
    e = local_findEntry(reg, blocks(1).fnName);
    if ~local_hasChecksXY(e), return; end
    if strcmp(key, 'p:checksX')
        x = double(local_paramValue(e, flat(row).params, 'checksX'));
        blocks = local_applyCellEdit(reg, blocks, row, 'p:checksY', local_checksYFromX(x));
    else
        y = double(local_paramValue(e, flat(row).params, 'checksY'));
        blocks = local_applyCellEdit(reg, blocks, row, 'p:checksX', local_checksXFromY(y));
    end
end


% ---------- protocol table: one row per EPOCH (blocks are the run-time grouping) ----------

function [cols, widths, editable, keys] = local_epochTableSpec(reg, blocks)
% Columns for the protocol table. A (normal) single-stimulus protocol gets one EDITABLE
% column per thing an epoch owns: Label, its seed (seeded stimuli), and every parameter in
% registry order. `keys` says what an edit to each column means: 'epoch' (read-only
% number), 'label', 'seed', or 'p:<paramName>'. A legacy mixed-stimulus protocol falls
% back to the old read-only overview ('readonly' keys).
    if ~isempty(blocks) && ~local_mixedStims(blocks)
        e   = local_findEntry(reg, blocks(1).fnName);
        idx = local_editableParams(e);
        % Weighted widths so the columns EXPAND to fill the table's full width -- no
        % dead space right of the last column. uitable weights must be INTEGER 'Nx'
        % ('1.4x' is rejected, unlike uigridlayout).
        cols     = {'Epoch #', 'Label'};
        widths   = {64, '2x'};
        keys     = {'epoch', 'label'};
        editable = [false, true];
        if local_seedArgFor(e) > 0
            cols{end+1} = 'seed';  widths{end+1} = 48;
            keys{end+1} = 'seed';  editable(end+1) = true;
        end
        for k = idx
            cols{end+1} = e.params{k, 1};                               %#ok<AGROW>
            keys{end+1} = ['p:' e.params{k, 1}];                        %#ok<AGROW>
            editable(end+1) = true;                                     %#ok<AGROW>
            switch e.params{k, 3}
                case 'vec2', widths{end+1} = '1x';                      %#ok<AGROW>
                case 'enum', widths{end+1} = '2x';                      %#ok<AGROW>
                otherwise,   widths{end+1} = '1x';                      %#ok<AGROW>
            end
        end
        if local_hasDuration(e)
            % the derived "duration (s)" sits right after stimFrames, exactly as in the
            % parameter panel: type seconds and that epoch's stimFrames follows
            di       = find(strcmp(cols, 'stimFrames'), 1);
            cols     = [cols(1:di),     {local_durRowName()}, cols(di+1:end)];
            widths   = [widths(1:di),   {'1x'},               widths(di+1:end)];
            keys     = [keys(1:di),     {'dur'},              keys(di+1:end)];
            editable = [editable(1:di), true,                 editable(di+1:end)];
        end
    else
        cols     = {'Epoch #', 'Stimulus', 'Label', 'Params'};
        widths   = {64, 220, 110, '1x'};
        keys     = {'epoch', 'readonly', 'readonly', 'readonly'};
        editable = [false, false, false, false];
    end
end

function rows = local_epochRows(reg, blocks)
% Expand the blocks into one display row per epoch, matching local_epochTableSpec's
% columns. Epoch numbers are global across the protocol, matching the order runExperiment
% presents them (and therefore the order Clampex saves the .abf files). Numeric parameters
% are numbers (so typing in a cell edits a number), vec2/enum are text.
    if isempty(blocks)
        rows = cell(0, 2);
        return;
    end
    if local_mixedStims(blocks)
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
        return;
    end
    e      = local_findEntry(reg, blocks(1).fnName);
    idx    = local_editableParams(e);
    seeded = local_seedArgFor(e) > 0;
    flat   = local_flattenEpochs(blocks);
    rows   = cell(numel(flat), 2 + double(seeded) + numel(idx));
    % Every cell is TEXT: a uifigure uitable renders raw doubles in a cell array as
    % "600.0000", which is unreadable for frame counts and seeds. Edits come back as
    % text and are parsed by local_applyCellEdit either way.
    for i = 1:numel(flat)
        rows{i, 1} = sprintf('%d', i);
        rows{i, 2} = char(flat(i).label);
        c = 3;
        if seeded
            rows{i, c} = local_valueStr('num', flat(i).seed);
            c = c + 1;
        end
        for k = idx
            name = e.params{k, 1};
            if isfield(flat(i).params, name), v = flat(i).params.(name); else, v = e.params{k, 2}; end
            rows{i, c} = local_valueStr(e.params{k, 3}, v);
            c = c + 1;
            if strcmp(name, 'stimFrames') && local_hasDuration(e)
                rr = double(local_paramValue(e, flat(i).params, 'refreshRate'));
                rows{i, c} = local_valueStr('num', local_durationFromFrames(double(v), rr));
                c = c + 1;
            end
        end
    end
end

function blocks = local_applyCellEdit(reg, blocks, row, key, newVal)
% One typed cell -> one epoch changed. The epoch is flattened out, the field rewritten,
% and runs of identical neighbours re-collapsed into blocks -- so editing a middle epoch
% splits its block, and editing it back re-merges. Throws (uialert-ready) on bad input.
    if local_mixedStims(blocks)
        error('stimulusGUI:mixedEdit', ['This legacy mixed-stimulus protocol is read-only ' ...
              'in the table. Rebuild it as single-stimulus protocols to edit epochs.']);
    end
    flat = local_flattenEpochs(blocks);
    if row < 1 || row > numel(flat), return; end
    e = local_findEntry(reg, blocks(1).fnName);
    switch key
        case 'label'
            flat(row).label = char(string(newVal));
        case 'seed'
            v = local_numFrom(newVal);
            if ~isscalar(v) || ~isfinite(v) || v < 0
                error('stimulusGUI:badSeed', 'seed must be a number >= 0 (got "%s").', ...
                      char(string(newVal)));
            end
            flat(row).seed = round(v);
        case 'dur'                                  % derived: seconds -> whole stimFrames
            rr = double(local_paramValue(e, flat(row).params, 'refreshRate'));
            flat(row).params.stimFrames = local_framesFromDuration(local_numFrom(newVal), rr);
        otherwise                                   % 'p:<paramName>'
            name = key(3:end);
            r = find(strcmp(e.params(:, 1), name), 1);
            if isempty(r)
                error('stimulusGUI:unknownParam', '"%s" is not an argument of %s.', name, e.fn);
            end
            typ = e.params{r, 3};
            if strcmp(typ, 'num') && isnumeric(newVal) && isscalar(newVal)
                if ~isfinite(newVal)
                    error('stimulusGUI:badNum', 'Parameter "%s" must be a number.', name);
                end
                v = double(newVal);
            else
                v = local_parseValue(typ, char(string(newVal)), e, name);
            end
            flat(row).params.(name) = v;
    end
    blocks = local_collapseEpochs(flat);
end

function v = local_numFrom(x)
    if isnumeric(x) && isscalar(x)
        v = double(x);
    else
        v = str2double(char(string(x)));
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
% Drop one epoch from the block owning `row` -- including ITS seed, so the remaining
% epochs keep the seeds they already had; drop the block when its last epoch goes.
    b = local_blockOfEpoch(blocks, row);
    if b == 0, return; end
    nBefore = 0;
    for i = 1:b-1
        nBefore = nBefore + blocks(i).epochs;
    end
    k = row - nBefore;
    if k >= 1 && k <= numel(blocks(b).seeds)
        blocks(b).seeds(k) = [];
    end
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
% One struct per epoch, in display order, carrying that epoch's own seed (NaN = the
% stimulus takes no seed).
    flat = struct('stimName', {}, 'fnName', {}, 'params', {}, 'label', {}, 'seed', {});
    for b = 1:numel(blocks)
        seeds = getfielddef(blocks(b), 'seeds', []);
        for k = 1:blocks(b).epochs
            if k <= numel(seeds), sd = seeds(k); else, sd = NaN; end
            flat(end + 1) = struct('stimName', blocks(b).stimName, 'fnName', blocks(b).fnName, ...
                                   'params', blocks(b).params, 'label', blocks(b).label, ...
                                   'seed', sd); %#ok<AGROW>
        end
    end
end

function blocks = local_collapseEpochs(flat)
% Inverse of local_flattenEpochs: consecutive epochs that agree on stimulus, parameters and
% label become one block again. Seeds are PER EPOCH, so they never split a block -- they
% ride along in the block's .seeds vector, in epoch order.
    blocks = local_emptyBlocks();
    for i = 1:numel(flat)
        f = flat(i);
        if ~isempty(blocks) && strcmp(blocks(end).fnName, f.fnName) && ...
                isequal(blocks(end).params, f.params) && strcmp(blocks(end).label, f.label)
            blocks(end).epochs = blocks(end).epochs + 1;
            if isfinite(f.seed), blocks(end).seeds(end + 1) = f.seed; end
        else
            sd = [];
            if isfinite(f.seed), sd = f.seed; end
            blocks(end + 1) = struct('stimName', f.stimName, 'fnName', f.fnName, ...
                                     'params', f.params, 'epochs', 1, 'label', f.label, ...
                                     'seeds', sd); %#ok<AGROW>
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
    protocol = struct('stim', {}, 'args', {}, 'epochs', {}, 'label', {}, 'seedArg', {}, 'seeds', {});
    for b = 1:numel(blocks)
        e = local_findEntry(reg, blocks(b).fnName);
        protocol(b).stim    = str2func(blocks(b).fnName);
        protocol(b).args    = local_argsFor(e, blocks(b).params);
        protocol(b).epochs  = blocks(b).epochs;
        protocol(b).label   = blocks(b).label;
        protocol(b).seedArg = local_seedArgFor(e);
        protocol(b).seeds   = getfielddef(blocks(b), 'seeds', []);   % per-epoch seeds (GUI-owned)
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
                       'epochs', blocks(i).epochs, 'label', blocks(i).label, ...
                       'seeds', getfielddef(blocks(i), 'seeds', []));
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
        % params / epochs / label / seeds still loads instead of throwing a raw field error.
        blocks(i) = struct('stimName', e.name, 'fnName', e.fn, ...
                           'params', getfielddef(r, 'params', struct()), ...
                           'epochs', double(getfielddef(r, 'epochs', 1)), ...
                           'label',  char(string(getfielddef(r, 'label', ''))), ...
                           'seeds',  double(reshape(getfielddef(r, 'seeds', []), 1, [])));
    end
    blocks = local_fixSeeds(reg, blocks);
end

function blocks = local_fixSeeds(reg, blocks)
% Every seeded block ends up with exactly one seed per epoch: pre-seeds files (or
% hand-edited ones) are topped up with fresh seeds, over-long lists are trimmed, and
% non-seeded stimuli carry none.
    for i = 1:numel(blocks)
        e = local_findEntry(reg, blocks(i).fnName);
        if local_seedArgFor(e) > 0
            s = double(reshape(getfielddef(blocks(i), 'seeds', []), 1, []));
            s = s(isfinite(s));
            n = blocks(i).epochs;
            if numel(s) > n, s = s(1:n); end
            if numel(s) < n
                s = [s, local_nextSeeds(blocks, n - numel(s))]; %#ok<AGROW>
            end
            blocks(i).seeds = s;
        else
            blocks(i).seeds = [];
        end
    end
end

function c = local_asCell(x)
    if iscell(x), c = x; elseif isstruct(x), c = num2cell(x); else, c = {x}; end
end

function v = getfielddef(s, f, d)
    if isstruct(s) && isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end

function local_checkRegistry(reg)
% The FIRST nargin(fn) rows must match the AA function's signature in order; rows
% BEYOND that are GENERATED-SCRIPT-ONLY parameters (e.g. the checkerboards' checksX /
% checksY) -- the per-run generated function takes them, the untouched AA file does not.
    for i = 1:numel(reg)
        want = nargin(reg(i).fn);
        got  = size(reg(i).params, 1);
        assert(want < 0 || got >= want, ...
            'stimRegistry drift: %s takes %d args but the registry lists only %d.', reg(i).fn, want, got);
    end
end


% ================================= headless self-test =================================
function selftest()
    reg = stimRegistry();
    local_checkRegistry(reg);
    fprintf('[selftest] registry: %d stimuli, params cover each AA signature\n', numel(reg));

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

    % ---- optional checksX <-> checksY auto-derivation (square on the wall) ----
    cb = local_findEntry(reg, 'AASeededGaussianCheckerboardGreyScaleStimFinal');
    assert(local_hasChecksXY(cb) && ~local_hasChecksXY(g) && ~local_hasChecksXY(j), ...
        'only the checkerboards expose checksX/checksY');
    cs = loadRigConfig('canvas_size', [912 1140]);
    pa = double(loadRigConfig('pixel_aspect', 2));
    assert(local_checksYFromX(40) == max(1, round(40 * (double(cs(2)) / double(cs(1))) / pa)), ...
        'checksY derives from checksX via (H/W) / pixel_aspect');
    if abs(pa - 2) < 1e-9
        assert(local_checksYFromX(40) == 25 && local_checksXFromY(25) == 40, ...
            'registry defaults 40 x 25 are the square-on-the-wall pair at pixel_aspect 2');
    end
    assert(local_checksYFromX(0.4) == 1, 'a tiny checksX still derives at least one check row');
    pcb = struct('mu', 0.5, 'sigma', 0.3, 'flickerHz', 4, 'stimFrames', 600, ...
                 'refreshRate', 60, 'checksX', 40, 'checksY', 25);
    rowsC = local_paramRows(cb, pcb);
    xR = find(strcmp(rowsC(:, 1), 'checksX'), 1);
    yR = find(strcmp(rowsC(:, 1), 'checksY'), 1);
    assert(~isempty(xR) && ~isempty(yR), 'the checkerboard panel lists both checks directions');
    rowsC{xR, 2} = '80';
    rc = local_syncChecks(cb, rowsC, 'checksX');
    assert(strcmp(rc{yR, 2}, num2str(local_checksYFromX(80))), 'editing checksX rewrites checksY');
    rc{yR, 2} = '10';
    rc2 = local_syncChecks(cb, rc, 'checksY');
    assert(strcmp(rc2{xR, 2}, num2str(local_checksXFromY(10))), 'editing checksY rewrites checksX');
    cbBlocks    = local_emptyBlocks();
    cbBlocks(1) = struct('stimName', cb.name, 'fnName', cb.fn, 'params', pcb, ...
                         'epochs', 2, 'label', 'cb', 'seeds', [7 8]);
    cbBlocks = local_applyCellEdit(reg, cbBlocks, 2, 'p:checksX', 80);
    cbBlocks = local_autoChecksEpoch(reg, cbBlocks, 2, 'p:checksX');
    flatC = local_flattenEpochs(cbBlocks);
    assert(flatC(2).params.checksX == 80 && flatC(2).params.checksY == local_checksYFromX(80), ...
        'the epoch-table twin re-derives the edited epoch''s checksY');
    assert(flatC(1).params.checksX == 40 && flatC(1).params.checksY == 25, ...
        'the untouched epoch keeps its own checks pair');
    cbBlocks = local_autoChecksEpoch(reg, cbBlocks, 2, 'p:sigma');   % non-checks column: no-op
    flatC2 = local_flattenEpochs(cbBlocks);
    assert(isequal(flatC2(2).params, flatC(2).params), 'a non-checks edit leaves the pair alone');
    fprintf('[selftest] auto checks: X <-> Y stay square-on-the-wall through panel and epoch table\n');

    % ---- per-epoch seeds: RANDOM auto-assignment, unique within the protocol ----
    blocks    = local_emptyBlocks();
    s3 = local_nextSeeds(blocks, 3);
    assert(numel(s3) == 3 && numel(unique(s3)) == 3 && all(s3 >= 1 & s3 <= 1e6) && ...
           all(s3 == round(s3)), 'fresh seeds are 3 distinct random integers in [1, 1e6]');
    assert(~isequal(local_nextSeeds(blocks, 3), local_nextSeeds(blocks, 3)), ...
        'consecutive draws differ (the seed stream advances)');
    assert(isempty(local_nextSeeds(blocks, 3, false)), 'non-seeded stimuli get no seeds');
    blocks(1) = struct('stimName', g.name, 'fnName', g.fn, 'params', ps, 'epochs', 5, ...
                       'label', 'grey gauss', 'seeds', [2 3 4 5 6]);
    for rep = 1:50   % new seeds NEVER collide with the ones already in the protocol
        assert(~any(ismember(local_nextSeeds(blocks, 2), blocks(1).seeds)), ...
            'fresh seeds avoid every seed already in use');
    end
    blocks(2) = struct('stimName', j.name, 'fnName', j.fn, 'params', pj, 'epochs', 3, ...
                       'label', 'jit', 'seeds', []);
    opts = struct('preStim', 2, 'postStim', 1, 'itp', 3, ...
                  'triggerAcq', false, 'stimIndex', 3);
    opts.leds = struct('enabled', true, 'port', 'AUTO', 'mode', 2, ...
                       'intensity', [0.75 0 0; 0 0.5 0; 0 0 0; 0 0 0.125]);
    [b2, o2] = local_jsonToExperiment(reg, local_experimentToJson(blocks, opts));
    assert(numel(b2) == 2 && strcmp(b2(1).fnName, g.fn) && b2(1).epochs == 5, 'json round-trip blocks');
    assert(isequal(b2(1).seeds, [2 3 4 5 6]) && isempty(b2(2).seeds), ...
        'per-epoch seeds round-trip through the experiment JSON');
    assert(isequal(local_argsFor(local_findEntry(reg, b2(1).fnName), b2(1).params), {[], 0.5, 0.3, 4, 600, 60}), ...
        'json round-trip rebuilds gaussian args');
    assert(o2.leds.enabled && o2.leds.mode == 2, 'json round-trip LED scalars');
    assert(isequal(size(o2.leds.intensity), [4, 3]) && abs(o2.leds.intensity(1, 1) - 0.75) < 1e-9, ...
        'json round-trip LED grid');
    assert(o2.stimIndex == 3 && o2.triggerAcq == false, ...
        'session-state round-trip (stimIndex / triggerAcq)');
    legacy = struct('format', 'neitz-experiment/1', 'opts', struct(), 'blocks', ...
                    {{struct('stim', g.fn, 'params', ps, 'epochs', 3, 'label', 'old')}});
    bl = local_jsonToExperiment(reg, jsonencode(legacy));
    assert(numel(bl(1).seeds) == 3 && numel(unique(bl(1).seeds)) == 3 && ...
           all(bl(1).seeds >= 1 & bl(1).seeds <= 1e6), ...
        'a pre-seeds file gets fresh (random, distinct) per-epoch seeds on load');

    % ---- protocol table lists one row per EPOCH; blocks stay the run-time grouping ----
    % (this test protocol is legacy-MIXED, so it renders as the read-only overview)
    eRows = local_epochRows(reg, blocks);                 % 5 gaussian epochs + 3 jitter epochs
    assert(isequal(size(eRows), [8 4]), '5 + 3 epochs -> 8 rows of {Epoch #, Stimulus, Label, Params}');
    assert(isequal(eRows{1, 1}, 1) && isequal(eRows{8, 1}, 8), 'epoch numbering is global and 1-based');
    assert(strcmp(eRows{5, 2}, g.name) && strcmp(eRows{6, 2}, j.name), 'each row carries its block''s stimulus');
    assert(strcmp(eRows{2, 4}, eRows{3, 4}), 'epochs of one block repeat identical parameters');
    [~, ~, edMix, keysMix] = local_epochTableSpec(reg, blocks);
    assert(~any(edMix) && all(strcmp(keysMix(2:end), 'readonly')), 'mixed protocols are read-only');

    % ---- single-stimulus protocol: one EDITABLE column per parameter + Label + seed ----
    gb    = local_emptyBlocks();
    gb(1) = struct('stimName', g.name, 'fnName', g.fn, 'params', ps, 'epochs', 3, ...
                   'label', 'ga', 'seeds', [2 3 4]);
    [cols1, ~, ed1, keys1] = local_epochTableSpec(reg, gb);
    assert(isequal(cols1, {'Epoch #', 'Label', 'seed', 'mu', 'sigma', 'flickerHz', ...
                           'stimFrames', 'duration (s)', 'refreshRate'}), ...
        'gaussian table: Label + seed + every parameter + the derived duration column');
    assert(~ed1(1) && all(ed1(2:end)), 'everything but Epoch # is editable');
    assert(strcmp(keys1{3}, 'seed') && strcmp(keys1{4}, 'p:mu') && strcmp(keys1{8}, 'dur'), ...
        'column keys map edits (duration key = dur)');
    gRows = local_epochRows(reg, gb);
    assert(isequal(size(gRows), [3 9]) && strcmp(gRows{2, 3}, '3') && ...
           strcmp(gRows{2, 4}, '0.5') && strcmp(gRows{2, 7}, '600') && strcmp(gRows{2, 8}, '10'), ...
        'rows carry per-epoch seed + parameter cells + duration (600/60 = 10 s)');
    gbd = local_applyCellEdit(reg, gb, 2, 'dur', '5');
    assert(gbd(2).params.stimFrames == 300, 'a duration edit rewrites that epoch''s stimFrames');
    % edit one epoch's sigma: it splits into its own block, seeds staying put
    gb2 = local_applyCellEdit(reg, gb, 2, 'p:sigma', 0.9);
    assert(numel(gb2) == 3 && gb2(2).params.sigma == 0.9 && ...
           isequal([gb2.seeds], [2 3 4]), 'a cell edit splits just that epoch, seeds kept');
    % edit it back: the three epochs re-merge into one block
    gb3 = local_applyCellEdit(reg, gb2, 2, 'p:sigma', 0.3);
    assert(isscalar(gb3) && gb3.epochs == 3 && isequal(gb3.seeds, [2 3 4]), ...
        'editing back re-merges the block');
    gb4 = local_applyCellEdit(reg, gb, 2, 'seed', 99);
    assert(isscalar(gb4) && isequal(gb4.seeds, [2 99 4]), ...
        'a seed edit changes only that epoch and never splits the block');
    gb5 = local_applyCellEdit(reg, gb, 3, 'label', 'last');
    assert(numel(gb5) == 2 && strcmp(gb5(2).label, 'last') && isequal(gb5(2).seeds, 4), ...
        'a label edit splits the labelled epoch out');
    ok = false;
    try
        local_applyCellEdit(reg, gb, 1, 'seed', 'grey');
    catch
        ok = true;
    end
    assert(ok, 'a junk seed is refused');
    jb    = local_emptyBlocks();
    jb(1) = struct('stimName', j.name, 'fnName', j.fn, 'params', pj, 'epochs', 2, ...
                   'label', '', 'seeds', []);
    [colsJ, ~, ~, keysJ] = local_epochTableSpec(reg, jb);
    assert(~any(strcmp(colsJ, 'seed')) && any(strcmp(keysJ, 'p:colorMode')), ...
        'non-seeded stimuli get no seed column; enum params get one');
    jb2 = local_applyCellEdit(reg, jb, 1, 'p:rfCenter', '100 200');
    assert(isequal(jb2(1).params.rfCenter, [100 200]), 'vec2 cells parse "x y" text');
    fprintf('[selftest] protocol table: per-parameter editable columns + per-epoch seeds\n');
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

    fprintf('[selftest] protocol table = one row per epoch; one stimulus type per protocol\n');

    % ---- LED row names: defaults, coercion, round-trip shape ----
    nm = local_coerceLedNames([]);
    assert(isequal(nm, {'LED 0', 'LED 1', 'LED 2', 'LED 3'}), 'missing led_names -> defaults');
    nm = local_coerceLedNames({'545nm'; ''; 42; 'IR'});      % jsondecode column + junk
    assert(isequal(nm, {'545nm', 'LED 1', 'LED 2', 'IR'}), ...
        'led_names coercion: keeps real names, defaults empties/junk, row shape');
    fprintf('[selftest] LED row names coerce + default correctly\n');

    pr = local_loadPresets();                       % presets read from rig_config.json
    assert(numel(pr) >= 2 && any(strcmp({pr.name}, 'Off')) && any(strcmp({pr.name}, 'macaque s-iso')), ...
        'presets load with friendly names preserved (spaces survive jsondecode)');
    kk = find(strcmp({pr.name}, 'macaque s-iso'), 1);
    assert(isequal(size(pr(kk).values), [4, 3]) && abs(pr(kk).values(4, 1) - 1.0) < 1e-9 ...
        && abs(pr(kk).values(2, 3) - 1.0) < 1e-9, 'macaque s-iso values (LED3 R=1, LED1 B=1)');
    assert(numel(local_presetNames(pr)) == numel(pr) + 1, 'preset dropdown includes the placeholder');
    fprintf('[selftest] LED grid round-trip + presets (Off / macaque s-iso) from rig_config\n');

    % ---- band spec (v2): defaults, normalization, v1 conversion, resolution ----
    def = local_defaultPhaseSpec(2, 1, 3);
    nrm = local_normalizePhaseSpec([], pr, def);
    assert(isequal(nrm, def), 'an absent phases spec normalizes to the defaults');

    ledsUI = struct('enabled', true, 'intensity', [0.75 0 0; 0 0.5 0; 0 0 0; 0 0 0.125]);
    spec = def;
    spec.stim.grid = ledsUI.intensity;
    spec.pre.grid  = pr(kk).values;               % macaque s-iso on the pre-stim phase
    spec.pre.rgb   = [0.5 0.5 0.5];
    spec.iti.rgb   = [0.2 0.2 0.2];
    spec.final.grid = [0 0 0; 0 0 0.25; 0 0 0; 0 0 0];
    spec.syncB   = true;
    spec.masterB = [0.25 0.25 0 0];
    mangled = spec;
    mangled.pre.rgb  = [0.5; 0.5; 0.5];           % jsondecode hands back columns
    mangled.masterB  = spec.masterB(:);
    nrm = local_normalizePhaseSpec(mangled, pr, def);
    assert(isequal(nrm.pre.rgb, [0.5 0.5 0.5]) && isequal(nrm.masterB, [0.25 0.25 0 0]) && ...
           nrm.syncB && isequal(nrm.pre.grid, pr(kk).values), ...
        'v2 spec normalizes jsondecode shapes back to rows');

    v1 = struct('pre',   struct('seconds', 4, 'rgb', [0.1 0.1 0.1], ...
                                'leds', struct('mode', 'preset', 'preset', 'macaque s-iso')), ...
                'post',  struct('seconds', 1, 'rgb', [0 0 0], 'leds', struct('mode', 'main', 'preset', '')), ...
                'iti',   struct('seconds', 3, 'rgb', [0 0 0], 'leds', struct('mode', 'off', 'preset', '')), ...
                'final', struct('rgb', [0 0 0], 'leds', struct('mode', 'off', 'preset', '')));
    defM = def;
    defM.stim.grid = ledsUI.intensity;            % what applyLedsToUI already loaded
    n1 = local_normalizePhaseSpec(v1, pr, defM);
    assert(n1.pre.seconds == 4 && isequal(n1.pre.grid, pr(kk).values) && ...
           isequal(n1.post.grid, ledsUI.intensity) && ~any(n1.iti.grid(:)) && ~any(n1.final.grid(:)), ...
        'a v1 (symbolic) spec converts: preset -> its grid, main -> the stimulus grid, off -> dark');

    ph = local_resolvePhaseSpec(spec);
    assert(ph.rendered && ph.pre.seconds == 2 && isequal(ph.pre.ledGrid, pr(kk).values) && ...
           isequal(ph.pre.rgb, [0.5 0.5 0.5]), 'resolve: pre carries seconds + rgb + grid');
    assert(isequal(ph.iti.rgb, [0.2 0.2 0.2]) && ~any(ph.iti.ledGrid(:)), 'resolve: iti as set');
    assert(isequal(ph.final.ledGrid, spec.final.grid), ...
        'resolve: a lit end-of-stim grid is applied (and handed off at run end)');
    specDarkEnd = spec;
    specDarkEnd.final.grid = zeros(4, 3);
    ph2 = local_resolvePhaseSpec(specDarkEnd);
    assert(isempty(ph2.final.ledGrid), 'resolve: an all-dark end grid = classic dark+close teardown');

    % the band spec survives the experiment JSON round-trip
    opts2 = opts;
    opts2.phases = spec;
    [~, o3] = local_jsonToExperiment(reg, local_experimentToJson(blocks, opts2));
    n3 = local_normalizePhaseSpec(getfielddef(o3, 'phases', []), pr, def);
    assert(isequal(n3.pre.grid, pr(kk).values) && isequal(n3.iti.rgb, [0.2 0.2 0.2]) && ...
           n3.syncB && isequal(n3.masterB, [0.25 0.25 0 0]) && ...
           isequal(n3.final.grid, spec.final.grid), ...
        'band spec (grids + colors + B-lock) round-trips through the experiment JSON');

    % ---- preset ASSIGNMENTS: per phase, JSON round-trip, junk tolerated ----
    assert(all(cellfun(@(k) isfield(def.(k), 'preset') && isempty(def.(k).preset), ...
        {'pre', 'stim', 'post', 'iti', 'final'})), 'default spec: every phase starts unassigned');
    spec.pre.preset  = 'macaque s-iso';
    spec.stim.preset = 'all on 25';
    opts3 = opts;
    opts3.phases = spec;
    [~, o4] = local_jsonToExperiment(reg, local_experimentToJson(blocks, opts3));
    n4 = local_normalizePhaseSpec(getfielddef(o4, 'phases', []), pr, def);
    assert(strcmp(n4.pre.preset, 'macaque s-iso') && strcmp(n4.stim.preset, 'all on 25') && ...
           isempty(n4.iti.preset), 'preset assignments round-trip through the experiment JSON');
    bad = n4;
    bad.pre.preset = 42;                          % junk in a hand-edited file
    n5 = local_normalizePhaseSpec(bad, pr, def);
    assert(ischar(n5.pre.preset), 'a junk preset field coerces to text (unknown names fall back on load)');
    fprintf('[selftest] band spec v2: defaults, v1 conversion, resolution, JSON round-trip, presets\n');

    % ---- Quick-load slots: JSON round-trip + labels + path resolution ----
    tq = tempname;
    mkdir(tq);
    cleanupQ = onCleanup(@() rmdir(tq, 's'));
    qf = fullfile(tq, 'quickload_slots.json');
    sl = repmat(struct('name', '', 'file', ''), 1, 10);
    sl(1) = struct('name', 'grey 5x', 'file', 'grey_5x.json');
    sl(7) = struct('name', '', 'file', fullfile(tq, 'abs.json'));
    local_saveQuickSlots(qf, sl);
    sl2 = local_loadQuickSlots(qf);
    assert(numel(sl2) == 10 && strcmp(sl2(1).name, 'grey 5x') && strcmp(sl2(1).file, 'grey_5x.json') ...
           && isempty(sl2(2).file) && strcmp(sl2(7).file, fullfile(tq, 'abs.json')), ...
        'quick-load slots round-trip through JSON');
    slMissing = local_loadQuickSlots(fullfile(tq, 'missing.json'));
    assert(numel(slMissing) == 10 && all(cellfun(@isempty, {slMissing.file})), ...
        'a missing slots file yields empty slots, not an error'); %#ok<*NASGU>
    assert(strcmp(local_quickLabel(3, sl2(3)), '3:  (empty)') && ...
           contains(local_quickLabel(1, sl2(1)), 'grey 5x') && ...
           contains(local_quickLabel(7, sl2(7)), 'abs'), 'slot labels: number + name / (empty)');
    assert(strcmp(local_slotPath('/exp', 'a.json'), fullfile('/exp', 'a.json')) && ...
           strcmp(local_slotPath('/exp', '/data/b.json'), '/data/b.json'), ...
        'bare slot files resolve under experiments/, absolute paths pass through');
    fprintf('[selftest] Quick-load slots: JSON round-trip, labels, path resolution\n');

    % ---- generateStimScript: every registry entry emits a parseable, complete script ----
    tg = tempname;
    mkdir(tg);
    cleanupG = onCleanup(@() local_cleanupGenTest(tg));
    phGen = ph;                          % the resolved plan from above (preset pre-grid etc.)
    for gi = 1:numel(reg)
        [gfn, gpath] = generateStimScript(reg(gi), phGen, ledsUI.intensity, tg);
        assert(exist(gpath, 'file') == 2, 'generated file exists: %s', reg(gi).fn);
        % parseable + exact signature: nargin resolves only if MATLAB can parse the file
        assert(nargin(gfn) == size(reg(gi).params, 1), ...
            'generated %s has the same arity as %s', gfn, reg(gi).fn);
        src = fileread(gpath);
        assert(contains(src, ['''' reg(gi).fn '''']), 'record keeps the AA stimulus name');
        assert(contains(src, 'stageClientShared') && contains(src, 'playAndLogTrial') && ...
               contains(src, 'phasePlan') && contains(src, 'AUTO-GENERATED'), ...
            'generated script wires client/logging/phases');
        assert(contains(src, 's.frame + 1') && ~contains(src, 'floor(s.time'), ...
            'generated controllers index by s.frame, never s.time');
    end
    fprintf('[selftest] generateStimScript: %d stimuli emit parseable scripts (arity + markers)\n', ...
        numel(reg));

    proto = local_buildProtocol(reg, blocks);
    assert(numel(proto) == 2 && proto(1).seedArg == 1 && proto(2).seedArg == 0, 'buildProtocol seedArg per block');
    assert(isa(proto(1).stim, 'function_handle'), 'buildProtocol resolves the handle');
    assert(isequal(proto(1).seeds, [2 3 4 5 6]) && isempty(proto(2).seeds), ...
        'buildProtocol hands runExperiment the per-epoch seeds');

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


function local_cleanupGenTest(td)
% Cleanup for the generator self-test: generateStimScript addpath'd the temp dir -- take
% it off the path again before removing it.
    try
        rmpath(td);
    catch
    end
    try
        rmdir(td, 's');
    catch
    end
end
