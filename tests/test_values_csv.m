function test_values_csv()
% test_values_csv  The troubleshooting values CSV is exact and self-describing.
%
% Checks writeStimValuesCsv directly (no rig_config flag needed, so it runs with the
% real repo config untouched): the '#' header carries the seed and the 4x3 LED grid
% (explicit arg, ledSession fallback, or "none"), and the body has one row per
% (update, check, channel) whose intended/sent columns reproduce the builders'
% lcGammaCorrect linearization and uint8 quantization exactly.
%
% RIG-SAFE: writes into a temp dir; the only "rig" is a FakeLedRig in ledSession.

    here = fileparts(mfilename('fullpath'));
    repo = fileparts(here);
    addpath(repo, here);
    td = tempname;
    mkdir(td);
    cleanup = onCleanup(@() local_cleanup(td)); %#ok<NASGU>
    ledSession('clear');

    % the same draw the seeded stimuli make, small enough to check every cell
    seed = 7;  cy = 2;  cx = 3;  nu = 4;  mu = 0.5;  sigma = 0.3;
    stream = RandStream('mt19937ar', 'Seed', seed);
    v = mu + sigma .* (sqrt(2) .* erfinv(2 .* rand(stream, cy, cx, nu) - 1));
    v = min(max(v, 0), 1);
    grid = [0 0 0.3; 0.1 0.2 0; 0 0 0; 1 0.5 0.25];

    % ---- greyscale + explicit LED grid: header lines + exact columns ----
    p = writeStimValuesCsv(td, 'stimA', seed, struct('grey', v), grid);
    txt = fileread(p);
    assert(contains(txt, '# seed: 7'), 'header carries the seed');
    assert(contains(txt, '# LED1: R=0 G=0 B=0.3') && contains(txt, '# LED4: R=1 G=0.5 B=0.25'), ...
        'header carries the 4x3 stimulus LED grid');
    [~, base] = fileparts(p);
    assert(contains(base, 'stimA_seed7_values'), 'file name embeds stimulus + seed');
    [~, sub] = fileparts(fileparts(p));
    assert(strcmp(sub, 'debug'), 'dumps land in a debug/ subdirectory of outDir');

    T = readtable(p, 'CommentStyle', '#');
    assert(height(T) == cy * cx * nu, 'one row per (update, check)');
    assert(all(T.seed == seed), 'seed column constant down the file');
    key = T.update * 10000 + T.check_row * 100 + T.check_col;
    [uu, rr, cc] = ndgrid(1:nu, 1:cy, 1:cx);
    assert(isequal(sort(key), sort(uu(:) * 10000 + rr(:) * 100 + cc(:))), ...
        'every check position appears exactly once per update');
    for i = 1:height(T)
        assert(abs(T.intended_linear(i) - v(T.check_row(i), T.check_col(i), T.update(i))) < 1e-12, ...
            'intended_linear reproduces the seeded draw at (%d,%d,u%d)', ...
            T.check_row(i), T.check_col(i), T.update(i));
    end
    assert(max(abs(T.sent_frac - lcGammaCorrect(T.intended_linear))) < 1e-12, ...
        'sent_frac is lcGammaCorrect(intended_linear)');
    assert(isequal(T.sent_code, double(uint8(round(255 * T.sent_frac)))), ...
        'sent_code is the uint8 imageMatrix quantization');

    % ---- S-cone iso: R and G channels, G = 1 - R per position ----
    p2 = writeStimValuesCsv(td, 'stimB', 3, struct('R', v, 'G', 1 - v), grid);
    T2 = readtable(p2, 'CommentStyle', '#', 'TextType', 'string');
    assert(height(T2) == 2 * cy * cx * nu, 'two rows per (update, check) for R+G');
    assert(isempty(setxor(unique(T2.channel), ["G"; "R"])), 'channels are exactly R and G');
    R = T2(T2.channel == "R", :);
    G = T2(T2.channel == "G", :);
    k = @(S) S.update * 10000 + S.check_row * 100 + S.check_col;
    assert(isequal(k(R), k(G)) && max(abs(R.intended_linear + G.intended_linear - 1)) < 1e-12, ...
        'per position, intended G = 1 - intended R');

    % ---- no grid anywhere -> header says none ----
    p3 = writeStimValuesCsv(td, 'stimC', 4, struct('grey', v(:, :, 1)));
    assert(contains(fileread(p3), '# led_grid: none'), 'no grid recorded as none');

    % ---- omitted grid falls back to the session''s loaded grid (standalone AA path) ----
    rig = FakeLedRig('FAKE');
    ledSession('set', rig, grid);
    p4 = writeStimValuesCsv(td, 'stimD', 5, struct('grey', v(:, :, 1)));
    assert(contains(fileread(p4), '# LED4: R=1 G=0.5 B=0.25') && ...
           contains(fileread(p4), 'from ledSession'), 'ledSession fallback grid in the header');
    ledSession('clear');

    fprintf('  ok  values CSV: LED-grid header + exact intended/sent columns per check\n');
end


function local_cleanup(td)
    ledSession('clear');
    try
        rmdir(td, 's');
    catch
    end
end
