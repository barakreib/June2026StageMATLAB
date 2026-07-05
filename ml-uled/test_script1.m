%% test_script1  --  LED-rig communication test
%
% LIFECYCLE: keep ONE rig and reuse it for many sends -- the COM port stays
% open (fast; you can keep sending at the prompt after the script). Close it
% with `clear rig` or `delete(rig)` (the destructor sets mode 0 + closes).
% The line below releases a previous run's rig so re-running never hits
% "port in use". (It can't move into the class -- it refers to this script's
% `rig` workspace variable.)
if exist('rig','var'); try, delete(rig); catch, end; clear rig; end

% ----- CONNECT: pick ONE. Hard-coding is the most predictable. -----
% rig = NeitzLedRig();                          % auto-detect (see note below)
% rig = NeitzLedRig("COM21");                   % Windows 11: hard-code the COM port
rig = NeitzLedRig('/dev/cu.usbserial-1101');    % macOS: hard-code the /dev/cu.* node
%
% Auto-detect is NOT a blind sweep: it opens each candidate, sends a scratch
% write, and keeps only the port that answers with the FPGA's ACK byte (0x06),
% so it won't grab a random device -- on Windows it tries FTDI-registry COM
% ports first. To hard-code, find the port in Device Manager (Windows, "USB
% Serial Port (COMxx)") or via `serialportlist` (either OS).

% ===== OperationMode -- rig.setMode(m) (matches the C# radio buttons) =====
%   0  OFF        all LEDs dark
%   1  DC red     every LED shows its RED value, constant (ignores i_RGB)
%   2  Video RGB  colour-field sequential; colour chosen by i_RGB (no sync)
%   3  Video RGB  same, with vsync
%   4  Pattern    (FUTURE) red-channel pattern w/ sync -- not in this FPGA
%                 build yet; currently dark
%   5  LUT        (FUTURE) LUT-driven waveforms -- not built yet; currently dark
% In the video modes (2/3) the colour comes from i_RGB: the real TTL pins, or
% rig.setTtlDebug(enable,R,G,B) to simulate them (R=011, G=101, B=110; two-or-
% more colours, or none, = intermediate = LEDs dark).



% load intensities: setIntensity(led 0..3, 'r'/'g'/'b', frac 0..1)
rig.setIntensity(0,'r',1.0);        % LED0 Red = 100%
rig.setIntensity(1,'r',0.0);         % LED1 Red = 0
rig.setIntensity(2,'r',0.0);         % LED2 Red = 0
rig.setIntensity(3,'r',0.0);         % LED3 Red = 0
rig.setIntensity(0,'g',0.0);        % LED0 Grn = 0
rig.setIntensity(1,'g',0.5);         % LED1 Grn = 0.5
rig.setIntensity(2,'g',0.0);         % LED2 Grn = 0
rig.setIntensity(3,'g',0.0);         % LED3 Grn = 0
rig.setIntensity(0,'b',0.0);        % LED0 Blu = 0
rig.setIntensity(1,'b',0.0);         % LED1 Blu = 0
rig.setIntensity(2,'b',0.0);         % LED2 Blu = 0
rig.setIntensity(3,'b',0.125);         % LED3 Blu = 0.125




%rig.setMode(1);                      % (1) DC red -> the 4 LEDs show their Red values
rig.setMode(2);                      % (1) video mode
rig.setTtlDebug(true, 1,0,0);        % (2) force Red field  -> red values on LEDs
%rig.setTtlDebug(true, 0,1,0);        %     force Green
%rig.setTtlDebug(true, 0,0,1);        %     force Blue
%rig.setTtlDebug(false,0,0,0);        %     release -> physical i_RGB pins
%rig.setMode(0);                      % off