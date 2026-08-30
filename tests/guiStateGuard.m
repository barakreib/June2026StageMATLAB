function guard = guiStateGuard()
% Protect the USER's saved stimulusGUI session while a test runs.
% stimulusGUI persists its last session to prefdir, which is the real MATLAB preferences
% directory -- earlier tests simply deleted it, which threw away the user's restored state.
% This moves it aside and puts it back on any exit.
    p   = fullfile(prefdir, 'neitzStimulusGUI_lastSession.json');
    bak = [p '.testbak'];
    if exist(p, 'file'), movefile(p, bak, 'f'); end
    guard = onCleanup(@() restore(p, bak));
end

function restore(p, bak)
    if exist(p, 'file'), delete(p); end
    if exist(bak, 'file'), movefile(bak, p, 'f'); end
end
