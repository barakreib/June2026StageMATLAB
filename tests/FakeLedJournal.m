classdef FakeLedJournal < handle
% The record a FakeLedRig writes into. A separate handle so the log SURVIVES the rig's
% destruction -- runExperiment's teardown delete()s the rig, and a deleted handle's
% properties are unreadable, which is exactly the moment a test wants to assert "it was
% darkened before it closed".
    properties
        sets   = struct('led', {}, 'chan', {}, 'v', {})   % every setIntensity, in order
        modes  = []                                       % every setMode, in order
        closed = false
    end
end
