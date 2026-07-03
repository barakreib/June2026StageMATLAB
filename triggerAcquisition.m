function triggerAcquisition(bringToFront)
% triggerAcquisition  Start one Clampex acquisition epoch via its sequencing key.
%
%   triggerAcquisition()       - send Ctrl+Shift+1 (the Clampex sequencing key)
%   triggerAcquisition(true)   - Alt+Tab to bring Clampex to the front first
%
%   This is the SendKeys trigger from Experimenter5000, factored out so runExperiment
%   can call it -- and so it can later be swapped for a proper acquisition-control
%   bridge (one that also STOPS by epoch count and captures the .abf filename) WITHOUT
%   touching the orchestrator. Windows-only (uses .NET System.Windows.Forms).
%
%   NOTE: this fires acquisition but cannot confirm it started or learn the .abf name;
%   that limitation is why the stimulus manifest is paired to .abf files by trial order.

    if nargin < 1, bringToFront = false; end
    NET.addAssembly('System.Windows.Forms');
    if bringToFront
        System.Windows.Forms.SendKeys.SendWait('%{TAB}');   % Alt+Tab -> Clampex to front
        pause(0.01);
    end
    System.Windows.Forms.SendKeys.SendWait('^+{1}');          % Ctrl+Shift+1 -> start epoch
end
