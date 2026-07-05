function host = stageHost()
% stageHost  The Stage/OpenGL server address for client.connect(), from rig_config.json.
%
%   host = stageHost()
%
%   Returns the ``stage_host`` field of rig_config.json, or 'localhost' if it is unset,
%   empty, or literally 'local'/'localhost'. The stimulus scripts and runExperiment call
%   ``client.connect(stageHost())``:
%     * stage_host = "localhost" (default) -> a plain local connection, identical to the
%       old bare ``client.connect()``;
%     * stage_host = "192.168.0.49" (an IPv4) -> connects to the Stage server on THAT
%       computer.
%
%   Set it ONCE in rig_config.json (or the GUI's "Stage host" field) instead of
%   commenting/uncommenting the connect line in every stimulus. After editing the file by
%   hand, run ``clear loadRigConfig`` (the GUI / setRigConfig do this for you).

    host = strtrim(char(loadRigConfig('stage_host', 'localhost')));
    if isempty(host) || any(strcmpi(host, {'local', 'localhost'}))
        host = 'localhost';
    end
end
