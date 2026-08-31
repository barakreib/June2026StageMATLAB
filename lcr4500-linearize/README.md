# LightCrafter 4500 — linearize video mode (Windows 11)

Bypasses the DLPC350's de-gamma table so that light output is linear in
code value while the projector runs in ordinary video (mini-HDMI) mode.

---

## What this actually does

The DLPC350 applies a **de-gamma** table to the video pipeline by default,
which is what makes 0–255 map non-linearly to light. It is controlled by one
register:

| | |
|---|---|
| Command | Gamma Correction (De-gamma) |
| I²C register | `0x31` |
| USB | `CMD2 = 0x1A`, `CMD3 = 0x0E` |
| bit 7 | `1` = enabled (power-on default) · **`0` = disabled → linear** |
| bit 0 | table pointer: `0` = TI Video (Enhanced), `1` = TI Video (Max Brightness) |

So the whole operation is a one-byte write of `0x00`. `0x80` puts it back.

The TI LightCrafter 4500 GUI does **not** expose this control, which is why
these scripts exist.

**It is volatile.** Nothing is written to flash. A power cycle restores the
factory default (enabled), so re-run `2-degamma-OFF.bat` after every power-up.
There is a startup-automation snippet at the bottom of this file.

---

## What you need

* The projector powered up, mini-HDMI connected, running in video mode
* A **mini-USB** cable from the projector to the PC
* Python 3.9+ on the PC, with "Add python.exe to PATH" ticked
* Internet on the PC for the one-time `setup.bat`

**No drivers.** The LightCrafter enumerates as a standard USB HID device and
Windows' built-in HID class driver claims it automatically. The `hidapi`
wheel installed by `setup.bat` is a userspace library that rides on top of
that — nothing goes near the driver layer, and there is no Zadig/WinUSB step.

> Do **not** install a WinUSB/libusb filter driver for this device. That is
> only needed for the pyusb route, and it will break the TI GUI.

---

## Run order

| Step | Script | What it does |
|---|---|---|
| 0 | `setup.bat` | one time — creates `.venv`, installs `hidapi` + `matplotlib` |
| 0b | `docs\GET-DOCS.bat` | one time, optional — pulls the five TI PDFs into `docs\` |
| 1 | `1-check-connection.bat` | read-only. Firmware rev, display mode, input source, current gamma state. Sends no writes. |
| 2 | `4-ramp.bat` + `5-log-measurements.bat` | *baseline* — measure the ramp with de-gamma still on |
| 3 | `2-degamma-OFF.bat` | the actual change |
| 4 | `4-ramp.bat` + `5-log-measurements.bat` | measure again |
| 5 | `6-analyze.bat` | fit both runs, get the verdict |
| — | `3-degamma-ON-restore.bat` | put it back the way it was |

Taking the baseline in step 2 is worth the ten minutes: it turns "I think it
worked" into a before/after with an exponent on it.

### Step 1 output looks like

```
  Display mode       video
  Input source       parallel (HDMI / 30-bit RGB)
  Gamma register     0x80  degamma ENABLED  -> non-linear output
```

If `Display mode` says `pattern`, the de-gamma setting is irrelevant — video
processing is bypassed entirely in pattern mode.

### Step 3 output looks like

```
before : 0x80  degamma ENABLED  -> non-linear output   [table: TI Video (Enhanced)]
after  : 0x00  degamma DISABLED -> linear output       [table: TI Video (Enhanced)]
OK.  Output should now be linear in code value.
```

The write is verified two ways — a read-back of the register **and** the
independent gamma bit in the DLPC350's Main Status word. If those disagree
you get a warning rather than a false success.

---

## The patch generator

`4-ramp.bat` opens a borderless full-field window (`tools/ramp.py`, tkinter,
standard library only). It defaults to `1280x800+1920+0`, i.e. the
projector's native resolution placed to the right of a 1920-wide primary
monitor. **Edit the `--geometry` line in the .bat if your layout differs.**

```
Up / Down          ± 1
PgUp / PgDn        ± 16
Right / Left       next / previous step in the measurement sequence
Home / End         0 / 255
digits then Enter  jump to a level
c                  cycle white → red → green → blue
h                  hide the readout (it stays echoed to the console)
Esc                quit
```

`tools/ramp.html` is a fallback for a browser. Prefer the Python one — a
browser may colour-manage the values you are trying to measure.

---

## Things that will still cost you linearity

Bypassing de-gamma fixes the projector. It does not fix the chain feeding it.

**Windows display path.** Set the projector's colour profile to plain sRGB
(Settings → System → Display → Advanced display → Display adapter properties
→ Color Management). Turn **HDR off** and **Night light off** for that
display. Set the GPU output to **full-range RGB 0–255**, not limited 16–235 —
limited range will clip both ends and quietly ruin the fit. In the NVIDIA
control panel this is "Output dynamic range: Full".

**Black offset.** DMD leakage means code 0 is not zero light. You get
`L = a·code + b` with `b > 0` — the slope is linear, there is a pedestal at
the bottom. `check_linearity.py` subtracts and reports it; don't mistake it
for a gamma problem.

**8 bits.** Video mode is 8-bit. If you need finer steps than 1/255 that's a
pattern-mode problem, not a gamma problem.

**Warm-up.** Give the LEDs 20–30 minutes before the baseline run, and take
before and after in one session. LED output drifts with junction temperature,
and a drifting source looks exactly like a nonlinearity.

**Re-measure after any firmware reload**, since defaults come back.

---

## Documentation

`docs\` carries the reference set:

* **`QUICK-REFERENCE.md`** — the DLPC350 material this package depends on,
  extracted and offline: packet layout, the gamma register bits, Main Status
  bits, the commands used here, and the commands to stay away from. Enough to
  work from without ti.com.
* **`REFERENCES.md`** — every URL, annotated with what it's for and whether
  you actually need it. Documents, TI software, source-code mirrors, and the
  E2E threads.
* **`GET-DOCS.bat`** — downloads the five TI PDFs into `docs\`:
  DLPU010 (Programmer's Guide — the important one), DLPU011 (EVM User's
  Guide), the DLP4500 and DLPC350 datasheets, and DLPU017 (Flash Programming
  Guide, reference only). Skips anything already there, and offers to open
  the TI tool page for the official GUI.

The PDFs are not bundled — they're TI's to distribute, and the download is
one click. Everything you need to *run* this package is already offline in
`QUICK-REFERENCE.md`.

---

## Risk

The gamma write itself is about as safe as it gets: one volatile register,
no flash access, reversible with `3-degamma-ON-restore.bat`, and fully
undone by a power cycle. A malformed packet gets NACKed or ignored.

The risk is in the neighbouring commands, and these scripts deliberately
never send them:

* **LED Driver Current Control** (`0x0B` / `0x01`) — TI puts an explicit
  caution on it; bad values can damage the LEDs.
* **Enter Program Mode** (`0x30`) and the flash programming commands — these
  park the DMD and jump to the bootloader. A botched flash operation is how
  these units get bricked, and recovery means reflashing over USB.

`info.py` sends no writes at all. `gamma.py` sends exactly one command word,
`0x1A0E`.

One operational note: **close the TI LightCrafter 4500 GUI before running
these.** Both want the same HID handle, and whichever grabs it first wins.

---

## Troubleshooting

**`Communication error: read error`, or a failed open.**
Something else has the USB HID handle. Nine times out of ten that is the TI
LightCrafter 4500 Control Software — close it completely, not minimised, and
check Task Manager for a leftover process. It polls the device continuously
when "Auto Update Status" is ticked. If that isn't it, unplug and replug the
mini-USB cable, wait five seconds, and retry.

**`The 'hid' module is missing from THIS Python`.**
You ran `python gamma.py ...` with the system Python instead of the project's
virtual environment. Use the numbered .bat files — they select the venv
automatically — or call it explicitly:

```
.venv\Scripts\python.exe gamma.py read
```

**The gamma setting reverted to `0x80` on its own.**
It is a volatile register, so anything that resets the controller restores the
default. Two things do it:

* **Power cycling the projector.**
* **The TI GUI.** Connecting with it, and especially `Apply Solution` or
  `Apply Default Solution`, pushes a batch of settings that can put gamma
  back. If you open the GUI at any point after running `2-degamma-OFF.bat`,
  assume the bypass is gone.

Working rule: **do all GUI work first, close the GUI, then set the bypass,
then measure — and don't reopen the GUI until you're finished.** Re-check with
`gamma.py read` immediately before and after any measurement run that matters.

**Sanity check that the bypass is actually live.** Don't sweep 17 levels to
find out. Park at code 128, note the meter, toggle, read again — bypassing
de-gamma should raise the reading at 128 by roughly 2.5x. At code 64 it is
more than 6x. That is far too large to hide in meter noise, and you can see it
with your eyes.

---

## When the image is wrong in a way gamma cannot explain

De-gamma is a single 1-D transfer curve. It has no per-channel or colour-path
involvement whatsoever, so it **cannot** desaturate the image, shift a hue, or
turn a colour projector monochrome. If that is what you are seeing, the cause
is elsewhere in the video path.

```
9-diagnose.bat
```

Read-only dump of every register that affects what leaves the projector:
display mode, input source and bit depth, pixel data format, CSC attribute,
port clock, gamma, LED enable state, LED drive currents, and sequencer status.
It then interprets what it found and names the likely fault.

**The usual culprit for "everything comes out grey".** In video mode the DMD
displays the red, green and blue bit planes in sequence and the *sequencer*
strobes the matching LED for each sub-frame. That time-multiplexing is what
makes a colour image. If LED Enable Outputs is switched from sequencer control
to MANUAL with all three LEDs held on, every sub-frame is lit white — the
projector sums R+G+B into one grey image, and a yellow stimulus comes out
white. Nothing in this package writes that register, but the TI GUI's LED
Driver Control panel does.

```
10-leds-auto.bat
```

Writes `0x08` to LED Enable Outputs, restoring sequencer control (the reset
default). Gamma is a separate register and is untouched, so **you keep the
linear response and get colour back.** This never writes LED drive currents —
that is the command TI attaches a damage warning to.

**A faster check needing no software at all:** open `4-ramp.bat` and press `c`
to cycle white → red → green → blue. If the red field projects as white rather
than red, the LEDs are not being sequenced and the diagnosis above is
confirmed in about five seconds.

---

## Making it stick

The bypass is volatile and reverts on every projector power cycle, and the TI
GUI can push it back too. Remembering to re-apply it is not a plan — the
failure is silent, and you only find out when the data looks wrong. Two tools
close that hole.

### `ensure_linear.py` — assert it, don't hope

```
8-verify-linear.bat                             double-click version
.venv\Scripts\python.exe ensure_linear.py       apply if needed, verify
.venv\Scripts\python.exe ensure_linear.py --require   verify only, never write
.venv\Scripts\python.exe ensure_linear.py --query     read-only report, never write
.venv\Scripts\python.exe ensure_linear.py --list      list attached units
```

Applies the bypass if it isn't set, then verifies two independent ways — the
register read-back *and* the gamma bit in Main Status — and reports through
its **exit code**: `0` verified linear, `1` not linear, `2` projector
unreachable, `3` bad usage. It always prints one parseable line:

```
LCR4500 GAMMA=0x00 LINEAR=1 CHANGED=0 MODE=video
```

Use plain mode at the start of a run and `--require` (or the read-only
`--query`) at the end, to prove the register held for the whole session.

### Two projectors on one machine — `--device`

With more than one LC4500 attached, every entry point (`ensure_linear.py`,
`gamma.py`, `info.py`, `diagnose.py`) takes `--device SEL` to pick one:
an **index** (into the `--list` order), an **exact serial number**, or a
case-insensitive **substring of the HID path**. A selector matching zero or
several units is a loud error, never a guess — LC4500s frequently report
empty or identical serials, so the reliable identity is the **path**, which
encodes the hub/port chain: stable across reboots and power cycles for a
given physical USB port, changed the moment the cable moves ports.
**Pin each unit by a path substring and label the USB ports** (STIM / MON).
No `--device` = first unit, exactly the single-projector behavior.

### From MATLAB

```matlab
addpath('D:\share\lcr4500-linearize\matlab');

ensureLightCrafterLinear();                 % start of experiment; errors if not linear
% ... run the experiment ...
ensureLightCrafterLinear('require', true);  % prove it held; errors if it reverted
```

It throws `LCr4500:notLinear` or `LCr4500:unreachable` rather than returning a
flag you might forget to check, so an experiment on a non-linear projector
stops instead of collecting bad data. `info = ensureLightCrafterLinear()`
returns `.linear`, `.gamma`, `.changed` and `.mode` if you want to log them.
It takes `'device', SEL` (see `--device` above) and `'query', true` (the
read-only mode, which never throws about projector state — branch on the
returned `.reachable` / `.linear` yourself).

**The stimulus suite does this automatically now.** When `rig_config.json`
has an `lc_projectors` section, `runExperiment` brackets every run: forces
each configured projector linear at start (refusing the run if a required one
won't verify), re-queries at the end, and flags the day's manifest if the
register reverted mid-run; `lcGammaCorrect` switches between raw values and
the measured LUT on the verdict (see `lcProjectorState.m` in the repo root).
The manual calls above remain for standalone scripts and bench work.

### `watch_linear.py` — cover a mid-session power cycle

```
7-watch-linear.bat
```

Polls every 10 s and re-applies the bypass the moment it sees `0x80`, logging
each event with a timestamp to `data\watch_log.txt`. Leave it running in its
own window for the duration of a measurement session. When it reports a
revert, the log tells you exactly which readings to distrust. It opens and
closes the device around each poll, so other tools still work between polls.

---

## Automating the re-apply after power cycle

Since the setting is volatile, fold it into whatever starts your rig. From a
batch file or shortcut:

```bat
"C:\path\to\lcr4500-linearize\.venv\Scripts\python.exe" ^
    "C:\path\to\lcr4500-linearize\gamma.py" off
```

From MATLAB:

```matlab
exe = 'C:\path\to\lcr4500-linearize\.venv\Scripts\python.exe';
scr = 'C:\path\to\lcr4500-linearize\gamma.py';
[status, out] = system(sprintf('"%s" "%s" off', exe, scr));
assert(status == 0, 'De-gamma bypass failed:\n%s', out);
disp(out);
```

From Python, in-process:

```python
from lcr4500 import LCr4500
with LCr4500() as p:
    p.set_gamma(False)
    assert not p.main_status()["gamma_enabled"]
```

Both return a non-zero exit code if the read-back doesn't confirm, so you can
make your experiment refuse to start on a projector that isn't linearized.

---

## Files

```
setup.bat                      one-time install
1-check-connection.bat         read-only status
2-degamma-OFF.bat              the change
3-degamma-ON-restore.bat       undo
4-ramp.bat                     patch generator
5-log-measurements.bat         record radiometer readings to CSV
6-analyze.bat                  fit + plot

lcr4500.py                     HID transport + DLPC350 command wrappers
gamma.py                       CLI: read / off / on
info.py                        CLI: status dump
tools/ramp.py                  tkinter patch generator (stdlib only)
tools/ramp.html                browser fallback
analysis/log_measurements.py   interactive CSV logger
analysis/check_linearity.py    least-squares fit, residuals, exponent, plot
data/                          your CSVs land here

diagnose.py                    read-only dump of the whole video path
leds.py                        LED enable state; restore sequencer control
9-diagnose.bat                 run the diagnostic
10-leds-auto.bat               give the LEDs back to the sequencer
ensure_linear.py               apply + verify, reports via exit code
watch_linear.py                re-applies the bypass if it ever reverts
7-watch-linear.bat             run the watcher
8-verify-linear.bat            one-shot verify
matlab/ensureLightCrafterLinear.m   MATLAB wrapper, throws if not linear

docs/QUICK-REFERENCE.md        offline DLPC350 register + packet reference
docs/REFERENCES.md             annotated URL list for every source
docs/GET-DOCS.bat              downloads the TI PDFs into docs/
```

### Packet format, for reference

```
byte 0     HID report ID ..... 0x00
byte 1     flags ............. 0x40 write / 0xC0 read  (bit7 rw, bit6 reply)
byte 2     sequence number
byte 3-4   payload length LE .. len(data) + 2
byte 5-6   command word LE .... CMD3 then CMD2
byte 7+    data, zero padded to 64 bytes
```

De-gamma off is therefore:

```
00  40  01  03 00  0E 1A  00  ...zeros to 64
```

CMD3 goes on the wire **before** CMD2. That is not a typo — TI's own API
packs the command as `(CMD2 << 8) | CMD3` into a little-endian `uint16`.
Getting this backwards is the most common reason a hand-rolled DLPC350
packet is silently ignored.

### Sources

Full annotated list in `docs\REFERENCES.md`. The three that the code rests on:

* [DLPC350 Programmer's Guide (DLPU010F)](https://www.ti.com/lit/ug/dlpu010f/dlpu010f.pdf) — gamma command, Main Status bits, command tables
* [LightCrafter 4500 EVM User's Guide (DLPU011F)](https://www.ti.com/lit/ug/dlpu011f/dlpu011f.pdf) — board, GUI, video pipeline
* [Stage-VSS/matlab-lcr `dlpc350_api.cpp`](https://github.com/Stage-VSS/matlab-lcr/blob/master/api/dlpc350_api.cpp) — packet byte order
