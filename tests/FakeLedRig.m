classdef FakeLedRig < handle
% Stands in for NeitzLedRig (via runExperiment's opts.ledFactory seam, or registered
% straight into ledSession). Every setIntensity/setMode lands in a FakeLedJournal (obj.J)
% that OUTLIVES the rig, so tests can assert the write order even after runExperiment's
% teardown delete()s the rig. delete() records the real destructor's behavior: dark
% (mode 0) + closed.
    properties
        Port = 'FAKE'
        J    FakeLedJournal
    end
    methods
        function obj = FakeLedRig(port, journal)
            if nargin >= 1, obj.Port = port; end
            if nargin >= 2, obj.J = journal; else, obj.J = FakeLedJournal(); end
        end
        function tf = isConnected(obj), tf = ~obj.J.closed; end
        function ok = setMode(obj, m)
            obj.J.modes(end + 1) = m;
            ok = true;
        end
        function ok = setIntensity(obj, led, chan, v)
            obj.J.sets(end + 1) = struct('led', led, 'chan', char(chan), 'v', v);
            ok = true;
        end
        function delete(obj)
            if ~isempty(obj.J) && isvalid(obj.J)
                obj.J.modes(end + 1) = 0;    % the real destructor darks before closing
                obj.J.closed = true;
            end
        end
    end
end
