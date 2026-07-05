function setRigConfig(key, value)
% setRigConfig  Persist one key into rig_config.json and drop the loadRigConfig cache.
%
%   setRigConfig('stage_host', '192.168.0.49')
%
%   Reads rig_config.json (next to this file), sets cfg.(key) = value, writes it back
%   pretty-printed, and clears the loadRigConfig cache so the next read sees the new value.
%   Used by the GUI to save the Stage host; you can also just edit rig_config.json by hand
%   and run ``clear loadRigConfig``.

    p = fullfile(fileparts(mfilename('fullpath')), 'rig_config.json');
    if exist(p, 'file')
        cfg = jsondecode(fileread(p));
    else
        cfg = struct();
    end
    cfg.(key) = value;

    fid = fopen(p, 'w');
    if fid < 0, error('setRigConfig:cannotWrite', 'Cannot write %s', p); end
    fwrite(fid, jsonencode(cfg, 'PrettyPrint', true), 'char');
    fclose(fid);

    clear('loadRigConfig');   % drop the persistent cache so the next read re-parses the file
end
