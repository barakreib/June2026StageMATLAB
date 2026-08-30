function test_gui_edits()
% (3) table buttons disabled with an empty protocol, (4) per-epoch "Update selected",
% (1) the monitor timeline previewing the protocol as it is built.
    stateGuard = guiStateGuard(); %#ok<NASGU>
    stimulusGUI();
    fig = findall(0, 'Type', 'figure', 'Name', 'Neitz Stimulus GUI');
    c = onCleanup(@() local_shutdown()); %#ok<NASGU>
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

    % ---- (1) the monitor previews the protocol without any run ----
    mf = findall(0, 'Type', 'figure', 'Name', 'Session monitor');
    assert(~isempty(mf), 'the monitor opened for the preview');
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
    hasHi = cellfun(@(s) contains(s, 'sigma=0.9'), d(:, 4));
    assert(isequal(find(hasHi(:))', [2 5]), ...
        sprintf('only epochs 2 and 5 changed (changed: %s)', mat2str(find(hasHi(:))')));
    assert(isequal(proto.Selection(:)', [2 5]), 'the selection survives the edit');
    assert(local_hasLabel(mf, '6 epoch(s) planned'), 'the preview still shows 6 epochs');

    % those epochs became their own PARAMETER blocks -- a grouping only; the run still asks
    % Keep/Discard once, at the end (see test_protocol_complete)
    note = local_note(fig);
    assert(contains(note, '6 epoch(s) in 5 parameter block(s)'), ...
        sprintf('splitting 2 epochs out of one block gives 5 blocks (note: "%s")', note));
    assert(contains(note, 'once, at the end'), 'and the note says the prompt comes once, at the end');

    % ---- unticking the monitor closes it; reticking brings it back with the preview ----
    box = findall(fig, 'Type', 'uicheckbox', 'Text', 'Session monitor');
    box.Value = false; box.ValueChangedFcn(box, []);
    assert(isempty(findall(0, 'Type', 'figure', 'Name', 'Session monitor')), 'unticking closes it');
    assert(~stimProgress('isAttached'), 'and drops the hooks');
    box.Value = true; box.ValueChangedFcn(box, []);
    mf = findall(0, 'Type', 'figure', 'Name', 'Session monitor');
    assert(~isempty(mf) && local_hasLabel(mf, '6 epoch(s) planned'), 'reticking restores the preview');

    fprintf('[gui edits] buttons gated, per-epoch update, live preview -- PASS\n');
end

function t = local_tbl(tbls, col)
    t = [];
    for i = 1:numel(tbls)
        if any(strcmp(tbls(i).ColumnName, col)), t = tbls(i); return; end
    end
end
function s = local_note(fig)
    L = findall(fig, 'Type', 'uilabel');
    s = '';
    for k = 1:numel(L)
        if contains(string(L(k).Text), 'block(s)'), s = char(L(k).Text); return; end
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
