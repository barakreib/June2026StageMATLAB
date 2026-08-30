function mon = stimulusMonitor(parentFig)
% stimulusMonitor  Live read-out of a running session: where the run is, what is on the
% screen, what the LEDs are doing, and a timeline of the whole experiment filling in.
%
%   mon = stimulusMonitor()           opens the window; returns a handle struct with
%   mon = stimulusMonitor(parentFig)  .fig, .update(kind, msg) and .close().
%
% It draws whatever stimProgress publishes -- runExperiment sends the plan and the epoch /
% phase transitions, playAndLogTrial sends the presentation's own progress and the
% stimulus's frequencies. stimulusGUI attaches it on Run and detaches it at the end.
%
% The timeline is drawn ONCE from the plan (one phase-coloured segment per epoch across the
% whole session) and afterwards only a "now" marker and a completed-so-far overlay move --
% so ticking at 20 Hz through a presentation stays cheap. Nothing here can affect the
% experiment: every update is best-effort and a closed window simply stops drawing.
%
% Cancel here is the same Cancel as the GUI's (routed through stimProgress), so the run can
% be stopped from whichever window is in front.

    if nargin < 1, parentFig = []; end
    h = struct();                 % handles, shared with the nested callbacks
    S = struct();                 % live state, ditto
    S.plan     = [];
    S.state    = local_emptyState();
    S.segs     = [];              % per-epoch timeline segments (cumulative seconds)
    S.total    = 0;               % planned session length (s)
    S.tRun     = [];              % tic at 'begin'
    S.lastDraw = 0;               % throttle: seconds (from tRun) of the last redraw
    S.finished = false;
    S.durFixed = false;           % has the plan's estimated stimulus length been corrected?
    S.running  = false;           % a run is in flight (vs just previewing a protocol)
    S.prevPhase = '';             % phase of the previous report, for transition detection
    S.tPrev     = 0;              % elapsed at the previous report
    S.wrap      = local_meanAcc(); % measured presenting -> post-stim gap (telemetry + log)
    S.epochDur  = [];              % measured epoch-to-epoch lengths -- the ground truth
    S.prepPer   = [];              % measured setup time, per epoch
    S.tZero     = [];              % elapsed when the FIRST epoch started -- the timeline's origin
    S.lastEpoch = [];              % elapsed at the current epoch's first report

    buildUI();
    mon = struct('fig', h.fig, 'update', @update, 'close', @closeWin);

    % ---------------------------------------------------------------- UI
    function buildUI()
        h.fig = uifigure('Name', 'Session monitor', 'Position', local_place(parentFig, 620, 930), ...
            'CloseRequestFcn', @(s, e) closeWin());
        g = uigridlayout(h.fig, [8 1]);
        % The two tables are FIXED at exactly their content -- 8 stimulus rows and 4 LEDs --
        % so nothing you need mid-experiment ends up behind a scrollbar. Only the timeline
        % flexes.
        g.RowHeight  = {58, 46, 30, 226, '1x', 182, 82, 38};
        g.RowSpacing = 6;

        % ---- headline: where we are ----
        hp = uipanel(g);
        hg = uigridlayout(hp, [2 1]); hg.RowHeight = {30, 20}; hg.Padding = [10 2 10 2]; hg.RowSpacing = 0;
        h.epochLbl = uilabel(hg, 'Text', 'Waiting for a run...', 'FontSize', 20, 'FontWeight', 'bold');
        h.blockLbl = uilabel(hg, 'Text', '', 'FontAngle', 'italic', 'FontColor', [0.45 0.45 0.45]);

        % ---- phase + its own clock ----
        pp2 = uigridlayout(g, [1 3]); pp2.ColumnWidth = {150, '1x', 190}; pp2.Padding = [10 2 10 2];
        h.phaseLbl = uilabel(pp2, 'Text', '-', 'FontSize', 16, 'FontWeight', 'bold');
        h.phaseBar = uilabel(pp2, 'Text', '', 'FontName', local_monoFont(), 'FontSize', 14);
        h.phaseClk = uilabel(pp2, 'Text', '', 'HorizontalAlignment', 'right', ...
            'FontName', local_monoFont(), 'FontSize', 14);

        % ---- session clock ----
        h.clockLbl = uilabel(g, 'Text', '', 'FontName', local_monoFont(), ...
            'FontColor', [0.30 0.30 0.30]);

        % ---- what is on the screen ----
        sp = uipanel(g, 'Title', 'Stimulus');
        sg = uigridlayout(sp, [1 1]); sg.Padding = [4 2 4 2];
        h.stimTbl = uitable(sg, 'ColumnName', {}, 'RowName', {}, ...
            'ColumnWidth', {180, '1x'}, 'Data', cell(0, 2));

        % ---- the whole session, filling in ----
        h.ax = uiaxes(g);
        title(h.ax, 'Session timeline');
        h.ax.XLabel.String = 'minutes';
        h.ax.YTick = [];
        h.ax.Box = 'on';
        h.ax.Toolbar.Visible = 'off';
        disableDefaultInteractivity(h.ax);

        % ---- LEDs ----
        lp = uipanel(g, 'Title', 'LEDs');
        lgd = uigridlayout(lp, [2 1]); lgd.RowHeight = {20, '1x'}; lgd.Padding = [6 2 6 2]; lgd.RowSpacing = 2;
        h.ledLbl  = uilabel(lgd, 'Text', 'not configured');
        h.ledTbl  = uitable(lgd, 'ColumnName', {'R', 'G', 'B'}, ...
            'RowName', {'LED 0', 'LED 1', 'LED 2', 'LED 3'}, 'Data', zeros(4, 3), ...
            'ColumnWidth', {58, 58, 58});

        % Wrapped: a pre-flight failure is several lines of remedy, and a clipped one-liner
        % ("Stage server at 192.168...") tells the operator nothing they can act on.
        h.noteLbl = uilabel(g, 'Text', '', 'FontAngle', 'italic', 'FontColor', [0.45 0.45 0.45], ...
            'WordWrap', 'on', 'VerticalAlignment', 'top');

        bp = uigridlayout(g, [1 2]); bp.ColumnWidth = {'1x', 150}; bp.Padding = [10 2 10 2];
        uilabel(bp, 'Text', '');
        h.cancelBtn = uibutton(bp, 'Text', 'Cancel run', 'ButtonPushedFcn', @(s, e) onCancel(), ...
            'BackgroundColor', [0.70 0.15 0.15], 'FontColor', 'w', 'FontWeight', 'bold', ...
            'Enable', 'off', 'BusyAction', 'queue', ...
            'Tooltip', ['Same Cancel as the main window: stops at the next clean epoch ' ...
                        'boundary, never mid-sweep.']);
    end

    function onCancel()
        h.cancelBtn.Enable = 'off';
        h.cancelBtn.Text   = 'Cancelling';
        h.noteLbl.Text     = 'Cancel requested -- stopping at the end of the current epoch.';
        h.noteLbl.FontColor = [0.85 0.45 0.10];
        stimProgress('requestCancel');
    end

    function closeWin()
        if ~isempty(h.fig) && isvalid(h.fig), delete(h.fig); end
    end

    % ------------------------------------------------------- the update sink
    function update(kind, msg)
        % Called from stimProgress on the same (only) thread as the run. Never let a
        % drawing error escape into the experiment.
        if isempty(h.fig) || ~isvalid(h.fig), return; end
        try
            switch kind
                case 'preview', onPreview(msg);
                case 'begin',  onBegin(msg);
                case 'report', onReport(msg);
                case 'finish', onFinish(msg);
                case 'failed', onFailed(msg);
            end
        catch
            % a monitor that cannot draw must not stop a session
        end
    end

    function onPreview(plan)
        % The protocol as it stands, not a run. Draw the planned timeline and say plainly
        % that nothing has started -- a live run must never be overwritten by a preview.
        if S.running, return; end
        S.plan     = plan;
        S.state    = local_emptyState();
        S.finished = false;
        S.tRun     = [];
        S.durFixed = false;
        [S.segs, S.total] = local_planSegments(plan);
        n = local_field(plan, 'totalEpochs', 0);
        h.cancelBtn.Enable   = 'off';
        h.noteLbl.Text       = '';
        h.noteLbl.FontColor  = [0.45 0.45 0.45];
        h.phaseLbl.Text      = 'not started';
        h.phaseLbl.FontColor = [0.40 0.40 0.45];
        h.phaseBar.Text      = '';
        h.phaseClk.Text      = '';
        h.stimTbl.Data       = cell(0, 2);
        if n < 1
            h.epochLbl.Text = 'No epochs yet';
            h.blockLbl.Text = 'Add a block in the main window to plan a session.';
        else
            h.epochLbl.Text = sprintf('%d epoch(s) planned', n);
            h.blockLbl.Text = local_headerLine(plan);
        end
        h.clockLbl.Text = sprintf('not started   |   planned total %s', local_hms(S.total));
        drawLeds(local_field(plan, 'leds', struct('enabled', false)));
        drawTimeline();
    end

    function onBegin(plan)
        S.plan     = plan;
        S.running  = true;
        S.state    = local_emptyState();
        S.finished = false;
        S.tRun      = tic;
        S.lastDraw  = -Inf;
        S.prevPhase = '';
        S.tPrev     = 0;
        S.wrap      = local_meanAcc();
        S.epochDur  = [];
        S.prepPer   = [];
        S.lastEpoch = [];
        S.tZero     = [];
        [S.segs, S.total] = local_planSegments(plan);
        h.cancelBtn.Enable  = 'on';
        h.cancelBtn.Text    = 'Cancel run';
        h.noteLbl.Text      = '';
        h.noteLbl.FontColor = [0.45 0.45 0.45];
        h.epochLbl.Text     = 'Starting run...';
        h.blockLbl.Text     = local_headerLine(plan);
        drawLeds(local_field(plan, 'leds', struct('enabled', false)));
        drawTimeline();
        redraw(true);
    end

    function onReport(msg)
        measureOverhead(msg);
        S.state = local_merge(S.state, msg);
        % The plan can only ESTIMATE the presentation length (stimFrames/refreshRate); the
        % stimuli append a few black frames. The first real presentation reports the true
        % duration, so redraw the timeline once against it and let it be accurate from then
        % on. Once only -- this must not run at the 20 Hz the presentation reports at.
        if ~S.durFixed && strcmp(local_field(msg, 'phase', ''), 'presenting')
            d = local_field(local_field(msg, 'stim', struct()), 'duration_s', NaN);
            if isfinite(d) && d > 0
                S.durFixed = true;
                if abs(d - local_planStimSeconds(S.plan)) > 0.25
                    S.plan = local_setStimSeconds(S.plan, d);
                    [S.segs, S.total] = local_planSegments(S.plan);
                    drawTimeline();
                end
            end
        end
        redraw(false);
    end

    function measureOverhead(msg)
        % The ground truth for the timeline is the EPOCH-TO-EPOCH wall time. Deriving the
        % overhead from that (rather than from the one gap we can name) absorbs every source
        % of drift at once -- stimulus setup, presentation upload, telemetry, the manifest
        % write, and whatever else an epoch spends time on -- so the modelled session length
        % cannot creep away from reality and strand the marker at the right-hand edge.
        el = local_runElapsed();

        e = local_field(msg, 'epoch', 0);
        if e > 0 && e ~= S.state.epoch
            if ~isempty(S.lastEpoch)
                S.epochDur(end + 1) = el - S.lastEpoch;
            end
            S.lastEpoch = el;
            % The timeline models EPOCHS, so epoch 1 is its origin. Everything before it --
            % the Stage pre-flight, opening the LED driver -- is setup, not session, and
            % counting it would push the marker ahead of the drawing for the whole run.
            if isempty(S.tZero), S.tZero = el; end
            reflowTimeline();
        end

        % `wrap` (last 'presenting' tick -> first 'poststim') is measured directly, so the
        % overhead is attributed to the right side of the presentation rather than all of it
        % being drawn before. Nothing reports during that gap, which is what makes it visible.
        ph = char(string(local_field(msg, 'phase', S.prevPhase)));
        if isempty(S.prevPhase)
            S.prevPhase = ph;
        elseif ~strcmp(ph, S.prevPhase)
            if strcmp(S.prevPhase, 'presenting') && strcmp(ph, 'poststim')
                S.wrap = local_meanPush(S.wrap, el - S.tPrev);
            elseif strcmp(S.prevPhase, 'prep') && strcmp(ph, 'presenting') && S.state.epoch > 0
                sizeSetupBand(S.state.epoch);
            end
            S.prevPhase = ph;
        end
        S.tPrev = el;
    end

    function sizeSetupBand(e)
        % The first frame is on the projector NOW, so this epoch's stimulus band must begin
        % exactly HERE. Rather than trusting a measured gap, size the setup band to whatever
        % makes that true -- which absorbs the acquisition trigger, the setup itself, and any
        % other unmodelled time in one step, and is what stops the marker resuming inside the
        % wrong segment after the pause.
        elT = local_timelineElapsed();
        S.prepPer(e)        = 0;                       % provisional: find where the epoch starts
        S.plan.prepPerEpoch = S.prepPer;
        st0  = local_epochStart(local_planSegments(S.plan), e);
        T    = local_field(S.plan, 'timings', struct());
        lead = local_field(T, 'settle', 1) + local_field(T, 'preStim', 2);
        S.prepPer(e)        = max(0, elT - st0 - lead);
        S.plan.prepPerEpoch = S.prepPer;
        [S.segs, S.total]   = local_planSegments(S.plan);
        S.total             = max(S.total, elT * 1.02);
        drawTimeline();
    end

    function reflowTimeline()
        % Redraw against what this session is ACTUALLY doing. Runs at an epoch boundary, not
        % at 20 Hz, so a full patch rebuild here is cheap.
        if isempty(S.epochDur), return; end
        wrap = local_meanGet(S.wrap, 0);
        est  = local_epochEstimate(S.epochDur);
        % ONLY the epochs that have actually finished go in here. Padding it out with the
        % estimate would make the measured-total branch of local_planSegments win for every
        % epoch, and the epoch in flight could never use its own measured setup time.
        S.plan.epochSeconds = S.epochDur(:)';
        S.plan.wrapSeconds  = wrap;
        S.plan.prepSeconds  = max(0, est - local_nominalEpoch(S.plan) - wrap);
        [S.segs, S.total]   = local_planSegments(S.plan);
        S.total             = max(S.total, local_timelineElapsed() * 1.02);   % never behind "now"
        drawTimeline();
    end

    function onFinish(msg)
        S.running = false;
        if S.finished, return; end
        S.finished    = true;
        S.state.phase = 'done';
        redraw(true);                 % settle the clocks + timeline marker FIRST: the
                                      % final phase text below must have the last word
        h.cancelBtn.Enable = 'off';
        h.cancelBtn.Text   = 'Cancel run';
        if local_field(msg, 'cancelled', false)
            h.phaseLbl.Text      = 'CANCELLED';
            h.phaseLbl.FontColor = [0.75 0.15 0.15];
            h.noteLbl.Text = sprintf('Cancelled after %d of %d epoch(s).', ...
                local_field(msg, 'epochs', 0), local_field(msg, 'totalEpochs', 0));
        else
            h.phaseLbl.Text      = 'FINISHED';
            h.phaseLbl.FontColor = [0.13 0.45 0.20];
            h.noteLbl.Text = 'Run complete.';
        end
        h.phaseBar.Text = '';
        h.phaseClk.Text = '';
    end

    function onFailed(msg)
        S.running = false;
        % The run died. Say so HERE as well as in the main window's dialog -- during a
        % pre-flight this is the window the operator is watching, and an alert behind it is
        % an alert nobody reads.
        S.finished           = true;
        h.cancelBtn.Enable   = 'off';
        h.epochLbl.Text      = 'RUN FAILED';
        h.phaseLbl.Text      = 'FAILED';
        h.phaseLbl.FontColor = [0.75 0.15 0.15];
        h.phaseBar.Text      = '';
        h.phaseClk.Text      = '';
        h.noteLbl.Text       = char(string(local_field(msg, 'message', 'unknown error')));
        h.noteLbl.FontColor  = [0.75 0.15 0.15];
        h.noteLbl.Tooltip    = h.noteLbl.Text;
    end

    % ------------------------------------------------------------- drawing
    function redraw(force)
        if isempty(h.fig) || ~isvalid(h.fig), return; end
        % Throttle to ~10 Hz: a presentation reports every 50 ms and the text is not worth
        % redrawing that often. Phase CHANGES always draw, so nothing looks stuck.
        el = local_runElapsed();
        if ~force && (el - S.lastDraw) < 0.1 && strcmp(S.state.phase, S.state.lastDrawnPhase)
            return;
        end
        S.lastDraw = el;
        S.state.lastDrawnPhase = S.state.phase;

        st = S.state;
        if st.epoch > 0
            h.epochLbl.Text = sprintf('Epoch %d of %d', st.epoch, max(st.totalEpochs, st.epoch));
            h.blockLbl.Text = sprintf('block %d of %d  (epoch %d of %d in this block)%s', ...
                st.block, st.nBlocks, st.epochInBlock, st.epochsInBlock, local_labelSuffix(st.label));
        end
        [nm, col]            = local_phaseFace(st.phase);
        h.phaseLbl.Text      = nm;
        h.phaseLbl.FontColor = col;
        if strcmp(st.phase, 'prep')
            h.phaseBar.Text = 'building + uploading';
            h.phaseClk.Text = '(no refresh until done)';
        elseif st.phaseTotal > 0
            h.phaseBar.Text = local_bar(st.phaseElapsed / st.phaseTotal, 18);
            h.phaseClk.Text = sprintf('%5.1f / %.1f s', min(st.phaseElapsed, st.phaseTotal), st.phaseTotal);
        elseif ~S.finished
            h.phaseBar.Text = '';
            h.phaseClk.Text = '';
        end
        elT = local_timelineElapsed();
        h.clockLbl.Text = sprintf('elapsed %s   |   planned total %s   |   remaining ~%s', ...
            local_hms(elT), local_hms(S.total), local_hms(max(0, S.total - elT)));
        h.stimTbl.Data = local_stimRows(st);
        moveNow(elT);
    end

    function drawTimeline()
        cla(h.ax);
        hold(h.ax, 'on');
        if isempty(S.segs)
            hold(h.ax, 'off');
            return;
        end
        for i = 1:numel(S.segs)
            sg = S.segs(i);
            patch(h.ax, 'XData', [sg.t0 sg.t1 sg.t1 sg.t0] / 60, 'YData', [0 0 1 1], ...
                'FaceColor', sg.color, 'EdgeColor', 'none');
        end
        % epoch boundaries, so you can count epochs on the plot
        for i = 1:numel(S.segs)
            if S.segs(i).isFirst
                xline(h.ax, S.segs(i).t0 / 60, '-', 'Color', [0.75 0.75 0.75], 'LineWidth', 0.5);
            end
        end
        h.doneP = patch(h.ax, 'XData', [0 0 0 0], 'YData', [0 0 1 1], ...
            'FaceColor', [0 0 0], 'FaceAlpha', 0.28, 'EdgeColor', 'none');
        h.nowL  = xline(h.ax, 0, '-', 'Color', [0.85 0.10 0.10], 'LineWidth', 2);
        xlim(h.ax, [0 max(S.total / 60, eps)]);
        ylim(h.ax, [0 1]);
        hold(h.ax, 'off');
        h.ax.Title.String = sprintf('Session timeline  -  %s', local_legendText());
    end

    function moveNow(el)
        if ~isfield(h, 'nowL') || isempty(h.nowL) || ~isvalid(h.nowL), return; end
        % Safety net: if the session outruns the model anyway, GROW the axis rather than
        % pinning the marker at the right-hand edge and silently lying about the progress.
        % The uncovered tail past the last segment reads honestly as "running long".
        if el > S.total
            S.total = el * 1.02;
            xlim(h.ax, [0 max(S.total / 60, eps)]);
        end
        x = el / 60;
        h.nowL.Value  = x;
        h.doneP.XData = [0 x x 0];
    end

    function drawLeds(L)
        if ~isstruct(L) || ~local_field(L, 'enabled', false)
            h.ledLbl.Text      = 'LED driver OFF for this run -- the LEDs are left untouched.';
            h.ledLbl.FontColor = [0.45 0.45 0.45];
            h.ledTbl.Data      = zeros(4, 3);
            return;
        end
        md = local_field(L, 'mode', 2);
        h.ledLbl.Text      = sprintf('mode %d (%s)   port %s', md, local_modeName(md), ...
                                     char(string(local_field(L, 'port', '?'))));
        h.ledLbl.FontColor = [0.13 0.45 0.20];
        I = local_field(L, 'intensity', zeros(4, 3));
        if iscell(I), I = cell2mat(I); end
        if ~isequal(size(I), [4 3]), I = zeros(4, 3); end
        h.ledTbl.Data = double(I);
    end

    function el = local_runElapsed()
        if isempty(S.tRun), el = 0; else, el = toc(S.tRun); end
    end

    function el = local_timelineElapsed()
        % Time on the timeline's own clock: zero until the first epoch starts.
        if isempty(S.tZero), el = 0; else, el = max(0, local_runElapsed() - S.tZero); end
    end
end


% ===================== pure helpers (shared with the self-test) =====================

function pos = local_place(parentFig, w, hgt)
% Sit to the right of the main GUI, but clamped to the screen: a rig display narrower than
% the two windows side by side must still show the monitor, not push it off the edge.
    scr = get(groot, 'ScreenSize');
    x   = scr(1) + scr(3) - w - 20;
    y   = scr(2) + max(20, round((scr(4) - hgt) / 2));
    try
        if ~isempty(parentFig) && isvalid(parentFig)
            pp = parentFig.Position;
            x  = pp(1) + pp(3) + 12;
            y  = pp(2) + max(0, pp(4) - hgt);
        end
    catch
    end
    x   = min(max(x, scr(1) + 10), scr(1) + scr(3) - w - 10);
    y   = min(max(y, scr(2) + 10), scr(2) + scr(4) - hgt - 10);
    pos = [x y w hgt];
end

function t0 = local_epochStart(segs, e)
% Where epoch e begins on the timeline (segments are tagged isFirst at each epoch boundary).
    t0 = 0;
    n  = 0;
    for i = 1:numel(segs)
        if segs(i).isFirst
            n = n + 1;
            if n == e, t0 = segs(i).t0; return; end
        end
    end
end

function d = local_epochEstimate(v)
% What the epochs still to come are likely to take. The FIRST epoch is dropped once there is
% anything to compare it with -- it pays one-off costs (first Stage connect, JIT, cold
% caches) the rest of the session does not. The most recent epoch sets a floor, so a session
% that is getting slower is not persistently under-modelled.
    if isempty(v),      d = 0;      return; end
    if isscalar(v),     d = v(1);   return; end
    d = max(mean(v(2:end)), v(end));
end

function d = local_nominalEpoch(plan)
% One epoch's modelled length EXCLUDING the learned overhead bands.
    T  = local_field(plan, 'timings', struct());
    bl = local_field(plan, 'blocks', []);
    stimS = 10;
    if ~isempty(bl), stimS = local_field(bl(1), 'stimSeconds', 10); end
    d = local_field(T, 'settle', 1) + local_field(T, 'preStim', 2) + stimS + ...
        local_field(T, 'postStim', 1) + local_field(T, 'itp', 3);
end

function a = local_meanAcc()
    a = struct('sum', 0, 'n', 0);
end

function a = local_meanPush(a, v)
    if ~isfinite(v) || v < 0, return; end
    a.sum = a.sum + v;
    a.n   = a.n + 1;
end

function v = local_meanGet(a, dflt)
    if a.n < 1, v = dflt; else, v = a.sum / a.n; end
end

function s = local_emptyState()
    s = struct('epoch', 0, 'totalEpochs', 0, 'block', 0, 'nBlocks', 0, ...
               'epochInBlock', 0, 'epochsInBlock', 0, 'label', '', 'stimName', '', ...
               'seed', NaN, 'phase', 'starting', 'phaseElapsed', 0, 'phaseTotal', 0, ...
               'stim', struct(), 'lastDrawnPhase', '');
end

function s = local_merge(s, msg)
% Reports are PARTIAL -- runExperiment knows the epoch, playAndLogTrial knows the
% presentation -- so each one only overwrites the fields it actually sent.
    if ~isstruct(msg), return; end
    f = fieldnames(msg);
    for i = 1:numel(f)
        s.(f{i}) = msg.(f{i});
    end
    % a new phase with no clock of its own must not inherit the previous phase's clock
    if isfield(msg, 'phase') && ~isfield(msg, 'phaseElapsed')
        s.phaseElapsed = 0;
        s.phaseTotal   = 0;
    end
end

function [segs, total] = local_planSegments(plan)
% Expand the plan into one coloured segment per phase per epoch, laid out on a cumulative
% seconds axis: the shape of the whole session before a single epoch has run.
    segs  = struct('t0', {}, 't1', {}, 'color', {}, 'isFirst', {});
    total = 0;
    if ~isstruct(plan), return; end
    T  = local_field(plan, 'timings', struct());
    bl = local_field(plan, 'blocks', struct('epochs', {}));
    % An epoch is NOT just settle + pre + stimulus + post + itp. Inside blk.stim, before a
    % single frame reaches the projector, the stimulus connects to Stage, precomputes every
    % frame and SERIALISES the whole presentation over TCP; afterwards it collects flip
    % telemetry and writes the manifest row. That setup/teardown is seconds per epoch and is
    % unknowable up front -- modelled here as prep/wrap, starting at 0 and replaced by the
    % monitor's own MEASUREMENTS after the first epoch (see onReport). Leaving it out is what
    % made the progress line reach the right-hand edge an epoch early.
    ph = { 'settle',   local_field(T, 'settle',   1),  [0.82 0.82 0.86]
           'prestim',  local_field(T, 'preStim',  2),  [0.62 0.72 0.88]
           'prep',     local_field(plan, 'prepSeconds', 0), [0.55 0.48 0.68]
           'presenting', NaN,                          [0.20 0.55 0.30]
           'wrap',     local_field(plan, 'wrapSeconds', 0), [0.55 0.48 0.68]
           'poststim', local_field(T, 'postStim', 1),  [0.62 0.72 0.88]
           'itp',      local_field(T, 'itp',      3),  [0.90 0.88 0.78] };
    % Per-epoch lengths: epochs that have ALREADY run are drawn at the length they actually
    % took, and only the ones still to come are estimated. That is what keeps the marker
    % honest -- the axis position of epoch k's start is the real elapsed time at that start,
    % so the marker cannot drift ahead of the drawing and strand itself at the right edge.
    eps_    = local_field(plan, 'epochSeconds',  []);   % measured length of finished epochs
    prepPer = local_field(plan, 'prepPerEpoch',   []);   % measured setup of THIS epoch
    prepEst = local_field(plan, 'prepSeconds',    0);    % estimate for epochs not yet run
    t = 0;
    n = 0;
    for b = 1:numel(bl)
        for e = 1:max(1, round(local_field(bl(b), 'epochs', 1)))
            n = n + 1;
            stimS = local_field(bl(b), 'stimSeconds', 10);
            % Everything except the learned setup band.
            nom = 0;
            for k = 1:size(ph, 1)
                if strcmp(ph{k, 1}, 'prep'), continue; end
                d = ph{k, 2};
                if isnan(d), d = stimS; end
                nom = nom + max(0, d);
            end
            % A finished epoch's measured TOTAL wins; an epoch in flight uses its own
            % measured setup once the presentation starts (so the marker lands exactly on
            % the stimulus band instead of jumping past it); anything else gets the estimate.
            if n <= numel(eps_) && isfinite(eps_(n))
                prep = max(0, eps_(n) - nom);
            elseif n <= numel(prepPer) && isfinite(prepPer(n))
                prep = prepPer(n);
            else
                prep = prepEst;
            end
            for k = 1:size(ph, 1)
                d = ph{k, 2};
                if isnan(d), d = stimS; end
                if strcmp(ph{k, 1}, 'prep'), d = prep; end
                if d <= 0, continue; end
                segs(end + 1) = struct('t0', t, 't1', t + d, 'color', ph{k, 3}, ...
                                       'isFirst', k == 1); %#ok<AGROW>
                t = t + d;
            end
        end
    end
    total = t;
end

function d = local_planStimSeconds(plan)
% The presentation length the timeline was drawn with (first block's; they are all the same
% stimulus type in a GUI-built protocol).
    d = NaN;
    bl = local_field(plan, 'blocks', []);
    if ~isempty(bl), d = local_field(bl(1), 'stimSeconds', NaN); end
    if ~isfinite(d), d = 10; end
end

function plan = local_setStimSeconds(plan, d)
    bl = local_field(plan, 'blocks', []);
    for i = 1:numel(bl)
        bl(i).stimSeconds = d;
    end
    plan.blocks = bl;
end

function txt = local_legendText()
    txt = 'settle | pre-stim | setup | STIMULUS | post-stim | inter-trial';
end

function [nm, col] = local_phaseFace(phase)
    switch lower(char(phase))
        case 'connecting', nm = 'CONNECTING';   col = [0.75 0.45 0.10];
        case 'leds',       nm = 'LED setup';    col = [0.75 0.45 0.10];
        case 'prep',       nm = 'preparing';    col = [0.40 0.35 0.55];
        case 'settle',     nm = 'settling';     col = [0.40 0.40 0.45];
        case 'trigger',    nm = 'TRIGGER';      col = [0.75 0.45 0.10];
        case 'prestim',    nm = 'pre-stim';     col = [0.25 0.40 0.65];
        case 'presenting', nm = 'PRESENTING';   col = [0.13 0.45 0.20];
        case 'poststim',   nm = 'post-stim';    col = [0.25 0.40 0.65];
        case 'itp',        nm = 'inter-trial';  col = [0.50 0.45 0.20];
        case 'done',       nm = 'done';         col = [0.13 0.45 0.20];
        otherwise,         nm = 'starting';     col = [0.40 0.40 0.45];
    end
end

function b = local_bar(frac, n)
    if ~isfinite(frac), frac = 0; end
    k = max(0, min(n, round(frac * n)));
    b = [repmat('#', 1, k) repmat('.', 1, n - k)];
end

function s = local_hms(sec)
    if ~isfinite(sec) || sec < 0, sec = 0; end
    s = sprintf('%02d:%02d', floor(sec / 60), floor(mod(sec, 60)));
end

function s = local_labelSuffix(label)
    label = strtrim(char(string(label)));
    if isempty(label), s = ''; else, s = ['   "' label '"']; end
end

function s = local_headerLine(plan)
    cn = strtrim(char(string(local_field(plan, 'cellName', ''))));
    if isempty(cn), cn = '(no cell name)'; end
    acq = 'Clampex OFF';
    if local_field(plan, 'triggerAcq', false), acq = 'Clampex ON'; end
    s = sprintf('cell "%s"   |   %d epoch(s) in %d block(s)   |   %s', ...
                cn, local_field(plan, 'totalEpochs', 0), local_field(plan, 'nBlocks', 0), acq);
end

function rows = local_stimRows(st)
% The "what is on the screen" table: identity first, then the numbers that decide what the
% cell actually sees (frequencies, frame count, duration, and this epoch's seed).
    si   = st.stim;
    rows = {'stimulus',            char(string(local_field(si, 'stimulus', st.stimName)))
            'cone isolation',      char(string(local_field(si, 'cone_isolation', '-')))
            'seed',                local_num(st.seed, '%d')
            'flicker (Hz)',        local_num(local_field(si, 'flicker_hz', NaN), '%g')
            'noise update (Hz)',   local_num(local_field(si, 'noise_update_hz', NaN), '%g')
            'refresh (Hz)',        local_num(local_field(si, 'refresh_hz', NaN), '%g')
            'frames (stim/total)', sprintf('%s / %s', ...
                local_num(local_field(si, 'stim_frames',  NaN), '%d'), ...
                local_num(local_field(si, 'total_frames', NaN), '%d'))
            'duration (s)',        local_num(local_field(si, 'duration_s', NaN), '%.2f')};
end

function s = local_num(v, fmt)
    if isempty(v) || ~isnumeric(v) || ~isscalar(v) || ~isfinite(v)
        s = '-';
    else
        s = sprintf(fmt, v);
    end
end

function n = local_modeName(m)
    switch double(m)
        case 0, n = 'off';
        case 1, n = 'DC red';
        case 2, n = 'video RGB';
        case 3, n = 'video RGB + sync';
        otherwise, n = '?';
    end
end

function f = local_monoFont()
    f = 'Menlo';
    if ispc, f = 'Consolas'; end
end

function v = local_field(s, f, d)
    if isstruct(s) && isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
