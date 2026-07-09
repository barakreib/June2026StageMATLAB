function triggerAcquisition(~)
% triggerAcquisition  Start one Clampex acquisition epoch via its sequencing key.
%
%   triggerAcquisition()      - focus Clampex, then send Ctrl+Shift+1
%   triggerAcquisition(any)   - the argument is ignored (kept so existing callers
%                               like runExperiment(...) can still pass a flag).
%
%   Sends the SAME keystroke Experimenter5000_v2 used -- Ctrl+Shift+1, the Clampex
%   sequencing key -- but FIRST explicitly brings the Clampex window to the
%   foreground by process name. This is the fix for "the GUI doesn't trigger
%   Clampex": Experimenter5000_v2 ran from the MATLAB command window (Clampex was
%   the previous window, so a bare Alt+Tab reached it), but stimulusGUI is its own
%   app window -- from there Alt+Tab lands on MATLAB or the app itself, so the
%   keystroke never got to Clampex. Activating Clampex explicitly works from
%   either caller. Windows-only (.NET System.Windows.Forms + Microsoft.VisualBasic).
%
%   NOTE: still fire-and-forget -- it cannot confirm acquisition started or learn
%   the .abf filename; that is why the manifest is paired to .abf files by trial
%   order downstream.

    NET.addAssembly('System.Windows.Forms');

    % Explicitly focus Clampex (robust when called from the GUI). Fall back to the
    % old Alt+Tab only if no Clampex process is found, so odd setups still behave
    % as before.
    activated = false;
    try
        procs = System.Diagnostics.Process.GetProcessesByName('Clampex');
        if procs.Length > 0
            NET.addAssembly('Microsoft.VisualBasic');
            Microsoft.VisualBasic.Interaction.AppActivate(procs(1).Id);   % by PID
            activated = true;
            pause(0.05);   % let the window come to the foreground before typing
        end
    catch
        activated = false;   % assembly/activation failed -> use the fallback below
    end
    if ~activated
        System.Windows.Forms.SendKeys.SendWait('%{TAB}');   % fallback: Alt+Tab
        pause(0.05);
    end

    System.Windows.Forms.SendKeys.SendWait('^+{1}');   % Ctrl+Shift+1 -> start epoch
end
