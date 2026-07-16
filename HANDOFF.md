# HANDOFF — Neitz June2026 Stimulus Suite

Context for a new session/person taking over. Companions: `README_SUMMARY.md` (change log),
`README_TESTING.md` (test strategy), `RIG_REMINDER.md` (on-rig checklist), `ml-uled/README.md`
(LED driver). As of tag **v0.2.1** (2026-07-05).

---

## 1. The goal
A MATLAB visual-stimulus rig (Stage-VSS + TI **LightCrafter 4500** projector) for a Neitz-lab
color-vision experiment, plus a Python analysis suite. Three jobs:
1. **Linear light output** — the LightCrafter's "Video" mode forces a ~2.2 power-law gamma;
   we invert it so emitted light is linear in the intended stimulus value.
2. **Reproducible + self-describing data** — every stimulus is regenerable from a seed, and
   each trial writes a JSON manifest row so the Python suite can auto-import it.
3. **Student-maintainable** — the maintainer (Barak) is a non-expert; keep it simple, one
   source of truth per thing, a GUI instead of hand-editing m-files.

## 2. Repos, branches, access
- **Stimulus rig (primary work):** `/Users/j/Neitz_Stimulus_Suite/June2026StageMATLAB`
  - remote `git@github.com:barakreib/June2026StageMATLAB.git`, branch **`kuch`**,
    SSH key `~/.ssh/id_ed25519_macbookproArm64` (in the repo's `core.sshCommand`).
  - Tags: `v0.1.0`, `v0.2.0` (GUI + LED presets + Stage host), **`v0.2.1`** (frame-lock fix).
- **Analysis suite (SHARED with a second Claude thread):** `/Users/j/Neitz_Analysis_Suite`,
  branch `kuch`. **Coordinate** — the other thread owns `viewer.py`'s Data-Explorer UI. Do only
  ADDITIVE backend work here (`neitz/io/stim.py`, `neitz/stimulus/reproduce.py`, tests). PULL first.

## 3. Run / test
- **MATLAB R2023b**, headless: `/Applications/MATLAB_R2023b.app/bin/matlab -batch "run('<script>')"`.
  Use a SINGLE-LINE `-batch` string or `run('file.m')` (multi-line `-batch` breaks).
- **Build/run an experiment:** `addpath(genpath('.../June2026StageMATLAB')); stimulusGUI`
  (`genpath` matters so `ml-uled/` is on the path). Or `Experimenter5000.m` / `_v2.m`.
  Headless GUI logic check (no display/server): `stimulusGUI('__selftest__')`.
- **Analysis tests:** `/Users/j/miniconda3/bin/python -m pytest -q` (MUST be miniconda python;
  ~91 tests). Homebrew `python`/`python3` lack the deps.
- **Hardware needed for real runs (all absent on this dev Mac):** Stage/OpenGL server,
  Clampex (Windows), the LightCrafter, the LED-driver FPGA. So the m-files can be linted +
  dry-run tested here, but actual presentation/acquisition/light-output need the rig.

## 4. What exists (the pieces)
**Stimulus side (`June2026StageMATLAB/`):**
- `lcGammaCorrect.m` — inverse gamma `code = intended^(1/γ)`; γ from `rig_config.json`.
- `rig_config.json` + `loadRigConfig.m` (cached reader) + `setRigConfig.m` (writer, clears
  cache) — single source of truth for γ, projector, `stage_host`, `led_port` (the LED
  driver's COM port), `channel_to_led` (TODO), `led_presets`. `calibrateGamma.m` re-fits γ.
- **Noise:** `sqrt(2)*erfinv(2*rand(mt19937ar)-1)` (inverse-CDF; base MATLAB, no Stats Toolbox).
  Byte-identical to numpy `RandomState` + `scipy.special.ndtri`, so noise regenerates in Python
  from the seed alone. **Never revert to `randn`** (ziggurat isn't Python-reproducible).
- `writeStimManifest.m` — **dual-write** per trial (git-ignored). (a) appends one JSON line to
  the flat `YYYY_MM_DD_stim_manifest.jsonl` (UNCHANGED — the analysis contract); (b) also
  maintains a nested `YYYY_MM_DD_stim_manifest.json` (`day → cell → block → epochs`) written
  atomically, using the base-workspace `neitzSessionContext` (cell/block/LEDs) that
  runExperiment/GUI publish; standalone runs fall back to cell `(standalone)` or a base
  `cellName`. Both add `stim_signature` (hash of defining params, EXCLUDING seed AND gamma), a
  `rig` block, and `timestamp`. The nested doc is losslessly flattenable to the flat row order;
  the `.jsonl` is transitional and will be dropped once the analysis reader consumes nested.
- `runExperiment.m` — session orchestrator: pre-flights Stage, triggers Clampex per epoch
  (`triggerAcquisition.m` = the unchanged SendKeys), auto-increments the seed per epoch
  (`opts.seedArg`/`opts.seedBase`), optionally drives the LEDs (`opts.leds`), aborts a failed
  epoch. `stageHost()` picks the Stage server host.
- **7 stimulus scripts** (`AA*.m`): 2 flicker, 4 Gaussian (grey/S-iso × full-field/checkerboard),
  1 jitter. They connect via `client.connect(stageHost())` and index frames by **`s.frame`**.
- `stimRegistry.m` — the 7 stimuli's name/args/types/seed-arg (single source for the GUI).
- **`stimulusGUI.m`** — the main app (see §5).
- `ml-uled/NeitzLedRig.m` — RS-232 LED-driver client (replaces the C# uLED GUI):
  `setIntensity(led 0..3,'r'/'g'/'b',0..1 duty)`, `setMode`, `setTtlDebug`, auto port-detect.
- `experiments/*.json` — saved GUI protocols (tracked).

**Analysis side (`Neitz_Analysis_Suite/`, additive):**
- `neitz/stimulus/reproduce.py` — `reproduce_noise(seed,...)` (RandomState+ndtri+order='F'+clip),
  `gamma_adjust`, `expand_to_frames`.
- `neitz/io/stim.py` — manifest reader; `noise_from_record`, `sent_codes_from_record`,
  `epoch_groups`, and **`apply_session_manifest`** (auto-tags recordings; refuses to mispair —
  see §6). `neitz/io/abf.py` gained `recorded_datetime()` (header-only, for the time cross-check).

## 5. The GUI (`stimulusGUI.m`) — feature map
Pick a stimulus → edit params → set epochs/label → **Add block** (chain blocks) → **Run**
(→ `runExperiment`). Save/Load protocols as JSON in `experiments/`.
- **Cell** field (top) — name/ID of the patched cell. NOT saved into protocols or the
  remembered session (transient per patch); passed into `opts.cellName` on Run only, so the
  nested manifest files each trial under the right cell (see §6). Update it per new cell.
- **Stage host (IPv4)** field — writes `rig_config` `stage_host` on Run; blank/`localhost` = local.
- **LEDs:** Mode dropdown, Port (default from `rig_config` `led_port` = COM3 at the rig;
  type AUTO to probe), **Preset dropdown** (from `rig_config` `led_presets`), and **ONE 4×3
  intensity grid** (LED 0..3 × R/G/B; a preset fills it). **Set now / Off now** buttons push
  the grid + Mode to the rig immediately (quick-set between runs). ONE shared base-workspace
  `rig` is used everywhere: quick-set adopts a live workspace `rig` or publishes its own; demo
  scripts reuse it too; it is released automatically before an LED-enabled Run (runExperiment
  opens its own). (The old During/Between/End three-grid selector was removed — `runExperiment`
  only ever applied the During grid, so the other two never drove the LEDs.)
- **Enable LED driver** + **Debug** checkboxes (above Run). **Debug = skip Clampex acquisition
  ONLY** — the LED driver stays independently controllable (do NOT make Debug force LEDs off).
- **Trigger Clampex acq** checkbox (uncheck on macOS / for local dry runs — the trigger is
  Windows-only .NET).
- **Remembers the last session** (all settings + protocol) in
  `prefdir/neitzStimulusGUI_lastSession.json` (per-user, NOT the repo).
- `stimulusGUI('__selftest__')` runs a headless logic test (registry/args/JSON/presets round-trip).

## 6. Data integrity — the guards that exist
- **Frame-lock (v0.2.1):** controllers index by `s.frame`, not `floor(s.time*refreshRate)`. The
  old time-based index doubled a frame ~every 30 (the display runs ~62 Hz, scripts assumed 60).
- **Manifest ↔ .abf pairing** (analysis `apply_session_manifest`): pairs by trial order, but
  REFUSES to mispair — (a) row-count ≠ (non-reference) recording-count → `ValueError`;
  (b) timestamp cross-check: each row's `timestamp` vs the paired `.abf`'s recorded time; an
  equal-count-but-shifted pairing is caught. `strict=False` downgrades to warn.
- `runExperiment` aborts on a failed epoch (keeps manifest aligned to `.abf`).

## 7. OPEN ITEMS / next steps (priority-ish)
1. **Manifest should stamp the REAL refresh rate.** After the frame-lock fix the stimulus is
   locked to the true ~62 Hz, but the manifest still records `refresh_rate_hz: 60`, so the
   analysis time-axis is off by ~3%. Capture the actual `s.frameRate` at play time → manifest.
2. **~~Per-phase LED switching~~ (RESOLVED, 2026-07-16).** The old GUI saved 3 LED grids
   (during/between/end) but `runExperiment` only ever applied the During grid, so Between/End
   never drove the LEDs. The three-grid selector was **removed** — the GUI now has ONE LED grid
   (= the applied one). If true per-phase switching is ever wanted, it would be a new feature
   (set at stim start / ITP / after the last epoch), not a fix to dead UI.
3. **`rig_config` TODOs:** `channel_to_led` (which external LED each projector R/G/B drives —
   we now know **LED 1 = 565 nm**; the other 3 wavelengths are unknown), `led_spectra_file`,
   and the true cone-isolation `silent_substitution_weights` (current S-iso is a naive
   `R=v, G=1-v` crossfade).
4. **Deterministic pairing (deferred):** the timestamp cross-check narrows but doesn't fully
   close order-mismatch; a `.abf`-filename capture (needs an acquisition-control rebuild) would.
5. **Flag to the viewer/other thread:** the Import Data call can now raise (count OR timestamp
   mismatch) — it may want a try/except + friendly dialog instead of a raw traceback.

## 8. Clampex external control (researched)
Clampex has **NO software API** (no CLI/COM/DDE/SDK/socket) and **cannot set or read the .abf
filename**. The current trigger is a faked keystroke (`Ctrl+Shift+1` sequencing key via .NET
SendKeys). The only official non-keystroke start is the **Digidata `START` BNC (TTL)** — but it
gives timing only, not naming. Robust path if ever rebuilt: TTL START + **read back** the newest
`.abf` (via pyABF/`abfload`) to learn the name. See project memory for the cited details.

## 9. Hard rules (from the user)
- **DO NOT touch Clampex acquisition start/stop** (SendKeys works). Only improve labeling/JSON.
  (Two SANCTIONED exceptions were made to the stimulus scripts, both user-approved: the
  `connect(stageHost())` IP support, and the `s.frame` frame-lock fix.)
- **KEEP `Experimenter5000_v2.m`** — the student's simple trial loop.
- **DO NOT commit `.claude/`** (gitignored). Generated `*_stim_manifest.jsonl` are gitignored too.
- **AVOID backticks inside `git commit -m "..."`** (zsh runs them as command substitution).
- End commit messages with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

## 10. Gotchas / lessons
- **Never index Stage frames by `s.time` — always `s.frame`.** (§6 frame-lock.)
- `rig_config` `led_presets` are an **array of `{name, values}`** (NOT an object keyed by name)
  so friendly names with spaces survive `jsondecode` (which mangles field names).
- `NeitzLedRig.setIntensity` **clamps duty to 0..1** — so any preset value >1 drives full-on,
  not N×. (The `macaque s-iso` preset's `B` values were `10`; corrected to `1.0` on 2026-07-16
  so the config is honest — same full-on result, no behavior change.)
- `runExperiment` **auto-adds `ml-uled/` to the path** so `NeitzLedRig` resolves under a bare
  `addpath(repo)`.
- MATLAB column-major fill == numpy `order='F'` (used in reproduce_noise).
- The stimulus scripts hard-code `refreshRate = 60` for the noise-update math; that's the nominal
  rate and is fine — only the frame INDEXING must not use it (now uses `s.frame`).

## 11. Verification you can run here (dev Mac)
- MATLAB: `checkcode` every `.m` (0 issues on our files; ml-uled has 7 cosmetic notes),
  `stimulusGUI('__selftest__')`, headless `stimulusGUI()` construction (56 components).
- Python: `pytest -q` (91 green) incl. `test_reproduce.py` (MATLAB-anchored),
  `test_manifest_countcheck.py` (count + timestamp guards).
- Cross-language pin: MATLAB `rand(mt19937ar,seed)` == numpy `RandomState(seed).rand` (0 diff);
  `sqrt(2)*erfinv(2u-1)` == `ndtri` (~1e-16). Do not break this.
