function varargout = stimProgress(action, varargin)
% stimProgress  Session-wide channel for LIVE run state: runExperiment and playAndLogTrial
% publish where the session is; stimulusMonitor draws it; stimulusGUI supplies the Cancel.
%
%   stimProgress('attach', reportFcn, cancelFcn)  install listeners (stimulusGUI, on Run)
%   stimProgress('detach')                        remove them (end of the run)
%   tf = stimProgress('isAttached')               is anything listening?
%
%   stimProgress('preview', plan)  the protocol as it currently stands, NOT running -- the
%                                  monitor draws its timeline while you are still building it
%   stimProgress('begin',  plan)   once per run: the whole planned session (see below)
%   stimProgress('report', state)  a PARTIAL state update; the monitor merges it onto the
%                                  last one, so a caller only sends what it actually knows
%   stimProgress('finish', summary) once, when the run ends or is cancelled
%   stimProgress('failed', struct('message', msg))  the run died -- show it where the
%                                  operator is already looking. Accepted AFTER 'finish',
%                                  because runExperiment's cleanup fires 'finish' on its way
%                                  out of an error and the reason would otherwise be lost.
%
%   stimProgress('requestCancel')  ask the GUI to cancel (the monitor's Cancel button)
%
% There is deliberately no 'cancelled' query here: a presentation already handed to the
% Stage server cannot be recalled, so the only place cancellation is ACTED on is
% runExperiment's epoch boundary, through its own opts.isCancelled hook.
%
% WHY A MODULE AND NOT THE BASE WORKSPACE: writeStimManifest already reads a base-workspace
% `neitzSessionContext` and writes its fields into the manifest JSON -- function handles in
% there would break jsonencode. This keeps the live hooks in a `persistent`, out of the
% manifest entirely, and reachable from inside the AA* stimulus functions (via
% playAndLogTrial) without threading arguments through every one of them.
%
% Everything here is BEST-EFFORT: with nothing attached every call is a fast no-op, and a
% listener that errors is dropped rather than allowed to take the session down. Progress
% reporting must never be able to break an experiment.
%
% Plan struct ('begin'), all optional:
%   .cellName .totalEpochs .nBlocks .triggerAcq .seedBase
%   .timings  struct(settle, preStim, postStim, itp)
%   .leds     struct(enabled, mode, port, intensity 4x3)
%   .blocks   struct array(label, stimName, epochs, params)
%
% State struct ('report'), all optional -- send what you know:
%   .epoch .totalEpochs .block .nBlocks .epochInBlock .epochsInBlock .label .stimName .seed
%   .phase        'settle' | 'trigger' | 'prestim' | 'presenting' | 'poststim' | 'itp' |
%                 'blockdone' | 'starting'
%   .phaseElapsed .phaseTotal    seconds within the current phase
%   .stim         struct of the stimulus's own numbers (frames, refresh, flicker Hz, ...)

    persistent reportFcn cancelFcn

    varargout = {};
    switch lower(char(action))
        case 'attach'
            reportFcn = local_asHandle(varargin, 1);
            cancelFcn = local_asHandle(varargin, 2);

        case 'detach'
            reportFcn = [];
            cancelFcn = [];

        case 'isattached'
            varargout{1} = ~isempty(reportFcn);

        case {'preview', 'begin', 'report', 'finish', 'failed'}
            if isempty(reportFcn), return; end
            msg = struct();
            if ~isempty(varargin) && isstruct(varargin{1}), msg = varargin{1}; end
            try
                reportFcn(lower(char(action)), msg);
            catch
                reportFcn = [];   % a broken listener is dropped, never propagated
            end

        case 'requestcancel'
            if isempty(cancelFcn), return; end
            try
                cancelFcn();
            catch
                cancelFcn = [];
            end

        otherwise
            error('stimProgress:badAction', 'Unknown action "%s".', char(action));
    end
end


function fn = local_asHandle(args, k)
    fn = [];
    if numel(args) >= k && isa(args{k}, 'function_handle'), fn = args{k}; end
end
