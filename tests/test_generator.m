function test_generator()
% test_generator  The generated stimulus scripts are frame-exact replacements for the AA*
% files, wrapped in the configured phases.
%
% For every stimRegistry entry: generate the script, RUN it against a FakeStageClient,
% then replay the captured presentation's controllers frame by frame and compare every
% frame against the AA algorithm recomputed here (same RNG draws, same lcGammaCorrect).
% The three-segment sync bar is checked on every frame too: top = projector frame clock
% (toggles every frame, pre through post), middle = the stimulus update clock (the legacy
% single-bar pattern, dark outside the stimulus), bottom = the stimulus envelope. Also
% checks the phase composition (pre/post full-screen values), the per-phase LED writes,
% and the manifest record (AA stimulus name kept, phase + provenance fields added, seed
% per epoch).
%
% RIG-SAFE: the Stage client is a fake injected via stageClientShared('set'), the LED rig
% is a FakeLedRig registered in ledSession, and everything runs in a temp dir.

    here = fileparts(mfilename('fullpath'));
    repo = fileparts(here);
    addpath(repo, here);

    td = tempname;
    mkdir(td);
    oldPwd = pwd;
    cleanup = onCleanup(@() local_cleanup(oldPwd, td));
    cd(td);                       % generated_stimuli/ + the day manifest land here
    stimProgress('detach');
    ledSession('clear');

    reg     = stimRegistry();
    refresh = 60;
    preRGB  = [0.25 0.25 0.25];  preS  = 0.2;   % 12 frames
    postRGB = [0 0 0.5];         postS = 0.1;   %  6 frames
    mainGrid = [0 0 0.3; 0 0 0; 0 0 0; 0.2 0 0];
    preGrid  = [0.1 0 0; 0 0 0; 0 0 0; 0 0 0];
    phases = struct('rendered', true, ...
        'pre',   struct('seconds', preS,  'rgb', preRGB,        'ledGrid', preGrid), ...
        'post',  struct('seconds', postS, 'rgb', postRGB,       'ledGrid', zeros(4, 3)), ...
        'iti',   struct('seconds', 0.1,   'rgb', [0.1 0.1 0.1], 'ledGrid', zeros(4, 3)), ...
        'final', struct('rgb', [0 0 0], 'ledGrid', []));
    genDir = fullfile(td, 'generated_stimuli');

    seed = 11; mu = 0.5; sigma = 0.3; flickerHz = 4; stimFrames = 30;
    preFrames = round(preS * refresh); postFrames = round(postS * refresh);
    total = preFrames + stimFrames + postFrames;
    W = 912; H = 1140;

    for gi = 1:numel(reg)
        e = reg(gi);
        [gfn, gpath] = generateStimScript(e, phases, mainGrid, genDir);
        assert(exist(gpath, 'file') == 2, '%s: generated file missing', e.fn);

        fake = FakeStageClient();
        fake.canvas = [W H];
        fake.durationS = total / refresh;
        fake.flipDurations = repmat(1 / refresh, 1, total - 1);
        stageClientShared('set', fake);

        useLeds = strcmp(e.kind, 'sq') && ~e.iso;   % assert the LED write order once
        rig = [];
        if useLeds
            rig = FakeLedRig('FAKE');
            ledSession('set', rig, mainGrid);
        end

        switch e.kind
            case 'sq',     feval(gfn, flickerHz, stimFrames, refresh);
            case 'gauss',  feval(gfn, seed, mu, sigma, flickerHz, stimFrames, refresh);
            case 'jitter', feval(gfn, [570 456], 80, 150, 50, stimFrames, refresh, 'S-Cone Isolating');
        end

        % ---- captured presentation: duration + frame-by-frame controller replay ----
        assert(fake.playCalled == 1, '%s: exactly one play', e.fn);
        p = fake.lastPlayer.presentation;
        assert(abs(p.duration - total / refresh) < 1e-12, '%s: presentation covers pre+stim+post', e.fn);
        local_checkBarGeometry(e, p, W, H);
        local_replayAndCheck(e, p, total, preFrames, stimFrames, refresh, ...
            preRGB, postRGB, seed, mu, sigma, flickerHz, W, H);

        % ---- per-phase LED writes: pre grid, then main grid, then post zeros ----
        if useLeds
            n = numel(rig.J.sets);
            assert(n == 36, 'LED writes: 3 phase grids x 12 registers (got %d)', n);
            local_checkGridWrites(rig.J.sets(1:12),  preGrid,     'pre-stim grid');
            local_checkGridWrites(rig.J.sets(13:24), mainGrid,    'stimulus (main) grid');
            local_checkGridWrites(rig.J.sets(25:36), zeros(4, 3), 'post-stim grid');
            ledSession('clear');
        end

        % ---- manifest: AA identity kept, phase + provenance + geometry fields added ----
        [blk, ep] = local_lastBlock(td);
        assert(strcmp(blk.stimulus, e.fn), '%s: manifest keeps the AA stimulus name', e.fn);
        pa = loadRigConfig('pixel_aspect', 2);
        assert(blk.params.canvas_w == W && blk.params.canvas_h == H && ...
               abs(blk.params.pixel_aspect - pa) < 1e-12, ...
            '%s: canvas size + pixel aspect recorded in the manifest', e.fn);
        if strcmp(e.kind, 'gauss') && ~isequal(e.checks, [1 1])
            cyExp = max(1, round(e.checks(1) * (H / W) / pa));
            assert(blk.params.checks_y == cyExp, '%s: checks_y derived for square checks', e.fn);
            if abs(pa - 2) < 1e-12
                assert(cyExp == 25, '912x1140 at pixel aspect 2 -> a 40 x 25 grid');
            end
        end
        assert(blk.params.pre_frames == preFrames && blk.params.post_frames == postFrames, ...
            '%s: phase frame counts in the manifest', e.fn);
        assert(isequal(blk.params.pre_rgb(:)', preRGB) && isequal(blk.params.post_rgb(:)', postRGB), ...
            '%s: phase screen values in the manifest', e.fn);
        assert(strcmp(blk.params.generator, 'generateStimScript/1') && ...
               strcmp(blk.params.generated_script, [gfn '.m']), '%s: provenance fields', e.fn);
        assert(strcmp(blk.params.sync_bar, 'triple/1'), '%s: sync-bar layout stamped', e.fn);
        assert(blk.params.stim_frames == stimFrames, '%s: stim_frames is stimulus-only', e.fn);
        assert(isfield(ep, 'frame_sync') && ep.frame_sync.measured, '%s: frame sync logged', e.fn);
        if strcmp(e.kind, 'gauss')
            assert(ep.seed == seed, '%s: per-epoch seed logged', e.fn);
        end
        stageClientShared('set', []);
    end
    fprintf('  ok  generated scripts are frame-exact for all %d stimuli (+phases, LEDs, manifest)\n', numel(reg));

    % ---- zero-length phases collapse to exactly the bare stimulus ----
    z = phases;
    z.pre.seconds = 0;  z.post.seconds = 0;
    e = reg(1);                                            % greyscale sq flicker
    gfn = generateStimScript(e, z, mainGrid, genDir);
    fake = FakeStageClient();
    fake.canvas = [W H];
    fake.durationS = stimFrames / refresh;
    fake.flipDurations = repmat(1 / refresh, 1, stimFrames - 1);
    stageClientShared('set', fake);
    feval(gfn, flickerHz, stimFrames, refresh);
    p = fake.lastPlayer.presentation;
    assert(abs(p.duration - stimFrames / refresh) < 1e-12, 'zero phases: duration = stimulus only');
    st = struct('frame', 0, 'frameRate', refresh, 'time', 0);
    cellfun(@(c) c.evaluate(st), p.controllers);
    assert(isequal(p.stimuli{1}.color, lcGammaCorrect([0 0 0])) && ...
           isequal(p.stimuli{2}.color, lcGammaCorrect([0 0 1])) && ...   % top: frame clock on
           isequal(p.stimuli{3}.color, lcGammaCorrect([0 0 1])) && ...   % mid: phase A of the sq wave
           isequal(p.stimuli{4}.color, lcGammaCorrect([0 0 1])), ...     % bottom: stimulus ON
        'zero phases: frame 0 is the first stimulus frame (all three bar segments lit)');
    stageClientShared('set', []);
    fprintf('  ok  zero-length phases collapse to the bare stimulus\n');

    % ---- checkerboard geometry is SETTABLE: explicit checksX/checksY reach the board ----
    ec  = reg(strcmp({reg.fn}, 'AASeededGaussianCheckerboardGreyScaleStimFinal'));
    gfn = generateStimScript(ec, phases, mainGrid, genDir);
    fake = FakeStageClient();
    fake.canvas = [W H];
    fake.durationS = total / refresh;
    fake.flipDurations = repmat(1 / refresh, 1, total - 1);
    stageClientShared('set', fake);
    feval(gfn, seed, mu, sigma, flickerHz, stimFrames, refresh, 8, 5);
    p = fake.lastPlayer.presentation;
    st = struct('frame', preFrames, 'frameRate', refresh, 'time', preFrames / refresh);
    cellfun(@(c) c.evaluate(st), p.controllers);
    assert(isequal(size(p.stimuli{1}.imageMatrix), [5 8 3]), ...
        'an explicit 8 x 5 board draws a 5 x 8 x 3 image');
    blk = local_lastBlock(td);
    assert(blk.params.checks_x == 8 && blk.params.checks_y == 5, ...
        'the manifest records the settable board size');
    stageClientShared('set', []);
    fprintf('  ok  checkerboard checksX/checksY are settable arguments\n');
end


% ---------------------------- frame-by-frame reference ----------------------------
function local_replayAndCheck(e, p, total, preFrames, stimFrames, refresh, ...
                              preRGB, postRGB, seed, mu, sigma, flickerHz, W, H)
% The last three stimuli of every generated presentation are the sync-bar segments
% (top / middle / bottom), drawn over everything. `wantMid` below is the LEGACY single-bar
% pattern per stimulus kind; top and bottom are common and checked in local_checkBars.
    nS = numel(p.stimuli);
    switch e.kind
        case 'sq'
            if e.iso, colA = [1 0 0]; colB = [0 1 0]; else, colA = [0 0 0]; colB = [1 1 1]; end
            fphc = max(1, round(refresh / (2 * flickerHz)));
            assert(nS == 4 && numel(p.controllers) == 4, 'sq: full field + 3 bar segments');
            for g = 0:total-1
                st = struct('frame', g, 'frameRate', refresh, 'time', g / refresh);
                cellfun(@(c) c.evaluate(st), p.controllers);
                f = g + 1;                                  % 1-based LUT row
                wantMid = [0 0 0];
                if f <= preFrames
                    wantFF = preRGB;
                elseif f <= preFrames + stimFrames
                    fs = f - preFrames;
                    hc = floor((fs - 1) / fphc);
                    if mod(hc, 2) == 0, wantFF = colA; wantMid = [0 0 1];
                    else,               wantFF = colB; end
                else
                    wantFF = postRGB;
                end
                assert(max(abs(p.stimuli{1}.color - lcGammaCorrect(wantFF))) < 1e-12, ...
                    '%s: full-field color at frame %d', e.fn, g);
                local_checkBars(e, p, f, preFrames, stimFrames, wantMid, g);
            end

        case 'gauss'
            cx = e.checks(1);
            if isequal(e.checks, [1 1])
                cy = 1;
            else
                % checksY is DERIVED for square-on-the-wall checks (diamond-pixel DMD)
                cy = max(1, round(cx * (H / W) / loadRigConfig('pixel_aspect', 2)));
            end
            uenf = max(1, round(refresh / (2 * flickerHz)));
            nUpd = ceil(stimFrames / uenf);
            stream = RandStream('mt19937ar', 'Seed', seed);
            noise = mu + sigma .* (sqrt(2) .* erfinv(2 .* rand(stream, cy, cx, nUpd) - 1));
            noise = min(max(noise, 0), 1);
            pre8  = uint8(round(255 * lcGammaCorrect(preRGB)));
            post8 = uint8(round(255 * lcGammaCorrect(postRGB)));
            assert(nS == 4 && isa(p.stimuli{1}, 'stage.builtin.stimuli.Image'), ...
                'gauss: Image + 3 bar segments');
            for g = 0:total-1
                st = struct('frame', g, 'frameRate', refresh, 'time', g / refresh);
                cellfun(@(c) c.evaluate(st), p.controllers);
                f = g + 1;
                img = p.stimuli{1}.imageMatrix;
                assert(isequal(size(img), [cy cx 3]) && isa(img, 'uint8'), '%s: image shape', e.fn);
                wantMid = [0 0 0];
                if f <= preFrames
                    want = cat(3, repmat(pre8(1), cy, cx), repmat(pre8(2), cy, cx), repmat(pre8(3), cy, cx));
                elseif f <= preFrames + stimFrames
                    fs = f - preFrames;
                    u  = min(max(floor((fs - 1) / uenf) + 1, 1), nUpd);
                    v  = noise(:, :, u);
                    if e.iso
                        want = cat(3, uint8(round(255 * lcGammaCorrect(v))), ...
                                      uint8(round(255 * lcGammaCorrect(1 - v))), ...
                                      zeros(cy, cx, 'uint8'));
                    else
                        gg = uint8(round(255 * lcGammaCorrect(v)));
                        want = cat(3, gg, gg, gg);
                    end
                    if mod(floor((fs - 1) / uenf), 2) == 0, wantMid = [0 0 1]; end
                else
                    want = cat(3, repmat(post8(1), cy, cx), repmat(post8(2), cy, cx), repmat(post8(3), cy, cx));
                end
                assert(isequal(img, want), '%s: noise image at frame %d', e.fn, g);
                local_checkBars(e, p, f, preFrames, stimFrames, wantMid, g);
            end

        case 'jitter'
            rfC = [570 456];
            stepSigma = 50 / refresh;  k = 0.02;
            stream = RandStream('mt19937ar', 'Seed', 2);
            posX = zeros(stimFrames, 1);  posY = zeros(stimFrames, 1);
            curX = rfC(1);  curY = rfC(2);
            for f = 1:stimFrames
                dx = stepSigma * sqrt(2) * erfinv(2 * rand(stream) - 1);
                dy = stepSigma * sqrt(2) * erfinv(2 * rand(stream) - 1);
                curX = curX + dx - k * (curX - rfC(1));
                curY = curY + dy - k * (curY - rfC(2));
                posX(f) = curX;  posY(f) = curY;
            end
            park = -10 * max(W, H);
            assert(nS == 5 && isa(p.stimuli{2}, 'stage.builtin.stimuli.Ellipse'), ...
                'jitter: background + circle + 3 bar segments');
            assert(max(abs(p.stimuli{2}.color - lcGammaCorrect([1 0 0]))) < 1e-12, ...
                'jitter: S-cone iso circle is red');
            paJ = loadRigConfig('pixel_aspect', 2);
            assert(abs(p.stimuli{2}.radiusX - 150) < 1e-9 && ...
                   abs(p.stimuli{2}.radiusY - 150 * paJ) < 1e-9, ...
                'jitter: radiusY = radius * pixel_aspect, so the circle is ROUND on the wall');
            for g = 0:total-1
                st = struct('frame', g, 'frameRate', refresh, 'time', g / refresh);
                cellfun(@(c) c.evaluate(st), p.controllers);
                f = g + 1;
                wantMid = [0 0 0];
                if f <= preFrames
                    wantBG = preRGB;  wantPos = [park park];
                elseif f <= preFrames + stimFrames
                    fs = f - preFrames;
                    wantBG = [0 0 0];
                    wantPos = [posX(fs) posY(fs)];
                    if mod(fs, 2) == 1, wantMid = [0 0 1]; end
                else
                    wantBG = postRGB;  wantPos = [park park];
                end
                assert(max(abs(p.stimuli{1}.color - lcGammaCorrect(wantBG))) < 1e-12, ...
                    'jitter: background at frame %d', g);
                assert(max(abs(p.stimuli{2}.position - wantPos)) < 1e-9, ...
                    'jitter: circle position at frame %d', g);
                local_checkBars(e, p, f, preFrames, stimFrames, wantMid, g);
            end
    end
end


function local_checkBarGeometry(e, p, W, H)
% The bar column is the rightmost W/8, split into equal thirds (top / middle / bottom).
    nS = numel(p.stimuli);
    ys = [5*H/6, H/2, H/6];
    for i = 1:3
        seg = p.stimuli{nS - 3 + i};
        assert(isa(seg, 'stage.builtin.stimuli.Rectangle') && ...
               max(abs(seg.size - [W/8, H/3])) < 1e-9 && ...
               max(abs(seg.position - [W - W/16, ys(i)])) < 1e-9, ...
            '%s: sync-bar segment %d geometry (rightmost W/8, thirds)', e.fn, i);
    end
end


function local_checkBars(e, p, f, preFrames, stimFrames, wantMid, g)
% The three sync segments are always the LAST three stimuli: top = frame clock (blue on
% every odd frame, through pre/stim/post), middle = the kind-specific stimulus update
% clock passed in, bottom = solid blue exactly while stimulus frames are on screen.
    nS = numel(p.stimuli);
    if mod(f, 2) == 1, wantTop = [0 0 1]; else, wantTop = [0 0 0]; end
    if f > preFrames && f <= preFrames + stimFrames, wantBot = [0 0 1]; else, wantBot = [0 0 0]; end
    assert(max(abs(p.stimuli{nS-2}.color - lcGammaCorrect(wantTop))) < 1e-12, ...
        '%s: top bar (frame clock) at frame %d', e.fn, g);
    assert(max(abs(p.stimuli{nS-1}.color - lcGammaCorrect(wantMid))) < 1e-12, ...
        '%s: middle bar (stimulus update clock) at frame %d', e.fn, g);
    assert(max(abs(p.stimuli{nS}.color - lcGammaCorrect(wantBot))) < 1e-12, ...
        '%s: bottom bar (stimulus envelope) at frame %d', e.fn, g);
end


function local_checkGridWrites(sets, grid, what)
% 12 recorded setIntensity calls == one 4x3 grid load in row order, channels r/g/b.
    cols = 'rgb';
    n = 0;
    for li = 1:4
        for ci = 1:3
            n = n + 1;
            assert(sets(n).led == li - 1 && sets(n).chan == cols(ci) && ...
                   abs(sets(n).v - grid(li, ci)) < 1e-12, ...
                'LED write %d of the %s is (led %d, %s, %g)', n, what, li - 1, cols(ci), grid(li, ci));
        end
    end
end


function [blk, ep] = local_lastBlock(td)
% The most recently appended block + its last epoch from the day manifest in td.
    ds   = char(datetime('now', 'Format', 'yyyy_MM_dd'));
    tree = jsondecode(fileread(fullfile(td, [ds '_stim_manifest.json'])));
    cells = local_asCells(tree.cells);
    blks  = local_asCells(cells{end}.blocks);
    blk   = blks{end};
    eps   = local_asCells(blk.epochs);
    ep    = eps{end};
end


function c = local_asCells(x)
    if isempty(x),      c = {};
    elseif iscell(x),   c = reshape(x, 1, []);
    elseif isstruct(x), c = num2cell(reshape(x, 1, []));
    else,               c = {x};
    end
end


function local_cleanup(oldPwd, td)
    cd(oldPwd);
    stageClientShared('set', []);
    ledSession('clear');
    ws = warning('off', 'MATLAB:rmpath:DirNotFound');
    try
        rmpath(fullfile(td, 'generated_stimuli'));
    catch
    end
    warning(ws);
    try
        rmdir(td, 's');
    catch
    end
end
