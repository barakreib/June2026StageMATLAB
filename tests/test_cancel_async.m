function test_cancel_async()
% The real mechanism: a callback that fires WHILE runExperiment is blocking in a wait
% (same path as the Cancel button interrupting the Run button's callback) must be seen.
    cancelRequested = false;
    fired = false;

    % stands in for the Cancel button press, ~1.2 s into the run
    t = timer('StartDelay', 1.2, 'TimerFcn', @(~,~) pressCancel());
    c = onCleanup(@() delete(t));

    o = struct('preStim', 0, 'postStim', 0, 'itp', 2, 'settle', 0.5, ...
               'triggerAcq', false, 'preflight', false, 'seedBase', 1);
    o.isCancelled = @isCancelledNow;          % nested handle, as stimulusGUI now uses
    proto = struct('stim', {@(varargin) pause(0.1)}, 'args', {{}}, ...
                   'epochs', {6}, 'label', {'async'}, 'seedArg', {0});

    start(t);
    tic; st = runExperiment(proto, o); el = toc;

    assert(fired, 'the stand-in Cancel callback actually ran');
    assert(st.cancelled, 'a callback firing mid-wait cancelled the run');
    assert(st.epochs >= 1 && st.epochs <= 2, ...
        sprintf('it stopped at the next epoch boundary, not at the end (ran %d of 6)', st.epochs));
    assert(el < 6, sprintf('it returned early (%.1f s, vs ~15 s for all 6 epochs)', el));
    fprintf('[async cancel] stopped after %d of 6 epochs in %.1f s -- PASS\n', st.epochs, el);

    function pressCancel()
        cancelRequested = true;
        fired = true;
    end
    function tf = isCancelledNow()
        tf = cancelRequested;
    end
end
