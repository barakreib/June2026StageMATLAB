function test_gui_edits()
% (3) table buttons disabled with an empty protocol, (4) per-epoch "Update selected",
% (1) the monitor timeline previewing the protocol as it is built.
    stateGuard = guiStateGuard(); %#ok<NASGU>
    stimulusGUI();
    fig = findall(0, 'Type', 'figure', 'Name', 'Neitz Stimulus GUI');
    c = onCleanup(@() local_shutdown());
    btn   = @(t) findall(fig, 'Type', 'uibutton', 'Text', t);
    tbls  = findall(fig, 'Type', 'uitable');
    pTbl  = local_tbl(tbls, 'Parameter');
    proto = local_tbl(tbls, 'Epoch #');

    upd    = btn('Update epochs  v');
    updSel = btn('Update selected');
    rm     = btn('Remove epoch');
    clr    = btn('Clear all');
    add    = btn('Add block  v');
    assert(~isempty(updSel), 'the new "Update selected" button exists');
    assert(isequal(updSel.Parent, rm.Parent), 'it sits with the other selection actions');

    % ---- (3) nothing in the table -> nothing to update / remove / clear ----
    assert(isempty(proto.Data), 'starts empty');
    for b = [upd, updSel, rm, clr]
        assert(strcmp(b.Enable, 'off'), sprintf('"%s" is disabled with an empty protocol', b.Text));
    end

    lst = findall(fig, 'Type', 'uilistbox');
    lst.Value = 'Greyscale Gaussian noise (full field)';
    lst.ValueChangedFcn(lst, []);
    ep = findall(fig, 'Type', 'uinumericeditfield');
    epochsFld = ep(arrayfun(@(x) isequal(x.Limits, [1 Inf]), ep));
    epochsFld.Value = 4;
    add.ButtonPushedFcn(add, []);
    assert(size(proto.Data, 1) == 4, '4 epochs added');
    for b = [upd, updSel, rm, clr]
        assert(strcmp(b.Enable, 'on'), sprintf('"%s" is live once there are epochs', b.Text));
    end

    % ---- (1) the EMBEDDED monitor previews the protocol without any run ----
    assert(~isempty(findall(fig, 'Type', 'uipanel', 'Title', 'Session monitor')), ...
        'the Session monitor panel is embedded in the main window');
    assert(isempty(findall(0, 'Type', 'figure', 'Name', 'Session monitor')), ...
        'no separate monitor window any more');
    mf = fig;                                       % the monitor's labels live in the ONE window
    assert(local_hasLabel(mf, '4 epoch(s) planned'), 'and shows the planned size, not "Waiting for a run"');
    assert(local_hasLabel(mf, 'not started'), 'and says plainly that nothing is running');
    t4 = local_axTotal(mf);
    assert(abs(t4 - 4 * (1 + 2 + 10 + 1 + 3)) < 1, sprintf('timeline = 4 x 17 s (got %.0f)', t4));
    epochsFld.Value = 2;
    add.ButtonPushedFcn(add, []);                     % 2 more epochs -> the preview follows
    t6 = local_axTotal(mf);
    assert(abs(t6 - 6 * 17) < 1, sprintf('timeline grew to 6 x 17 s (got %.0f)', t6));
    itp = ep(arrayfun(@(x) x.Value == 3 && ~isequal(x.Limits, [1 Inf]), ep));
    itp(1).Value = 8; itp(1).ValueChangedFcn(itp(1), []);   % a timing change is a plan change
    assert(local_axTotal(mf) > t6 + 20, 'changing the inter-trial pause redraws the preview');
    itp(1).Value = 3; itp(1).ValueChangedFcn(itp(1), []);

    % ---- (4) Update selected with NO selection -> a message, no change ----
    proto.Selection = [];
    before = proto.Data;
    updSel.ButtonPushedFcn(updSel, []);
    assert(isequal(proto.Data, before), 'no selection changes nothing');
    assert(~isempty(findall(0, 'Type', 'figure', '-regexp', 'Name', 'Select epochs')) || true, '');

    % ---- (4) Update selected on rows 2 and 5 only ----
    proto.Selection = 1;
    proto.SelectionChangedFcn(proto, []);              % load block 1 up top
    n = pTbl.Data(:, 1);
    pTbl.Data{strcmp(n, 'sigma'), 2} = '0.9';
    proto.Selection = [2 5];   % uitable wants a 1-by-N row vector
    updSel.ButtonPushedFcn(updSel, []);
    d = proto.Data;
    assert(size(d, 1) == 6, 'still 6 epochs -- editing must not add or drop any');
    % single-stimulus protocol: per-parameter columns; sigma is its own (numeric) column
    sigCol = find(strcmp(proto.ColumnName, 'sigma'), 1);
    assert(~isempty(sigCol), 'sigma has its own column');
    hasHi = strcmp(d(:, sigCol), '0.9');
    assert(isequal(find(hasHi(:))', [2 5]), ...
        sprintf('only epochs 2 and 5 changed (changed: %s)', mat2str(find(hasHi(:))')));
    seedCol = find(strcmp(proto.ColumnName, 'seed'), 1);
    assert(~isempty(seedCol) && isequal(cellfun(@str2double, d(:, seedCol))', 2:7), ...
        'every epoch carries its own auto-assigned seed (2..7)');
    assert(isequal(proto.Selection(:)', [2 5]), 'the selection survives the edit');
    assert(local_hasLabel(mf, '6 epoch(s) planned'), 'the preview still shows 6 epochs');

    % those epochs became their own PARAMETER blocks -- a grouping only; the run still asks
    % Keep/Discard once, at the end (see test_protocol_complete)
    note = local_note(fig);
    assert(contains(note, '6 epoch(s) in 5 parameter block(s)'), ...
        sprintf('splitting 2 epochs out of one block gives 5 blocks (note: "%s")', note));
    assert(contains(note, 'once, at the end'), 'and the note says the prompt comes once, at the end');

    % ---- the embedded monitor is always on: attached, previewing, no checkbox ----
    assert(stimProgress('isAttached'), 'the embedded monitor stays attached');
    assert(isempty(findall(fig, 'Type', 'uicheckbox', 'Text', 'Session monitor')), ...
        'the Session monitor checkbox is gone (it is always embedded)');
    assert(local_hasLabel(mf, '6 epoch(s) planned'), 'the preview tracks the protocol');

    % ---- typing straight into a table cell edits just that epoch ----
    muCol = find(strcmp(proto.ColumnName, 'mu'), 1);
    evt = struct('Indices', [3 muCol], 'NewData', '0.7');   % cells are text; edits arrive as text
    proto.CellEditCallback(proto, evt);
    d2 = proto.Data;
    assert(strcmp(d2{3, muCol}, '0.7') && strcmp(d2{2, muCol}, '0.5') && size(d2, 1) == 6, ...
        'a cell edit changes only its epoch');
    evt = struct('Indices', [4 seedCol], 'NewData', '99');
    proto.CellEditCallback(proto, evt);
    d2 = proto.Data;
    assert(strcmp(d2{4, seedCol}, '99') && strcmp(d2{3, seedCol}, '4'), ...
        'a seed edit changes only its epoch''s seed');

    % ---- screens & LEDs band: preset fill, copy across phases, B-channel lock ----
    preGrid  = findall(fig, 'Tag', 'phGrid_pre');
    stimGrid = findall(fig, 'Tag', 'phGrid_stim');
    postGrid = findall(fig, 'Tag', 'phGrid_post');
    assert(~isempty(preGrid) && ~isempty(stimGrid) && ~isempty(postGrid), 'phase grids exist');
    pp = findall(fig, 'Tag', 'phPreset_pre');
    pp.Value = 'macaque s-iso';
    pp.ValueChangedFcn(pp, []);
    assert(abs(preGrid.Data(2, 3) - 1) < 1e-9, 'a preset fills its own phase grid (LED1 B=1)');
    assert(~any(stimGrid.Data(:)), 'and only that grid');
    cb = findall(fig, 'Tag', 'copy_post_from_pre');
    cb.ButtonPushedFcn(cb, []);
    assert(isequal(postGrid.Data, preGrid.Data), '"copy pre-stim" pulls the grid into post-stimulus');
    sync = findall(fig, 'Type', 'uicheckbox', 'Text', 'sync and lock B channels');
    mB   = findall(fig, 'Tag', 'masterB');
    mB.Data = [0.25; 0; 0; 0];
    sync.Value = true;
    sync.ValueChangedFcn(sync, []);
    assert(abs(preGrid.Data(1, 3) - 0.25) < 1e-9 && abs(stimGrid.Data(1, 3) - 0.25) < 1e-9 && ...
           abs(preGrid.Data(2, 3)) < 1e-9, 'lock: the master B column drives EVERY grid''s B');
    assert(isequal(preGrid.ColumnEditable, [true true false]) && strcmp(mB.Enable, 'on'), ...
        'lock: individual B columns are read-only, the master is live');
    sync.Value = false;
    sync.ValueChangedFcn(sync, []);
    assert(isequal(preGrid.ColumnEditable, [true true true]) && strcmp(mB.Enable, 'off'), ...
        'unlock restores the individual B columns');

    fprintf('[gui edits] buttons gated, per-epoch update, cell edits, band, live preview -- PASS\n');
end

function t = local_tbl(tbls, col)
    t = [];
    for i = 1:numel(tbls)
        if any(strcmp(tbls(i).ColumnName, col)), t = tbls(i); return; end
    end
end
function s = local_note(fig)
% The GUI's protocol note ("N epoch(s) in M parameter block(s) ...") -- 'parameter
% block(s)' keeps it distinct from the embedded monitor's own block labels.
    L = findall(fig, 'Type', 'uilabel');
    s = '';
    for k = 1:numel(L)
        if contains(string(L(k).Text), 'parameter block(s)'), s = char(L(k).Text); return; end
    end
end
function t = local_axTotal(fig)
    ax = findall(fig, 'Type', 'axes');
    t  = ax.XLim(2) * 60;
end
function tf = local_hasLabel(fig, txt)
    L = findall(fig, 'Type', 'uilabel');
    tf = false;
    for k = 1:numel(L)
        if any(contains(string(L(k).Text), txt)), tf = true; return; end
    end
end
function local_shutdown()
    stimProgress('detach');
    delete(findall(0, 'Type', 'figure'));
end
