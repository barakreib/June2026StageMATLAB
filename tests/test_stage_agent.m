function test_stage_agent()
% lcProjectorState's 'stage-agent' transport against a canned localhost TCP
% server standing in for lcr_agent.py. Loopback only, ephemeral port -- never
% goes near the Stage server or its 5677/5678 block. No hardware, no Python.
    cleanup = onCleanup(@() lcProjectorState('clear')); %#ok<NASGU>
    lcProjectorState('clear');

    rs = RandStream('mt19937ar', 'Seed', 'shuffle');

    % tcpserver ships with the Instrument Control Toolbox (tcpclient is base
    % MATLAB). Without it the fake-agent scenarios cannot run -- still prove
    % the no-listener path, which only needs tcpclient.
    if isempty(which('tcpserver'))
        local_deadPortScenario(randi(rs, [40000 65000]));
        fprintf(['[stage agent test] PASS (fake-server scenarios SKIPPED: no ' ...
                 'tcpserver / Instrument Control Toolbox on this MATLAB)\n']);
        return;
    end

    resp = '';          % what the fake agent answers; set per scenario
    reqs = {};          % request lines the fake agent received
    % tcpserver refuses port 0 (no ephemeral auto-assign) -- probe for a free
    % high port. Loopback only; nowhere near Stage's 5676-5678 block.
    srv = [];
    for attempt = 1:20
        try
            srv = tcpserver('127.0.0.1', randi(rs, [20000 65000]));
            break;
        catch
        end
    end
    assert(~isempty(srv), 'could not bind a loopback port for the fake agent');
    srvCleanup = onCleanup(@() delete(srv)); %#ok<NASGU>
    configureCallback(srv, 'terminator', @(sck, ~) onRequest(sck));
    function onRequest(sck)
        reqs{end+1} = char(readline(sck)); %#ok<AGROW>
        write(sck, unicode2native(resp, 'UTF-8'));
    end
    base = struct('transport', 'stage-agent', 'host', '127.0.0.1', ...
                  'port', srv.ServerPort, 'device', 'STIMPATH', 'timeout', 10);

    % ---- ensure, agent says linear ----
    resp = sprintf('LCR4500 GAMMA=0x00 LINEAR=1 CHANGED=1 MODE=video\nEXIT=0\n');
    s = lcProjectorState('ensure', 'stim', base);
    assert(s.known && s.reachable && s.linear && s.changed && ...
           strcmp(s.mode, 'video') && s.gamma == 0, 'EXIT=0 maps to verified linear');
    assert(strcmp(lcProjectorState('regime'), 'linear'), 'regime follows the agent verdict');
    assert(strcmp(strtrim(reqs{end}), 'ensure --device STIMPATH'), ...
        'the request carries the command and the device selector');

    pause(0.4);   % let the single-client fake server free the last connection
    % ---- refresh (read-only query), agent says de-gamma on ----
    resp = sprintf('LCR4500 GAMMA=0x80 LINEAR=0 CHANGED=0 MODE=video\nEXIT=1\n');
    s = lcProjectorState('refresh', 'stim', base);
    assert(s.known && s.reachable && ~s.linear && s.gamma == 128, ...
        'EXIT=1 maps to reachable, not linear');
    assert(strcmp(lcProjectorState('regime'), 'degamma'), 'regime falls back to degamma');
    assert(strcmp(strtrim(reqs{end}), 'query --device STIMPATH'), 'refresh sends query');

    pause(0.4);   % let the single-client fake server free the last connection
    % ---- agent reports the projector unreachable ----
    resp = sprintf('LCR4500 GAMMA=?? LINEAR=0 CHANGED=0 MODE=?\nEXIT=2\n');
    s = lcProjectorState('refresh', 'stim', base);
    assert(s.known && ~s.reachable, 'EXIT=2 maps to unreachable');

    pause(0.4);   % let the single-client fake server free the last connection
    % ---- agent refuses the request: toolkit-level error, thrown ----
    resp = sprintf('agent: unknown command\nEXIT=3\n');
    err = [];
    try
        lcProjectorState('refresh', 'stim', base);
    catch err
    end
    assert(~isempty(err) && strcmp(err.identifier, 'lcProjectorState:agent'), ...
        'EXIT=3 is a config/toolkit bug and must throw');

    pause(0.4);   % let the single-client fake server free the last connection
    % ---- nobody listening: recorded unreachable, no throw ----
    deadPort = srv.ServerPort;
    delete(srv);                        % free the port, then talk to it
    local_deadPortScenario(deadPort);

    fprintf('[stage agent test] all PASS\n');
end


function local_deadPortScenario(port)
% Connecting where no agent listens must record unreachable, never throw.
    s = lcProjectorState('ensure', 'stim', struct('transport', 'stage-agent', ...
        'host', '127.0.0.1', 'port', port, 'device', 'STIMPATH', 'timeout', 10));
    assert(s.known && ~s.reachable, 'refused connection = unreachable, not an error');
end
