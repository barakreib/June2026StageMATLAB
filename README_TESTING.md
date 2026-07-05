# README_TESTING — testing strategy

The pipeline spans two languages (MATLAB stimulus rig → Python analysis) and one piece
of hardware (the LightCrafter + Clampex) that isn't on this dev machine. Testing is
therefore layered: everything that can be automated off-rig is, and a short on-rig
checklist covers what only the real rig can prove.

## Constraints — what runs where
- **This Mac has MATLAB R2023b** (headless: `matlab -batch "run('<script>')"`), but
  **not** the Stage/OpenGL stimulus server or Clampex (Windows). So MATLAB code can be
  linted + unit/dry-run tested here; **actual stimulus presentation, acquisition
  triggering, and real light output require the rig.**
- **Analysis suite** runs under `/Users/j/miniconda3/bin/python` (`pytest`).

## Layer 1 — Stimulus repo, off-rig (this Mac, automatable)
All of these pass today (developed as scratch scripts; **recommend committing them as a
`tests/` folder with a `runTests.m` driver** run under `matlab -batch`):
- **`checkcode`** (lint) every `.m` file → 0 issues.
- **`lcGammaCorrect`**: intended `[0 .25 .5 .75 1]` → codes `[0 136 186 224 255]`; 0 and
  1 are fixed points.
- **`calibrateGamma()`**: default reference points reproduce **γ = 2.2056, R² ≈ 1**.
- **`loadRigConfig`**: returns gamma/projector; falls back for a missing key.
- **`writeStimManifest`**: JSONL round-trip (append → `jsondecode`); `rig` block present;
  stamped γ matches config.
- **`stim_signature`**: a Gaussian block ×3 with **different per-epoch seeds** →
  **identical** signature (so it groups as 3 epochs of one stimulus); a changed
  `mu`/`sigma`/rate/type → **different**; the `rig` block does **not** perturb it. (The
  seed is deliberately **excluded** from the signature.)
- **Noise recipe (`erfinv`)**: `sqrt(2)*erfinv(2*rand-1)` == `norminv(rand)` to < 1e-12
  (base MATLAB, no Statistics Toolbox), and still reproduces the Python side to ~3e-16.
- **`runExperiment`**: dry-run sequences blocks/epochs; a failed epoch **aborts** the
  session (keeps the manifest aligned to the `.abf` files); the **per-epoch seed
  auto-increments** (seeds `[2 3 4 …]`, advancing only on seeded blocks).
- **`Experimenter5000`**: builds a valid protocol and drives the *real* `runExperiment`
  (verified by shadow-stubbing `runExperiment` and the stimulus so no rig is needed).
- **`stimulusGUI('__selftest__')` + `stimRegistry`**: headless logic test — the registry's
  arg count matches every `nargin(@fn)`; `argsFor` builds correct positional calls (seed
  slot `[]`, vec2 row, enum char); parse rejects bad enums; the experiment JSON
  round-trips; `buildProtocol` sets `seedArg` per block. The full `uifigure` also
  **constructs headless** (32 components, no API error); only its *visual* behaviour needs
  the user's display.

## Layer 2 — Analysis repo (this Mac, pytest)
- `/Users/j/miniconda3/bin/python -m pytest -q`. Seed-side tests to keep green:
  `tests/test_reproduce.py` (MATLAB-anchored — pins γ and the noise recipe to ~1e-12),
  `tests/test_io_stim.py`, `tests/test_epoch_groups.py`.

## Layer 3 — Cross-language / integration (the critical guarantee)
- **RNG regression** (foundation of seed reproduction): MATLAB `rand(mt19937ar, seed)` ==
  numpy `RandomState(seed).rand` (verified 0 difference); MATLAB `sqrt(2)*erfinv(2u-1)` ==
  `norminv(u)` == `scipy.special.ndtri` (~1e-16). **Pin this**; do NOT revert noise to
  `randn` (its ziggurat is not reproducible in Python) and do NOT reintroduce a Statistics
  Toolbox dependency.
- **End-to-end**: MATLAB `writeStimManifest` → Python `noise_from_record` regenerates the
  `(checks_y, checks_x, n_updates)` tensor **bit-for-bit** (verified 3e-16 at 32×40×5).
  **Recommend a committed golden-file test**: check in a small MATLAB-generated reference
  tensor + assert Python matches (guards both sides against drift).

## Layer 4 — On-rig verification (REQUIRED — cannot be done off-rig)
Only the real rig can prove these:
1. **Light linearity** — present a grey ramp / a few known values, **measure emitted
   light** (photometer), confirm it is linear in the intended value (mid-grey 0.5 reads
   ~50 % of max, not ~22 %). Validates γ for the current rig; if it drifts, re-run
   `calibrateGamma(measuredInput, measuredOutput, 'write', true)`.
2. **S-cone isolation** — confirm the R/G channels produce the intended modulation.
   (Note: the current `R=v, G=1-v` is a naive crossfade; true silent-substitution weights
   from the LED spectra + cone fundamentals are a roadmap item.)
3. **Manifest ↔ .abf alignment** — run a session; confirm the manifest has exactly one
   row per Clampex `.abf`, in the same order; import into the suite and confirm each
   recording auto-tags with the correct stimulus (and repeats collapse to "N epochs"). The
   suite now **refuses to import** on a row ≠ recording count mismatch (rather than
   silently mis-pairing) — verify a deliberately short/long manifest triggers that error.
4. **Acquisition** — confirm the SendKeys trigger still starts/stops each epoch's
   recording (unchanged code, but re-verify after any Clampex/Windows environment change).

## Regressions to guard
- γ has ONE source (`rig_config.json`); recalibrate via `calibrateGamma('write', true)`
  and both `lcGammaCorrect` and the manifest pick it up.
- The `.abf` ↔ manifest pairing is **by order** — a missed/aborted trial can desync it.
  Two guards now exist: `runExperiment` **aborts on a failed epoch**, and the analysis
  `apply_session_manifest` **raises on a row ≠ recording count mismatch** instead of
  mis-pairing. (Deterministic pairing via capturing the `.abf` filename is still a deferred
  roadmap item — equal-but-misordered counts would slip past a pure count-check.)
