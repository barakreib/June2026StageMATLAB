# LightCrafter 4500 linearization — context handoff

**For:** a Claude session picking up this work with different surrounding context.
**Subject:** TI DLP LightCrafter 4500 (DLPC350 controller), firmware 2.0.0, driven
from a Windows 11 machine. Goal: linear light output vs. code value in ordinary
video (mini-HDMI) mode.

Read this before offering advice. Several conclusions below were expensive to
reach and are easy to un-learn.

---

## 1. The core fact

The DLPC350 applies a **de-gamma table** to the video pipeline by default. That is
why output is not linear between 0,0,0 and 255,255,255. It is controlled by one
register, and the TI GUI does **not** expose it.

| | |
|---|---|
| Command | Gamma Correction (De-gamma) |
| I²C register | `0x31` |
| USB | `CMD2 = 0x1A`, `CMD3 = 0x0E` |
| bit 7 | `1` = enabled (**power-on default**) · `0` = disabled → **linear** |
| bit 0 | table pointer: `0` = TI Video (Enhanced), `1` = TI Video (Max Brightness) |

Write `0x00` to linearize. Write `0x80` to restore.

**Independent confirmation:** Main Status (`CMD2 0x1A` / `CMD3 0x0C`) **bit 3** is
"Gamma Correction Function Enable". It is reported by a different command, so
checking both catches a write that appears to land but doesn't reach the pipeline.
Always verify both.

---

## 2. The register is VOLATILE — this is the single biggest trap

Nothing is written to flash. It reverts to `0x80` on:

* **any power cycle of the projector**, and
* **the TI Control Software** — connecting with it, and especially
  `Apply Solution` / `Apply Default Solution`, pushes a batch of settings back.

The failure is **completely silent**. No error, no indication. In this session it
destroyed two full measurement sessions before it was caught.

**Working rule:** do all GUI work first → close the GUI → set the bypass → measure
→ don't reopen the GUI. Verify the register immediately before *and* after any
measurement run that matters.

---

## 3. USB transport — the byte-order trap

Standard HID. **VID `0x0451`, PID `0x6401`. No driver required on any OS** — the
built-in HID class driver claims it. Do not install a WinUSB/libusb filter (Zadig);
that is only needed for the pyusb route and it breaks the TI GUI.

```
byte 0     HID report ID ...... 0x00
byte 1     flags .............. 0x40 write / 0xC0 read  (bit7 rw, bit6 reply)
byte 2     sequence number
byte 3-4   payload length ..... little endian, = len(data) + 2
byte 5-6   command word ....... little endian u16 -> CMD3 FIRST, then CMD2
byte 7+    data, zero padded to 64 bytes
```

**CMD3 goes on the wire before CMD2.** TI's own API packs the command as
`(CMD2 << 8) | CMD3` into a little-endian `uint16`. Getting this backwards means
the packet is silently ignored with no error. Verified against
`Stage-VSS/matlab-lcr/api/dlpc350_api.cpp`.

De-gamma off is: `00 40 01 03 00 0E 1A 00` + zeros to 64.

Use **hidapi** (`pip install hidapi`), not pyusb. On macOS pyusb cannot claim a HID
interface at all; on Windows it needs the filter driver above.

---

## 4. Gamma and colour are ORTHOGONAL — established empirically

De-gamma is a single 1-D transfer curve. It has no per-channel or colour-path
involvement and **cannot** desaturate, shift hue, or make the projector monochrome.

This was tested directly: the DLPC350's internal colour-bar generator
(`CMD2 0x12` / `CMD3 0x03` = 0x9, with Input Source `CMD2 0x1A`/`CMD3 0x00` = 1)
was run **while the gamma register read `0x00`**. Colour bars rendered in full
colour. Linear + RGB coexist. Do not let anyone re-litigate this.

That internal pattern generator is also the best split-half diagnostic available:
it bypasses PC, GPU, HDMI and stimulus software entirely.

---

## 5. Other registers that matter (verified against DLPU010F)

| Purpose | CMD2 | CMD3 | I²C | Notes |
|---|---|---|---|---|
| Firmware version | `0x02` | `0x05` | `0x11` | 16 bytes, four u32; major `[31:24]`, minor `[23:16]`, patch `[15:0]` |
| Main Status | `0x1A` | `0x0C` | `0x22` | bit0 DMD park, bit1 sequencer run, bit2 buffer frozen, **bit3 gamma enable** |
| Gamma Correction | `0x1A` | `0x0E` | `0x31` | §1 above |
| Display Mode | `0x1A` | `0x1B` | `0x69` | bit0: 0 = video, 1 = pattern |
| Input Source | `0x1A` | `0x00` | `0x00` | bits 2:0 source (0 parallel, 1 test pattern, 2 flash, 3 FPD-link); bits 5:3 parallel bit depth |
| Input Pixel Format | `0x1A` | `0x02` | `0x02` | 0 = RGB 4:4:4, 1 = YCrCb 4:4:4, 2 = YCrCb 4:2:2 |
| CSC input attribute | `0x1A` | `0x0D` | `0x26` | same encoding |
| Port Clock | `0x1A` | `0x03` | `0x03` | |
| **LED Enable Outputs** | `0x1A` | `0x07` | `0x10` | bits 2:0 R/G/B enable; **bit 3: 0 = manual, 1 = sequencer controlled**. Reset `0x08` |
| LED Driver Current | `0x0B` | `0x01` | `0x4B` | R,G,B one byte each. Defaults 151,120,125. **TI damage caution — do not write** |
| Internal Test Pattern | `0x12` | `0x03` | `0x0A` | 0x0 solid … 0x9 colour bars, 0xA step bars |

### Commands to stay away from
* **LED Driver Current** (`0x0B`/`0x01`) — TI: *"Improper use of this command can
  lead to damage to the system."*
* **Enter Program Mode** (I²C `0x30`) and flash programming (DLPU010 Appendix A.3)
  — this is how these units get bricked. Reflashing also resets the gamma register.

---

## 6. How colour CAN be lost (if the symptom reappears)

In video mode the DMD displays R, G and B bit planes **in sequence** while the
sequencer strobes the matching LED per sub-frame. That time-multiplexing is the
entire colour mechanism. If **LED Enable Outputs bit 3** is cleared (manual) with
all three LEDs held on, every sub-frame is lit white — the projector sums R+G+B
into one grey image, and a yellow stimulus comes out white.

Nothing in the toolkit writes that register; the TI GUI's LED Driver Control panel
does. Fix is writing `0x08` (sequencer control, the reset default). **This was
checked in this session and read `0x08` — it was NOT the cause here.**

---

## 7. What linearization actually changes downstream

Removing de-gamma does not touch primaries, white point, LED currents, sequencing,
resolution, bit depth or frame rate. Only the code→duty-cycle mapping changes.

But it **hugely amplifies the bottom of the range** relative to full scale:

| Code | Before (γ≈2.2) | After (linear) | Relative increase |
|---|---|---|---|
| 8 | 0.05% | 3.1% | **63×** |
| 16 | 0.23% | 6.3% | **28×** |
| 32 | 1.0% | 12.5% | **12×** |
| 64 | 4.7% | 25% | **5.3×** |
| 128 | 22% | 50% | 2.3× |

Consequences that matter:
* Anything previously buried in near-black is now clearly luminous. A small nonzero
  blue that was invisible becomes enough to desaturate a yellow toward white.
* Ordinary sRGB content looks washed out. That is **correct**, not a fault — the
  decoder has been removed.
* Stimulus code must now work in **linear units**. Values tuned against the
  gamma-encoded projector are wrong. For silent substitution this is the desired
  state: cone excitations become a straight matrix multiply on the primaries.

---

## 8. Measurement method — what works and what doesn't

**The projector defeats fast detectors.** PWM bit-planes plus sequential RGB LEDs
mean any detector integrating less than several whole frame periods samples a
different slice each time and the reading swings wildly. This looks like a broken
instrument and is not. Require **500 ms – 1 s integration**, several readings per
level.

**You do not need absolute calibration.** Only curve shape matters, so any detector
linear in its own response works. Ranked: silicon photodiode into a DMM on current
range (best) → camera RAW at fixed manual exposure ≥ 1/4 s → handheld spectrometer.
A phone ambient-light sensor is a poor choice: coarsely quantized, auto-gain, and
nonlinear near both ends of its range.

**Best analysis trick — doubling ratios.** Within a *single* run,
`reading(2V)/reading(V) = 2^γ`. Linear → 2.0. De-gamma enabled → ~4.9. Instrument
calibration cancels out entirely, and it needs only two points. Use this before
trusting any fitted curve.

**Never compare two runs taken with different instruments.** Different spectral
weighting, geometry and integration make the comparison meaningless.

**Corollary that solved this session:** gamma stages compose multiplicatively, so if
two runs return the *same* exponent, the projector was in the *same* state for both
— regardless of instrument quality. That is how the reverted register was caught.

---

## 9. Toolkit

Lives at `D:\share\lcr4500-linearize` on the Windows 11 machine. Python 3.9.9 with
a `.venv` alongside. Key entry points:

```
setup.bat                  one-time install (hidapi, matplotlib)
1-check-connection.bat     read-only status
2-degamma-OFF.bat          the bypass
3-degamma-ON-restore.bat   undo
4-ramp.bat                 full-field patch generator; [s] split R|G|B|white, [c] channel
5-log-measurements.bat     interactive CSV logger
6-analyze.bat              fit, residuals, exponent, plot
7-watch-linear.bat         re-applies the bypass if it ever reverts, timestamped log
8-verify-linear.bat        one-shot verify
9-diagnose.bat             read-only dump of the whole video path + interpretation
10-leds-auto.bat           restore sequencer LED control
11-colorbars.bat           projector's internal colour bars (bypasses the PC)

lcr4500.py                 HID transport + DLPC350 command wrappers
ensure_linear.py           apply + verify; exit 0 linear / 1 not / 2 unreachable
matlab/ensureLightCrafterLinear.m   throws if the projector is not verified linear
docs/QUICK-REFERENCE.md    offline register + packet reference
docs/REFERENCES.md         annotated URLs
docs/GET-DOCS.bat          downloads the TI PDFs
```

`ensure_linear.py` always prints one parseable line:
`LCR4500 GAMMA=0x00 LINEAR=1 CHANGED=0 MODE=video`

Recommended habit: bracket every experiment with
`ensureLightCrafterLinear()` before and `ensureLightCrafterLinear('require',true)`
after, so a reverted register halts the run instead of silently corrupting data.

---

## 10. Verified state as of handoff

```
Application 2.0.0   API 2.0.0   Software config 69.0.0   Sequencer config 69.0.1
Display mode        video
Input source        parallel (HDMI), parallel bit depth 24 bit
Pixel data format   RGB 4:4:4 (30 bit)
CSC input           RGB 4:4:4
Gamma register      0x00  (linear)      Gamma status bit: disabled
LED enable          0x08  sequencer controlled
LED currents        R=151 G=120 B=125   (factory defaults)
Sequencer running   True   DMD parked False   Buffer frozen False
```

Internal colour bars confirmed rendering **in colour** at `GAMMA=0x00`.

---

## 11. Open threads

1. **Quantify the linearity.** No trustworthy sweep exists yet. Needs one clean run
   with a properly integrating detector, **including code 0** for the black offset,
   and levels below 32. Phone-sensor estimates put the residual exponent near 1.3,
   but that instrument cannot distinguish 1.0 from 1.3 and both its error modes bias
   the estimate downward. If a real residual survives, a correction LUT is the fix.
2. **The stimulus projects white instead of yellow.** Projector fully exonerated
   (§4, §10). Cause is PC-side. Leading hypothesis is §7: a small nonzero blue,
   previously invisible, now contributing ~20–60× more. Next step is to read the
   actual RGB integers the stimulus writes rather than judging by the preview
   window. Also confirm `ramp.py` is closed — it forces itself always-on-top and
   will cover a stimulus on the projector display.
3. **Recompute stimulus values in linear units.** Anything tuned against the
   gamma-encoded display is now wrong.
4. **Measurement hardware.** The UPRtek MK350S battery keeps dying. Running it
   tethered, or moving to a photodiode + DMM, would remove the recurring blocker.

---

## 12. Sources

* [DLPC350 Programmer's Guide (DLPU010F)](https://www.ti.com/lit/ug/dlpu010f/dlpu010f.pdf) — every register above
* [LightCrafter 4500 EVM User's Guide (DLPU011F)](https://www.ti.com/lit/ug/dlpu011f/dlpu011f.pdf)
* [Stage-VSS/matlab-lcr `dlpc350_api.cpp`](https://github.com/Stage-VSS/matlab-lcr/blob/master/api/dlpc350_api.cpp) — packet byte order
* [SivyerLab/pyCrafter4500](https://github.com/SivyerLab/pyCrafter4500) — pyusb-based alternative
* [DLPLCR4500EVM tool page](https://www.ti.com/tool/DLPLCR4500EVM) — GUI and firmware
