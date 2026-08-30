function h = stageHost()
% TEST SHADOW of the repo's stageHost.m (runTests addpath's tests/ AFTER the repo, and
% addpath prepends, so this file wins while the suite runs).
%
% RIG SAFETY NET: no test may ever open a real Stage connection -- every test injects a
% FakeStageClient via stageClientShared('set') -- but if a bug ever slips a real
% StageClient construction through, this sends its connect to localhost (instant refusal)
% instead of the LIVE rig that rig_config.json's stage_host points at.
    h = '127.0.0.1';
end
