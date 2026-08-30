function out = stageClientShared(action, arg)
% stageClientShared  ONE Stage client per MATLAB session, shared by everything in a run.
%
%   client = stageClientShared('get')      connected client (connects on first use)
%   client = stageClientShared('peek')     current client, [] if none -- never connects
%   stageClientShared('set', clientOrEmpty)  install a client (test seam / adopt), or
%                                            [] to forget one WITHOUT disconnecting it
%   stageClientShared('release')           disconnect (best-effort) + forget
%
% WHY: the Stage server is SINGLE-client. The old AA* scripts each constructed and
% connected their own StageClient per epoch, so every epoch paid a fresh TCP connect and
% two clients could never coexist (an inter-epoch background setter would fight the
% stimulus for the one server slot). Generated stimulus scripts and the inter-epoch /
% end-of-run background screens (stageHoldScreen) all draw on this one shared client
% instead. runExperiment releases it at the end of a run so standalone scripts (and the
% next run's pre-flight) find the server free.
%
% 'get' validates a held client via isConnected and reconnects a dead one. A test double
% without an isConnected property is trusted as-is.

    persistent client

    if nargin < 1, action = 'get'; end
    out = [];
    switch action
        case 'get'
            if isempty(client) || ~local_usable(client)
                c = stage.core.network.StageClient();
                c.connect(stageHost());
                client = c;
            end
            out = client;
        case 'peek'
            out = client;
        case 'set'
            client = arg;
        case 'release'
            if ~isempty(client)
                try
                    client.disconnect();
                catch
                end
            end
            client = [];
        otherwise
            error('stageClientShared:badAction', 'Unknown action "%s".', char(string(action)));
    end
end


function tf = local_usable(c)
% A held client is reused only if it still says it is connected. Anything that cannot
% answer (a fake without the property) is treated as usable -- tests install those.
    try
        tf = logical(c.isConnected);
    catch
        tf = true;
    end
end
