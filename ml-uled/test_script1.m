%% test_script1  --  LED-rig communication test
%
% LIFECYCLE: ONE shared rig for the whole MATLAB session -- this script, the
% stimulusGUI quick-set, and the command prompt all reuse the base-workspace
% `rig` (one open COM port, no reconnect cost). A live rig is REUSED as-is; a
% stale one (cleared / unplugged) is rebuilt. `clear rig` closes the port when
% you are done (the destructor sets mode 0 first).
if ~(exist('rig','var') && isa(rig,'NeitzLedRig') && isvalid(rig) && rig.isConnected())
    clear rig                                   % drop any stale handle, then connect:
    rig = NeitzLedRig('COM3');                  % this rig's port (rig_config led_port)
    % rig = NeitzLedRig();                      % AUTO-probe fallback (slower)
    % rig = NeitzLedRig('/dev/cu.usbserial-1101');   % macOS node
end
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
% rig.setTtlDebug(enable,R,G,B) to simulate them (R=100, G=010, B=001; two-or-
% more colours, or none, = LEDs dark).



% load intensities: setIntensity(led 0..3, 'r'/'g'/'b', frac 0..1)
%rig.setIntensity(0,'r',1.0);        % LED0 Red = 100%
%rig.setIntensity(1,'r',0.0);         % LED1 Red = 0
%rig.setIntensity(2,'r',0.0);         % LED2 Red = 0
%rig.setIntensity(3,'r',0.0);         % LED3 Red = 0
%rig.setIntensity(0,'g',0.0);        % LED0 Grn = 0
%rig.setIntensity(1,'g',0.0625);         % LED1 Grn = 0.5
%rig.setIntensity(2,'g',0.0);         % LED2 Grn = 0
%rig.setIntensity(3,'g',0.0);         % LED3 Grn = 0
%rig.setIntensity(0,'b',0.0);        % LED0 Blu = 0
%rig.setIntensity(1,'b',0.0);         % LED1 Blu = 0
%rig.setIntensity(2,'b',1.0);         % LED2 Blu = 0
%rig.setIntensity(3,'b',1.0);         % LED3 Blu = 0.125

% load intensities: setIntensity(led 0..3, 'r'/'g'/'b', frac 0..1)
rig.setIntensity(0,'r',0.125);        % LED0 Red = 100%
rig.setIntensity(1,'r',0.125);         % LED1 Red = 0
rig.setIntensity(2,'r',0.125);         % LED2 Red = 0
rig.setIntensity(3,'r',0.125);         % LED3 Red = 0
rig.setIntensity(0,'g',0.125);        % LED0 Grn = 0
rig.setIntensity(1,'g',0.125);         % LED1 Grn = 0.5
rig.setIntensity(2,'g',0.125);         % LED2 Grn = 0
rig.setIntensity(3,'g',0.125);         % LED3 Grn = 0
rig.setIntensity(0,'b',0.125);        % LED0 Blu = 0
rig.setIntensity(1,'b',0.125);         % LED1 Blu = 0
rig.setIntensity(2,'b',0.125);         % LED2 Blu = 0
rig.setIntensity(3,'b',0.125);         % LED3 Blu = 0.125


%rig.setMode(1);                      % (1) DC red -> the 4 LEDs show their Red values
rig.setMode(3);                      % (1) video mode
%pause(5);
%rig.setTtlDebug(true, 1,0,0);        % (2) force Red field  -> red values on LEDs
%rig.setTtlDebug(true, 0,1,0);        %     force Green
%rig.setTtlDebug(true, 0,0,1);        %     force Blue
%rig.setTtlDebug(false,0,0,0);        %     release -> physical i_RGB pins
%rig.setMode(0);                      % off