function stimulusGUI(mode)
% stimulusGUI  Point-and-click builder for a stimulus session.
%
%   stimulusGUI            opens the GUI.
%   stimulusGUI('__selftest__')  runs the headless logic self-test (no window).
%
% Pick a stimulus (left), edit its parameters, set epochs + a label, and "Add block"
% to append it to the protocol. Repeat to chain blocks, then "Run experiment" — which
% builds a protocol struct and hands it to runExperiment.m (same path as Experimenter5000).
% Save/Load store the protocol as human-readable JSON under June2026StageMATLAB/experiments/.
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
    expDir    = fullfile(fileparts(mfilename('fullpath')), 'experiments');
    if ~exist(expDir, 'dir'), mkdir(expDir); end
    stateFile = fullfile(prefdir, 'neitzStimulusGUI_lastSession.json');
    h = struct();

    buildUI();
    onSelectStim();
    loadState();   % restore the last-used settings + protocol, if any

    % ================= nested callbacks (share reg / blocks / curEntry / h) =================
    function buildUI()
        h.fig = uifigure('Name', 'Neitz Stimulus GUI', 'Position', [80 80 1020 900], ...
            'CloseRequestFcn', @(s,e) onClose());
        outer = uigridlayout(h.fig, [1 2]);
        outer.ColumnWidth = {250, '1x'};

        lp = uipanel(outer, 'Title', 'Stimuli');
        lg = uigridlayout(lp, [2 1]); lg.RowHeight = {'1x', 74};
        h.list = uilistbox(lg, 'Items', {reg.name}, 'ValueChangedFcn', @(s,e) onSelectStim());
        uilabel(lg, 'Text', sprintf(['%d stimuli. Pick one, set its parameters,\n' ...
            'Add block, repeat to chain blocks, then Run.'], numel(reg)), ...
            'WordWrap', 'on', 'FontAngle', 'italic');

        rp = uigridlayout(outer, [11 1]);
        rp.RowHeight = {24, '1x', 40, 20, '1x', 36, 152, 34, 36, 30, 40};

        h.paramTitle = uilabel(rp, 'Text', 'Parameters', 'FontWeight', 'bold');
        h.paramTable = uitable(rp, 'ColumnName', {'Parameter', 'Value'}, ...
            'ColumnEditable', [false true], 'ColumnWidth', {180, 220}, 'RowName', {});

        er = uigridlayout(rp, [1 5]); er.ColumnWidth = {60, 70, 55, '1x', 130};
        er.Padding = [6 3 6 3];
        uilabel(er, 'Text', 'Epochs:');
        h.epochs = uieditfield(er, 'numeric', 'Value', 5, 'Limits', [1 Inf], 'RoundFractionalValues', 'on');
        uilabel(er, 'Text', 'Label:');
        h.label = uieditfield(er, 'text', 'Value', '');
        uibutton(er, 'Text', 'Add block  v', 'ButtonPushedFcn', @(s,e) onAddBlock());

        h.seedNote = uilabel(rp, 'Text', '', 'FontAngle', 'italic');

        h.protoTable = uitable(rp, 'ColumnName', {'#', 'Stimulus', 'Epochs', 'Label', 'Params'}, ...
            'ColumnWidth', {30, 240, 60, 120, '1x'}, 'RowName', {}, 'SelectionType', 'row');

        % ----- LEDs (NeitzLedRig): optional per-session RGB channel intensities -----
        lh = uigridlayout(rp, [1 6]);
        lh.ColumnWidth = {'fit', 'fit', 150, 'fit', 170, '1x'};
        lh.Padding = [6 4 6 4]; lh.ColumnSpacing = 8;
        uilabel(lh, 'Text', 'LEDs:', 'FontWeight', 'bold');
        uilabel(lh, 'Text', 'Mode');
        h.ledMode = uidropdown(lh, 'Items', {'off (0)', 'DC red (1)', 'video RGB (2)', 'video RGB + sync (3)'}, ...
            'ItemsData', [0 1 2 3], 'Value', 2);
        uilabel(lh, 'Text', 'Port');
        h.ledPort = uieditfield(lh, 'text', 'Value', 'AUTO', ...
            'Tooltip', 'AUTO auto-detects the FPGA; or a COM name (Windows 11) / /dev/cu.* node (macOS).');

        h.ledTable = uitable(rp, 'Data', zeros(4, 3), ...
            'ColumnName', {'R', 'G', 'B'}, 'RowName', {'LED 0', 'LED 1', 'LED 2', 'LED 3'}, ...
            'ColumnEditable', [true true true], 'ColumnWidth', {70, 70, 70}, ...
            'Tooltip', 'Per-LED intensity, 0..1 linear duty (pre-distort like lcGammaCorrect for eye-linear).');

        % ----- Stage/OpenGL server host (blank = this machine; an IPv4 = remote) -----
        sr = uigridlayout(rp, [1 3]); sr.ColumnWidth = {'fit', 200, '1x'}; sr.Padding = [6 3 6 3];
        uilabel(sr, 'Text', 'Stage host (IPv4):');
        h.stageHost = uieditfield(sr, 'text', 'Value', char(loadRigConfig('stage_host', 'localhost')), ...
            'Tooltip', ['The Stage/OpenGL server computer. Blank / "localhost" = this machine; an ' ...
                        'IPv4 (e.g. 192.168.0.49) connects to that computer. Saved to rig_config on Run.']);
        uilabel(sr, 'Text', 'blank / localhost = this machine', 'FontAngle', 'italic', 'FontColor', [0.45 0.45 0.45]);

        og = uigridlayout(rp, [1 9]); og.ColumnWidth = {'fit', 58, 'fit', 58, 'fit', 58, 'fit', 58, '1x'};
        og.Padding = [6 3 6 3];
        uilabel(og, 'Text', 'preStim (s)');  h.preStim  = uieditfield(og, 'numeric', 'Value', 2, 'Limits', [0 Inf]);
        uilabel(og, 'Text', 'postStim (s)'); h.postStim = uieditfield(og, 'numeric', 'Value', 1, 'Limits', [0 Inf]);
        uilabel(og, 'Text', 'itp (s)');      h.itp      = uieditfield(og, 'numeric', 'Value', 3, 'Limits', [0 Inf]);
        uilabel(og, 'Text', 'seedBase');     h.seedBase = uieditfield(og, 'numeric', 'Value', 2, 'Limits', [0 Inf], 'RoundFractionalValues', 'on');
        h.triggerAcq = uicheckbox(og, 'Text', 'Trigger Clampex acq', 'Value', true, ...
            'Tooltip', ['Uncheck for a local dry run: present OpenGL only, no Clampex trigger ' ...
                        '(e.g. Stage server on this machine, no rig). Leave checked at the rig.']);

        dr = uigridlayout(rp, [1 2]); dr.ColumnWidth = {200, '1x'}; dr.Padding = [6 2 6 2]; dr.ColumnSpacing = 24;
        h.ledEnable = uicheckbox(dr, 'Text', 'Enable LED driver', 'Value', false, ...
            'Tooltip', 'On: runExperiment opens NeitzLedRig and applies the LED grid above during the run. Off: LEDs left untouched.');
        h.debug = uicheckbox(dr, 'Value', false, 'ValueChangedFcn', @(s,e) onDebugToggle(), ...
            'Text', 'Debug: no Clampex acquisition  (LED driver still available)', ...
            'FontWeight', 'bold', 'Tooltip', ...
            'Run still presents via the Stage host but sends no Clampex keystrokes. The LED driver is INDEPENDENT -- tick "Enable LED driver" to run it while debugging.');

        bg = uigridlayout(rp, [1 5]); bg.ColumnWidth = {'1x', '1x', '1x', '1x', '1.4x'};
        bg.Padding = [6 4 6 4];
        uibutton(bg, 'Text', 'Remove block', 'ButtonPushedFcn', @(s,e) onRemoveBlock());
        uibutton(bg, 'Text', 'New',          'ButtonPushedFcn', @(s,e) onNew());
        uibutton(bg, 'Text', 'Save...',      'ButtonPushedFcn', @(s,e) onSave());
        uibutton(bg, 'Text', 'Load...',      'ButtonPushedFcn', @(s,e) onLoad());
        uibutton(bg, 'Text', 'Run experiment', 'ButtonPushedFcn', @(s,e) onRun(), ...
            'BackgroundColor', [0.20 0.55 0.30], 'FontColor', 'w', 'FontWeight', 'bold');
    end

    function onSelectStim()
        curEntry = reg(h.list.ValueIndex);
        idx  = local_editableParams(curEntry);
        data = cell(numel(idx), 2);
        for k = 1:numel(idx)
            r = idx(k);
            data{k, 1} = curEntry.params{r, 1};
            data{k, 2} = local_valueStr(curEntry.params{r, 3}, curEntry.params{r, 2});
        end
        h.paramTable.Data  = data;
        h.paramTitle.Text  = ['Parameters for:  ' curEntry.name '   (' curEntry.fn ')'];
        if local_seedArgFor(curEntry) > 0
            h.seedNote.Text = 'Seed: auto-increments +1 per epoch from seedBase, and is recorded per epoch in the manifest.';
        else
            h.seedNote.Text = 'Seed: not applicable to this stimulus.';
        end
    end

    function onAddBlock()
        try
            data = h.paramTable.Data;
            ps   = struct();
            for k = 1:size(data, 1)
                name = data{k, 1};
                r    = find(strcmp(curEntry.params(:, 1), name), 1);
                ps.(name) = local_parseValue(curEntry.params{r, 3}, data{k, 2}, curEntry, name);
            end
            b = struct('stimName', curEntry.name, 'fnName', curEntry.fn, 'params', ps, ...
                       'epochs', round(h.epochs.Value), 'label', char(h.label.Value));
            blocks(end + 1) = b;
            refreshProtocol();
        catch err
            uialert(h.fig, err.message, 'Invalid parameter');
        end
    end

    function onRemoveBlock()
        sel = h.protoTable.Selection;
        if isempty(sel), return; end
        row = sel(1);
        if row >= 1 && row <= numel(blocks)
            blocks(row) = [];
            refreshProtocol();
        end
    end

    function onNew()
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
        try
            runExperiment(protocol, opts);
            uialert(h.fig, sprintf('Experiment finished (%d block(s)).', numel(blocks)), 'Done', 'Icon', 'success');
        catch err
            uialert(h.fig, err.message, 'runExperiment error');
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
        catch err
            uialert(h.fig, err.message, 'Load failed');
        end
    end

    function refreshProtocol()
        n    = numel(blocks);
        data = cell(n, 5);
        for b = 1:n
            e = local_findEntry(reg, blocks(b).fnName);
            data(b, :) = {b, blocks(b).stimName, blocks(b).epochs, blocks(b).label, ...
                          local_paramSummary(e, blocks(b).params)};
        end
        h.protoTable.Data = data;
    end

    function o = gatherOpts()
        o = struct('preStim', h.preStim.Value, 'postStim', h.postStim.Value, ...
                   'itp', h.itp.Value, 'seedBase', round(h.seedBase.Value), ...
                   'triggerAcq', logical(h.triggerAcq.Value));
        o.leds = gatherLeds();
        if h.debug.Value                 % Debug: skip Clampex acquisition only
            o.triggerAcq = false;        % (LED driver stays as set by the 'Enable LED driver' box)
        end
    end

    function onDebugToggle()
        state = 'on';
        if h.debug.Value, state = 'off'; end   % Debug greys out ONLY the Clampex trigger
        h.triggerAcq.Enable = state;           % (the LED driver stays under user control)
    end

    % ----- remember the last-used session across GUI opens (in prefdir, not the repo) -----
    function onClose()
        saveState();
        delete(h.fig);
    end

    function saveState()
        try
            o = struct('preStim', h.preStim.Value, 'postStim', h.postStim.Value, ...
                       'itp', h.itp.Value, 'seedBase', round(h.seedBase.Value), ...
                       'triggerAcq', logical(h.triggerAcq.Value), ...
                       'debug', logical(h.debug.Value), 'stimIndex', h.list.ValueIndex);
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
        h.debug.Value      = logical(getfielddef(o, 'debug', false));
        applyLedsToUI(getfielddef(o, 'leds', struct()));
        onDebugToggle();
        si = round(getfielddef(o, 'stimIndex', 1));
        if si >= 1 && si <= numel(reg), h.list.ValueIndex = si; onSelectStim(); end
        blocks = blk;
        refreshProtocol();
    end

    function leds = gatherLeds()
        I = h.ledTable.Data;
        if iscell(I), I = cell2mat(I); end
        leds = struct('enabled', logical(h.ledEnable.Value), ...
                      'port', char(h.ledPort.Value), ...
                      'mode', double(h.ledMode.Value), ...
                      'intensity', double(I));
    end

    function applyLedsToUI(L)
        if ~isstruct(L), return; end
        h.ledEnable.Value = logical(getfielddef(L, 'enabled', false));
        h.ledPort.Value   = char(getfielddef(L, 'port', 'AUTO'));
        m = double(getfielddef(L, 'mode', 2));
        if ismember(m, [0 1 2 3]), h.ledMode.Value = m; end
        I = double(getfielddef(L, 'intensity', zeros(4, 3)));
        if isequal(size(I), [4, 3]), h.ledTable.Data = I; else, h.ledTable.Data = zeros(4, 3); end
    end
end


% ===================== pure logic (shared by the GUI and the self-test) =====================
function b = local_emptyBlocks()
    b = struct('stimName', {}, 'fnName', {}, 'params', {}, 'epochs', {}, 'label', {});
end

function idx = local_editableParams(entry)
    idx = find(~strcmp(entry.params(:, 3), 'seed'))';
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

    blocks    = local_emptyBlocks();
    blocks(1) = struct('stimName', g.name, 'fnName', g.fn, 'params', ps, 'epochs', 5, 'label', 'grey gauss');
    blocks(2) = struct('stimName', j.name, 'fnName', j.fn, 'params', pj, 'epochs', 3, 'label', 'jit');
    opts = struct('preStim', 2, 'postStim', 1, 'itp', 3, 'seedBase', 7, ...
                  'triggerAcq', false, 'debug', true, 'stimIndex', 3);
    opts.leds = struct('enabled', true, 'port', 'AUTO', 'mode', 2, ...
                       'intensity', [0.75 0 0; 0 0.5 0; 0 0 0; 0 0 0.125]);
    [b2, o2] = local_jsonToExperiment(reg, local_experimentToJson(blocks, opts));
    assert(numel(b2) == 2 && strcmp(b2(1).fnName, g.fn) && b2(1).epochs == 5, 'json round-trip blocks');
    assert(isequal(local_argsFor(local_findEntry(reg, b2(1).fnName), b2(1).params), {[], 0.5, 0.3, 4, 600, 60}), ...
        'json round-trip rebuilds gaussian args');
    assert(o2.seedBase == 7, 'json round-trip opts');
    assert(o2.leds.enabled && o2.leds.mode == 2, 'json round-trip LED scalars');
    assert(isequal(size(o2.leds.intensity), [4, 3]) && abs(o2.leds.intensity(1, 1) - 0.75) < 1e-9, ...
        'json round-trip LED 4x3 grid');
    assert(o2.debug == true && o2.stimIndex == 3 && o2.triggerAcq == false, ...
        'session-state round-trip (debug / stimIndex / triggerAcq)');
    fprintf('[selftest] LED config + session-state (debug/stimIndex/triggerAcq) round-trip\n');

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

    fprintf('[selftest] args / parse / json round-trip / buildProtocol all PASS\n');
end
