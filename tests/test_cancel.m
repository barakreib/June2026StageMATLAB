function test_cancel()
% Headless check of runExperiment's cancel hook: no Stage server, no Clampex, no LEDs.
    presented = {};
    stim = @(varargin) local_record(varargin);
    function local_record(a)
        presented{end+1} = a; %#ok<AGROW>
    end

    base = struct('preStim', 0, 'postStim', 0, 'itp', 0.2, 'settle', 0.2, ...
                  'triggerAcq', false, 'preflight', false, 'seedBase', 10);

    % ---- 1. no cancel hook at all: unchanged behaviour, status still returned ----
    proto = struct('stim', {stim, stim}, 'args', {{[], 1}, {[], 2}}, ...
                   'epochs', {3, 2}, 'label', {'A', 'B'}, 'seedArg', {1, 1});
    presented = {};
    st = runExperiment(proto, base);
    assert(~st.cancelled && st.epochs == 5 && st.blocks == 2, 'no hook: all 5 epochs run');
    seeds = cellfun(@(a) a{1}, presented);
    assert(isequal(seeds, 10:14), 'no hook: seeds still advance 10..14 across blocks');

    % ---- 2. cancel BEFORE the first epoch: nothing is triggered, hook never fires ----
    o = base; o.isCancelled = @() true;
    o.onProtocolComplete = @(varargin) error('the completion hook must not fire with zero epochs');
    presented = {};
    st = runExperiment(proto, o);
    assert(st.cancelled && st.epochs == 0 && isempty(presented), 'cancel before epoch 1 presents nothing');

    % ---- 3. cancel mid-run: the current epoch completes, later blocks are skipped ----
    n = 0;
    o = base;
    o.isCancelled = @local_stop;               % nested handle: sees the LIVE n (see note below)
    hookCalls = {};
    o.onProtocolComplete = @(nb, ne, cn) local_hook(nb, ne, cn);
    function cn2 = local_hook(nb, ne, cn)
        hookCalls{end+1} = struct('nBlocks', nb, 'nEpochs', ne); %#ok<AGROW>
        cn2 = cn;
    end
    presented = {};
    countingStim = @(varargin) local_count(varargin);
    function local_count(a)
        presented{end+1} = a; %#ok<AGROW>
        n = n + 1;
    end
    function tf = local_stop()
        tf = n >= 2;   % true once 2 epochs have been presented
    end
    proto2 = struct('stim', {countingStim, countingStim}, 'args', {{[], 1}, {[], 2}}, ...
                    'epochs', {3, 2}, 'label', {'A', 'B'}, 'seedArg', {1, 1});
    st = runExperiment(proto2, o);
    assert(st.cancelled, 'mid-run cancel reports cancelled');
    assert(st.epochs == 2 && numel(presented) == 2, ...
        sprintf('the in-flight epoch finished, then it stopped (got %d)', st.epochs));
    assert(isscalar(hookCalls) && hookCalls{1}.nBlocks == 1 && hookCalls{1}.nEpochs == 2, ...
        'the Keep/Discard hook fired once, covering the partly-run protocol');
    seeds = cellfun(@(a) a{1}, presented);
    assert(isequal(seeds, [10 11]), 'a cancelled epoch consumes no seed');

    % ---- 4. a cancel hook that throws must not take the session down ----
    o = base; o.isCancelled = @() error('boom');
    presented = {};
    st = runExperiment(proto, o);
    assert(~st.cancelled && st.epochs == 5, 'a broken cancel hook is ignored, the run completes');

    % ---- 5. the cancellable wait keeps plain-pause timing ----
    o = base; o.itp = 1; o.settle = 0; o.isCancelled = @() false;
    p1 = struct('stim', {@(varargin) []}, 'args', {{}}, 'epochs', {2}, 'label', {'t'}, 'seedArg', {0});
    t = tic; runExperiment(p1, o); el = toc(t);
    assert(el > 1.9 && el < 2.6, sprintf('2 x 1 s inter-trial waits took %.2f s', el));

    fprintf('[cancel test] all PASS\n');
end
