%% demoLedRig  Precise example: connect, set values, pick mode, inject R/G/B TTL.
%
% Every call returns a logical ok = the FPGA ACKed the write.
%
% LIFECYCLE: keep ONE rig and reuse it for many sends -- the COM port stays
% open until you `clear rig` / `delete(rig)` (the destructor sets mode 0 and
% closes it).  The guard below releases a previous run's rig so re-running
% never hits "port in use".
if exist('rig','var'); try, delete(rig); catch, end; clear rig; end

% ----- CONNECT: pick ONE. Hard-coding is the most predictable. -----
% rig = NeitzLedRig();                          % auto-detect (probes for the
%                                               %   FPGA's ACK -- not a blind sweep)
% rig = NeitzLedRig("COM21");                   % Windows 11: hard-code the COM port
rig = NeitzLedRig('/dev/cu.usbserial-1101');    % macOS: hard-code the /dev/cu.* node
% Find the port in Device Manager (Windows, "USB Serial Port (COMxx)") or via
% `serialportlist` (either OS).

cleanupObj = onCleanup(@() clear('rig'));   % close the port when this clears

% ===== OperationMode -- rig.setMode(m) (matches the C# radio buttons) =====
%   0 OFF    1 DC red    2 Video RGB (no sync)    3 Video RGB (w/ sync)
%   4 Pattern (FUTURE, not built -> dark)         5 LUT (FUTURE, not built -> dark)
% DC red drives the Red column ignoring i_RGB; the video modes pick the colour
% from i_RGB (real TTL pins, or setTtlDebug below: R=011, G=101, B=110; else dark).

% ---- load the 12 intensity registers (4 LEDs x R/G/B), 0..1 linear duty ----
for led = 0:3
    rig.setIntensity(led, 'r', 0.75);    % Red   column
    rig.setIntensity(led, 'g', 0.50);    % Green column
    rig.setIntensity(led, 'b', 0.25);    % Blue  column
end

% ---- (1) select the program mode (== the C# radio buttons) ----
rig.setMode(1);        % 1 = "LEDs DC (red chan)": the 4 LEDs show their RED
pause(2);              %     values now, no i_RGB needed.

% ---- (2) video mode + simulated R/G/B TTL (== the C# Debug checkboxes) ----
rig.setMode(2);                      % 2 = Video RGB: colour chosen by i_RGB
rig.setTtlDebug(true, 1, 0, 0);      % force Red   field -> red values show
pause(1);
rig.setTtlDebug(true, 0, 1, 0);      % force Green field
pause(1);
rig.setTtlDebug(true, 0, 0, 1);      % force Blue  field
pause(1);
rig.setTtlDebug(true, 1, 1, 0);      % two colours = intermediate -> LEDs dark
pause(1);
rig.setTtlDebug(false, 0, 0, 0);     % release override -> physical i_RGB pins

rig.setMode(0);                      % off
fprintf('demo done -- LEDs off.\n');
