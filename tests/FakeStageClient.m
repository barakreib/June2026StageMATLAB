classdef FakeStageClient < handle
% Stands in for stage.core.network.StageClient: play() ACKs immediately (as the real one
% does -- the server renders asynchronously) and getPlayInfo() blocks until the presentation
% would have finished, which is exactly the behaviour that used to freeze the GUI.
    properties
        durationS   = 1.0
        refresh     = 60
        tPlayed     = []
        playCalled  = 0
        infoCalled  = 0
        infoBlockedFor = NaN     % how long getPlayInfo actually had to wait
        flipDurations = []
    end
    methods
        function r = getMonitorRefreshRate(obj), r = obj.refresh; end
        function play(obj, ~)
            obj.playCalled = obj.playCalled + 1;
            obj.tPlayed = tic;            % returns instantly, like the real ACK
        end
        function i = getPlayInfo(obj)
            obj.infoCalled = obj.infoCalled + 1;
            t0 = tic;
            while toc(obj.tPlayed) < obj.durationS   % blocks, like the real one
                pause(0.005);
            end
            obj.infoBlockedFor = toc(t0);
            i = struct('flipDurations', obj.flipDurations);
        end
    end
end
