# DLPC350 quick reference

Everything here was read out of the DLPC350 Programmer's Guide (DLPU010F)
and cross-checked against TI's C API, so it stands on its own if that box
never reaches ti.com. Page-level detail still lives in the PDF —
run `GET-DOCS.bat`.

**USB identity:** VID `0x0451` (Texas Instruments), PID `0x6401` (DLPC350).
Enumerates as a standard HID device. No driver install, on any Windows version.

---

## USB HID packet layout

```
byte 0     HID report ID ...... 0x00
byte 1     flags .............. bit 7 rw    (0 = write, 1 = read)
                                bit 6 reply (1 = reply requested)
                                -> 0x40 write, 0xC0 read
byte 2     sequence number .... any value, echoed back
byte 3-4   payload length ..... little endian, = len(data) + 2
byte 5-6   command word ....... little endian u16 -> CMD3 first, then CMD2
byte 7+    data ............... zero padded to 64 bytes
```

**CMD3 goes on the wire before CMD2.** TI's own API builds the command as
`(CMD2 << 8) | CMD3` into a little-endian `uint16`, so the low byte — CMD3 —
is transmitted first. Reversing these is the single most common reason a
hand-rolled DLPC350 packet is silently ignored, with no error of any kind.

Worked example, de-gamma off:

```
00  40  01  03 00  0E 1A  00   <zeros to 64>
^   ^   ^   ^      ^      ^
|   |   |   |      |      data = 0x00 (bit 7 clear -> disabled)
|   |   |   |      CMD3=0x0E, CMD2=0x1A
|   |   |   length = 3 (one data byte + two command bytes)
|   |   sequence
|   flags: write, reply requested
report ID
```

Read the same register back: flags `0xC0`, length `2`, no data byte. The
reply arrives as a 64-byte input report; payload starts at byte 4.

---

## Gamma Correction (De-gamma) — the command this package exists for

| | |
|---|---|
| I²C register | `0x31` |
| USB | `CMD2 = 0x1A`, `CMD3 = 0x0E` |
| Data | one byte |

| Bit | Meaning | Reset |
|---|---|---|
| 7 | Gamma correction enable. `0` = disabled, `1` = enabled | `1` |
| 6:1 | Reserved (read only) | `0` |
| 0 | De-gamma table pointer. `0` = TI Video (Enhanced), `1` = TI Video (Max Brightness) | `0` |

* Write `0x00` → de-gamma bypassed → **light output linear in code value**
* Write `0x80` → factory default restored

**Volatile.** Nothing is written to flash. Power cycling — or reflashing
firmware — restores the default of enabled. Re-apply on every power-up.

---

## Other commands used by this package

| Purpose | CMD2 | CMD3 | I²C | Notes |
|---|---|---|---|---|
| Firmware version | `0x02` | `0x05` | `0x11` | 16 bytes: application, API, software config, sequencer config. Each u32 packs major `[31:24]`, minor `[23:16]`, patch `[15:0]` |
| Main Status | `0x1A` | `0x0C` | `0x22` | one byte, bits below |
| Gamma Correction | `0x1A` | `0x0E` | `0x31` | above |
| Display Mode | `0x1A` | `0x1B` | `0x69` | bit 0: `0` = video, `1` = pattern |
| Input Source | `0x1A` | `0x00` | `0x00` | bits 2:0: `0` parallel/HDMI, `1` internal test pattern, `2` flash, `3` FPD-link |

### Main Status byte

| Bit | Meaning |
|---|---|
| 0 | DMD park status — `1` = mirrors parked |
| 1 | Sequencer run flag — `1` = running |
| 2 | Frame buffer swap flag — `1` = frozen |
| 3 | **Gamma correction enable — `0` = disabled, `1` = enabled** |
| 7:4 | Reserved |

Bit 3 is an independent confirmation of the gamma state, reported by a
different command than the register you wrote. `gamma.py` checks both and
warns if they disagree, which is how you catch a write that appeared to
succeed but didn't take.

---

## Commands to stay away from

| Command | CMD2 | CMD3 | Why |
|---|---|---|---|
| LED Driver Current Control | `0x0B` | `0x01` | TI attaches an explicit CAUTION: *"Improper use of this command can lead to damage to the system."* Bad current values can damage the LEDs. |
| Enter Program Mode | — | — | I²C `0x30`. Powers off the illumination, parks the DMD, jumps to the bootloader. |
| Flash programming (DLPU010 Appendix A.3) | — | — | Erase and download. A botched operation here is how these units get bricked; recovery means reflashing over USB. |

The scripts in this package send exactly two things: read requests, and one
write to `0x1A0E`. `info.py` sends no writes at all.

TI also notes **momentary image corruption during command writes** — some
commands cause brief visual artifacts, and the guide suggests disabling the
LEDs first. Not required for the gamma write, but don't take a radiometer
reading across the instant you send it.

---

## Reading the result

With de-gamma bypassed, the DMD's PWM duty cycle is proportional to the
8-bit code value, so measured output should fit

```
L = a·code + b
```

with `b` the black offset from DMD leakage — real, nonzero, and not a gamma
problem. `analysis\check_linearity.py` subtracts it, reports worst-case
deviation as a percentage of full scale, and fits an exponent:

* exponent ≈ **1.0** → linear, de-gamma is out of circuit
* exponent ≈ **2.2** → the table is still applied, *or* something upstream
  (Windows colour management, HDR, a display profile) is re-encoding

That second case is the one worth dwelling on: a correct projector fed by a
colour-managed desktop measures exactly like a broken projector.
