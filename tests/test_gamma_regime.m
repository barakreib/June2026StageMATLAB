function test_gamma_regime()
% lcGammaCorrect's regime branch: LUT behavior is bit-for-bit unchanged with no
% projector knowledge, identity when the stim projector is verified linear, and
% back again after a clear. Hermetic -- reads rig_config, never writes it.
    cleanup = onCleanup(@() lcProjectorState('clear')); %#ok<NASGU>
    lcProjectorState('clear');

    x = [0 1/255 0.03 0.25 0.5 0.75 0.99 1];

    % ---- regression pin: empty cache == today's measured-LUT behavior ----
    codes = loadRigConfig('dlp_lut_codes', []);
    Rn    = loadRigConfig('dlp_lut_output_norm', []);
    assert(~isempty(codes) && ~isempty(Rn), 'this repo config carries the measured LUT');
    expected = reshape(interp1(Rn(:), codes(:) / 255, x(:), 'pchip'), size(x));
    assert(isequal(lcGammaCorrect(x), expected), ...
        'with no projector knowledge the LUT path is byte-identical to before');

    % ---- verified linear: identity, including the clamp and both endpoints ----
    lcProjectorState('assume', 'stim', ...
        struct('reachable', true, 'linear', true, 'mode', 'video', 'gamma', 0));
    assert(isequal(lcGammaCorrect(x), x), 'linear regime passes values through');
    assert(isequal(lcGammaCorrect([-0.5 0 0.25 1 2]), [0 0 0.25 1 1]), ...
        'the [0,1] clamp still applies in the linear regime');
    M = rand(4, 3, 2);
    assert(isequal(lcGammaCorrect(M), M), 'any shape passes through unchanged');

    % ---- doubt restores the LUT ----
    lcProjectorState('clear');
    assert(isequal(lcGammaCorrect(x), expected), 'after clear the LUT path is back');
    lcProjectorState('assume', 'stim', ...
        struct('reachable', true, 'linear', true, 'mode', 'pattern'));
    assert(isequal(lcGammaCorrect(x), expected), 'pattern mode is not the linear regime');

    fprintf('[gamma regime test] all PASS\n');
end
