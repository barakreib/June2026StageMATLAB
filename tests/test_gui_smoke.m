function test_gui_smoke()
% Build the real window and drive the real callbacks (no rig, no Stage server).
    % guiStateGuard moves the user's saved session ASIDE (clean slate) and restores it on
    % any exit -- never delete the real prefdir state (that mistake has been made once).
    stateGuard = guiStateGuard(); %#ok<NASGU>

    stimulusGUI();
    fig = findall(0, 'Type', 'figure', 'Name', 'Neitz Stimulus GUI');
    assert(numel(fig) == 1, 'the GUI window opened');
    c = onCleanup(@() delete(fig)); %#ok<NASGU>

    btn   = @(txt) local_btn(fig, txt);
    tbls  = findall(fig, 'Type', 'uitable');
    pTbl  = local_tableWithCol(tbls, 'Parameter');
    proto = local_tableWithCol(tbls, 'Epoch #');
    assert(~isempty(pTbl) && ~isempty(proto), 'parameter + protocol tables exist');
    assert(strcmp(proto.ColumnName{1}, 'Epoch #'), 'protocol columns: Epoch # first');
    assert(isempty(proto.Data), 'a fresh session starts with an empty protocol');

    % ---- button inventory / placement ----
    clr = btn('Clear all');
    rm  = btn('Remove epoch');
    aps = btn('Apply params to selected');
    add = btn('Add block  v');
    assert(~isempty(clr) && ~isempty(rm) && ~isempty(aps), ...
        'Clear all / Remove epoch / Apply params to selected exist');
    assert(isempty(local_btn(fig, 'New')), '"New" is gone -- Clear all took its place');
    assert(isempty(local_btn(fig, 'Update epochs  v')), ...
        '"Update epochs" is gone -- rows are edited directly or via Apply params to selected');
    assert(isequal(rm.Parent, clr.Parent) && isequal(aps.Parent, rm.Parent), ...
        'the row operations share one toolbar, under the rows they act on');
    assert(~isequal(rm.Parent, btn('Run experiment').Parent), 'that toolbar is not the bottom button row');
    clr.ButtonPushedFcn(clr, []);                 % empty protocol: clears without a confirm
    assert(isempty(proto.Data), 'Clear all on an empty protocol is a no-op');

    lst = findall(fig, 'Type', 'uilistbox');
    lst.Value = 'Greyscale Gaussian noise (full field)';
    lst.ValueChangedFcn(lst, []);

    names = pTbl.Data(:, 1);
    d = find(strcmp(names, 'duration (s)'), 1);
    f = find(strcmp(names, 'stimFrames'),   1);
    r = find(strcmp(names, 'refreshRate'),  1);
    m = find(strcmp(names, 'mu'),           1);
    assert(~isempty(d) && d == f + 1, 'duration (s) row sits under stimFrames');
    assert(strcmp(pTbl.Data{d, 2}, '10'), 'duration starts at 600/60 = 10 s');

    % ---- duration <-> stimFrames <-> refreshRate ----
    pTbl.Data{d, 2} = '5';
    pTbl.CellEditCallback(pTbl, struct('Indices', [d 2]));
    assert(strcmp(pTbl.Data{f, 2}, '300'), sprintf('5 s -> 300 frames (got %s)', pTbl.Data{f, 2}));
    pTbl.Data{f, 2} = '450';
    pTbl.CellEditCallback(pTbl, struct('Indices', [f 2]));
    assert(strcmp(pTbl.Data{d, 2}, '7.5'), sprintf('450 frames -> 7.5 s (got %s)', pTbl.Data{d, 2}));
    pTbl.Data{r, 2} = '90';
    pTbl.CellEditCallback(pTbl, struct('Indices', [r 2]));
    assert(strcmp(pTbl.Data{d, 2}, '5'), sprintf('450 frames at 90 Hz -> 5 s (got %s)', pTbl.Data{d, 2}));
    pTbl.Data{m, 2} = '0.4';
    pTbl.CellEditCallback(pTbl, struct('Indices', [m 2]));
    assert(strcmp(pTbl.Data{d, 2}, '5') && strcmp(pTbl.Data{f, 2}, '450'), 'editing mu leaves duration alone');

    % ---- 5 epochs + Add block -> five rows of the SAME stimulus ----
    ep = findall(fig, 'Type', 'uinumericeditfield');
    epochsFld = ep(arrayfun(@(x) isequal(x.Limits, [1 Inf]) && x.Value == 5, ep));
    assert(numel(epochsFld) == 1, 'found the Epochs field');
    add.ButtonPushedFcn(add, []);
    assert(size(proto.Data, 1) == 5, sprintf('5 epochs -> 5 rows (got %d)', size(proto.Data, 1)));
    assert(isequal(cellfun(@str2double, proto.Data(:, 1))', 1:5), 'rows are numbered 1..5');
    % single-stimulus protocol: one editable column per parameter + Label + per-epoch seed
    assert(isequal(proto.ColumnName(:)', ...
        {'Epoch #', 'Label', 'seed', 'mu', 'sigma', 'flickerHz', 'stimFrames', 'refreshRate'}), ...
        'gaussian protocol: Label + seed + every parameter as its own column');
    muCol = find(strcmp(proto.ColumnName, 'mu'), 1);
    sfCol = find(strcmp(proto.ColumnName, 'stimFrames'), 1);
    sdCol = find(strcmp(proto.ColumnName, 'seed'), 1);
    assert(strcmp(proto.Data{1, sfCol}, '450') && strcmp(proto.Data{1, muCol}, '0.4'), ...
        'the synced frame count and edited mu reach the protocol');
    seeds5 = cellfun(@str2double, proto.Data(:, sdCol))';
    assert(numel(unique(seeds5)) == 5 && all(seeds5 >= 1 & seeds5 <= 1e6 & seeds5 == round(seeds5)), ...
        'five fresh per-epoch seeds: distinct random integers in [1, 1e6]');

    % ---- a second block of the SAME stimulus keeps numbering global + seeds fresh ----
    epochsFld.Value = 2;
    add.ButtonPushedFcn(add, []);
    assert(size(proto.Data, 1) == 7 && str2double(proto.Data{7, 1}) == 7, '2 more epochs -> rows 6 and 7');
    seeds7 = cellfun(@str2double, proto.Data(:, sdCol))';
    assert(isequal(seeds7(1:5), seeds5) && numel(unique(seeds7)) == 7, ...
        'the new block''s seeds are fresh and the existing ones are untouched');

    % ---- Remove epoch takes one row off its own block ----
    proto.Selection = 7;
    rm.ButtonPushedFcn(rm, []);
    assert(size(proto.Data, 1) == 6, 'Remove epoch drops exactly one epoch');

    % ---- clicking an epoch loads its block back into the top window ----
    proto.Selection = 1;
    proto.SelectionChangedFcn(proto, []);
    n2 = pTbl.Data(:, 1);
    assert(strcmp(pTbl.Data{find(strcmp(n2, 'stimFrames'), 1), 2}, '450') && ...
           strcmp(pTbl.Data{find(strcmp(n2, 'mu'), 1), 2}, '0.4'), ...
        'the selected epoch''s parameters came back up top');
    assert(epochsFld.Value == 5, 'the epoch count of that block came back too');
    assert(strcmp(lst.Value, 'Greyscale Gaussian noise (full field)'), 'and its stimulus is selected');

    % ---- edit up top, then Apply params to selected rewrites JUST those rows ----
    seedsBefore = cellfun(@str2double, proto.Data(:, sdCol))';
    pTbl.Data{find(strcmp(n2, 'mu'), 1), 2} = '0.25';
    d2 = find(strcmp(n2, 'duration (s)'), 1);
    pTbl.Data{d2, 2} = '2';
    pTbl.CellEditCallback(pTbl, struct('Indices', [d2 2]));   % 2 s at 90 Hz -> 180 frames
    proto.Selection = [1 2];
    aps.ButtonPushedFcn(aps, []);
    assert(size(proto.Data, 1) == 6, 'apply-to-selected never changes the row count');
    assert(strcmp(proto.Data{1, muCol}, '0.25') && strcmp(proto.Data{2, sfCol}, '180'), ...
        'the edited parameters landed on the selected epochs');
    assert(strcmp(proto.Data{3, muCol}, '0.4') && strcmp(proto.Data{6, sfCol}, '450'), ...
        'unselected epochs were left alone');
    assert(isequal(cellfun(@str2double, proto.Data(:, sdCol))', seedsBefore), ...
        'every epoch kept its own seed through the bulk edit');
    assert(isequal(proto.Selection(:)', [1 2]), 'the selection survives the update');

    % ---- last-used parameters are remembered PER STIMULUS TYPE ----
    lst.Value = 'Greyscale full-field flicker';
    lst.ValueChangedFcn(lst, []);
    lst.Value = 'Greyscale Gaussian noise (full field)';
    lst.ValueChangedFcn(lst, []);
    n3 = pTbl.Data(:, 1);
    assert(strcmp(pTbl.Data{find(strcmp(n3, 'mu'), 1), 2}, '0.25') && ...
           strcmp(pTbl.Data{find(strcmp(n3, 'stimFrames'), 1), 2}, '180'), ...
        'switching away and back restores the last-used parameters for that stimulus');

    % ---- Cancel / Run idle state ----
    cb = btn('Cancel');
    assert(~isempty(cb) && strcmp(cb.Enable, 'off'), 'Cancel is present and disabled while idle');
    assert(strcmp(btn('Run experiment').Enable, 'on'), 'Run is enabled while idle');
    fprintf('[gui smoke] all PASS\n');
end

function b = local_btn(fig, txt)
    b = findall(fig, 'Type', 'uibutton', 'Text', txt);
    if numel(b) > 1, b = b(1); end
end

function t = local_tableWithCol(tbls, col)
    t = [];
    for i = 1:numel(tbls)
        if any(strcmp(tbls(i).ColumnName, col)), t = tbls(i); return; end
    end
end
