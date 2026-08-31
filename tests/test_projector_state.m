function test_projector_state()
% lcProjectorState: cache semantics, regime mapping, and the no-hardware guarantees.
% Hermetic -- no projector, no Python, no config writes.
    cleanup = onCleanup(@() lcProjectorState('clear')); %#ok<NASGU>
    lcProjectorState('clear');

    % ---- empty cache: default struct, never hardware ----
    s = lcProjectorState('get', 'stim');
    assert(~s.known && ~s.reachable && ~s.linear && isnan(s.gamma) && ...
           strcmp(s.source, 'none'), 'empty cache returns the default struct');
    assert(strcmp(lcProjectorState('regime'), 'degamma'), ...
           'unknown state maps to degamma (today''s LUT behavior)');

    % ---- assume/get round trip, per role ----
    lcProjectorState('assume', 'stim', ...
        struct('reachable', true, 'linear', true, 'mode', 'video', 'gamma', 0));
    s = lcProjectorState('get', 'stim');
    assert(s.known && s.reachable && s.linear && strcmp(s.mode, 'video') && ...
           strcmp(s.source, 'assume'), 'assume populates the role');
    m = lcProjectorState('get', 'monitor');
    assert(~m.known, 'roles are independent: monitor is still unknown');
    assert(strcmp(lcProjectorState('regime'), 'linear'), ...
           'verified linear + video maps to the linear regime');

    % ---- every doubt maps back to degamma ----
    lcProjectorState('assume', 'stim', ...
        struct('reachable', true, 'linear', true, 'mode', 'pattern'));
    assert(strcmp(lcProjectorState('regime'), 'degamma'), 'pattern mode -> degamma');
    lcProjectorState('assume', 'stim', ...
        struct('reachable', false, 'linear', true, 'mode', 'video'));
    assert(strcmp(lcProjectorState('regime'), 'degamma'), 'unreachable -> degamma');
    lcProjectorState('assume', 'stim', ...
        struct('reachable', true, 'linear', false, 'mode', 'video'));
    assert(strcmp(lcProjectorState('regime'), 'degamma'), 'not linear -> degamma');

    % ---- clear: one role, then all ----
    lcProjectorState('assume', 'stim', struct('linear', true));
    lcProjectorState('assume', 'monitor', struct('linear', true));
    lcProjectorState('clear', 'stim');
    assert(~lcProjectorState('get', 'stim').known, 'per-role clear wipes that role');
    assert(lcProjectorState('get', 'monitor').known, '...and only that role');
    lcProjectorState('clear');
    assert(~lcProjectorState('get', 'monitor').known, 'bare clear wipes everything');

    % ---- hardware paths refuse to run unconfigured (proves no accidental I/O) ----
    err = [];
    try
        lcProjectorState('refresh', 'stim');
    catch err
    end
    assert(~isempty(err) && strcmp(err.identifier, 'lcProjectorState:notConfigured'), ...
        'refresh without lc_projectors config must throw notConfigured, not touch hardware');

    % ---- input validation ----
    err = [];
    try
        lcProjectorState('get');
    catch err
    end
    assert(~isempty(err) && strcmp(err.identifier, 'lcProjectorState:badRole'), ...
        'a role is required');
    err = [];
    try
        lcProjectorState('bogus', 'stim');
    catch err
    end
    assert(~isempty(err) && strcmp(err.identifier, 'lcProjectorState:badAction'), ...
        'unknown actions are rejected');

    fprintf('[projector state test] all PASS\n');
end
