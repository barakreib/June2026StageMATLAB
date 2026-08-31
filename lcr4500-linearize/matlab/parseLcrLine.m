function info = parseLcrLine(out)
%PARSELCRLINE Parse the machine-readable status line ensure_linear.py prints.
%
%   info = parseLcrLine(out) scans the captured stdout/stderr text for the
%   line the toolkit always emits and returns:
%       .linear   logical  register bit7 clear AND status bit agree
%       .gamma    double   gamma register value (NaN if the line was absent
%                          or the toolkit printed 'GAMMA=??')
%       .changed  logical  the bypass was applied during this call
%       .mode     char     'video' | 'pattern' | '' when unknown
%
%   Tolerates all three line shapes the toolkit has ever produced:
%       LCR4500 GAMMA=0x00 LINEAR=1 CHANGED=0 MODE=video     (normal)
%       LCR4500 GAMMA=0x80 LINEAR=0 CHANGED=0                (legacy --require)
%       LCR4500 GAMMA=?? LINEAR=0 CHANGED=0 MODE=?           (unreachable)
%
%   Pure text function -- no I/O -- so it is testable without Python or a
%   projector. Used by ensureLightCrafterLinear.

info = struct('linear', false, 'gamma', NaN, 'changed', false, 'mode', '');

tok = regexp(out, 'GAMMA=0x([0-9A-Fa-f]{2})\s+LINEAR=(\d)\s+CHANGED=(\d)', ...
    'tokens', 'once');
if ~isempty(tok)
    info.gamma   = hex2dec(tok{1});
    info.linear  = str2double(tok{2}) == 1;
    info.changed = str2double(tok{3}) == 1;
end

% 'MODE=?' deliberately fails the \w+ match and leaves mode empty.
mtok = regexp(out, 'MODE=(\w+)', 'tokens', 'once');
if ~isempty(mtok)
    info.mode = mtok{1};
end
end
