function host = stageHost()
% stageHost  The Stage/OpenGL server address that client.connect() uses.
%
% The host is set in ONE place -- rig_config.json's "stage_host" -- which you change
% either through the GUI "Stage host (IPv4)" field (it saves on Run) or by editing the
% file. This function only READS it; do NOT hard-code an address here (that would
% silently override the GUI/rig_config).
%
%   "stage_host": "192.168.0.51"        -> connect to the Stage server on THAT computer
%   "stage_host": "localhost" (or "")   -> connect to a server on THIS machine
%                                          (exactly what the old bare client.connect() did)
%
% After editing rig_config.json by hand, run:  clear loadRigConfig  (the GUI does this).

    host = strtrim(char(loadRigConfig('stage_host', 'localhost')));
    if isempty(host) || any(strcmpi(host, {'local', 'localhost'}))
        host = 'localhost';
    end
end
