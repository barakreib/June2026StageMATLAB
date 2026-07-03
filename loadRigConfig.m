function val = loadRigConfig(key, default)
% loadRigConfig  Read the rig's hardware/calibration state from rig_config.json.
%
%   cfg = loadRigConfig()                -> the whole config struct
%   val = loadRigConfig(key, default)    -> cfg.(key), or `default` if absent
%
%   rig_config.json is the single source of truth for the rig gamma, projector mode,
%   and the projector-channel -> external-LED mapping. It lives next to this file (the
%   repo) and travels with the data via the stimulus manifest, so the Analysis Suite
%   knows the exact hardware state that produced each recording.
%
%   The file is read once and CACHED (persistent). After editing rig_config.json,
%   run `clear loadRigConfig` to force a reload. If the file is missing or a key is
%   absent, the supplied `default` is returned (so stimuli still run un-configured).

    persistent cfg
    if isempty(cfg)
        p = fullfile(fileparts(mfilename('fullpath')), 'rig_config.json');
        if exist(p, 'file')
            cfg = jsondecode(fileread(p));
        else
            cfg = struct();     % no config yet -> callers fall back to their defaults
        end
    end

    if nargin == 0
        val = cfg;
        return;
    end
    if isstruct(cfg) && isfield(cfg, key)
        val = cfg.(key);
    else
        val = default;
    end
end
