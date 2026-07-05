classdef NeitzLedRig < handle
% NeitzLedRig  RS-232 driver for the lc4500 patch-rig RGB->4-LED xo3d FPGA.
%
%   rig = NeitzLedRig();            % auto-detect (Windows COMxx or macOS /dev/cu.*)
%   rig = NeitzLedRig("COM7");      % or name it explicitly on Windows 11
%   rig = NeitzLedRig("/dev/cu.usbserial-XXXX");   % ...or macOS
%
%   Cross-platform: on Windows auto-detect prefers FTDI COM ports (FTDIBUS
%   registry) then probes the rest; on macOS it uses the /dev/cu.* node.  DTR
%   and RTS are asserted on open so the FTDI VCP drives TX on both.
%
%   MATLAB replacement for the C# uLED GUI.  Talks to the MachXO3D breakout's
%   on-board FTDI channel B (a plain COM port) using the same framed protocol
%   the C# uses, and writes the SAME sp256x8 register file the design has
%   always used -- so a value set here is identical to the GUI setting it.
%
%   HARDWARE MODEL (4 LEDs x R/G/B, colour-field sequential):
%     * 4 physical LEDs                       -> led   = 0..3
%     * each LED has R, G and B intensities   -> colour = 'r' | 'g' | 'b'
%       The LightCrafter drives i_RGB to say which colour it is showing; each
%       LED then displays that colour's value.  So you set 12 intensities
%       (4 LEDs x 3 colours), exactly the C# GUI's grid.
%     * OperationMode: 0=off, 1=manual, 2=video, 3=pattern, 4=LUT
%       (0 = all dark; anything else enables the drive).
%
%   Intensity is a 17-bit PFM interval (duty = 256/interval): 256 = full on,
%   larger = dimmer, 0x1FFFF (131071) = dark.  Use intensityToCounts() to work
%   in 0..1 linear-duty units (pre-distort like lcGammaCorrect.m for light
%   that is linear at the eye).
%
%   EXAMPLE
%       rig = NeitzLedRig();
%       rig.setMode(0);                 % off while we load values
%       rig.setIntensity(0,'r',0.75);   % LED0 red   = 75%
%       rig.setIntensity(0,'g',0.50);   % LED0 green = 50%
%       rig.setMode(2);                 % video mode -> LightCrafter i_RGB drives it
%       ...
%       rig.setMode(0);                 % off
%       clear rig                       % closes the port

    properties (Constant)
        BAUD_DEFAULT   = 115200;
        CMD_WRITE_RAM  = uint8(1);      % payload = [address, data...]
        CMD_SET_TTL    = uint8(2);      % payload byte = bits[2:0] i_RGB value (active-low) + bit3 enable
        ACK_BYTE       = uint8(6);      % 0x06
        NACK_BYTE      = uint8(21);     % 0x15
        ADDR_MODE      = uint8(2);      % sp256x8 RAM address of OperationMode
        ADDR_SCRATCH   = uint8(255);    % undecoded RAM cell -> harmless probe
        PFM_DARK       = 131071;        % 0x1FFFF
        PFM_MAX        = 131071;
        PFM_ON_FULL    = 256;
    end

    properties (SetAccess = private)
        Port     string = "";
        Baud (1,1) double = 115200;
    end

    properties (Access = private)
        sp = [];
    end

    methods
        function obj = NeitzLedRig(port, baud)
            if nargin < 2 || isempty(baud), baud = NeitzLedRig.BAUD_DEFAULT; end
            obj.Baud = baud;
            if nargin < 1 || isempty(port) || strcmpi(port,"AUTO")
                obj.Port = NeitzLedRig.autoDetect(baud);
                if obj.Port == ""
                    error("NeitzLedRig:noDevice", ...
                        "No LED-driver FPGA answered on any serial port.");
                end
            else
                obj.Port = NeitzLedRig.toCallout(port);   % force /dev/cu.*, never /dev/tty.*
            end
            try
                obj.sp = serialport(obj.Port, obj.Baud);
            catch openErr
                error("NeitzLedRig:portBusy", ...
                    ['Could not open %s: %s\n' ...
                     'If a previous NeitzLedRig is still holding it, run:  clear rig'], ...
                    obj.Port, openErr.message);
            end
            configureTerminator(obj.sp, "LF");
            obj.sp.Timeout = 0.5;
            setDTR(obj.sp, true);   % FTDI VCP won't reliably drive TX until DTR and
            setRTS(obj.sp, true);   % RTS are asserted (same fix as the C# SerialTransport)
            flush(obj.sp);
            if ~obj.sendPacket(obj.CMD_WRITE_RAM, uint8([obj.ADDR_SCRATCH, 0]))
                delete(obj.sp); obj.sp = [];
                error("NeitzLedRig:noAck", "Port %s did not ACK a test write.", obj.Port);
            end
            fprintf("NeitzLedRig connected on %s\n", obj.Port);
        end

        function delete(obj)
            try
                if ~isempty(obj.sp) && isvalid(obj.sp), obj.setMode(0); end
            catch
            end
            if ~isempty(obj.sp), try, delete(obj.sp); catch, end, obj.sp = []; end
        end

        function tf = isConnected(obj)
            tf = ~isempty(obj.sp) && isvalid(obj.sp);
        end

        % --- commands (return logical ok = FPGA-confirmed ACK) ---
        function ok = setMode(obj, mode)
            % OperationMode (same as the C# radio buttons):
            %   0 = off        1 = DC red (drives red channel, ignores i_RGB)
            %   2 = video RGB (no sync)   3 = video RGB (w/ sync)
            %   4 = pattern    5 = LUT    (4/5 are dark in this pfmval build)
            % Video modes 2/3 use i_RGB (real TTL pins or setTtlDebug) to pick
            % the colour; modes 0/1 ignore it.
            ok = obj.writeRam(obj.ADDR_MODE, uint8(bitand(mode,7)));
        end

        function ok = setPfm(obj, led, colour, counts)
            % Write one 32-bit pfmval register (raw 17-bit interval in counts).
            addr = NeitzLedRig.pfmAddr(led, colour);
            counts = max(0, min(obj.PFM_MAX, round(counts)));
            data = uint8([ bitand(bitshift(counts,-24),255), ...
                           bitand(bitshift(counts,-16),255), ...
                           bitand(bitshift(counts, -8),255), ...
                           bitand(counts,255) ]);
            ok = obj.writeRam(addr, data);
        end

        function ok = setIntensity(obj, led, colour, frac)
            % Set one channel from a 0..1 linear duty (see intensityToCounts).
            ok = obj.setPfm(led, colour, NeitzLedRig.intensityToCounts(frac));
        end

        function ok = allOff(obj)
            % Simplest safe "off": OperationMode 0 darkens every LED.
            ok = obj.setMode(0);
        end

        function ok = setTtlDebug(obj, enable, r, g, b)
            % Debug: inject the i_RGB colour field over RS-232, matching the
            % real TTL lines (active-low / one-cold): R=011, G=101, B=110; 0 or
            % 2+ colours -> intermediate -> dark.  enable=false reverts to pins.
            rgb = 7;                            % 111 = no colour
            if logical(r), rgb = rgb - 4; end   % R = i_RGB bit2 low
            if logical(g), rgb = rgb - 2; end   % G = i_RGB bit1 low
            if logical(b), rgb = rgb - 1; end   % B = i_RGB bit0 low
            v = uint8(rgb + logical(enable) * 8);
            ok = obj.sendPacket(obj.CMD_SET_TTL, v);
        end

        function ok = writeRam(obj, addr, dataBytes)
            % Low-level: write dataBytes into sp256x8 starting at addr.
            ok = obj.sendPacket(obj.CMD_WRITE_RAM, uint8([addr, dataBytes(:).']));
        end
    end

    methods (Static)
        function counts = intensityToCounts(frac)
            % 0..1 linear duty -> 17-bit PFM interval (duty = 256/interval).
            frac = min(max(frac,0),1);
            if frac <= 0, counts = NeitzLedRig.PFM_DARK; return; end
            counts = round(NeitzLedRig.PFM_ON_FULL / frac);
            counts = max(NeitzLedRig.PFM_ON_FULL, min(NeitzLedRig.PFM_MAX, counts));
        end

        function addr = pfmAddr(led, colour)
            % sp256x8 MSB-byte address of a pfmval (matches C# rgb_xo3_addresses).
            if led < 0 || led > 3, error("NeitzLedRig:led", "led must be 0..3"); end
            switch lower(char(colour))
                case 'r', base = 37;   % 37,41,45,49
                case 'g', base = 21;   % 21,25,29,33
                case 'b', base = 5;    %  5, 9,13,17
                otherwise, error("NeitzLedRig:colour", "colour must be 'r','g' or 'b'");
            end
            addr = uint8(base + 4*led);
        end

        function port = autoDetect(baud)
            if nargin < 1, baud = NeitzLedRig.BAUD_DEFAULT; end
            port = "";
            try, names = serialportlist("available"); catch, names = serialportlist(); end
            names = string(names);
            if isempty(names), return; end
            if ispc
                % Windows 11: probe COM ports -- FTDI ones first (from the
                % FTDIBUS registry, like the C#), then any other COM as fallback.
                com  = names(startsWith(upper(names), "COM"));
                ftdi = NeitzLedRig.windowsFtdiPorts();
                ftdi = ftdi(ismember(upper(ftdi), upper(com)));            % only ports present now
                names = [ftdi, com(~ismember(upper(com), upper(ftdi)))];   % FTDI first, deduped
            else
                % macOS/Linux: only real USB-serial nodes, on the cu.* call-out
                % node.  Never poke Bluetooth / headphones / debug-console --
                % opening those floods timeouts and can hijack a BT link.
                keep  = contains(lower(names), ["usbserial","usbmodem"]);
                names = names(keep);
                names = names(~startsWith(names, "/dev/tty."));
            end
            for nm = names
                cand = NeitzLedRig.toCallout(nm);   % no-op on Windows COM names
                if NeitzLedRig.probePort(cand, baud), port = cand; return; end
            end
        end

        function out = toCallout(name)
            % macOS: use the /dev/cu.* call-out node, never /dev/tty.* (tty.*
            % blocks on carrier-detect the FPGA never drives).  On Windows the
            % name is "COMxx" and this is a no-op.
            out = replace(string(name), "/dev/tty.", "/dev/cu.");
        end

        function ports = windowsFtdiPorts()
            % Windows only: COM ports belonging to an FTDI device, read from the
            % FTDIBUS registry enumeration.  Empty on any failure (caller then
            % just probes every COM port).
            ports = strings(1,0);
            try
                [st, out] = system(['reg query ' ...
                    '"HKLM\SYSTEM\CurrentControlSet\Enum\FTDIBUS" /s /v PortName']);
                if st == 0
                    toks = regexp(out, 'PortName\s+REG_SZ\s+(COM\d+)', 'tokens');
                    for i = 1:numel(toks), ports(end+1) = string(toks{i}{1}); end %#ok<AGROW>
                    ports = unique(ports, 'stable');
                end
            catch
                ports = strings(1,0);
            end
        end

        function tf = probePort(name, baud)
            % Open a bare serialport, assert DTR/RTS, send a scratch write, and
            % return true iff the FPGA ACKs (0x06).  Always closes; never warns.
            tf = false; sp = [];
            ws = warning('off','all');
            try
                sp = serialport(name, baud);
                configureTerminator(sp, "LF");
                sp.Timeout = 0.3;
                setDTR(sp, true); setRTS(sp, true);
                flush(sp);
                type = NeitzLedRig.CMD_WRITE_RAM;
                payload = uint8([NeitzLedRig.ADDR_SCRATCH, 0]);
                ck = bitxor(bitxor(bitxor(type, uint8(2)), payload(1)), payload(2));
                write(sp, [type, uint8(2), payload, ck], "uint8");
                b = read(sp, 1, "uint8");
                tf = ~isempty(b) && uint8(b(1)) == NeitzLedRig.ACK_BYTE;
            catch
                tf = false;
            end
            if ~isempty(sp), try, delete(sp); catch, end, end
            warning(ws);
        end
    end

    methods (Access = private)
        function ok = sendPacket(obj, type, payload, maxRetries)
            if nargin < 4, maxRetries = 2; end
            payload = uint8(payload);
            len = uint8(numel(payload));
            cksum = bitxor(type, len);
            for k = 1:numel(payload), cksum = bitxor(cksum, payload(k)); end
            frame = [type, len, payload, cksum];
            for attempt = 0:maxRetries
                flush(obj.sp);
                write(obj.sp, frame, "uint8");
                b = obj.readByte(0.25);
                if isempty(b)
                    continue;
                elseif b == obj.ACK_BYTE
                    ok = true; return;
                elseif b == obj.NACK_BYTE
                    continue;
                end
            end
            ok = false;
        end

        function b = readByte(obj, timeoutS)
            if nargin >= 2 && ~isempty(timeoutS), obj.sp.Timeout = timeoutS; end
            ws = warning('off','all');   % an empty read is expected here -- don't spam the console
            try, raw = read(obj.sp, 1, "uint8"); catch, raw = []; end
            warning(ws);
            if isempty(raw), b = []; else, b = uint8(raw(1)); end
        end
    end
end
