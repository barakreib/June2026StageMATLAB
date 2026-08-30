function out = ledSession(action, varargin)
% ledSession  The run's LED-driver handle + last-applied grid, for PER-PHASE LED values.
%
%   ledSession('set', rig, grid)   register the run's open NeitzLedRig and the 4x3 grid
%                                  it was just loaded with (runExperiment, after setup)
%   ok = ledSession('apply', grid) write a 4x3 intensity grid to the registered rig.
%                                  No rig registered (dry run / LED driver unchecked) or
%                                  an empty grid -> silent no-op. A grid identical to the
%                                  one already loaded is skipped (no serial traffic), so
%                                  "(main grid)" phase settings cost nothing. Returns true
%                                  iff a write actually happened. Best-effort: a serial
%                                  error is warned about once, never thrown mid-run.
%   g  = ledSession('current')     the grid the LEDs are currently loaded with ([] if none)
%   r  = ledSession('rig')         the registered rig handle ([] if none)
%   ledSession('handoff')          mark the rig as HANDED OFF: the end-of-run teardown
%                                  must leave it open (a "final LEDs" state that persists
%                                  after the run; runExperiment publishes it as base `rig`)
%   tf = ledSession('isHandedOff')
%   ledSession('clear')            forget the registration (does NOT delete the rig --
%                                  its owner does that)
%
% This is the seam that lets playAndLogTrial switch LED grids at pre-stim / stimulus /
% post-stim boundaries, and runExperiment at inter-stim / end-of-run, without threading a
% rig handle through the generated stimulus scripts. Everything is a no-op until
% runExperiment registers a rig, so standalone scripts and local dry runs are unaffected.

    persistent S
    if isempty(S), S = local_empty(); end

    out = [];
    switch action
        case 'set'
            S.rig     = varargin{1};
            S.current = local_coerce(varargin{2});
            S.handoff = false;
            S.warned  = false;
        case 'apply'
            out = false;
            grid = local_coerce(varargin{1});
            if isempty(grid) || isempty(S.rig) || ~isvalid(S.rig), return; end
            if isequal(grid, S.current), return; end
            try
                cols = {'r', 'g', 'b'};
                for li = 1:4
                    for ci = 1:3
                        S.rig.setIntensity(li - 1, cols{ci}, grid(li, ci));
                    end
                end
                S.current = grid;
                out = true;
            catch err
                if ~S.warned
                    warning('ledSession:applyFailed', ...
                        'Phase LED write failed (further failures silent): %s', err.message);
                    S.warned = true;
                end
            end
        case 'current'
            out = S.current;
        case 'rig'
            if ~isempty(S.rig) && isvalid(S.rig), out = S.rig; end
        case 'handoff'
            S.handoff = true;
        case 'isHandedOff'
            out = S.handoff;
        case 'clear'
            S = local_empty();
        otherwise
            error('ledSession:badAction', 'Unknown action "%s".', char(string(action)));
    end
end


function S = local_empty()
    S = struct('rig', [], 'current', [], 'handoff', false, 'warned', false);
end


function g = local_coerce(v)
% Accept a 4x3 numeric grid; anything else (including []) means "no grid".
    if iscell(v), v = cell2mat(v); end
    g = [];
    if isnumeric(v) && isequal(size(v), [4 3]) && all(isfinite(v(:)))
        g = double(v);
    end
end
