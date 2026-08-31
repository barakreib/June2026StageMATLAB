function info = ensureLightCrafterLinear(varargin)
%ENSURELIGHTCRAFTERLINEAR Guarantee the LightCrafter 4500 is linear, or error.
%
%   ensureLightCrafterLinear() applies the DLPC350 de-gamma bypass if it is
%   not already set, verifies it two independent ways, and throws an error
%   if the projector is not confirmed linear. Call it at the top of any
%   experiment that assumes a linear projector.
%
%   The de-gamma setting is VOLATILE. It reverts on every projector power
%   cycle, and the TI Control Software can push it back too. Checking once
%   at startup is not paranoia -- it is the only thing standing between you
%   and a session of quietly gamma-encoded data.
%
%   info = ensureLightCrafterLinear() returns a struct:
%       .linear   logical, always true if this returned without erroring
%       .gamma    the gamma register value, e.g. 0
%       .changed  true if the bypass had to be applied just now
%       .mode     'video' or 'pattern'
%
%   ensureLightCrafterLinear('require', true) verifies WITHOUT writing, and
%   errors if the projector is not already linear. Use this to assert state
%   part-way through a long session, or immediately after a run, to prove
%   the register held for the whole thing.
%
%   Example
%       ensureLightCrafterLinear();              % at experiment start
%       ... run the experiment ...
%       ensureLightCrafterLinear('require',true) % prove it held
%
%   Errors thrown:
%       LCr4500:notLinear     bypass would not take
%       LCr4500:unreachable   projector off, unplugged, or GUI has the handle
%       LCr4500:toolkit       the Python toolkit could not be located

p = inputParser;
p.addParameter('require', false, @(x) islogical(x) || isnumeric(x));
p.addParameter('root', '', @ischar);
p.parse(varargin{:});
requireOnly = logical(p.Results.require);

% ---- locate the toolkit (this file lives in <root>\matlab) --------------
if isempty(p.Results.root)
    root = fileparts(fileparts(mfilename('fullpath')));
else
    root = p.Results.root;
end

pyExe  = fullfile(root, '.venv', 'Scripts', 'python.exe');
script = fullfile(root, 'ensure_linear.py');

if ~isfile(pyExe)
    pyExe = 'python';   % fall back to whatever is on PATH
end
if ~isfile(script)
    error('LCr4500:toolkit', ...
        ['Could not find ensure_linear.py under:\n  %s\n' ...
         'Pass the toolkit folder explicitly:\n' ...
         '  ensureLightCrafterLinear(''root'', ''D:\\share\\lcr4500-linearize'')'], ...
        root);
end

% ---- run it -------------------------------------------------------------
cmd = sprintf('"%s" "%s"', pyExe, script);
if requireOnly
    cmd = [cmd ' --require'];
end

[status, out] = system(cmd);

% ---- parse the machine-readable line ------------------------------------
info = struct('linear', false, 'gamma', NaN, 'changed', false, 'mode', '');

tok = regexp(out, 'GAMMA=0x([0-9A-Fa-f]{2})\s+LINEAR=(\d)\s+CHANGED=(\d)', 'tokens', 'once');
if ~isempty(tok)
    info.gamma   = hex2dec(tok{1});
    info.linear  = str2double(tok{2}) == 1;
    info.changed = str2double(tok{3}) == 1;
end
mtok = regexp(out, 'MODE=(\w+)', 'tokens', 'once');
if ~isempty(mtok)
    info.mode = mtok{1};
end

% ---- verdict ------------------------------------------------------------
switch status
    case 0
        if info.changed
            fprintf('LightCrafter 4500: de-gamma bypass applied, verified linear.\n');
        else
            fprintf('LightCrafter 4500: verified linear (already set).\n');
        end
        if ~isempty(info.mode) && ~strcmp(info.mode, 'video')
            warning('LCr4500:notVideoMode', ...
                'Projector is in %s mode; de-gamma only affects video mode.', info.mode);
        end
    case 2
        error('LCr4500:unreachable', ...
            ['Cannot reach the LightCrafter 4500.\n%s\n' ...
             'Check power and the mini-USB cable, and close the TI Control ' ...
             'Software if it is open.'], strtrim(out));
    otherwise
        error('LCr4500:notLinear', ...
            ['The LightCrafter 4500 is NOT linear -- refusing to continue.\n%s'], ...
            strtrim(out));
end
end
