function out = lcProjectorState(action, varargin)
% lcProjectorState  Cached, per-role LightCrafter 4500 gamma/mode state.
%
%   The DLPC350's de-gamma bypass is VOLATILE (any power cycle or the TI
%   Control Software silently restores it), so the suite must know, per run,
%   whether each projector is actually linear. This module owns that
%   knowledge: a per-MATLAB-process cache keyed by role, populated only by
%   explicit calls -- nothing here runs from a timer or a render callback.
%
%   Roles are short names matching rig_config.json's `lc_projectors` keys.
%   The rig uses two: 'stim' (microscope light path -- the projector Stage
%   renders to, and the one lcGammaCorrect's regime follows) and 'monitor'
%   (stimulus monitoring / light-detector driving).
%
%   s = lcProjectorState('get', role)      cached state; NEVER touches
%                                          hardware; unknown role -> default
%                                          struct with known=false
%   s = lcProjectorState('refresh', role)  read-only hardware query
%                                          (ensure_linear.py --query)
%   s = lcProjectorState('ensure', role)   apply the de-gamma bypass if
%                                          needed + verify (writes!)
%   ...('refresh'|'ensure', role, devCfg)  same, with the device config
%                                          given directly instead of read
%                                          from rig_config (a test seam)
%   s = lcProjectorState('assume', role, s)  inject state without hardware
%                                          (tests, manual override); missing
%                                          fields take defaults
%       lcProjectorState('clear')          wipe every role
%       lcProjectorState('clear', role)    wipe one role
%   r = lcProjectorState('regime')         'linear' | 'degamma' -- pure
%                                          cache lookup on the STIM role,
%                                          safe to call per frame
%
%   State struct fields:
%       role       'stim' | 'monitor' | ...
%       known      logical  any refresh/ensure/assume populated this role
%       reachable  logical  last hardware contact succeeded
%       linear     logical  register bit7 clear AND main-status bit agree
%       gamma      double   gamma register value (NaN when unknown)
%       mode       'video' | 'pattern' | ''
%       changed    logical  last 'ensure' had to apply the bypass
%       checkedAt  datetime of last hardware contact (NaT for assume/none)
%       source     'ensure' | 'query' | 'assume' | 'none'
%
%   'regime' maps known && reachable && linear && mode=='video' to 'linear'
%   and EVERYTHING else to 'degamma' -- so with no configuration, no
%   hardware, or any doubt, lcGammaCorrect keeps applying the measured LUT
%   exactly as before this module existed.
%
%   'refresh'/'ensure' need the role configured in rig_config.json:
%       "lc_projectors": {
%         "stim":    {"device": "<hid-path-substring>", "required_for_run": true,
%                     "transport": "local"},
%         "monitor": {"device": "...", "required_for_run": false}
%       }
%   plus optionally "lc_toolkit_root" (default: <repo>/lcr4500-linearize).
%   `device` is an index, exact serial, or HID-path substring (run
%   `ensure_linear.py --list` on the rig; pin by path, label the ports).
%   `transport` 'local' shells out on this machine. 'stage-agent' reaches
%   a projector whose USB is on ANOTHER machine (the Stage-server box)
%   through lcr_agent.py listening there -- optional `host` (default:
%   rig_config stage_host) and `port` (default 5676; the wake listener is
%   5677 and Stage itself 5678 -- this never touches those).
%
%   Unreachable/not-linear outcomes are RECORDED in the struct, not thrown
%   -- the caller (runExperiment's bracket) decides what refuses a run.
%   Only toolkit breakage (missing script, bad usage) throws.
%
%   Errors: lcProjectorState:badAction, :badRole, :notConfigured,
%           :transportUnsupported

persistent cache
if isempty(cache), cache = struct(); end

switch lower(char(action))
    case 'get'
        role = local_role(varargin);
        out = local_get(cache, role);

    case 'refresh'
        role = local_role(varargin);
        s = local_transport(local_deviceConfig(role, varargin), 'query');
        s.role = role;
        cache.(role) = s;
        out = s;

    case 'ensure'
        role = local_role(varargin);
        s = local_transport(local_deviceConfig(role, varargin), 'ensure');
        s.role = role;
        cache.(role) = s;
        out = s;

    case 'assume'
        role = local_role(varargin);
        if numel(varargin) < 2 || ~isstruct(varargin{2})
            error('lcProjectorState:badAction', ...
                '''assume'' needs a role and a state struct.');
        end
        s = local_default(role);
        given = varargin{2};
        for f = fieldnames(given)'
            s.(f{1}) = given.(f{1});
        end
        s.role = role;
        s.known = true;
        s.source = 'assume';
        cache.(role) = s;
        out = s;

    case 'clear'
        if isempty(varargin)
            cache = struct();
        else
            role = local_role(varargin);
            if isfield(cache, role)
                cache = rmfield(cache, role);
            end
        end
        out = [];

    case 'regime'
        s = local_get(cache, 'stim');
        if s.known && s.reachable && s.linear && strcmp(s.mode, 'video')
            out = 'linear';
        else
            out = 'degamma';
        end

    otherwise
        error('lcProjectorState:badAction', ...
            'Unknown action ''%s''. See help lcProjectorState.', char(action));
end
end

% ------------------------------------------------------------------------
function role = local_role(args)
if isempty(args) || ~(ischar(args{1}) || isstring(args{1})) || ...
        ~isvarname(char(args{1}))
    error('lcProjectorState:badRole', ...
        'Role must be a simple name like ''stim'' or ''monitor''.');
end
role = char(args{1});
end

function s = local_default(role)
s = struct('role', role, 'known', false, 'reachable', false, ...
    'linear', false, 'gamma', NaN, 'mode', '', 'changed', false, ...
    'checkedAt', NaT, 'source', 'none');
end

function s = local_get(cache, role)
if isfield(cache, role)
    s = cache.(role);
else
    s = local_default(role);
end
end

function devCfg = local_deviceConfig(role, args)
% args is the action's varargin: an optional struct after the role overrides
% rig_config entirely (test seam / one-off manual calls).
if numel(args) >= 2 && isstruct(args{2})
    devCfg = args{2};
    return;
end
cfgAll = loadRigConfig('lc_projectors', []);
if ~isstruct(cfgAll) || ~isfield(cfgAll, role)
    error('lcProjectorState:notConfigured', ...
        ['rig_config.json has no lc_projectors.%s entry -- hardware ' ...
         'queries are disabled on this machine. Configure the projector ' ...
         'on the rig (see help lcProjectorState), or use ' ...
         '''assume''/''get'' here.'], role);
end
devCfg = cfgAll.(role);
end

function s = local_transport(devCfg, mode)
% The ONLY place this module touches hardware. 'local' shells out via the
% toolkit's MATLAB wrapper; 'stage-agent' (a projector on the remote Stage
% machine) is a reserved seam, same contract over TCP, not built yet.
transport = 'local';
if isfield(devCfg, 'transport') && ~isempty(devCfg.transport)
    transport = char(devCfg.transport);
end

switch transport
    case 'local'
        s = local_transportLocal(devCfg, mode);
    case 'stage-agent'
        s = local_transportAgent(devCfg, mode);
    otherwise
        error('lcProjectorState:transportUnsupported', ...
            ['transport ''%s'' is not implemented (use ''local'' or ' ...
             '''stage-agent'').'], transport);
end
end

function root = local_toolkitRoot()
% The toolkit folder; both transports need its matlab/ (parseLcrLine) on path.
root = char(string(loadRigConfig('lc_toolkit_root', '')));
here = fileparts(mfilename('fullpath'));
if isempty(root)
    root = fullfile(here, 'lcr4500-linearize');
elseif ~ismember(':', root) && root(1) ~= '/' && root(1) ~= '\'
    root = fullfile(here, root);    % relative paths hang off the repo
end
if exist('parseLcrLine', 'file') ~= 2 || exist('ensureLightCrafterLinear', 'file') ~= 2
    addpath(fullfile(root, 'matlab'));
end
end

function s = local_transportLocal(devCfg, mode)
root = local_toolkitRoot();

device = '';
if isfield(devCfg, 'device'), device = char(string(devCfg.device)); end

s = local_default('');
s.checkedAt = datetime('now');

if strcmp(mode, 'query')
    r = ensureLightCrafterLinear('query', true, 'device', device, 'root', root);
    s.known = true;
    s.reachable = r.reachable;
    s.linear = r.reachable && r.linear;
    s.gamma = r.gamma;
    s.mode = r.mode;
    s.source = 'query';
    return;
end

% ensure: the wrapper throws on unreachable/not-linear -- convert those two
% outcomes into recorded state; anything else is toolkit breakage.
s.source = 'ensure';
try
    r = ensureLightCrafterLinear('device', device, 'root', root);
    s.known = true;
    s.reachable = true;
    s.linear = r.linear;
    s.gamma = r.gamma;
    s.mode = r.mode;
    s.changed = r.changed;
catch err
    switch err.identifier
        case 'LCr4500:unreachable'
            s.known = true;
            s.reachable = false;
        case 'LCr4500:notLinear'
            s.known = true;
            s.reachable = true;
            s.linear = false;
        otherwise
            rethrow(err);
    end
end
end

function s = local_transportAgent(devCfg, mode)
% Reach a projector whose USB is on ANOTHER machine, through lcr_agent.py
% listening there (lcr4500-linearize/lcr_agent.py; 13-start-agent.bat).
% Protocol: one request line -> ensure_linear.py's output + a final
% 'EXIT=<n>' line. Exit codes mirror the local path: 0 linear, 1 not
% linear, 2 unreachable. No reply / refused connection is recorded as
% unreachable (the bracket then refuses the run for a required role);
% EXIT=3 or a garbled reply is toolkit breakage and throws.
local_toolkitRoot();                        % parseLcrLine on the path

host = '';
if isfield(devCfg, 'host') && ~isempty(devCfg.host), host = char(string(devCfg.host)); end
if isempty(host), host = char(string(loadRigConfig('stage_host', 'localhost'))); end
if isempty(host), host = 'localhost'; end
port = 5676;
if isfield(devCfg, 'port') && ~isempty(devCfg.port), port = double(devCfg.port); end
timeoutS = 30;
if isfield(devCfg, 'timeout') && ~isempty(devCfg.timeout), timeoutS = double(devCfg.timeout); end

if strcmp(mode, 'query'), req = 'query'; else, req = 'ensure'; end
if isfield(devCfg, 'device') && ~isempty(devCfg.device)
    req = sprintf('%s --device %s', req, char(string(devCfg.device)));
end

s = local_default('');
s.checkedAt = datetime('now');
s.source = mode;                            % 'ensure' | 'query'

buf = '';
exitCode = [];
try
    t = tcpclient(host, port, 'ConnectTimeout', 5, 'Timeout', 5);
    cleanupT = onCleanup(@() delete(t)); %#ok<NASGU>
    writeline(t, req);
    t0 = tic;
    while toc(t0) < timeoutS
        n = t.NumBytesAvailable;
        if n > 0
            buf = [buf reshape(char(read(t, n, 'char')), 1, [])]; %#ok<AGROW>
            tok = regexp(buf, 'EXIT=(\d+)', 'tokens', 'once');
            if ~isempty(tok)
                exitCode = str2double(tok{1});
                break;
            end
        else
            pause(0.05);
        end
    end
catch
    % refused / host down / bad address -> recorded as unreachable below
end

if isempty(exitCode)
    s.known = true;
    s.reachable = false;
    fprintf(2, ['[lcProjectorState] no reply from lcr_agent at %s:%d -- start ' ...
                '13-start-agent.bat on the projector machine (and allow inbound ' ...
                'TCP %d in its firewall once).\n'], host, port, port);
    return;
end

switch exitCode
    case {0, 1}
        r = parseLcrLine(buf);
        s.known = true;
        s.reachable = true;
        s.linear = r.linear;
        s.gamma = r.gamma;
        s.mode = r.mode;
        s.changed = r.changed;
    case 2
        s.known = true;
        s.reachable = false;
    otherwise
        error('lcProjectorState:agent', ...
            'lcr_agent at %s:%d rejected the request (EXIT=%d):\n%s', ...
            host, port, exitCode, strtrim(buf));
end
end
