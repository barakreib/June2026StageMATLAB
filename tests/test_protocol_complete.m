function test_protocol_complete()
% REGRESSION: "if epochs have different parameters, the 'stimulus protocol complete' message
% comes up between epochs. It should not do that ... the message only should be presented at
% the end."
%
% Per-epoch parameters mean several blocks. The run must go straight through them and ask
% ONCE, at the end -- while every epoch still records its own parameters.
    presented = {};
    calls     = {};
    n         = 0;      % epochs presented so far (the nested stim shares this)
    o = struct('preStim', 0, 'postStim', 0, 'itp', 0.05, 'settle', 0.05, ...
               'triggerAcq', false, 'preflight', false, 'seedBase', 10);
    o.onProtocolComplete = @(nb, ne, cn) local_note(nb, ne, cn);

    % 5 epochs, sigma alternating -> 5 separate blocks (exactly what "Update selected" makes)
    sig  = [0.3 0.9 0.3 0.9 0.3];
    stim = @(seed, sg) local_record(seed, sg);
    proto = struct('stim', {}, 'args', {}, 'epochs', {}, 'label', {}, 'seedArg', {});
    for k = 1:numel(sig)
        proto(k) = struct('stim', stim, 'args', {{[], sig(k)}}, 'epochs', 1, ...
                          'label', sprintf('b%d', k), 'seedArg', 1);
    end

    st = runExperiment(proto, o);
    assert(st.epochs == 5 && st.blocks == 5, '5 epochs across 5 parameter blocks');
    assert(isscalar(calls), sprintf(['the protocol-complete hook fired ONCE, not per block ' ...
        '(fired %d times)'], numel(calls)));
    c = calls{1};
    assert(c.nBlocks == 5 && c.nEpochs == 5, ...
        sprintf('it is told the whole run: %d block(s), %d epoch(s)', c.nBlocks, c.nEpochs));

    % every epoch kept its own parameters, and the seeds still advance across blocks
    got = cellfun(@(p) p.sigma, presented);
    assert(isequal(got, sig), 'each epoch ran with its OWN sigma');
    seeds = cellfun(@(p) p.seed, presented);
    assert(isequal(seeds, 10:14), 'seeds still advance 10..14 across the block boundaries');

    % ---- a run cancelled partway still gets exactly one prompt, sized to what ran ----
    calls = {}; presented = {}; n = 0;
    o2 = o; o2.isCancelled = @local_stop;   % nested, not @() n>=2: an anonymous handle
                                            % would capture n BY VALUE and never fire
    st2 = runExperiment(proto, o2);
    assert(st2.cancelled && st2.epochs == 2, 'stopped after 2 epochs');
    assert(isscalar(calls) && calls{1}.nBlocks == 2 && calls{1}.nEpochs == 2, ...
        'one prompt, covering only the 2 blocks that actually recorded epochs');

    % ---- a single-block protocol still gets exactly one prompt ----
    calls = {}; presented = {};
    p1 = struct('stim', {stim}, 'args', {{[], 0.3}}, 'epochs', {3}, 'label', {'one'}, 'seedArg', {1});
    runExperiment(p1, o);
    assert(isscalar(calls) && calls{1}.nBlocks == 1 && calls{1}.nEpochs == 3, ...
        'one block, one prompt, 3 epochs');

    % ---- no hook at all (Experimenter5000, a dry run) is still fine ----
    o3 = rmfield(o, 'onProtocolComplete');
    calls = {};
    runExperiment(p1, o3);
    assert(isempty(calls), 'no hook -> nothing fires');

    fprintf('[protocol complete] one prompt per RUN, not per block -- PASS\n');

    function local_record(seed, sg)
        presented{end+1} = struct('seed', seed, 'sigma', sg); %#ok<AGROW>
        n = n + 1;
    end
    function tf = local_stop()
        tf = n >= 2;
    end
    function cn2 = local_note(nb, ne, cn)
        calls{end+1} = struct('nBlocks', nb, 'nEpochs', ne, 'cell', cn); %#ok<AGROW>
        cn2 = cn;
    end
end
