function [fnName, scriptPath] = generateStimScript(entry, phases, stimLeds, outDir)
% generateStimScript  Write the per-run stimulus m-file that Run actually executes.
%
%   [fnName, scriptPath] = generateStimScript(entry, phases, stimLeds, outDir)
%
%   entry    : a stimRegistry() entry (.fn/.params/.kind/.iso/.checks). The generated
%              function takes entry.params IN ORDER: the first nargin(entry.fn) of them
%              are the AA function's own signature; any extra rows (the checkerboards'
%              checksX / checksY) exist ONLY on the generated function. runExperiment's
%              protocol machinery (args, per-epoch seed auto-increment) is unchanged --
%              and its stimulus segment reproduces entry.fn's presentation EXACTLY
%              (same RNG draws, same lcGammaCorrect linearization, same s.frame-indexed
%              lookup tables, same sync-bar pattern, same manifest fields).
%   phases   : resolved phase plan from the stimulusGUI "Phases" panel:
%                .pre   .seconds .rgb .ledGrid   rendered INSIDE the presentation, before
%                .post  .seconds .rgb .ledGrid   / after the stimulus frames (sync bar dark)
%                .iti   .seconds .rgb .ledGrid   applied BETWEEN epochs by runExperiment
%                .final .rgb .ledGrid            applied at the END by runExperiment
%              (.rgb linear intent 0..1; .ledGrid a 4x3 duty grid or [] = leave LEDs).
%              iti/final are baked into the manifest record here purely as provenance.
%   stimLeds : the 4x3 LED grid in force DURING the stimulus frames (the GUI's main grid),
%              or [] when the LED driver is disabled.
%   outDir   : where to write the script (default <pwd>/generated_stimuli). Created if
%              missing and added to the path. The file is kept forever: it sits next to
%              the day's data as the exact record of what ran.
%
% WHY GENERATED: the seven AA* scripts each reconnect to the (single-client) Stage server
% every epoch, hard-code their phase behavior, and can't render a controlled full-screen
% value around the stimulus. Rather than editing them (house rule: they stay untouched),
% Run now writes ONE self-contained script per run -- pre-stim + stimulus + post-stim in a
% single frame-locked presentation on the SHARED client (stageClientShared), with the
% per-phase LED grids applied at the phase boundaries by playAndLogTrial.
%
% DIAMOND-PIXEL GEOMETRY: the DLP4500 canvas is 912 x 1140, but each canvas pixel lands
% pixel_aspect x wider than tall on the wall (2.0 from the diamond DMD geometry -> a
% 16:10 image). Checkerboard geometry is SETTABLE (checksX x checksY arguments; registry
% defaults 40 x 25 = square-on-the-wall at pixel_aspect 2), and the jitter circle gets
% radiusY = radius * pixel_aspect so it is round. rig_config `pixel_aspect` tunes it.
%
% The generated file is plain readable MATLAB with the whole plan in its header -- open it
% to see exactly what was presented.

    if nargin < 2, phases = []; end
    if nargin < 3, stimLeds = []; end
    if nargin < 4 || isempty(outDir), outDir = fullfile(pwd, 'generated_stimuli'); end

    if ~isstruct(entry) || ~isfield(entry, 'kind') || ~isfield(entry, 'fn')
        error('generateStimScript:badEntry', ...
              'entry must be a stimRegistry() entry (with .fn and .kind).');
    end
    P        = local_resolvePhases(phases);
    stimLeds = local_grid(stimLeds);

    tag    = local_tag(entry);
    stamp  = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
    fnName = sprintf('genStim_%s_%s', tag, stamp);
    if ~exist(outDir, 'dir'), mkdir(outDir); end
    scriptPath = fullfile(outDir, [fnName '.m']);
    n = 2;
    while exist(scriptPath, 'file')      % same stimulus twice within one second
        fnName     = sprintf('genStim_%s_%s_%d', tag, stamp, n);
        scriptPath = fullfile(outDir, [fnName '.m']);
        n = n + 1;
    end

    txt = local_emit(entry, P, stimLeds, fnName);

    fid = fopen(scriptPath, 'w');
    if fid < 0
        error('generateStimScript:cannotWrite', 'Cannot write %s', scriptPath);
    end
    fwrite(fid, txt, 'char');
    fclose(fid);

    % Make the new function resolvable NOW (str2func + call in this same session).
    if ~any(strcmp(strsplit(path, pathsep), outDir)), addpath(outDir); else, rehash; end
    if isempty(which(fnName))
        error('generateStimScript:notOnPath', ...
              'Generated %s but MATLAB cannot resolve it (path problem?).', scriptPath);
    end
    fprintf('[generateStimScript] wrote %s\n', scriptPath);
end


% ================================ phase resolution ================================
function P = local_resolvePhases(phases)
% Fill a partial phase plan with the defaults that reproduce the pre-overhaul behavior:
% black screens, LEDs left alone.
    P = struct( ...
        'pre',   struct('seconds', 2, 'rgb', [0 0 0], 'ledGrid', []), ...
        'post',  struct('seconds', 1, 'rgb', [0 0 0], 'ledGrid', []), ...
        'iti',   struct('seconds', 3, 'rgb', [0 0 0], 'ledGrid', []), ...
        'final', struct('rgb', [0 0 0], 'ledGrid', []));
    if ~isstruct(phases), return; end
    for f = {'pre', 'post', 'iti', 'final'}
        if ~isfield(phases, f{1}) || ~isstruct(phases.(f{1})), continue; end
        src = phases.(f{1});
        dst = P.(f{1});
        if isfield(dst, 'seconds') && isfield(src, 'seconds') && ~isempty(src.seconds)
            s = double(src.seconds);
            if isscalar(s) && isfinite(s) && s >= 0, dst.seconds = s; end
        end
        if isfield(src, 'rgb') && ~isempty(src.rgb)
            dst.rgb = local_rgb(src.rgb);
        end
        if isfield(src, 'ledGrid')
            dst.ledGrid = local_grid(src.ledGrid);
        end
        P.(f{1}) = dst;
    end
end

function v = local_rgb(v)
    v = double(reshape(v, 1, []));
    if numel(v) ~= 3 || any(~isfinite(v))
        error('generateStimScript:badRGB', 'A phase RGB must be three finite numbers (0..1).');
    end
    v = min(max(v, 0), 1);
end

function g = local_grid(v)
    if iscell(v), v = cell2mat(v); end
    g = [];
    if isnumeric(v) && isequal(size(v), [4 3]) && all(isfinite(v(:)))
        g = double(v);
    end
end

function t = local_tag(entry)
    switch entry.kind
        case 'sq'
            if entry.iso, t = 'sqSiso'; else, t = 'sqGrey'; end
        case 'gauss'
            if isequal(entry.checks, [1 1]), base = 'gauss'; else, base = 'check'; end
            if entry.iso, t = [base 'Siso']; else, t = [base 'Grey']; end
        case 'jitter'
            t = 'jitter';
        otherwise
            error('generateStimScript:badKind', 'Unknown stimulus kind "%s".', entry.kind);
    end
end


% ================================== code emission ==================================
function txt = local_emit(entry, P, stimLeds, fnName)
    L = {};
    function add(fmt, varargin)
        if nargin == 0, L{end+1} = ''; else, L{end+1} = sprintf(fmt, varargin{:}); end
    end
    m = @mat2str;                                 % numeric literal -> MATLAB source
    argNames = entry.params(:, 1)';
    args     = strjoin(argNames, ', ');

    % ---- header ----
    add('function %s(%s)', fnName, args);
    add('%% %s  AUTO-GENERATED stimulus script -- do not edit (regenerated every run).', fnName);
    add('%%');
    add('%% Written by generateStimScript.m (generateStimScript/1) on %s.', ...
        char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
    add('%% Reproduces the presentation of %s exactly (same RNG draws, same', entry.fn);
    add('%% lcGammaCorrect linearization, same s.frame-indexed lookups, same sync bar),');
    add('%% wrapped in the configured pre/post-stim phases, in ONE presentation:');
    add('%%');
    add('%%   pre-stim   %g s   full screen RGB %s   LEDs %s', ...
        P.pre.seconds, m(P.pre.rgb), local_gridNote(P.pre.ledGrid));
    add('%%   stimulus   (stimFrames / refreshRate) s          LEDs %s', local_gridNote(stimLeds));
    add('%%   post-stim  %g s   full screen RGB %s   LEDs %s', ...
        P.post.seconds, m(P.post.rgb), local_gridNote(P.post.ledGrid));
    add('%%');
    add('%% Between epochs runExperiment holds RGB %s for %g s (LEDs %s); at the end of', ...
        m(P.iti.rgb), P.iti.seconds, local_gridNote(P.iti.ledGrid));
    add('%% the run it holds RGB %s (LEDs %s). Those are recorded here as provenance.', ...
        m(P.final.rgb), local_gridNote(P.final.ledGrid));
    add('%%');
    add('%% SYNC BAR (rightmost W/8 of the screen, never covered by any full-screen value),');
    add('%% three photodiode segments, top to bottom:');
    add('%%   top    - projector FRAME CLOCK: toggles blue/dark every frame, pre through post');
    add('%%   middle - STIMULUS UPDATE CLOCK: the legacy sync pattern, at the stimulus''s own');
    add('%%            base update rate; dark outside the stimulus frames');
    add('%%   bottom - STIMULUS ENVELOPE: solid blue while stimulus frames are on screen');
    add();

    % ---- defaults (mirror the AA script, so standalone calls behave the same) ----
    add('    %% ---- arguments (same signature and defaults as %s) ----', entry.fn);
    switch entry.kind
        case 'sq'
            add('    if nargin < 3 || isempty(refreshRate), refreshRate = 60;              end');
            add('    if nargin < 1 || isempty(flickerHz),   flickerHz   = 4;               end');
            add('    if nargin < 2 || isempty(stimFrames),  stimFrames  = 10 * refreshRate; end');
        case 'gauss'
            add('    if nargin < 6 || isempty(refreshRate), refreshRate = 60;              end');
            add('    if nargin < 1 || isempty(seed),        seed        = 2;               end');
            add('    if nargin < 2 || isempty(mu),          mu          = 0.5;             end');
            add('    if nargin < 3 || isempty(sigma),       sigma       = 0.3;             end');
            add('    if nargin < 4 || isempty(flickerHz),   flickerHz   = 4;               end');
            add('    if nargin < 5 || isempty(stimFrames),  stimFrames  = 10 * refreshRate; end');
            if size(entry.params, 1) >= 8      % checkerboard: settable checksX x checksY
                add('    if nargin < 7 || isempty(checksX),     checksX     = %s;              end', m(entry.params{7, 2}));
                add('    if nargin < 8 || isempty(checksY),     checksY     = %s;              end', m(entry.params{8, 2}));
            end
        case 'jitter'
            add('    if nargin < 6 || isempty(refreshRate),  refreshRate  = 60;          end');
            add('    if nargin < 5 || isempty(stimFrames),   stimFrames   = 10 * refreshRate; end');
            add('    if nargin < 4 || isempty(walkSpeed),    walkSpeed    = 50;          end');
            add('    if nargin < 3 || isempty(circleRadius), circleRadius = 150;         end');
            add('    if nargin < 2 || isempty(rfRadius),     rfRadius     = 80;          end');
            add('    if nargin < 1 || isempty(rfCenter),     rfCenter     = [570, 456];  end');
            add('    if nargin < 7 || isempty(colorMode),    colorMode    = ''Greyscale''; end');
    end
    add();

    % ---- baked phase plan ----
    add('    %% ---- phase plan (baked in from the stimulusGUI Phases panel) ----');
    add('    preS    = %s;', m(P.pre.seconds));
    add('    postS   = %s;', m(P.post.seconds));
    add('    preRGB  = %s;   %% linear intent 0..1 (linearized with the stimulus colors)', m(P.pre.rgb));
    add('    postRGB = %s;', m(P.post.rgb));
    add('    preLeds  = %s;  %% 4x3 LED duty grid at phase start ([] = leave the LEDs alone)', local_gridSrc(P.pre.ledGrid));
    add('    stimLeds = %s;', local_gridSrc(stimLeds));
    add('    postLeds = %s;', local_gridSrc(P.post.ledGrid));
    add();

    % ---- client + geometry + timing ----
    add('    %% ---- Stage client (SHARED: connects once per session, reused across epochs) ----');
    add('    client = stageClientShared(''get'');');
    add('    canvasSize = client.getCanvasSize();');
    add('    fprintf(''[%s] Canvas: %%d x %%d\\n'', canvasSize(1), canvasSize(2));', fnName);
    add('    W = canvasSize(1);');
    add('    H = canvasSize(2);');
    add();
    add('    %% ---- physical pixel geometry (diamond-pixel DMD) ----');
    add('    %% The DLP4500''s 912 x 1140 diamond array lands each canvas pixel pixel_aspect x');
    add('    %% WIDER than tall on the wall (2.0 from the diamond geometry -> a 16:10 image),');
    add('    %% so anything meant to look square on the screen must span pixel_aspect x more');
    add('    %% rows than columns. Tune rig_config `pixel_aspect` if a measured checkerboard');
    add('    %% still looks stretched.');
    add('    pixelAspect = loadRigConfig(''pixel_aspect'', 2);');
    add();
    add('    %% ---- timing: pre-stim + stimulus + post-stim rendered as ONE presentation,');
    add('    %% so stimulus onset is frame-locked exactly preFrames after presentation start ----');
    add('    preFrames   = round(preS  * refreshRate);');
    add('    postFrames  = round(postS * refreshRate);');
    add('    totalFrames = preFrames + stimFrames + postFrames;');
    add('    totalDuration = totalFrames / refreshRate;');
    add();

    switch entry.kind
        case 'sq',     local_emitSq(@add, entry, m);
        case 'gauss',  local_emitGauss(@add, entry, m);
        case 'jitter', local_emitJitter(@add, m);
    end

    % ---- manifest record ----
    add('    %% ---- manifest record: the same fields %s logs, plus the phase plan ----', entry.fn);
    add('    record = struct( ...');
    switch entry.kind
        case 'sq'
            add('        ''stimulus'',        ''%s'', ...', entry.fn);
            add('        ''stim_type'',       ''sq_wave'', ...');
            add('        ''cone_isolation'',  ''%s'', ...', local_cone(entry.iso));
            add('        ''flicker_hz'',      flickerHz, ...');
            add('        ''refresh_rate_hz'', refreshRate, ...');
            add('        ''stim_frames'',     stimFrames, ...');
        case 'gauss'
            if isequal(entry.checks, [1 1]), st = 'gaussian_noise'; else, st = 'checkerboard'; end
            add('        ''stimulus'',              ''%s'', ...', entry.fn);
            add('        ''stim_type'',             ''%s'', ...', st);
            add('        ''cone_isolation'',        ''%s'', ...', local_cone(entry.iso));
            add('        ''seed'',                  seed, ...');
            add('        ''mu'',                    mu, ...');
            add('        ''sigma'',                 sigma, ...');
            add('        ''checks_x'',              checksX, ...');
            add('        ''checks_y'',              checksY, ...');
            add('        ''n_updates'',             nUpdates, ...');
            add('        ''update_every_n_frames'', updateEveryNFrames, ...');
            add('        ''flicker_hz'',            flickerHz, ...');
            add('        ''noise_update_hz'',       refreshRate / updateEveryNFrames, ...');
            add('        ''refresh_rate_hz'',       refreshRate, ...');
            add('        ''stim_frames'',           stimFrames, ...');
            add('        ''gamma'',                 loadRigConfig(''gamma'', 2.2056), ...');
            add('        ''noise_method'',          ''mt19937ar+invCDF'', ...');
            add('        ''fill_order'',            ''F'', ...');
        case 'jitter'
            add('        ''stimulus'',        ''%s'', ...', entry.fn);
            add('        ''stim_type'',       ''jitter'', ...');
            add('        ''cone_isolation'',  coneIso, ...');
            add('        ''seed'',            2, ...');
            add('        ''walk_speed'',      walkSpeed, ...');
            add('        ''spring_k'',        k, ...');
            add('        ''circle_radius'',   circleRadius, ...');
            add('        ''rf_center_x'',     rfCenter(1), ...');
            add('        ''rf_center_y'',     rfCenter(2), ...');
            add('        ''rf_radius'',       rfRadius, ...');
            add('        ''refresh_rate_hz'', refreshRate, ...');
            add('        ''stim_frames'',     stimFrames, ...');
            add('        ''noise_method'',    ''mt19937ar+invCDF'', ...');
            add('        ''fill_order'',      ''F'', ...');
    end
    add('        ''canvas_w'',         W, ...');
    add('        ''canvas_h'',         H, ...');
    add('        ''pixel_aspect'',     pixelAspect, ...');
    add('        ''sync_bar'',         ''triple/1'', ...');
    add('        ''pre_stim_s'',       preFrames  / refreshRate, ...');
    add('        ''post_stim_s'',      postFrames / refreshRate, ...');
    add('        ''pre_frames'',       preFrames, ...');
    add('        ''post_frames'',      postFrames, ...');
    add('        ''pre_rgb'',          preRGB, ...');
    add('        ''post_rgb'',         postRGB, ...');
    add('        ''iti_s'',            %s, ...', m(P.iti.seconds));
    add('        ''iti_rgb'',          %s, ...', m(P.iti.rgb));
    add('        ''final_rgb'',        %s, ...', m(P.final.rgb));
    add('        ''generator'',        ''generateStimScript/1'', ...');
    add('        ''generated_script'', ''%s.m'');', fnName);
    add('    %% (generated_script is excluded from the stim_signature -- see writeStimManifest)');
    add();

    % ---- phase schedule + presentation ----
    add('    %% ---- phase schedule: playAndLogTrial reports these to the session monitor and');
    add('    %% applies each phase''s LED grid (via ledSession) as its frames start ----');
    add('    phasePlan = struct( ...');
    add('        ''name'', {''prestim'', ''presenting'', ''poststim''}, ...');
    add('        ''durS'', {preFrames / refreshRate, stimFrames / refreshRate, postFrames / refreshRate}, ...');
    add('        ''leds'', {preLeds, stimLeds, postLeds});');
    add();
    add('    presentation = stage.core.Presentation(totalDuration);');
    switch entry.kind
        case 'sq'
            add('    presentation.addStimulus(fullField);');
            local_emitBarAdds(@add);
            add('    presentation.addController(fullFieldCtrl);');
            local_emitBarCtrlAdds(@add);
        case 'gauss'
            add('    presentation.addStimulus(noiseImage);');
            local_emitBarAdds(@add);
            add('    presentation.addController(imageCtrl);');
            local_emitBarCtrlAdds(@add);
        case 'jitter'
            add('    presentation.addStimulus(background);');
            add('    presentation.addStimulus(circle);');
            local_emitBarAdds(@add);
            add('    presentation.addController(bgCtrl);');
            add('    presentation.addController(posCtrl);');
            local_emitBarCtrlAdds(@add);
    end
    add();
    add('    player = stage.builtin.players.RealtimePlayer(presentation);');
    add('    fprintf(''[%s] Playing %%.1f s (pre %%g + stim %%g + post %%g)...\\n'', ...', fnName);
    add('        totalDuration, preFrames / refreshRate, stimFrames / refreshRate, postFrames / refreshRate);');
    add('    playAndLogTrial(client, player, pwd, record, refreshRate, totalFrames, phasePlan);');
    add('    fprintf(''[%s] Done.\\n'');', fnName);
    add('end');

    txt = [strjoin(L, newline) newline];
end


% ---------------------------- stimulus cores ----------------------------
function local_emitSq(add, entry, m)
% Full-field square-wave flicker (AAGreyScaleFullFieldNoiseFinal2026 /
% AASConeIsoFullFieldNoiseStimFinal2026): two colors alternating at flickerHz; the middle
% sync segment is blue on phase A of each half-cycle (the legacy bar pattern).
    if entry.iso
        colA = [1 0 0]; colB = [0 1 0];  what = 'RED <-> GREEN (S-cone iso)';
    else
        colA = [0 0 0]; colB = [1 1 1];  what = 'BLACK <-> WHITE (greyscale)';
    end
    add('    %% ---- square-wave flicker: %s at flickerHz ----', what);
    add('    framesPerHalfCycle = max(1, round(refreshRate / (2 * flickerHz)));');
    add();
    add('    %% per-frame colors: pre-stim block, stimulus square wave, post-stim block.');
    add('    %% The middle sync segment carries the STIMULUS UPDATE CLOCK: blue on phase A');
    add('    %% of each half-cycle (the legacy single-bar pattern), dark outside the stimulus.');
    add('    fullFieldColors = zeros(totalFrames, 3);');
    add('    midBarColors    = zeros(totalFrames, 3);');
    add('    fullFieldColors(1:preFrames, :) = repmat(preRGB, preFrames, 1);');
    add('    for f = 1:stimFrames');
    add('        halfCycleIdx = floor((f - 1) / framesPerHalfCycle);');
    add('        if mod(halfCycleIdx, 2) == 0');
    add('            fullFieldColors(preFrames + f, :) = %s;', m(colA));
    add('            midBarColors(preFrames + f, :)    = [0 0 1];');
    add('        else');
    add('            fullFieldColors(preFrames + f, :) = %s;', m(colB));
    add('        end');
    add('    end');
    add('    fullFieldColors(preFrames + stimFrames + 1:end, :) = repmat(postRGB, postFrames, 1);');
    add();
    local_emitBarLuts(add);
    add('    %% linearize every streamed color for the LightCrafter (measured LUT)');
    add('    fullFieldColors = lcGammaCorrect(fullFieldColors);');
    local_emitBarGamma(add);
    add();
    add('    %% ---- stimuli ----');
    add('    fullField          = stage.builtin.stimuli.Rectangle();');
    add('    fullField.size     = [W, H];');
    add('    fullField.position = [W/2, H/2];');
    add('    fullField.color    = [0 0 0];');
    add();
    local_emitSyncBars(add);
    add('    %% frame-locked lookups: index by s.frame, NEVER s.time (project rule)');
    add('    fullFieldCtrl = stage.builtin.controllers.PropertyController(fullField, ''color'', ...');
    add('        @(s) fullFieldColors(min(max(s.frame + 1, 1), totalFrames), :));');
    local_emitSyncBarCtrls(add);
end


function local_emitGauss(add, entry, m)
% Seeded Gaussian noise as an Image stimulus: full-field (1x1) or checkerboard (40x32),
% greyscale (R=G=B=v) or S-cone iso (R=v, G=1-v, B=0). Mirrors the four AASeededGaussian*
% scripts: same RandStream draws, same per-update images, same frame->update mapping.
    add('    %% ---- seeded Gaussian noise geometry ----');
    if isequal(entry.checks, [1 1])
        add('    checksX = 1;');
        add('    checksY = 1;');
    elseif size(entry.params, 1) >= 8
        add('    %% checkerboard geometry from the checksX / checksY ARGUMENTS (settable per');
        add('    %% epoch in the GUI). The registry defaults, 40 x 25, are square-on-the-wall');
        add('    %% at pixel_aspect 2; for square checks at another width use');
        add('    %% checksY ~ checksX * (H/W) / pixel_aspect.');
        add('    checksX = max(1, round(checksX));');
        add('    checksY = max(1, round(checksY));');
    else
        add('    checksX = %s;', m(entry.checks(1)));
        add('    %% checksY is DERIVED so the checks are SQUARE ON THE WALL, not on the canvas:');
        add('    %% the old fixed 40x32 grid drew checks ~1.3x wider than tall on the diamond');
        add('    %% DMD. At 912 x 1140 with pixel_aspect 2 this gives a 40 x 25 grid.');
        add('    checksY = max(1, round(checksX * (H / W) / pixelAspect));');
    end
    add();
    add('    updateEveryNFrames = max(1, round(refreshRate / (2 * flickerHz)));');
    add('    nUpdates = ceil(stimFrames / updateEveryNFrames);');
    add();
    add('    %% Inverse-CDF normals (not randn): uniform draws from mt19937ar rand() match');
    add('    %% numpy''s RandomState exactly, so the Analysis Suite regenerates this noise');
    add('    %% bit-identically from the seed. erfinv is base MATLAB (no Stats Toolbox).');
    add('    stream = RandStream(''mt19937ar'', ''Seed'', seed);');
    add('    noiseVals = mu + sigma .* (sqrt(2) .* erfinv(2 .* rand(stream, checksY, checksX, nUpdates) - 1));');
    add('    noiseVals = min(max(noiseVals, 0), 1);');
    add();
    add('    %% optional troubleshooting dump (rig_config: "debug_values_csv": true):');
    add('    %% intended vs gamma-corrected sent values, stimulus LED grid in the header');
    add('    if loadRigConfig(''debug_values_csv'', false)');
    if entry.iso
        add('        writeStimValuesCsv(pwd, ''%s'', seed, struct(''R'', noiseVals, ''G'', 1 - noiseVals), stimLeds);', entry.fn);
    else
        add('        writeStimValuesCsv(pwd, ''%s'', seed, struct(''grey'', noiseVals), stimLeds);', entry.fn);
    end
    add('    end');
    add();
    add('    %% ---- per-update noise images (linearized uint8, exactly as the AA script) ----');
    add('    rgbImages = cell(nUpdates, 1);');
    add('    for u = 1:nUpdates');
    add('        v = noiseVals(:, :, u);');
    add('        img = zeros(checksY, checksX, 3, ''uint8'');');
    if entry.iso
        add('        img(:, :, 1) = uint8(round(255 * lcGammaCorrect(v)));        %% R = v');
        add('        img(:, :, 2) = uint8(round(255 * lcGammaCorrect(1 - v)));    %% G = 1 - v');
        add('        %% B stays 0 (S-cone isolation drives only R/G)');
    else
        add('        g = uint8(round(255 * lcGammaCorrect(v)));                   %% R = G = B = v');
        add('        img(:, :, 1) = g;');
        add('        img(:, :, 2) = g;');
        add('        img(:, :, 3) = g;');
    end
    add('        rgbImages{u} = img;');
    add('    end');
    add();
    add('    %% constant full-screen images for the pre / post phases');
    add('    pre8  = uint8(round(255 * lcGammaCorrect(preRGB)));');
    add('    post8 = uint8(round(255 * lcGammaCorrect(postRGB)));');
    add('    preImg  = zeros(checksY, checksX, 3, ''uint8'');');
    add('    postImg = zeros(checksY, checksX, 3, ''uint8'');');
    add('    for c = 1:3');
    add('        preImg(:, :, c)  = pre8(c);');
    add('        postImg(:, :, c) = post8(c);');
    add('    end');
    add();
    add('    %% ---- per-frame imageMatrix lookup: pre, stimulus updates, post ----');
    add('    allFrameImages = cell(totalFrames, 1);');
    add('    for f = 1:preFrames');
    add('        allFrameImages{f} = preImg;');
    add('    end');
    add('    for f = 1:stimFrames');
    add('        updateIdx = min(max(floor((f - 1) / updateEveryNFrames) + 1, 1), nUpdates);');
    add('        allFrameImages{preFrames + f} = rgbImages{updateIdx};');
    add('    end');
    add('    for f = 1:postFrames');
    add('        allFrameImages{preFrames + stimFrames + f} = postImg;');
    add('    end');
    add();
    add('    %% middle sync segment: the STIMULUS UPDATE CLOCK -- blue/dark at the noise');
    add('    %% update rate (the legacy single-bar pattern), dark outside the stimulus');
    add('    midBarColors = zeros(totalFrames, 3);');
    add('    for f = 1:stimFrames');
    add('        updateIdx = floor((f - 1) / updateEveryNFrames);');
    add('        if mod(updateIdx, 2) == 0');
    add('            midBarColors(preFrames + f, :) = [0 0 1];');
    add('        end');
    add('    end');
    add();
    local_emitBarLuts(add);
    local_emitBarGamma(add);
    add();
    add('    %% ---- stimuli ----');
    add('    noiseImage = stage.builtin.stimuli.Image(allFrameImages{1});');
    add('    noiseImage.position = [W/2, H/2];');
    add('    noiseImage.size = [W, H];');
    add('    noiseImage.setMinFunction(GL.NEAREST);');
    add('    noiseImage.setMagFunction(GL.NEAREST);');
    add();
    local_emitSyncBars(add);
    add('    %% frame-locked lookups: index by s.frame, NEVER s.time (project rule)');
    add('    imageCtrl = stage.builtin.controllers.PropertyController(noiseImage, ''imageMatrix'', ...');
    add('        @(s) allFrameImages{min(max(s.frame + 1, 1), totalFrames)});');
    local_emitSyncBarCtrls(add);
end


function local_emitJitter(add, m) %#ok<INUSD>
% Random-walk circle (AAJitteringCircleStimulusFinal): OU walk around rfCenter, seed 2,
% sync bar alternating every frame. The circle parks off-canvas during pre/post and the
% background rectangle carries the phase colors.
    add('    %% ---- Ornstein-Uhlenbeck random walk around rfCenter (seed 2, as the AA script) ----');
    add('    posX = zeros(stimFrames, 1);');
    add('    posY = zeros(stimFrames, 1);');
    add('    curX = rfCenter(1);');
    add('    curY = rfCenter(2);');
    add('    stepSigma = walkSpeed / refreshRate;');
    add('    k = 0.02;   %% spring constant: pulls 2%% of the way back to center each frame');
    add('    stream = RandStream(''mt19937ar'', ''Seed'', 2);');
    add('    for f = 1:stimFrames');
    add('        %% inverse-CDF normals so the walk reproduces from the seed in Python');
    add('        dx = stepSigma * sqrt(2) * erfinv(2 * rand(stream) - 1);');
    add('        dy = stepSigma * sqrt(2) * erfinv(2 * rand(stream) - 1);');
    add('        curX = curX + dx - k * (curX - rfCenter(1));');
    add('        curY = curY + dy - k * (curY - rfCenter(2));');
    add('        posX(f) = curX;');
    add('        posY(f) = curY;');
    add('    end');
    add();
    add('    %% park the circle off-canvas during the pre / post phases');
    add('    parkAt = -10 * max(W, H);');
    add('    posXFull = parkAt * ones(totalFrames, 1);');
    add('    posYFull = parkAt * ones(totalFrames, 1);');
    add('    posXFull(preFrames + 1:preFrames + stimFrames) = posX;');
    add('    posYFull(preFrames + 1:preFrames + stimFrames) = posY;');
    add();
    add('    %% background carries the phase colors (black during the stimulus, as the AA script)');
    add('    backgroundColors = zeros(totalFrames, 3);');
    add('    backgroundColors(1:preFrames, :) = repmat(preRGB, preFrames, 1);');
    add('    backgroundColors(preFrames + stimFrames + 1:end, :) = repmat(postRGB, postFrames, 1);');
    add();
    add('    %% middle sync segment: the STIMULUS UPDATE CLOCK -- the walk updates every');
    add('    %% frame, so it alternates blue/dark per frame (the legacy single-bar pattern);');
    add('    %% dark outside the stimulus');
    add('    midBarColors = zeros(totalFrames, 3);');
    add('    for f = 1:stimFrames');
    add('        if mod(f, 2) == 1');
    add('            midBarColors(preFrames + f, :) = [0 0 1];');
    add('        end');
    add('    end');
    add();
    local_emitBarLuts(add);
    add('    if strcmpi(colorMode, ''S-Cone Isolating'')');
    add('        circColor = [1 0 0];    %% S-cone iso: red circle');
    add('        coneIso   = ''S'';');
    add('    else');
    add('        circColor = [1 1 1];    %% greyscale: white circle');
    add('        coneIso   = ''achromatic'';');
    add('    end');
    add();
    add('    %% linearize every streamed color for the LightCrafter (measured LUT)');
    add('    circColor        = lcGammaCorrect(circColor);');
    add('    backgroundColors = lcGammaCorrect(backgroundColors);');
    local_emitBarGamma(add);
    add();
    add('    %% ---- stimuli ----');
    add('    background          = stage.builtin.stimuli.Rectangle();');
    add('    background.size     = [W, H];');
    add('    background.position = [W/2, H/2];');
    add('    background.color    = [0 0 0];');
    add();
    add('    circle          = stage.builtin.stimuli.Ellipse();');
    add('    circle.radiusX  = circleRadius;');
    add('    %% pixel_aspect x more rows than columns = the same PHYSICAL radius vertically:');
    add('    %% with equal canvas radii the diamond DMD drew this as a wide ellipse.');
    add('    circle.radiusY  = circleRadius * pixelAspect;');
    add('    circle.color    = circColor;');
    add('    circle.position = rfCenter;');
    add();
    local_emitSyncBars(add);
    add('    %% frame-locked lookups: index by s.frame, NEVER s.time (project rule)');
    add('    bgCtrl = stage.builtin.controllers.PropertyController(background, ''color'', ...');
    add('        @(s) backgroundColors(min(max(s.frame + 1, 1), totalFrames), :));');
    add('    posCtrl = stage.builtin.controllers.PropertyController(circle, ''position'', ...');
    add('        @(s) [posXFull(min(max(s.frame + 1, 1), totalFrames)), ...');
    add('              posYFull(min(max(s.frame + 1, 1), totalFrames))]);');
    local_emitSyncBarCtrls(add);
end


% ---------------------------- the three-segment sync bar ----------------------------
% Rightmost W/8 of the screen, drawn OVER every stimulus and full-screen value (the bar
% stimuli are added last, so no phase color ever covers them). Top to bottom:
%   top    - projector FRAME CLOCK: toggles blue/dark every frame across the whole
%            presentation (pre-stim through post-stim) -- a photodiode on it measures the
%            true frame rate of the LightCrafter, whatever it is running at.
%   middle - STIMULUS UPDATE CLOCK: the legacy sync pattern at the stimulus's own base
%            update rate; dark outside the stimulus frames (emitted per stimulus kind).
%   bottom - STIMULUS ENVELOPE: solid blue exactly while stimulus frames are on screen.

function local_emitBarLuts(add)
% Emit the top (frame clock) and bottom (envelope) lookup tables; the middle one is
% emitted by each stimulus kind, since it carries that stimulus's own update pattern.
    add('    %% top sync segment: the projector FRAME CLOCK -- toggles every single frame,');
    add('    %% through pre-stim, stimulus and post-stim alike');
    add('    topBarColors = zeros(totalFrames, 3);');
    add('    topBarColors(1:2:totalFrames, 3) = 1;');
    add();
    add('    %% bottom sync segment: the STIMULUS ENVELOPE -- solid blue while stimulus');
    add('    %% frames are on screen, dark during pre/post');
    add('    botBarColors = zeros(totalFrames, 3);');
    add('    botBarColors(preFrames + 1:preFrames + stimFrames, 3) = 1;');
    add();
end

function local_emitBarGamma(add)
    add('    topBarColors = lcGammaCorrect(topBarColors);');
    add('    midBarColors = lcGammaCorrect(midBarColors);');
    add('    botBarColors = lcGammaCorrect(botBarColors);');
end

function local_emitSyncBars(add)
    add('    %% sync bar: three segments in the rightmost W/8, drawn OVER everything, so no');
    add('    %% full-screen value ever reaches this region (top=frame clock, middle=stimulus');
    add('    %% update clock, bottom=stimulus envelope)');
    add('    barW = W / 8;');
    add('    barX = W - W / 16;');
    add('    topBar          = stage.builtin.stimuli.Rectangle();');
    add('    topBar.size     = [barW, H/3];');
    add('    topBar.position = [barX, 5*H/6];');
    add('    topBar.color    = [0 0 0];');
    add('    midBar          = stage.builtin.stimuli.Rectangle();');
    add('    midBar.size     = [barW, H/3];');
    add('    midBar.position = [barX, H/2];');
    add('    midBar.color    = [0 0 0];');
    add('    botBar          = stage.builtin.stimuli.Rectangle();');
    add('    botBar.size     = [barW, H/3];');
    add('    botBar.position = [barX, H/6];');
    add('    botBar.color    = [0 0 0];');
    add();
end

function local_emitSyncBarCtrls(add)
    add('    topBarCtrl = stage.builtin.controllers.PropertyController(topBar, ''color'', ...');
    add('        @(s) topBarColors(min(max(s.frame + 1, 1), totalFrames), :));');
    add('    midBarCtrl = stage.builtin.controllers.PropertyController(midBar, ''color'', ...');
    add('        @(s) midBarColors(min(max(s.frame + 1, 1), totalFrames), :));');
    add('    botBarCtrl = stage.builtin.controllers.PropertyController(botBar, ''color'', ...');
    add('        @(s) botBarColors(min(max(s.frame + 1, 1), totalFrames), :));');
    add();
end

function local_emitBarAdds(add)
% The bar stimuli go in LAST, so they draw over every stimulus and phase color.
    add('    presentation.addStimulus(topBar);');
    add('    presentation.addStimulus(midBar);');
    add('    presentation.addStimulus(botBar);');
end

function local_emitBarCtrlAdds(add)
    add('    presentation.addController(topBarCtrl);');
    add('    presentation.addController(midBarCtrl);');
    add('    presentation.addController(botBarCtrl);');
end

function c = local_cone(iso)
    if iso, c = 'S'; else, c = 'achromatic'; end
end

function s = local_gridNote(g)
    if isempty(g), s = '(left alone)'; else, s = mat2str(g, 4); end
end

function s = local_gridSrc(g)
    if isempty(g), s = '[]'; else, s = mat2str(g); end
end
