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
%       .linear      logical, always true if this returned without erroring
%       .gamma       the gamma register value, e.g. 0
%       .changed     true if the bypass had to be applied just now
%       .mode        'video' or 'pattern' ('' when it could not be read)
%       .reachable   logical, the toolkit talked to the projector
%       .exitStatus  raw exit code from ensure_linear.py
%
%   Name-value options:
%       'require'  verify WITHOUT writing; error if not already linear.
%                  Use to assert state after a run, proving the register
%                  held the whole time.
%       'query'    read-only state report that NEVER throws about the
%                  projector's state: exit codes 0 (linear), 1 (not linear)
%                  and 2 (unreachable) all return the info struct -- branch
%                  on .reachable/.linear/.mode yourself. Only a toolkit
%                  problem (missing script, bad usage) still errors.
%                  Mutually exclusive with 'require'.
%       'device'   selector when more than one LC4500 is attached: an
%                  index, an exact serial number, or a case-insensitive
%                  substring of the HID path. Empty = first device.
%       'root'     toolkit folder, when not auto-detected.
%
%   Example
%       ensureLightCrafterLinear('device', '7&2b9a1c');   % at run start
%       ... run the experiment ...
%       s = ensureLightCrafterLinear('device', '7&2b9a1c', 'query', true);
%       if ~(s.reachable && s.linear), warning('state did not hold'); end
%
%   Errors thrown (never for 'query' state outcomes):
%       LCr4500:notLinear     bypass would not take / --require unmet
%       LCr4500:unreachable   projector off, unplugged, or GUI has the handle
%       LCr4500:toolkit       the Python toolkit could not be located or
%                             was called incorrectly

p = inputParser;
p.addParameter('require', false, @(x) islogical(x) || isnumeric(x));
p.addParameter('query',   false, @(x) islogical(x) || isnumeric(x));
p.addParameter('device',  '',    @(x) ischar(x) || isstring(x));
p.addParameter('root',    '',    @ischar);
p.parse(varargin{:});
requireOnly = logical(p.Results.require);
queryOnly   = logical(p.Results.query);
device      = char(p.Results.device);

if requireOnly && queryOnly
    error('LCr4500:toolkit', ...
        '''require'' and ''query'' are mutually exclusive.');
end

% ---- locate the toolkit (this file lives in <root>/matlab) --------------
if isempty(p.Results.root)
    root = fileparts(fileparts(mfilename('fullpath')));
else
    root = p.Results.root;
end

% The checked-in .venv is a WINDOWS venv; on other platforms its
% Scripts/python.exe exists as a file but is not runnable here.
if ispc
    pyExe = fullfile(root, '.venv', 'Scripts', 'python.exe');
    if ~isfile(pyExe), pyExe = 'python'; end
else
    pyExe = fullfile(root, '.venv', 'bin', 'python');
    if ~isfile(pyExe), pyExe = 'python3'; end
end

script = fullfile(root, 'ensure_linear.py');
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
elseif queryOnly
    cmd = [cmd ' --query'];
end
if ~isempty(device)
    cmd = sprintf('%s --device "%s"', cmd, device);
end

[status, out] = system(cmd);

% ---- parse the machine-readable line ------------------------------------
info = parseLcrLine(out);
info.exitStatus = status;
info.reachable  = (status == 0 || status == 1);

% ---- verdict ------------------------------------------------------------
if queryOnly
    if info.reachable || status == 2
        return;                       % state outcomes never throw on query
    end
    error('LCr4500:toolkit', ...
        'ensure_linear.py --query failed (exit %d):\n%s', status, strtrim(out));
end

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
    case 3
        error('LCr4500:toolkit', ...
            'ensure_linear.py rejected its arguments (exit 3):\n%s', strtrim(out));
    otherwise
        error('LCr4500:notLinear', ...
            ['The LightCrafter 4500 is NOT linear -- refusing to continue.\n%s'], ...
            strtrim(out));
end
end
