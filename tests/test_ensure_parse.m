function test_ensure_parse()
% parseLcrLine against every line shape ensure_linear.py has ever produced.
% Pure text -- no Python, no projector.
    here = fileparts(mfilename('fullpath'));
    addpath(fullfile(fileparts(here), 'lcr4500-linearize', 'matlab'));

    % ---- the normal full line ----
    s = parseLcrLine(sprintf('noise before\nLCR4500 GAMMA=0x00 LINEAR=1 CHANGED=1 MODE=video\nnoise after'));
    assert(s.linear && s.gamma == 0 && s.changed && strcmp(s.mode, 'video'), 'full line parses');

    s = parseLcrLine('LCR4500 GAMMA=0x81 LINEAR=0 CHANGED=0 MODE=pattern');
    assert(~s.linear && s.gamma == hex2dec('81') && ~s.changed && strcmp(s.mode, 'pattern'), ...
        'non-linear pattern-mode line parses');

    % ---- the legacy --require refusal line (no MODE field) ----
    s = parseLcrLine('LCR4500 GAMMA=0x80 LINEAR=0 CHANGED=0');
    assert(~s.linear && s.gamma == 128 && ~s.changed && isempty(s.mode), ...
        'MODE-less legacy line parses with mode empty');

    % ---- the unreachable line: GAMMA=?? and MODE=? must NOT half-parse ----
    s = parseLcrLine('LCR4500 GAMMA=?? LINEAR=0 CHANGED=0 MODE=?');
    assert(~s.linear && isnan(s.gamma) && ~s.changed && isempty(s.mode), ...
        'the error line leaves gamma NaN and mode empty');

    % ---- garbage in, defaults out ----
    s = parseLcrLine('');
    assert(~s.linear && isnan(s.gamma) && ~s.changed && isempty(s.mode), 'empty text -> defaults');
    s = parseLcrLine('python: command not found');
    assert(isnan(s.gamma), 'unrelated text -> defaults');

    fprintf('[ensure parse test] all PASS\n');
end
