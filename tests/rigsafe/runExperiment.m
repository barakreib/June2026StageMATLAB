function status = runExperiment(protocol, opts)
% RIG-SAFE STUB. Shadows the real runExperiment so a GUI test can press "Run experiment"
% without any chance of reaching the Stage server, the LED driver or Clampex.
    global RIGSAFE_CALLS RIGSAFE_SAMPLER RIGSAFE_THROW %#ok<GVMIS>
    if isempty(RIGSAFE_CALLS), RIGSAFE_CALLS = {}; end
    RIGSAFE_CALLS{end+1} = struct('protocol', protocol, 'opts', opts);
    if ~isempty(RIGSAFE_SAMPLER), RIGSAFE_SAMPLER(); end
    if ~isempty(RIGSAFE_THROW) && RIGSAFE_THROW
        error('runExperiment:serverSilent', ...
            ['Stage server at 192.168.0.51:5678 accepted the connection but did not answer ' ...
             'within 10 s.']);
    end
    status = struct('cancelled', false, 'epochs', 0, 'blocks', numel(protocol));
end
