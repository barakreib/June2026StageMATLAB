"""
lcr4500.py -- minimal USB-HID transport for the TI DLP LightCrafter 4500
(DLPC350 controller). Windows 11 / Python 3.9+.

Requires:  pip install hidapi

Packet format (DLPC350 Programmer's Guide, DLPU010):
    byte 0     HID report ID .......... 0x00
    byte 1     flags .................. bit7 rw (0=write, 1=read)
                                        bit6 reply requested
    byte 2     sequence number
    byte 3-4   payload length, LE ..... len(data) + 2
    byte 5-6   command word, LE ....... CMD3 then CMD2
    byte 7+    data, zero padded to 64 bytes

The CMD3-before-CMD2 ordering is not a typo: TI's own API packs the
command as (CMD2 << 8) | CMD3 into a little-endian uint16, so CMD3 goes
out on the wire first. Getting this backwards is the single most common
reason a hand-rolled DLPC350 packet is silently ignored.

Multiple projectors: LCr4500(device=<selector>) picks one unit when more
than one is attached. A selector is an index (into the path-sorted list),
an exact serial number, or a case-insensitive substring of the HID path.
LC4500 units frequently report empty or identical serial numbers, so the
HID path is the reliable identity: on Windows it encodes the hub/port
chain, which is stable across reboots and power cycles FOR A GIVEN
PHYSICAL USB PORT but changes if the cable moves to a different port.
Label the ports on the rig machine and pin each unit by path substring.
"""

import time

try:
    import hid
except ImportError:  # pragma: no cover
    raise SystemExit(
        "The 'hid' module is missing from THIS Python.\n"
        "\n"
        "Most likely you ran `python gamma.py` with the system Python instead\n"
        "of the virtual environment. Use the numbered .bat files, which pick\n"
        "the venv automatically:\n"
        "    .\\1-check-connection.bat\n"
        "    .\\2-degamma-OFF.bat\n"
        "\n"
        "Or call the venv interpreter directly:\n"
        "    .venv\\Scripts\\python.exe gamma.py read\n"
        "\n"
        "Failing that:  pip install hidapi"
    )

VID = 0x0451          # Texas Instruments
PID = 0x6401          # DLPC350 / LightCrafter 4500

REPORT_LEN = 64
FLAG_WRITE = 0x40     # rw = 0 (write), reply = 1
FLAG_READ = 0xC0      # rw = 1 (read),  reply = 1

# (CMD2, CMD3) pairs used here
CMD_VERSION = (0x02, 0x05)
CMD_MAIN_STATUS = (0x1A, 0x0C)
CMD_GAMMA = (0x1A, 0x0E)
CMD_DISPLAY_MODE = (0x1A, 0x1B)
CMD_INPUT_SOURCE = (0x1A, 0x00)
CMD_PIXEL_FORMAT = (0x1A, 0x02)
CMD_PORT_CLOCK = (0x1A, 0x03)
CMD_CSC_INPUT = (0x1A, 0x0D)
CMD_LED_ENABLE = (0x1A, 0x07)
CMD_LED_CURRENT = (0x0B, 0x01)
CMD_TESTPATTERN = (0x12, 0x03)

SRC_PARALLEL = 0
SRC_TESTPATTERN = 1

TEST_PATTERNS = {
    "solid": 0x0,
    "hramp": 0x1,
    "vramp": 0x2,
    "hlines": 0x3,
    "diaglines": 0x4,
    "vlines": 0x5,
    "grid": 0x6,
    "checker": 0x7,
    "rgbramp": 0x8,
    "colorbars": 0x9,
    "stepbars": 0xA,
}


class DeviceNotFound(Exception):
    pass


class AmbiguousDevice(DeviceNotFound):
    """A device selector matched more than one attached unit."""
    pass


def enumerate_devices():
    """Every HID interface the OS is exposing for the LightCrafter."""
    try:
        return hid.enumerate(VID, PID)
    except Exception:
        return []


def list_devices():
    """enumerate_devices(), stable-sorted by path -- the order that index
    selectors and DEV listings refer to."""
    return sorted(enumerate_devices(), key=_path_str)


def _path_str(d):
    p = d.get("path", b"") or b""
    if isinstance(p, bytes):
        return p.decode("utf-8", errors="replace")
    return str(p)


def format_device_line(i, d):
    serial = d.get("serial_number") or ""
    return f'DEV index={i} serial="{serial}" path="{_path_str(d)}"'


def _device_listing(devices):
    if not devices:
        return "  (no LightCrafter HID interfaces enumerated)"
    return "\n".join("  " + format_device_line(i, d) for i, d in enumerate(devices))


def resolve_device(devices, selector):
    """Pick exactly one device dict out of a hid.enumerate() list.

    selector, tried in order:
      1. all digits ......... index into the list stable-sorted by path
                              (hid.enumerate order is not guaranteed)
      2. exact match ........ on a non-empty serial_number
      3. substring .......... case-insensitive, against the HID path

    Raises DeviceNotFound on zero matches and AmbiguousDevice on more than
    one -- never silently picks the first when a selector was given, because
    LC4500 serials are often empty or identical across units.
    """
    devices = sorted(devices, key=_path_str)
    sel = str(selector).strip()
    if not devices:
        raise DeviceNotFound(
            f"Device selector '{sel}' matched nothing: no LightCrafter HID "
            f"interfaces are enumerated at all.{TROUBLESHOOT}")
    if not sel:
        raise DeviceNotFound(
            "Empty device selector. Give an index, an exact serial number, "
            "or a substring of the HID path. Attached now:\n"
            + _device_listing(devices))
    if sel.isdigit():
        i = int(sel)
        if i >= len(devices):
            raise DeviceNotFound(
                f"Device index {i} is out of range -- {len(devices)} "
                f"device(s) attached:\n" + _device_listing(devices))
        return devices[i]
    matches = [d for d in devices if (d.get("serial_number") or "") == sel]
    if not matches:
        matches = [d for d in devices if sel.lower() in _path_str(d).lower()]
    if len(matches) == 1:
        return matches[0]
    if matches:
        raise AmbiguousDevice(
            f"Device selector '{sel}' matches {len(matches)} units -- refusing "
            f"to guess. Pin each unit by a unique HID-path substring "
            f"(serials on LC4500s are often empty or duplicated):\n"
            + _device_listing(matches))
    raise DeviceNotFound(
        f"Device selector '{sel}' matched no attached unit. Attached now:\n"
        + _device_listing(devices))


TROUBLESHOOT = """
Troubleshooting, in the order worth trying:

  1. Close the TI LightCrafter 4500 Control Software COMPLETELY -- not
     minimised, and check Task Manager for a leftover process. It holds the
     USB HID handle and polls continuously when "Auto Update Status" is
     ticked. This is by far the most common cause.
  2. Close any other window of this toolkit that may still be talking to
     the projector.
  3. Unplug and replug the mini-USB cable, wait ~5 seconds, retry.
  4. Confirm the projector is powered and not in Power Standby.
  5. Device Manager -> Human Interface Devices should show a
     "HID-compliant vendor-defined device" while it is plugged in.
"""


def build_packet(flags, seq, cmd2, cmd3, data=b""):
    length = len(data) + 2
    body = bytes([flags, seq & 0xFF, length & 0xFF, (length >> 8) & 0xFF, cmd3, cmd2])
    body += bytes(data)
    return bytes([0x00]) + body.ljust(REPORT_LEN, b"\x00")


class LCr4500:
    def __init__(self, device=None):
        """device: None opens the first unit the OS hands over (single-
        projector behavior, unchanged); otherwise a selector for
        resolve_device() -- index, exact serial, or path substring."""
        self.dev = None
        self.device = device
        self._seq = 0

    # -- lifecycle ---------------------------------------------------
    def open(self):
        target_path = None
        if self.device is not None:
            # resolve first: raises DeviceNotFound/AmbiguousDevice with a
            # full listing, which beats a bare open() error.
            target_path = resolve_device(enumerate_devices(), self.device)["path"]
        self.dev = hid.device()
        try:
            if target_path is None:
                self.dev.open(VID, PID)
            else:
                self.dev.open_path(target_path)
        except (OSError, IOError) as exc:
            found = enumerate_devices()
            if found:
                detail = (f"The OS DOES see the device ({len(found)} HID "
                          f"interface(s)), so it is plugged in and enumerating "
                          f"-- something else has the handle.")
            else:
                detail = ("The OS does not see the device at all. It is "
                          "unplugged, unpowered, or the cable is bad.")
            which = "" if self.device is None else f" (selector '{self.device}')"
            raise DeviceNotFound(
                f"Could not open the LightCrafter 4500 ({VID:04X}:{PID:04X}){which}.\n"
                f"  {exc}\n"
                f"  {detail}\n{TROUBLESHOOT}"
            )
        self.dev.set_nonblocking(0)
        return self

    def close(self):
        if self.dev is not None:
            self.dev.close()
            self.dev = None

    def __enter__(self):
        return self.open()

    def __exit__(self, *exc):
        self.close()
        return False

    # -- transport ---------------------------------------------------
    def _next_seq(self):
        self._seq = (self._seq + 1) & 0xFF
        return self._seq

    def _drain(self):
        """Discard any stale input reports. Never fatal."""
        for _ in range(16):
            try:
                if not self.dev.read(REPORT_LEN, timeout_ms=20):
                    return
            except (OSError, IOError):
                return

    def write(self, cmd, data, attempts=3):
        cmd2, cmd3 = cmd
        last = None
        for attempt in range(attempts):
            try:
                self._drain()
                self.dev.write(
                    build_packet(FLAG_WRITE, self._next_seq(), cmd2, cmd3, bytes(data)))
                time.sleep(0.05)
                try:
                    self.dev.read(REPORT_LEN, timeout_ms=300)   # ack, ignored
                except (OSError, IOError):
                    pass
                return
            except (OSError, IOError) as exc:
                last = exc
                time.sleep(0.15 * (attempt + 1))
        raise IOError(
            f"Write of CMD2=0x{cmd2:02X} CMD3=0x{cmd3:02X} failed after "
            f"{attempts} attempts: {last}\n{TROUBLESHOOT}")

    def read(self, cmd, nbytes=1, timeout_ms=1000, attempts=3):
        cmd2, cmd3 = cmd
        last = None
        for attempt in range(attempts):
            try:
                self._drain()
                self.dev.write(build_packet(FLAG_READ, self._next_seq(), cmd2, cmd3))
                time.sleep(0.05)
                rep = self.dev.read(REPORT_LEN, timeout_ms=timeout_ms)
                if rep:
                    # reply layout: flags, seq, len_lo, len_hi, data...
                    return bytes(rep[4:4 + nbytes])
                last = "empty reply"
            except (OSError, IOError) as exc:
                last = exc
            time.sleep(0.15 * (attempt + 1))
        raise IOError(
            f"Read of CMD2=0x{cmd2:02X} CMD3=0x{cmd3:02X} failed after "
            f"{attempts} attempts: {last}\n{TROUBLESHOOT}")

    # -- convenience -------------------------------------------------
    def firmware_version(self):
        raw = self.read(CMD_VERSION, 16)
        names = ("Application", "API", "Software config", "Sequencer config")
        out = {}
        for i, name in enumerate(names):
            word = int.from_bytes(raw[i * 4:i * 4 + 4], "little")
            out[name] = f"{(word >> 24) & 0xFF}.{(word >> 16) & 0xFF}.{word & 0xFFFF}"
        return out

    def main_status(self):
        b = self.read(CMD_MAIN_STATUS)[0]
        return {
            "raw": b,
            "dmd_parked": bool(b & 0x01),
            "sequencer_running": bool(b & 0x02),
            "buffer_frozen": bool(b & 0x04),
            "gamma_enabled": bool(b & 0x08),
        }

    def get_gamma(self):
        return self.read(CMD_GAMMA)[0]

    def set_gamma(self, enabled, table=0):
        value = (0x80 if enabled else 0x00) | (table & 0x01)
        self.write(CMD_GAMMA, [value])
        return value

    def display_mode(self):
        return "pattern" if (self.read(CMD_DISPLAY_MODE)[0] & 0x01) else "video"

    def input_source(self):
        b = self.read(CMD_INPUT_SOURCE)[0]
        src = {0: "parallel (HDMI)", 1: "internal test pattern",
               2: "flash", 3: "FPD-link"}.get(b & 0x07, f"unknown ({b & 0x07})")
        depth = {0: "30 bit", 1: "24 bit", 2: "20 bit", 3: "16 bit",
                 4: "10 bit", 5: "8 bit"}.get((b >> 3) & 0x07, "?")
        return f"{src}, parallel bit depth {depth}"

    def pixel_format(self):
        v = self.read(CMD_PIXEL_FORMAT)[0] & 0x0F
        return {0: "RGB 4:4:4 (30 bit)", 1: "YCrCb 4:4:4 (30 bit)",
                2: "YCrCb 4:2:2"}.get(v, f"unknown ({v})")

    def csc_input(self):
        v = self.read(CMD_CSC_INPUT)[0] & 0x03
        return {0: "RGB 4:4:4", 1: "YCrCb 4:4:4",
                2: "YCrCb 4:2:2"}.get(v, f"unknown ({v})")

    def port_clock(self):
        return self.read(CMD_PORT_CLOCK)[0] & 0x07

    def led_enable(self):
        """LED Enable Outputs. Reset default is 0x08 = sequencer controlled."""
        b = self.read(CMD_LED_ENABLE)[0]
        return {
            "raw": b,
            "sequencer_controlled": bool(b & 0x08),
            "red": bool(b & 0x01),
            "green": bool(b & 0x02),
            "blue": bool(b & 0x04),
        }

    def set_led_sequencer(self):
        """Hand the LEDs back to the sequencer (the power-on default, 0x08).

        Does NOT touch LED drive currents -- that is the command TI puts a
        damage warning on, and nothing here writes to it.
        """
        self.write(CMD_LED_ENABLE, [0x08])
        return self.led_enable()

    def set_input_source(self, source, bit_depth_bits=None):
        """source: 0 = parallel/HDMI, 1 = internal test pattern.

        Preserves the existing parallel bit-depth field unless told otherwise.
        """
        current = self.read(CMD_INPUT_SOURCE)[0]
        depth = current & 0x38 if bit_depth_bits is None else (bit_depth_bits << 3) & 0x38
        self.write(CMD_INPUT_SOURCE, [(source & 0x07) | depth])

    def set_test_pattern(self, pattern):
        self.write(CMD_TESTPATTERN, [pattern & 0x0F])

    def led_currents(self):
        raw = self.read(CMD_LED_CURRENT, 3)
        return {"red": raw[0], "green": raw[1], "blue": raw[2]}


def describe_gamma(byte):
    state = "ENABLED  -> non-linear output" if (byte & 0x80) else "DISABLED -> linear output"
    table = "TI Video (Max Brightness)" if (byte & 0x01) else "TI Video (Enhanced)"
    return f"0x{byte:02X}  degamma {state}   [table: {table}]"
