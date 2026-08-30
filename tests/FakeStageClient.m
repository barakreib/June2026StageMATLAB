classdef FakeStageClient < handle
% Stands in for stage.core.network.StageClient: play() ACKs immediately (as the real one
% does -- the server renders asynchronously) and getPlayInfo() blocks until the presentation
% would have finished, which is exactly the behaviour that used to freeze the GUI.
%
% Also enough of the client surface for the GENERATED stimulus scripts and the backdrop
% setter (getCanvasSize / connect / disconnect / isConnected), and it captures every played
% player so tests can introspect the presentations (player.presentation is public read).
    properties
        durationS   = 1.0
        refresh     = 60
        canvas      = [912 1140]
        isConnected = true
        tPlayed     = []
        playCalled  = 0
        infoCalled  = 0
        infoBlockedFor = NaN     % how long getPlayInfo actually had to wait
        flipDurations = []
        lastPlayer  = []
        players     = {}         % every player handed to play(), in order
    end
    methods
        function connect(obj, varargin), obj.isConnected = true; end
        function disconnect(obj), obj.isConnected = false; end
        function s = getCanvasSize(obj), s = obj.canvas; end
        function r = getMonitorRefreshRate(obj), r = obj.refresh; end
        function play(obj, player)
            obj.playCalled = obj.playCalled + 1;
            obj.lastPlayer = player;
            obj.players{end + 1} = player;
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
