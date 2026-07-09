%% demoLedRig  Precise example: connect, set values, pick mode, inject R/G/B TTL.
%
% Every call returns a logical ok = the FPGA ACKed the write.
%
% LIFECYCLE: ONE shared rig for the whole MATLAB session -- this script, the
% stimulusGUI quick-set, and the command prompt all reuse the base-workspace
% `rig` (one open COM port, no reconnect cost). A live rig is REUSED as-is; a
% stale one (cleared / unplugged) is rebuilt. `clear rig` closes the port when
% you are done (the destructor sets mode 0 first).
if ~(exist('rig','var') && isa(rig,'NeitzLedRig') && isvalid(rig) && rig.isConnected())
    clear rig                                   % drop any stale handle, then connect:
    rig = NeitzLedRig('COM3');                  % this rig's port (rig_config led_port)
    % rig = NeitzLedRig();                      % AUTO-probe fallback (slower), if the
    %                                           %   port ever moves; see Device Manager
    % rig = NeitzLedRig('/dev/cu.usbserial-1101');   % macOS node
end

% ===== OperationMode -- rig.setMode(m) (matches the C# radio buttons) =====
%   0 OFF    1 DC red    2 Video RGB (no sync)    3 Video RGB (w/ sync)
%   4 Pattern (FUTURE, not built -> dark)         5 LUT (FUTURE, not built -> dark)
% DC red drives the Red column ignoring i_RGB; the video modes pick the colour
% from i_RGB (real TTL pins, or setTtlDebug below: R=100, G=010, B=001; else dark).

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
