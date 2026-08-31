# RIG_REMINDER — hardware verification checklist

Off the dev Mac we can lint, dry-run, and prove the math (noise reproduction, gamma
numbers, GUI logic). Only the **rig** can prove the physical parts: LightCrafter light
output, Clampex acquisition, Stage/OpenGL presentation, and the LED driver. This is the
one-at-a-time checklist. **Nothing in this session changed acquisition start/stop** — that
SendKeys trigger is preserved; the goal is to confirm everything *around* it still "just
works" when a cell is patched.

Work top-to-bottom. §0 needs no cell. §3 is the "must-not-break." Save §9 (LED) for when
you have the FPGA wired.

---

## Already proven off-rig (trust these going in)
- `checkcode` clean on all 18 of our `.m` files (ml-uled copied as-is, 7 cosmetic notes).
- Noise: `sqrt(2)*erfinv(2u-1)` == old `norminv` to 1e-12; reproduces the Python analysis
  suite to ~3e-16. No Statistics Toolbox needed.
- Seed auto-increments `[2 3 4 …]` per epoch (seeded blocks only); `stim_signature`
  excludes seed **and** gamma.
- `lcGammaCorrect`: `[0 .25 .5 .75 1]` → codes `[0 136 186 224 255]` (0 and 255 fixed).
- GUI logic (registry ↔ signatures, arg-building, JSON save/load, protocol build) +
  headless `uifigure` construction (33 components).
- Analysis suite: 91 tests green, incl. the manifest count-check + timestamp cross-check.

## Must be running at the rig
- **Stage / OpenGL server** (localhost for §0, the rig server otherwise).
- **Clampex** — armed, protocol loaded, `File > Set Data File Names` configured, on the
  Windows PC. (See the separate Clampex research: the `.abf` name is auto-assigned; we pair
  by order + timestamp, not by pushing a name in.)
- **LightCrafter 4500** in **Video** mode (the ~2.2 gamma we invert).
- MATLAB **R2023b** with `June2026StageMATLAB` on the path (`addpath(genpath(...))`).
- (§9 only) MachXO3D LED-driver FPGA on its FTDI serial port.

---

## "Can I send OpenGL from the GUI with a local Stage server?"  → **Yes.**
Start the Stage server on the same machine, run `stimulusGUI`, and **uncheck "Trigger
Clampex acq"** before Run. Then:
- `runExperiment` still **pre-flights** the Stage server (prints the canvas size) and
  **presents** the stimulus over OpenGL — but skips the Clampex keystroke, so no rig is
  needed.
- **macOS caveat:** the Clampex trigger uses Windows-only `.NET System.Windows.Forms`, so
  it *only* works on the Windows rig PC. On the Mac you **must** leave that box unchecked or
  Run will error at the trigger step. Leave it **checked** at the real (Windows) rig.
- **Remote Stage server:** if the Stage/OpenGL server runs on a *different* computer, put
  its **IPv4 in the "Stage host" field** (or `rig_config.json` → `stage_host`); blank /
  `localhost` = this machine. It's saved to `rig_config` on Run, so the stimulus scripts'
  `client.connect(stageHost())` reach it — the centralized version of the old
  comment/uncomment-the-connect-line pattern (your `192.168.0.49` / `192.168.86.55` scripts).
- Each Run still writes a manifest row (`YYYY_MM_DD_stim_manifest.jsonl`) into `pwd`, so
  you can eyeball that too.

---

## §0 — Local dry run (no cell, no Clampex)   ☐
Isolate the acquisition with the **Debug** checkbox in the GUI (just above Run): Run then
presents the stimulus via the Stage host but sends no Clampex keystrokes — so you can
troubleshoot presentation + DLP linearization without acquisition. The **LED driver is
independent** of Debug: tick "Enable LED driver" if you want it running while you debug.
1. ☐ Start the Stage server (local machine, or the "Stage host" IP set in rig_config).
2. ☐ `stimulusGUI` → pick **Greyscale full-field flicker** → add a block → tick **Debug** →
   **Run experiment**.
3. ☐ Expect: `[runExperiment] Stage server OK. Canvas: W x H`, the flicker presents, then
   `Experiment finished`. Confirm a `*_stim_manifest.jsonl` appeared in `pwd`.
4. ☐ Repeat for a **Gaussian** stimulus (checks the seeded path + erfinv noise render).

## §1 — Gamma / light linearity (photometer)   ☐
1. ☐ Present a few known values (0.25 / 0.5 / 0.75 grey) full-field.
2. ☐ Measure emitted light. **0.5 should read ~50 % of max, not ~22 %.** 0 and full stay
   fixed. This is the whole point of `lcGammaCorrect` (γ from `rig_config.json`).
3. ☐ If it's off: re-measure input→output and run
   `calibrateGamma(measuredIn, measuredOut, 'write', true)`, then re-test. Both
   `lcGammaCorrect` and the manifest read γ from the one config, so they can't drift apart.

## §2 — Each stimulus presents correctly (7)   ☐
Present each once (GUI, trigger unchecked is fine here) and eyeball it:
- ☐ Greyscale full-field flicker   ☐ S-cone-iso full-field flicker
- ☐ Greyscale Gaussian (full field)   ☐ S-cone-iso Gaussian (full field)
- ☐ Greyscale Gaussian checkerboard   ☐ S-cone-iso Gaussian checkerboard
- ☐ Jittering circle
Watch for the right-bar blue/black flicker on the noise stimuli, correct checker grid size,
and that S-iso ones modulate R↔G as expected.

## §3 — Acquisition trigger UNCHANGED (the must-not-break)   ☐
This is the "currently works 100 %" path. Confirm it is byte-for-byte the same behavior.
1. ☐ **`Experimenter5000_v2.m`** (the student's loop): run it, confirm Clampex starts and
   stops each epoch exactly as it always has, and files land where expected.
2. ☐ **`runExperiment` / GUI with "Trigger Clampex acq" CHECKED**: confirm the same
   Alt+Tab (first epoch) + Ctrl+Shift+1 trigger fires per epoch. `triggerAcquisition.m` is
   just the old SendKeys factored out — verify it is indistinguishable from before.
3. ☐ Sanity: number of `.abf` files == number of epochs == number of manifest rows.

## §4 — Manifest ↔ .abf pairing + import   ☐
1. ☐ Run a short real session (e.g. one Gaussian block, 3 epochs, trigger ON).
2. ☐ Confirm the day's `*_stim_manifest.jsonl` has **exactly one row per `.abf`**, in order.
3. ☐ Import into the Analysis Suite; confirm each recording auto-tags with the right
   stimulus and the 3 identical-protocol epochs **group as "N epochs."**
4. ☐ **Break it on purpose** (guards should refuse, not silently mislabel):
   - delete one `.abf` (or add a stray) → import should **raise a count mismatch**.
   - reorder / mis-time a manifest row → import should **raise a timestamp mismatch**.
   (Both self-skip on older data with no timestamps — no false alarms.)

## §5 — Noise reproducibility end-to-end   ☐
1. ☐ Run a seeded Gaussian epoch; note the `seed` in its manifest row.
2. ☐ In Python: `noise_from_record(row)` (or `reproduce_noise(seed, …)`), compare to what
   was shown. Should match to ~1e-15. This is the seed-only reproduction contract.

## §6 — Seed auto-increment   ☐
1. ☐ Run a seeded block of N epochs (GUI or `runExperiment`).
2. ☐ Confirm the manifest seeds are `seedBase, +1, +2, …` and each epoch's noise is
   **independent** (not a frozen repeat), while they still share one `stim_signature`.

## §7 — GUI end-to-end   ☐
1. ☐ Build a 2-block protocol, **Save…** to `experiments/`, **New**, **Load…** it back —
   confirm identical. Then **Run** (trigger ON) against a test/cell.
2. ☐ Confirm the `experiments/*.json` is human-readable and re-runs the same session.

## §8 — rig_config fill + stamp   ☐
1. ☐ Fill the real `channel_to_led` map and `led_spectra_file` in `rig_config.json`
   (currently TODO placeholders).
2. ☐ Run one epoch; confirm the manifest `rig` block stamps the real projector / mode /
   gamma / channel→LED map (and that it does **not** change `stim_signature`).

## §9 — LED driver (NeitzLedRig, ml-uled)   ☐
See `ml-uled/README.md`. Standalone from the OpenGL scripts.
1. ☐ `rig = NeitzLedRig();` (auto-detect) or hard-code the COM / `/dev/cu.*` port.
   Expect `NeitzLedRig connected on …`. If "port in use": `clear rig`.
2. ☐ `rig.setIntensity(0,'r',0.75); rig.setMode(1);` (DC-red) → LED 0 shows ~75 % red.
3. ☐ `rig.setMode(2); rig.setTtlDebug(true,1,0,0)` etc. → colour-field select works.
4. ☐ Confirm a value set here matches the old C# `uLED` GUI setting it (same registers).
5. ☐ `rig.setMode(0); clear rig` → LEDs dark, port closed.
6. ☐ **GUI-driven (now built into the experiment):** in `stimulusGUI`, fill the **LEDs** grid
   (per-LED R/G/B, 0..1 linear duty), pick a **Mode**, tick **Enable**, add a block, Run.
   Expect `runExperiment` to print `LED driver configured on <port> (mode M)`, drive the LEDs
   through the blocks, and **dark + close** them when the session ends **or aborts**. Then
   **Save…** and **Load…** the experiment and confirm the grid / mode / port persist in the
   JSON (`opts.leds`). Values are **linear duty** (pre-distort like `lcGammaCorrect` if you
   want light linear at the eye). Leave **Enable off** (and "Trigger Clampex acq" off) for a
   local dry run with no FPGA. Per-session config for now — one LED setup per experiment.

## §10 — Generated stimulus scripts + single-window GUI (2026-08-29 overhaul)   ☐
**Layout since the rework:** ONE window — protocol builder (middle), Session monitor
embedded (right, no separate window, no second Cancel), and the **Screens & LEDs band**
along the bottom: five sections (pre-stim | stimulus | post-stimulus | inter-stim | end
of stim), each with a preset dropdown + its own 4×3 LED grid, and (except "stimulus") a
screen column (R/G/B boxes + color picker). "copy <phase>" buttons pull grids/screens
across; "sync and lock B channels" makes the far-right master B column drive every grid's
B channel. **Seeds are per epoch**: the protocol table has one editable column per
parameter plus Label and seed; every Gaussian epoch gets its own auto-assigned seed
(recorded in the manifest, and in the values CSV's new `seed` column when the debug dump
is on). `seedBase` is gone from the GUI.

Run no longer calls the `AA*` files: it writes ONE generated m-file per run into
`<data dir>/generated_stimuli/` (the exact record of what ran) and executes that. The
stimulus segment is frame-exact with the AA scripts (proven off-rig, all 7); what needs
the rig is the *physical* phase behavior:
1. ☐ Local dry run (§0 setup): set **Pre-stim** RGB to `0.5 0.5 0.5` and run 2 epochs.
   Expect: grey full screen for preStim seconds (sync bar dark) → stimulus → post-stim
   screen → the **Inter-stim** screen HOLDS between epochs → the **Run end** screen holds
   after the last one. No flashes between phases.
2. ☐ Frame clock on the photodiode: the first blue sync-bar flash still lands on the FIRST
   stimulus frame (pre-stim renders with the bar dark), so analysis alignment is unchanged.
3. ☐ Only ONE Stage connection per run (the scripts share a client now): watch the server
   console — one "Client connected" per Run, one disconnect at the end, and the server is
   free for standalone scripts afterwards.
4. ☐ Per-phase LEDs (FPGA wired): give Pre-stim a preset, leave the rest "(main grid)".
   Expect the grid to switch at the phase boundaries (~50 ms granularity, serial).
5. ☐ **Run end** LEDs: "Off" darks + closes as before; any grid/preset stays ON after the
   run and the driver lives on as base-workspace `rig` (`clear rig` to darken + close).
6. ☐ Quick load: Assign slot 1 to the current protocol, restart the GUI, click slot 1 →
   the whole experiment (protocol + phases + LEDs) comes back.
7. ☐ Open the day's `generated_stimuli/genStim_*.m` and confirm it reads as the record of
   the run; its name is stamped in the manifest (`params.generated_script`).
8. ☐ **Three-segment sync bar** (rightmost W/8, never covered by any full-screen value):
   photodiode/scope on each segment — **top** toggles every frame through pre/stim/post
   (a refresh/2 Hz square wave: ~30 Hz at 60 fps — measures the true LightCrafter rate);
   **middle** = the legacy stimulus-update pattern, dark outside the stimulus; **bottom**
   = solid while stimulus frames are up (envelope). On held screens (inter-stim / run end
   / startup) the top segment is SOLID blue ("projector alive, frame held" — DC on the
   photodiode) and middle/bottom are dark — a held frame is static, nothing flips.
9. ☐ **Diamond-pixel geometry (SQUARE checks)**: the DLP4500's 912×1140 diamond array
   lands each canvas pixel `pixel_aspect`× wider than tall (2.0 from the diamond
   geometry → a 16:10 image, per TI's WXGA spec — n.b. not quite the 16:9 we said).
   Generated checkerboards now DERIVE checksY for square-on-the-wall checks (40×25 at
   pixel_aspect 2; the old fixed 40×32 drew them ~1.3× wide, as in the 2026-08-29 photo),
   and the jitter circle gets radiusY = radius × pixel_aspect. **Verify**: run a
   checkerboard, photograph/measure a check — if still not square, tune rig_config
   `pixel_aspect` (2.222 would correspond to a true 16:9 image). The pre-flight prints
   the server's canvas and WARNS if it differs from rig_config `canvas_size` [912 1140];
   the manifest now records canvas_w/canvas_h/pixel_aspect per block. (AA* standalone
   scripts are untouched and still draw the old stretched 40×32.)
10. ☐ **Startup state**: launch `stimulusGUI` with the Stage server running → the screen
   goes dark (full field black, bar dark) and the LEDs load the **"startup"** preset
   (R/G dark, B duty 0.25 on the 545 nm LED). **CHECK THE ROW**: rig_config.json's
   `startup` preset drives **LED 1** (inferred from the "565nm on R/G" presets, which
   drive that row) — confirm LED 1 really is the green ~545/565 nm unit, and confirm
   whether its true peak is 545 or 565 nm while you're at it (the presets disagree with
   the request). With no server running, launch just notes it in the status line.

## §11 — Projector gamma bracket (2026-08-30, force-linear runs)   ☐
The DLPC350's de-gamma is now bypassed over USB (`lcr4500-linearize/`), and
`runExperiment` brackets every run: at start it forces each projector in rig_config's
`lc_projectors` linear and verifies (a required one that fails REFUSES the run); at end it
re-queries the stim projector and a mid-run revert warns loudly + flags the manifest
(`data_quality_warnings`). `lcGammaCorrect` follows automatically: verified linear → raw
values; anything else → the measured LUT, exactly as before. No config key = bracket inert.

1. ☐ **Identify the two units**: with both LC4500s plugged in,
   `.venv\Scripts\python.exe ensure_linear.py --list` → two `DEV` lines. Unplug/replug one
   to see which path is which. **Label the USB ports** (STIM / MON) — the HID path is
   stable per physical port, not per unit.
2. ☐ Pin them in rig_config.json (then `clear loadRigConfig`):
   `"lc_projectors": {"stim": {"device": "<path-substring>", "required_for_run": true},
   "monitor": {"device": "<path-substring>", "required_for_run": false}}`
3. ☐ GUI Run: expect the monitor's `projector` phase line, then
   `[runExperiment] projector: stim LINEAR (0x00, video); monitor LINEAR ...` before the
   LED setup. Manifest block gains `projector_linearity.state = "linear"`.
4. ☐ **Refusal drill**: power-cycle the stim projector, Run → the run must REFUSE only if
   the bypass cannot be applied (TI GUI open); with the GUI closed it silently re-applies
   (CHANGED=1) and runs. Unplug its USB → `projectorUnreachable` refusal.
5. ☐ **Mid-run revert drill**: start a long run, power-cycle the projector mid-run →
   at run end expect the red `DATA SUSPECT` lines + a `data_quality_warnings` entry in the
   day's nested manifest.
6. ☐ **Optical proof (the only real one)**: with a run-started (linear) projector, present
   0.25/0.5/0.75 full-field and measure — 0.5 must read ~50 %. Integrate ≥0.5 s per
   reading (PWM + sequential LEDs defeat fast detectors; see LCR4500-HANDOFF §8). This
   also settles the residual-γ question (handoff open thread 1): if a clean sweep shows a
   real residual, wire it into the reserved `dlp_residual_lut_*` keys.
7. ☐ Analysis Suite still imports a manifest carrying the new
   `projector_linearity` / `data_quality_warnings` fields (additive — should be ignored).

---

## Gotchas / quick fixes
- **macOS vs Windows:** the Clampex trigger is Windows-only .NET. Local Mac testing =
  trigger box **unchecked**. Real rig (Windows) = **checked**.
- **"port in use"** (LED driver): a previous `NeitzLedRig` still holds it → `clear rig`.
- **Stage server not reachable:** `runExperiment` fails fast in pre-flight before any
  acquisition — start the server first.
- **Manifest lands in `pwd`:** each stimulus writes its row to the current directory; run
  from the day's data folder so the manifest sits with the `.abf` files.
- **A failed epoch aborts the session** (by design) so no `.abf` is left without its row.
- **Legacy standalone AA\* scripts after a bracketed run:** a FRESH MATLAB knows nothing
  about the projector, so `lcGammaCorrect` applies the LUT — but the bracket left the
  projector LINEAR. Either run through the GUI (the bracket re-verifies) or run
  `3-degamma-ON-restore.bat` first. The bracket deliberately does NOT restore de-gamma at
  run end (a session is many runs; flip-flopping the register between them is worse).

## If a guard fires on import (Analysis side)
The importer now **refuses** on a row≠recording count mismatch OR a timestamp mismatch,
instead of silently mislabeling. That's intended. To pair anyway (you've checked by hand),
the analysis call takes `strict=False` (warn + skip) or `check_time=False`. Flag to the
viewer/Data-Explorer thread: it may want to catch these and offer a friendly "pair by hand?"
dialog rather than showing a raw error.
