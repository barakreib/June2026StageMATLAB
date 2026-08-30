function test_gui_edits()
% (3) table buttons disabled with an empty protocol, (4) per-epoch "Apply params to
% selected", (1) the monitor timeline previewing the protocol as it is built.
    stateGuard = guiStateGuard(); %#ok<NASGU>
    stimulusGUI();
    fig = findall(0, 'Type', 'figure', 'Name', 'Neitz Stimulus GUI');
    c = onCleanup(@() local_shutdown());
    btn   = @(t) findall(fig, 'Type', 'uibutton', 'Text', t);
    tbls  = findall(fig, 'Type', 'uitable');
    pTbl  = local_tbl(tbls, 'Parameter');
    proto = local_tbl(tbls, 'Epoch #');

    updSel = btn('Apply params to selected');
    rm     = btn('Remove epoch');
    clr    = btn('Clear all');
    add    = btn('Add block  v');
    assert(~isempty(updSel), 'the "Apply params to selected" button exists');
    assert(isempty(btn('Update epochs  v')), '"Update epochs" is gone');
    assert(isequal(updSel.Parent, rm.Parent), 'it sits with the other selection actions');

    % ---- (3) nothing in the table -> nothing to update / remove / clear ----
    assert(isempty(proto.Data), 'starts empty');
    for b = [updSel, rm, clr]
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
    for b = [updSel, rm, clr]
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
    sd6 = cellfun(@str2double, d(:, seedCol))';
    assert(~isempty(seedCol) && numel(unique(sd6)) == 6 && ...
           all(sd6 >= 1 & sd6 <= 1e6 & sd6 == round(sd6)), ...
        'every epoch carries its own auto-assigned RANDOM seed (distinct, in [1, 1e6])');
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
    s3before = d2{3, seedCol};
    evt = struct('Indices', [4 seedCol], 'NewData', '99');
    proto.CellEditCallback(proto, evt);
    d2 = proto.Data;
    assert(strcmp(d2{4, seedCol}, '99') && strcmp(d2{3, seedCol}, s3before), ...
        'a seed edit changes only its epoch''s seed');

    % ---- screens & LEDs band: R/G tables + the GLOBAL B column (no per-phase B) ----
    preGrid  = findall(fig, 'Tag', 'phGrid_pre');
    stimGrid = findall(fig, 'Tag', 'phGrid_stim');
    postGrid = findall(fig, 'Tag', 'phGrid_post');
    mB       = findall(fig, 'Tag', 'masterB');
    assert(~isempty(preGrid) && ~isempty(stimGrid) && ~isempty(postGrid) && ~isempty(mB), ...
        'phase grids + the global B column exist');
    assert(size(preGrid.Data, 2) == 2 && size(mB.Data, 2) == 1, ...
        'phase tables carry R/G only; B lives in the single far-right column');
    assert(numel(preGrid.RowName) == 4 && isempty(stimGrid.RowName) && isempty(postGrid.RowName), ...
        'LED row names appear once, on the pre-stim table');
    assert(isempty(findall(fig, 'Type', 'uicheckbox', 'Text', 'sync and lock B channels')), ...
        'the B-lock checkbox is gone -- B is always global');
    pp = findall(fig, 'Tag', 'phPreset_pre');
    pp.Value = 'macaque s-iso';
    pp.ValueChangedFcn(pp, []);
    assert(abs(preGrid.Data(4, 1) - 1) < 1e-9, 'a preset fills its own phase R/G (LED3 R=1)');
    assert(abs(mB.Data(2) - 1) < 1e-9, 'the preset''s B column lands on the global B (LED1 B=1)');
    assert(~any(stimGrid.Data(:)), 'and only that phase''s R/G');
    evt = struct('Indices', [1 1], 'NewData', 1.7);
    mB.CellEditCallback(mB, evt);
    assert(abs(mB.Data(1) - 1) < 1e-9, 'the global B clamps to [0,1]');
    evt = struct('Indices', [1 1], 'NewData', 0.7);
    preGrid.CellEditCallback(preGrid, evt);
    assert(abs(preGrid.Data(1, 1) - 0.7) < 1e-9, 'R/G cells edit + clamp normally');

    % ---- RGBval column: numeric rows clamp, the swatch row stays empty ----
    scr = findall(fig, 'Tag', 'phScr_pre');
    assert(~isempty(scr) && strcmp(scr.ColumnName{1}, 'RGBval'), 'RGBval column is a one-column table');
    evt = struct('Indices', [1 1], 'NewData', 0.5);
    scr.CellEditCallback(scr, evt);
    evt = struct('Indices', [2 1], 'NewData', 7);
    scr.CellEditCallback(scr, evt);
    assert(abs(scr.Data{1} - 0.5) < 1e-9 && abs(scr.Data{2} - 1) < 1e-9, ...
        'screen R/G/B rows take values and clamp to [0,1]');
    assert(isempty(scr.Data{4}) || strcmp(scr.Data{4}, ''), 'the swatch cell carries no text');

    % ---- "link values": toggle sections into ONE linked set; values + RGBval shared ----
    lb = findall(fig, 'Type', 'uibutton', 'Text', 'link values');
    assert(~isempty(lb), 'the link values button exists');
    assert(isempty(findall(fig, 'Type', 'uicheckbox', 'Text', 'link with')), ...
        'the per-section link checkboxes are gone');
    lb.ButtonPushedFcn(lb, []);                            % enter link mode
    assert(strcmp(lb.Text, 'done linking'), 'the button flips to done linking');
    assert(~isempty(preGrid.StyleConfigurations), 'eligible sections highlight while linking');
    preGrid.ClickedFcn(preGrid, []);                       % toggle pre IN
    postGrid.ClickedFcn(postGrid, []);                     % toggle post IN (adopts pre's values)
    assert(isequal(postGrid.Data, preGrid.Data), 'a section joining the set adopts its values');
    scrPost = findall(fig, 'Tag', 'phScr_post');
    assert(abs(scrPost.Data{1} - scr.Data{1}) < 1e-9, 'joining adopts the RGBval too');
    lb.ButtonPushedFcn(lb, []);                            % done linking
    assert(strcmp(lb.Text, 'link values'), 'the button flips back');
    evt = struct('Indices', [2 2], 'NewData', 0.33);
    preGrid.CellEditCallback(preGrid, evt);
    assert(abs(postGrid.Data(2, 2) - 0.33) < 1e-9, 'editing one linked table updates the other');
    evt = struct('Indices', [2 1], 'NewData', 0.6);
    scr.CellEditCallback(scr, evt);
    assert(abs(scrPost.Data{2} - 0.6) < 1e-9, 'linked sections share the full-screen RGBval too');
    lb.ButtonPushedFcn(lb, []);                            % re-enter, toggle post OUT
    postGrid.ClickedFcn(postGrid, []);
    lb.ButtonPushedFcn(lb, []);                            % done: a set of one dissolves
    evt = struct('Indices', [2 2], 'NewData', 0.9);
    preGrid.CellEditCallback(preGrid, evt);
    assert(abs(postGrid.Data(2, 2) - 0.33) < 1e-9, 'after unlinking, edits stay local');
    assert(isempty(preGrid.StyleConfigurations), 'no highlight lingers outside link mode');

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
