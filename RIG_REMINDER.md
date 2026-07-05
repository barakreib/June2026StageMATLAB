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
- Each Run still writes a manifest row (`YYYY_MM_DD_stim_manifest.jsonl`) into `pwd`, so
  you can eyeball that too.

---

## §0 — Local dry run (no cell, no Clampex)   ☐
1. ☐ Start the Stage server locally.
2. ☐ `stimulusGUI` → pick **Greyscale full-field flicker** → **uncheck "Trigger Clampex
   acq"** → **Run experiment**.
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

## If a guard fires on import (Analysis side)
The importer now **refuses** on a row≠recording count mismatch OR a timestamp mismatch,
instead of silently mislabeling. That's intended. To pair anyway (you've checked by hand),
the analysis call takes `strict=False` (warn + skip) or `check_time=False`. Flag to the
viewer/Data-Explorer thread: it may want to catch these and offer a friendly "pair by hand?"
dialog rather than showing a raw error.
