# LightCrafter 4500 pattern mode from the video port — verified reference

**Goal:** DLPC350 in pattern display mode, patterns streamed over mini-HDMI,
TRIG_OUT_1/TRIG_OUT_2 synchronizing an external LED driver, up to 2880 Hz
1-bit patterns (120 Hz × 24 bit-planes).

**Sources (local PDFs in this directory).** Note the filename/revision mismatch —
cite the revision actually inside the file:

| Local file | Actual document | Title |
|---|---|---|
| `dlpu010f.pdf` | **DLPU010G** (May 2013 – rev. July 2018) | DLPC350 Programmer's Guide |
| `dlpu011f.pdf` | **DLPU011F** (July 2013 – rev. July 2017) | LightCrafter 4500 EVM User's Guide |
| `dlpc350.pdf` | **DLPS029F** (Apr 2013 – rev. May 2019) | DLPC350 datasheet |

Every fact below carries its source. Where the docs are silent or ambiguous it is
flagged **[DOC GAP]** or **[AMBIGUOUS]**. Transport (USB HID packet format, byte
order CMD3-first-on-wire) is in `LCR4500-HANDOFF.md` §3 and DLPU010G §1.2.3 —
not repeated here. I²C trap (DLPU010G §1.1.1.3): the I²C **write** sub-address is
the register with bit 7 set (write to reg 0x77 → sub-address 0xF7); read uses the
bare register. USB does not do this — USB CMD2/CMD3 are the same for read/write,
distinguished by the flags byte.

---

## 1. Pattern mode command set (DLPU010G §2.4.3 unless noted)

All are USB `CMD2=0x1A` except where noted. "Stop first" = TI requires stopping
the pattern sequence before writing, then Validate before Start (stated per
command in DLPU010G).

| Command | USB CMD2/CMD3 | I²C | Bytes | Stop first? | Source |
|---|---|---|---|---|---|
| Display Mode Select (0=video, 1=pattern; bit 0) | 0x1A / 0x1B | 0x69 | 1 | — | §2.4.1, Table 2-49 |
| Pattern Trigger Mode Select (0–4) | 0x1A / 0x23 | 0x70 | 1 | yes | §2.4.3.2.1, Table 2-53 |
| Pattern Display Data Input Source (0b00=24-bit RGB/FPD stream, 0b11=flash; 0b01/0b10 reserved; reset=0b11) | 0x1A / 0x22 | 0x6F | 1 | yes | §2.4.3.4.1, Table 2-61 |
| Pattern Exposure Time + Frame Period (µs, u32 + u32, LSB first) | 0x1A / 0x29 | 0x66 | 8 | yes | §2.4.3.4.3, Table 2-63 |
| Pattern Display LUT Control | 0x1A / 0x31 | 0x75 | 4 | yes | §2.4.3.4.5, Table 2-65 |
| Pattern Display LUT Offset Pointer | 0x1A / 0x32 | 0x76 | 1 | — | §2.4.3.4.7, Table 2-66 |
| Pattern Display LUT Access Control (mailbox open/close) | 0x1A / 0x33 | 0x77 | 1 | yes | §2.4.3.4.8, Table 2-67 |
| Pattern Display LUT Data (mailbox payload) | 0x1A / 0x34 | 0x78 | 1 or 3/entry | — | §2.4.3.4.9, Tables 2-68/2-69 |
| Validate Data (write dummy byte, then read 1 status byte) | 0x1A / 0x1A | 0x7D | 1 | — | §2.4.3.1, Table 2-52 |
| Pattern Display Start/Pause/Stop (0=stop, 1=pause, 2=start) | 0x1A / 0x24 | 0x65 | 1 | — | §2.4.3.4.2, Table 2-62 |
| Pattern Display Invert Data | 0x1A / 0x30 | 0x74 | 1 | yes | §2.4.3.4.4, Table 2-64 |
| Trigger Out1 Control | 0x1A / 0x1D | 0x6A | 3 | yes | §2.4.3.2.2, Table 2-54 |
| Trigger Out2 Control | 0x1A / 0x1E | 0x6B | 2 | yes | §2.4.3.2.3, Table 2-55 |
| Trigger In1 Control (rising-edge delay, bits 18:0) | 0x1A / 0x35 | 0x79 | 4 | yes | §2.4.3.2.4, Table 2-56 |
| Trigger In2 Control (mode-2 advance polarity) | 0x1A / 0x36 | 0x7A | 1 | yes | §2.4.3.2.5, Table 2-57 |
| Red LED Enable Delay | 0x1A / 0x1F | 0x6C | 2 | — | §2.4.3.3.1, Table 2-58 |
| Green LED Enable Delay | 0x1A / 0x20 | 0x6D | 2 | — | §2.4.3.3.2, Table 2-59 |
| Blue LED Enable Delay | 0x1A / 0x21 | 0x6E | 2 | — | §2.4.3.3.3, Table 2-60 |
| Var-Exposure LUT Offset Pointer (u16, 0–1823) | 0x1A / 0x3F | 0x5C | 2 | — | §2.4.3.4.10, Table 2-71 |
| Var-Exposure LUT Control | 0x1A / 0x40 | 0x5B | 6 | yes | §2.4.3.4.11, Table 2-72 |
| Var-Exposure LUT Data (12 bytes/entry, incl. per-pattern exposure+period) | 0x1A / 0x3E | 0x5D | 12 | — | §2.4.3.4.12, Table 2-73 |

Supporting commands (elsewhere in DLPU010G):

| Command | USB | I²C | Notes | Source |
|---|---|---|---|---|
| Main Status (bit0 DMD parked, bit1 sequencer running, bit2 buffer frozen, bit3 gamma enabled) | 0x1A / 0x0C | 0x22 | read 1 byte; poll bit 1 after Stop | §2.1.3, Table 2-3 |
| Input Source Select (0=parallel, 1=test pat, 2=flash, 3=FPD; bits 5:3 parallel depth, 1=24-bit) | 0x1A / 0x00 | 0x00 | video-path source, distinct from 0x1A22 | §2.3.4.2, Table 2-19 |
| Port Clock Select (parallel port: clock A/B/C) | 0x1A / 0x03 | 0x03 | | §2.3.4.1, Table 2-18 |
| Input Pixel Data Format (0=RGB 4:4:4) | 0x1A / 0x02 | 0x02 | | §2.3.4.3, Table 2-20 |
| Input Video Signal Detection Status (28-byte read: status, H/V res, polarities, pixel clock, totals, actives, porches) | 0x07 / 0x1C | 0x01 | **[AMBIGUOUS]** DLPU010G §2.1.5 prints "(USB: 0x04, CMD2: 0x07, CMD3: 0x1C)" — the stray 0x04 is unexplained; CMD2=0x07/CMD3=0x1C is the usable pair. FW ≥ 2.0.0. | §2.1.5, Table 2-5 |
| Force Buffer Swap (buffer **must be frozen first**) | 0x1A / 0x26 | 0x71 | | §2.3.1.4.1, Table 2-10 |
| Display Buffer Freeze (1=freeze; reset default is **1**) | 0x10 / 0x0A | 0x7C | TI recommends freezing during reconfiguration | §2.3.1.4.2, Table 2-11 |
| Buffer Write Disable | 0x1A / 0x27 | 0x72 | | §2.3.1.4.3, Table 2-12 |
| Current Read Buffer Pointer | 0x1A / 0x28 | 0x73 | | §2.3.1.4.4, Table 2-13 |
| LED Enable Outputs (bits 2:0 R/G/B manual, bit 3 = sequencer control, reset 0x08) | 0x1A / 0x07 | 0x10 | | §2.3.7.1, Table 2-34 |

### 1.1 LUT Control byte layout (Table 2-65, USB 0x1A31, 4 bytes)

| Byte | Bits | Meaning |
|---|---|---|
| 0 | 6:0 | Number of LUT entries − 1 (1–128 entries) |
| 1 | 0 | 0 = play sequence once, 1 = repeat forever |
| 2 | 7:0 | Number of patterns to display − 1 (1–256). In repeat mode this sets how often TRIG_OUT_2 fires. |
| 3 | 5:0 | Number of image-index LUT entries − 1 (1–64). **Irrelevant unless input source = 0x3 (flash).** |

### 1.2 Mailbox mechanism (§2.4.3.4.8–.9)

1. Open mailbox: write **0x1A33** = `1` (image indexes, flash only), `2`
   (pattern definitions), or `3` (variable-exposure definitions). `0` closes.
2. Set offset: **0x1A32** (one byte; var-exposure uses **0x1A3F**, u16).
3. Write entries via **0x1A34** (var-exposure: **0x1A3E**): image-index mailbox
   takes 1 byte per entry (0-based flash image index); pattern-definition
   mailbox takes **3 bytes per pattern**.
4. Close mailbox: **0x1A33** = `0`. Then Validate.

Prerequisite (bold in DLPU010G §2.4.3.4.9): *display mode, trigger mode,
exposure, and frame rate must be set up before sending any mailbox data.* With
streaming input, image indexes are not required; the pattern definition always is.

**[AMBIGUOUS]** Whether multiple 3-byte pattern entries may be packed into one
0x1A34 USB packet, and whether the offset pointer must be re-written per entry,
is not stated for the fixed-exposure LUT. The variable-exposure flowchart
(Figure 2-12) explicitly increments the offset pointer per 12-byte entry. TI's
Table 4-1/4-2 examples set the offset once. Follow the GUI/reference C code at
the bench; safest is offset=n then one entry, per entry.

### 1.3 Pattern LUT entry encoding (Table 2-69, 3 bytes per pattern)

| Byte | Bits | Field |
|---|---|---|
| 0 | 1:0 | Trigger type: `00` internal, `01` external positive, `10` external negative, `11` no input trigger (continue from previous; pattern still gets full exposure) |
| 0 | 7:2 | **Pattern number** (0-based; see §2 mapping). 0x3F = no pattern display. Max 24 for 1-bit. Pattern number **25** at 1-bit inserts a white-fill pattern (invert it for black-fill), same exposure as Table 2-63 setting. |
| 1 | 3:0 | Bit depth: `0001`=1 … `1000`=8 (0, 9–15 reserved) |
| 1 | 7:4 | LED select: b0=Red, b1=Green, b2=Blue → `000` none (pass-through), `001` R, `010` G, `011` Y, `100` B, `101` M, `110` C, `111` W |
| 2 | 0 | 1 = invert pattern |
| 2 | 1 | 1 = insert black-fill after this pattern (**requires 230 µs before next pattern start; cannot combine with bit 3**) |
| 2 | 2 | 1 = perform buffer swap. **Table 4-2 step 6(c): must be set at every external-positive-trigger entry in streaming mode.** |
| 2 | 3 | 1 = TRIG_OUT_1 stays high across this and the previous pattern (no falling edge between them; exposure time is shared among all patterns under a common trigger-out). 0 = TRIG_OUT_1 rises at pattern start, falls at pattern end. |
| 2 | 7:4 | Reserved (write 0) |

Table 2-69 also lists the power-on default LUT entries (e.g. first entry
0x042120) — i.e. the chip boots with a populated pattern LUT.

### 1.4 Validate response byte (Table 2-52, USB 0x1A1A: write 1 dummy byte, then read 1 byte)

| Bit | 1 means |
|---|---|
| 0 | exposure/frame-period settings **invalid** |
| 1 | pattern numbers in LUT **invalid** |
| 2 | warning: continuous TRIG_OUT_1 request or overlapping black sectors |
| 3 | warning: post (black) vector not inserted prior to external-triggered vector |
| 4 | warning: frame period − exposure < 230 µs |
| 7 | **busy validating — only interpret bits 0–4 after bit 7 transitions 1→0 (poll)** |

---

## 2. Video → pattern-from-video, the documented sequence

### 2.1 TI's required procedure for any settings change with a streaming source (DLPU010G §2.4.3, quoted)

> "When a streaming source is used in pattern display mode, use the following
> procedure to apply any parameter changes.
> 1. Ensure the source is still active
> 2. Issue a Stop command
> 3. Wait at least two frame periods
> 4. Read the status register to check that pattern mode is stopped. If it is
>    not, then poll the status register, delaying one frame time per read until
>    the register indicates pattern mode has stopped.
> 5. Apply the new setting(s)
> 6. Ensure the source is active
> 7. Send the Validate command
> 8. Start the sequence"

Also (§2.4.3, NOTE): "If the pattern display is already active, the display must
be stopped using the I2C command 0x65 before making a change" and "Any changes
in the setting must be validated using the validate data command."

### 2.2 Full command order, video-port patterns, trigger mode 0 (DLPU010G §4.2, Table 4-2)

| # | USB | Data | Meaning |
|---|---|---|---|
| 1 | 0x1A1B | 01 | pattern display mode |
| 2 | 0x1A22 | 00 | pattern data from external video |
| 3 | 0x1A31 | e.g. `0C 01 03 00` | LUT control: 13 entries, repeat, 4 patterns per TRIG_OUT_2, (byte 3 irrelevant for streaming) |
| 4 | 0x1A23 | 00 | trigger mode 0 (VSYNC-triggered) |
| 5 | 0x1A29 | 8 bytes | exposure + frame period (µs). "For a 60-Hz vsync, the maximum exposure time is 16667 ÷ 3" (their 3-pattern example) |
| 6 | 0x1A33=`02`; 0x1A32=offset; 0x1A34×N (3 bytes each); 0x1A33=`00` | | open **pattern-definition** mailbox, write LUT, close. First pattern in each sequence: trigger type = external positive **with buffer-swap bit set**; the rest: `11` no-input-trigger. |
| 7 | 0x1A1A | 00 | write Validate |
| 8 | 0x1A1A | read 1 byte | poll bit 7, check bits 0–4 |
| 9 | 0x1A24 | 02 | start |
| 10 | 0x1A24 | 00 | stop (when done) |

**Trap — TI doc self-contradiction:** the generic example (Table 4-1, "Set up
the LUT") opens the mailbox with `01`, but Table 2-67 defines `01` = image-index
mailbox and `02` = pattern-definition mailbox, and Table 4-2 step 6 uses `02`.
Use **`02`** for pattern definitions; Table 4-1 appears to be a typo.

### 2.3 Going back to video mode

**[DOC GAP]** TI documents no explicit reverse sequence. Implied path: Stop
(0x1A24=00) → poll Main Status until sequencer/pattern stopped → Display Mode
Select 0x1A1B = 00. Video mode then reapplies the full processing path
(de-gamma per its own register, scaler, etc.). Verify on the bench that HDMI
video resumes cleanly and whether Input Source (0x1A00) / pixel format need
re-assertion.

### 2.4 What happens to the HDMI input in pattern mode

- Pattern-from-video **requires the incoming resolution to be exactly
  912 × 1140** — "especially in the Pattern Display Mode where the resolution
  must match the native resolution of 912 × 1140 pixels" (DLPU010G §2.1.5);
  "if using the video port, the incoming image resolution must be 912x1140"
  (DLPU011F §3.3.1 step 5(d)). The EVM's mini-HDMI EDID is factory-programmed
  with 1280×800 **and 912×1140** (DLPU011F §1.5, J8).
- The video frame updates the internal buffer on each VSYNC; VSYNC is the
  trigger in mode 0 and the VSYNC period is the total time available for the
  pattern sequence of that frame (DLPU011F §3.3.1 step 5(d); DLPU010G Table 2-53).
- All image processing is bypassed — pixel-accurate, no scaler, no CSC, and
  **a linear 1:1 de-gamma table is applied in pattern sequence mode**
  (DLPU010G Table 2-50 NOTE; §2.4.1). The video-mode gamma register is
  irrelevant here.
- Displayed data is **one 24-bit frame behind** the stream: 48-bit-plane
  double buffer, DMD shows the previous frame while the current one fills the
  other buffer (DLPU010G §2.4 Figures 2-7/2-8; DLPS029F §8.4.1).
- Signal-status reporting: in pattern-streaming mode the GUI's Signal Status
  reads "Stopped — the DLP LightCrafter 4500 is no longer locking to the video
  source... This prevents a delay in pattern display if synchronization is
  temporarily lost" (DLPU011F §3.2.6). Expected, not a fault.

### 2.5 24-bit-plane packing (Table 2-70, DLPU010G — "Pattern Number Mapping")

The LUT's pattern-number field selects which wire bits of the 24-bit RGB word
form the displayed bit-plane(s). **Green is first, LSB first.** For 1-bit
patterns:

| Pattern # | Plane | Pattern # | Plane | Pattern # | Plane |
|---|---|---|---|---|---|
| 0 | G0 | 8 | R0 | 16 | B0 |
| 1 | G1 | 9 | R1 | 17 | B1 |
| 2 | G2 | 10 | R2 | 18 | B2 |
| 3 | G3 | 11 | R3 | 19 | B3 |
| 4 | G4 | 12 | R4 | 20 | B4 |
| 5 | G5 | 13 | R5 | 21 | B5 |
| 6 | G6 | 14 | R6 | 22 | B6 |
| 7 | G7 | 15 | R7 | 23 | B7 |

Pattern # 24 = Black (Table 2-70 last row). Display **order** is set by the
order of LUT entries, not by this table — the table only maps pattern number →
wire bit(s). Multi-bit depths group adjacent planes, e.g. 8-bit: pattern 0 =
G7..G0, 1 = R7..R0, 2 = B7..B0; 4-bit: pattern 0 = G3..G0, 1 = G7..G4,
2 = R3..R0, … (full table in DLPU010G Table 2-70). GUI labels the same planes
G0–G7, R0–R7, B0–B7 and confirms "the groupings cannot be changed"
(DLPU011F §3.3.1 step 5(d)).

So: pack 24 one-bit frames into one 912×1140 24-bpp HDMI frame; to display
them in temporal order 1…24, write 24 LUT entries with pattern numbers
0,1,…,23 (G0 first, B7 last).

---

## 3. Trigger outputs and inputs

### 3.1 Semantics (DLPU010G §2.4.3.2; DLPS029F §8.4.1, Table 7)

- **TRIG_OUT_1** "frames the exposure time of the pattern": rising edge at
  pattern start, falling at pattern end (unless LUT byte 2 bit 3 holds it high
  across patterns). Active high by default.
- **TRIG_OUT_2** "indicates the start of the pattern sequence or internal
  buffer boundary of a 24-bit plane" — one pulse per "Number of patterns to
  display" group (LUT Control byte 2). Rising edge only is programmable.
- **Trigger mode 0** (video/FPD source): VSYNC is the input trigger;
  TRIG_IN_1 unused; TRIG_IN_2 rising starts / falling stops the sequence
  (DLPS029F Table 7 + §8.4.1 text; DLPU010G Table 2-57).
- Modes 1 and 2 are flash-source modes (TRIG_IN_1 advances/alternates
  patterns). Modes 3/4 are the variable-exposure twins of 1/0
  (DLPU010G Table 2-53).
- Mode 0 note (Table 2-53): "For proper operation, the pattern exposure must
  equal the total pattern period in this mode."
- **WARNING (DLPU010G §2.4.3.2):** "When using an external hardware triggering
  mode, it is critical that unused trigger, VSYNC and pixel clock lines be
  properly isolated, even if not in use by the mode selected. Any noise or
  signal presence on these lines can cause undesired behavior."

### 3.2 Delay/polarity commands

All delays are relative to "when the pattern is displayed on the DMD"
(DLPU010G §2.4.3.2.2–.5). Step size: **107.2 ns per count** per DLPU010G
Tables 2-54/2-55; the EVM guide states **107.136 ns** for the same controls
(DLPU011F §3.3.4). [AMBIGUOUS — 107.136 ns is the likelier exact value since
Trig In1 (Table 2-56) also says 107.136 ns; sub-ns discrepancy, irrelevant in
practice.]

| Signal | Command | Byte layout | Range |
|---|---|---|---|
| TRIG_OUT_1 | USB 0x1A1D / I²C 0x6A | byte0 bit1 = invert (1 = active-low); byte1 = rising-edge delay; byte2 = falling-edge delay | each 0x00=−20.05 µs … 0xBB=0 (default) … 0xD5=+2.787 µs |
| TRIG_OUT_2 | USB 0x1A1E / I²C 0x6B | byte0 bit1 = invert; byte1 = rising-edge delay (no falling control) | 0x00=−20.05 µs … 0xBB=0 … 0xFF=+7.29 µs |
| TRIG_IN_1 | USB 0x1A35 / I²C 0x79 | bytes 3:0, bits 18:0 = rising-edge delay, 107.136 ns/count | 0 … (2^19−1) counts ≈ 56 ms; GUI exposes 0–28084.95 µs (DLPU011F §3.3.4) |
| TRIG_IN_2 | USB 0x1A36 / I²C 0x7A | byte0 bit0: mode-2 advance on rising (0) or falling (1) edge | — |

TRIG_IN_1 polarity is set per-pattern in the LUT (external positive/negative),
not in the Trig In1 command (DLPU010G §2.4.3.2.4).

LED enable delays (0x1A1F/20/21) have the same encoding: byte0 = rising, byte1
= falling, each 0x00=−20.05 µs … 0xBB=0 … 0xFF=+7.29 µs (Tables 2-58/59/60).
"This command is only for pattern display mode. In video mode, these delays
must be set to 0x0." (§2.4.3.3.)

### 3.3 Electrical (DLPS029F)

| Item | Value | Source |
|---|---|---|
| Pins | TRIG_IN_1 = G19, TRIG_IN_2 = F22, TRIG_OUT_1 = C17, TRIG_OUT_2 = K21; all VDD33 domain, async, I/O type B2 | DLPS029F Pin Functions ("Trigger Control") |
| Buffer type B2 | 3.3-V LVCMOS bidirectional, **8-mA drive** | DLPS029F Table 2 (I/O Type Definition) |
| IOH / IOL | ±8.0 mA at VO = 2.4 V / 0.4 V (type 2) | DLPS029F §6.5 |
| VOH / VOL | ≥ 2.8 V @ max rated IOH; ≤ 0.4 V @ max rated IOL | DLPS029F §6.5 |
| VIH / VIL (inputs) | ≥ 2.0 V / ≤ 0.8 V, 400 mV hysteresis | DLPS029F §6.5 |
| TRIG_OUT_1 pin description | "Active high trigger output signal during pattern exposure" | DLPS029F Pin Functions |
| TRIG_OUT_2 pin description | "Active high trigger output to indicate first pattern display" | DLPS029F Pin Functions |

**Trap:** those are the bare DLPC350 pins. On the EVM the trigger signals pass
through level shifters to the J11/J14 connectors (jumper-selectable rail, §4
below; PandaBoard tables call the shifted nets DRV_TRIG_OUT*). The shifter part
and its drive strength at J14 are **[DOC GAP]** — not in DLPU011F; get it from
the DLPLCR4500EVM design files or measure.

---

## 4. EVM connectors (DLPU011F)

### 4.1 Trigger output connector — **J14** (DLPU011F §7.2, Table 7-2)

| Pin | Function |
|---|---|
| 1 | Trigger Out 1 supply (1.8 V / 3.3 V, selected by **J13**) |
| 2 | **TRIG_OUT_1** |
| 3 | GND |
| 4 | Trigger Out 2 supply (1.8 V / 3.3 V, selected by **J15**) |
| 5 | **TRIG_OUT_2** |
| 6 | GND |

J13/J15: jump pins 3–4 for 3.3 V, pins 5–6 for 1.8 V (DLPU011F §1.5,
Figure 1-11). Board location: "External trigger output connector", item 3 in
Figure 1-8 (back-side view), DLPU011F §1.4.

### 4.2 Trigger input connector — **J11** (DLPU011F §7.1, Table 7-1)

| Pin | Function |
|---|---|
| 1 | Trigger In 1 supply ("external or internal 1.8-V and 3.3-V selectable at J10") |
| 2 | **TRIG_IN_1** |
| 3 | GND |
| 4 | Trigger In 2 supply (J12) |
| 5 | **TRIG_IN_2** |
| 6 | GND |

Inputs have hysteresis (§7.1). **[AMBIGUOUS]** §1.4 item 6 says inputs support
"5 V, 3.3 V and 1.8 V through jumpers J10 and J12", but §1.5 lists only
3.3-V (pins 3–4) and 1.8-V (pins 5–6) jumper positions and Table 7-1 says
"external or internal 1.8-V and 3.3-V". The 5-V path is presumably an external
supply into pin 1/4 — not documented. Do not feed 5 V until verified against
the EVM schematic.

### 4.3 Mating connector / our cables

DLPU011F §7.1/§7.2 names the mate for J11 and J14: six-pin, **1.25-mm** pitch,
housing **Molex 51021-0600** (Digi-Key WM1724-ND), crimps **Molex 50079-8100**
(WM2023-ND). That is the Molex **PicoBlade** family.

Our stock: Molex **0151340603** (15134-0603) — a factory PicoBlade-to-PicoBlade
6-circuit cable assembly built with 51021-0600 housings on both ends → **mates
with J11 and J14**. *Caveat:* DLPU011F never names 15134; the match is via the
Molex family (51021 housing = what 15134 assemblies terminate in). **Bench
check required:** double-ended 15134 cables can be wired 1:1 or mirrored
(pin 1 → pin 6) depending on assembly type — buzz out pin 1→pin 1 before
wiring the LED driver. Pin-1 marking on the board itself: **[DOC GAP]**,
DLPU011F shows no silkscreen detail; identify pin 1 from the connector key /
EVM design files.

### 4.4 LED-related headers

- **External LED driver connector** (item 15, Figure 1-7 top view, DLPU011F
  §1.4): "Install a jumper in J30 to disable the DLP LightCrafter 4500 LED
  drivers and set jumper J28 for 3.3-V or 1.8-V supply. Then use this connector
  to control an external LED driver board..." — **[DOC GAP] DLPU011F Chapter 7
  contains NO pinout table for this connector** (Tables 7-1…7-12 cover
  triggers, UART, I²C, fan, R/G/B LED supplies, FPD-link, JTAG, power only).
  Its reference designator is not even given in the text. Pinout must come
  from the DLPLCR4500EVM design files/schematic before anything is wired.
- **J28** — LED enable/PWM signal voltage for external-driver use: pins 1–2 =
  3.3 V, pins 3–4 = 1.8 V. "Must be populated when bypassing the onboard LED
  driver" (DLPU011F §1.5).
- **J30** — jump to disable onboard LED driver ("turn off all LEDs, regardless
  of video mode"); leave open for normal operation (DLPU011F §1.5).
- Onboard LED supply connectors (not for external drivers): J31 red (9-pin,
  Molex 87439-0900 mate), J32 green / J33 blue (6-pin, 87439-0600) —
  DLPU011F §7.7–7.9.
- Behavior in pattern mode: LED enables are driven by the **sequencer per the
  LUT's LED-select field** when LED Enable Outputs bit 3 = 1 (DLPU010G Table
  2-34; DLPU011F §3.2.4 "Automatic... In Pattern Sequence mode, the LED
  enables are controlled by the downloaded Pattern Sequence settings").
  Manual mode (bit 3 = 0) holds the checked LEDs continuously on. Edge timing
  trims via the LED Enable Delay commands (§3.2 above).
- DLPC350 LED pins: LEDR_EN L3, LEDG_EN L4, LEDB_EN K1; LEDR_PWM K2,
  LEDG_PWM K3, LEDB_PWM K4 — 3.3-V LVCMOS type O2 (8 mA) (DLPS029F Pin
  Functions, LED driver interface).

### 4.5 Video input

Mini-HDMI (DVI) connector, item 20, back side, feeds a TFP401 DVI receiver
into the DLPC350 parallel port (DLPU011F §1.4 item 20, §3.2.5). Supported up
to 120 Hz; "In Pattern Sequence mode, this input supports 912 × 1140
resolution" (§1.4 item 20).

---

## 5. Rates and timing

### 5.1 Pattern-rate table (DLPU010G Table 2-48 = DLPS029F Table 8; min exposure from DLPU011F Table 4-1)

| Bit depth | Max **external input** pattern rate (Hz) | Max pre-loaded rate (Hz) | Min pattern exposure (µs) | Max # pre-loaded patterns |
|---|---|---|---|---|
| 1 | **2880** | 4225 | **235** | 48 |
| 2 | 1428 | 1428 | 700 | 24 |
| 3 | 636 | 636 | 1570 | 16 |
| 4 | 588 | 588 | 1700 | 12 |
| 5 | 480 | 500 | 2000 | 8 |
| 6 | 400 | 400 | 2500 | 8 |
| 7 | 222 | 222 | 4500 | 6 |
| 8 | 120 | 120 | 8333 | 6 |

2880 Hz = 24 one-bit planes per 120-Hz input frame (8333 µs / 24 ≈ 347 µs per
pattern, comfortably above the 235-µs minimum). The 4225-Hz figure applies
only to flash-pre-loaded patterns, and only if the whole sequence fits and
plays out of one 24-plane buffer at a time (DLPS029F §8.4.1: a load penalty
kills the max rate otherwise; flash buffer load is up to ~200 ms per 24
planes, DLPU011F §4.1).

### 5.2 Input timing required for 2880 Hz

- Source: 912 × 1140 at 120 Hz over the parallel (HDMI→TFP401) port.
- Port 1 pixel clock: **12–150 MHz** (DLPS029F §6.7); setup/hold 3 ns/3 ns,
  sampled on rising edge.
- **120-Hz sources have their own blanking minimums** (DLPS029F §6.11.1,
  Table 4 — Port 1): VBP ≥ 3 lines, VFP ≥ 17 lines, VSYNC ≥ 10 lines (total
  vertical blanking 30 lines); HBP ≥ 10 px, HFP ≥ 56 px, HSYNC ≥ 64 px (total
  horizontal blanking 128 px); pixel clock **146.0 MHz**. That is exactly
  (912+128) × (1140+30) × 120 = 146.016 MHz — i.e. the classic
  **912×1140 @ 120 Hz, 1040×1170 total, ~146 MHz** modeline.
- Non-120-Hz sources instead need VBP ≥ 370 µs etc. (DLPS029F Table 3).
- Video mode is limited to the same ports; FPD-link (Port 2) max clock is
  90 MHz (DLPS029F §6.8) — **too slow for 912×1140@120; use the parallel/HDMI
  port for 2880 Hz.**

### 5.3 Exposure / frame-period rules

- Exposure must equal the frame period, OR be shorter by ≥ **230 µs**
  (DLPU010G §2.4.3.4.3; Table 2-62 NOTE; Validate bit 4 warns below 230 µs).
- "In external video input pattern sequence modes, the pattern exposure time
  must equal the frame period." (Table 2-63 NOTE.) Same requirement stated for
  trigger modes 0 and 4 (Table 2-53).
- Worked example in Table 2-62 NOTE: 60 Hz, 24-bit → frame 16666 µs, exposure
  16666/24 = 694 µs per 1-bit pattern. At 120 Hz: 8333/24 ≈ 347 µs.
- GUI phrasing: patterns × exposure ≤ VSYNC period (DLPU011F §3.3.1).
- Insert-black (LUT byte 2 bit 1) consumes 230 µs before the next pattern
  (Table 2-69).

---

## 6. Traps

1. **Nothing takes effect without Validate, and Start is refused/undefined
   without it.** Poll the Validate byte until bit 7 falls, then check bits 0–4
   (DLPU010G §2.4.3.1). Every trigger/LUT/exposure/source command carries the
   "stop first, validate after" requirement.
2. **After a Stop, the LUT must be re-sent before the next Start**: "When
   stopped, before 'Start,' at a minimum Pattern Display LUT (0x75 I2C) and
   pattern display lookup table must be sent again, followed by Validate."
   (Table 2-62 NOTE.) Pause (01) does not have this requirement.
3. **Buffer-swap bit discipline (streaming):** set the buffer-swap bit on
   every external-positive-trigger LUT entry in streaming mode (Table 4-2
   step 6(c)) — this is what advances the double buffer each VSYNC. A "Forced
   Swap" error flags "pattern sequence timings do not match the video port
   VSYNC" (DLPU011F §3.2.1). Force Buffer Swap (0x1A26) requires the buffer
   frozen first (Table 2-10).
4. **Mailbox open code:** `02` for pattern definitions (`01` is image indexes).
   TI's own Table 4-1 example shows `01` — a typo; trust Table 2-67 and
   Table 4-2.
5. **One-frame latency:** displayed patterns lag the HDMI stream by one 24-bit
   frame (DLPU010G Figures 2-7/2-8). Plan stimulus timestamps accordingly.
6. **Power cycle resets everything** — the Reset column in every command table
   is "the default value after power up" (DLPU010G Ch. 2 intro), and power-up
   auto-initialization re-runs the flash-stored configuration (DLPU010G §3.3).
   Pattern mode, trigger settings, and the LUT all revert. (Same volatility
   class as the gamma register — see LCR4500-HANDOFF.md §2. The TI GUI's
   Apply Solution also rewrites settings behind your back.)
7. **Gamma is irrelevant in pattern mode:** a linear 1:1 de-gamma table is
   applied in pattern sequence mode; the 0x1A0E register applies only to video
   mode (Table 2-50 NOTE). Do not "fix" gamma for pattern experiments.
8. **Trigger mode default is 1, not 0** (Table 2-53 reset = d1). For
   video-port patterns you must explicitly write mode 0 (or 4).
9. **Pattern input source default is flash (0b11)** (Table 2-61 reset = x3).
   Must write 0b00 for streaming.
10. **Isolate unused trigger/VSYNC/pixel-clock lines** — noise on them causes
    undesired behavior (WARNING, DLPU010G §2.4.3.2).
11. **Insert-black and shared-TRIG_OUT_1 are mutually exclusive** (Table 2-69
    byte 2 bits 1 and 3); black insertion needs 230 µs.
12. **Play Once + video port "may not work as expected. Repeat is the
    recommended setting for video input."** (DLPU011F §3.3.1 step 6.)
13. **GUI polling interferes:** uncheck Auto Update Status while a pattern
    sequence runs (DLPU011F §3.2.1) — and generally keep the TI GUI closed
    during runs (HANDOFF §2).
14. **Commands can corrupt the displayed image momentarily** — TI suggests
    disabling LEDs around command writes if that matters (DLPU010G Ch. 2 NOTE).
    Reads never disturb the image.
15. **Reserved bits must be written 0** (DLPU010G Ch. 2 NOTE). Do not write
    undocumented registers.
16. **1-bit pattern number 25 = white fill** (invert → black fill) — useful for
    dark gaps without touching the stream (Table 2-69).
17. Validate warning bit 2 fires on "continuous Trigger Out1 request or
    overlapping black sectors" — check it when using shared TRIG_OUT_1 or
    insert-black (Table 2-52).

---

## 7. Open questions for the bench

The docs do **not** settle these; verify with a scope / schematic before
trusting the rig:

1. **TRIG_OUT_1 edge vs actual light:** delays are specified relative to "when
   the pattern is displayed on the DMD" — the offset between the TRIG_OUT_1
   edge at J14 and photodiode-measured illumination (DMD settling + EVM level
   shifter + LED driver latency) is undocumented. Measure at 0-delay
   (0xBB) and calibrate.
2. **EVM level-shifter drive at J14:** part number, source impedance, and edge
   rate of the shifted trigger outputs are absent from DLPU011F. Needed to
   know what cable length/load the 1.8/3.3-V outputs can drive into the LED
   driver. (Bare DLPC350 pin is 8-mA LVCMOS, but that is not what J14 exposes.)
3. **HDMI chain at 912×1140@120 (≈146 MHz):** DLPU011F item 20 says "up to
   120 Hz", and DLPS029F Table 4 defines the 146-MHz timing, but whether the
   EVM's TFP401 receiver + the factory EDID (which lists 912×1140 — refresh
   rate unstated) + the GPU will actually negotiate and lock 120 Hz is
   unverified. Confirm with Input Video Signal Detection Status (0x07/0x1C):
   pixel clock, totals, actives, and 120 Hz vertical frequency.
4. **TRIG_OUT_2 cadence in repeat mode:** doc says "start of the pattern
   sequence or internal buffer boundary of a 24-bit plane"; with LUT Control
   byte 2 setting "patterns per TRIG_OUT_2", scope the exact pulse timing per
   24-plane frame at 120 Hz (one pulse per VSYNC expected, but the
   "buffer-boundary" wording leaves room).
5. **External LED driver connector pinout** — completely undocumented in
   DLPU011F (§4.4 above). Requires DLPLCR4500EVM design files. Also verify
   LED_EN polarity (active high assumed from "Active high" language on
   triggers only — not stated for LED enables) at the chosen J28 level.
6. **Internal LED enables with external LEDs:** with J30 jumped (onboard
   driver disabled) confirm the sequencer still toggles the LED_EN pins per
   the LUT, and that manual LED Enable (0x1A07 bits 2:0) behaves at the
   external header. Docs describe behavior only for the onboard driver.
7. **Molex 15134-0603 cable wiring** (1:1 vs mirrored) and J11/J14 pin-1
   orientation on the PCB — continuity-check before connecting the LED driver.
8. **Exposure rounding at 120 Hz:** 8333 µs / 24 = 347.2 µs; exposure and
   frame period are integer µs (Table 2-63). Whether Validate accepts
   24 × 347 = 8328 µs vs frame 8333 µs (mode 0 wants exposure = pattern
   period) or requires other rounding — try 347/348 and read the Validate
   flags.
9. **5-V trigger-input claim** (DLPU011F §1.4 item 6) vs the 1.8/3.3-only
   jumper table — resolve from schematic before applying 5 V to J11.
10. **Return-to-video-mode sequence** (§2.3 above) — undocumented; verify no
    residual pattern-mode state (input source 0x1A00, buffer freeze state,
    LED enable mode) after switching back.
