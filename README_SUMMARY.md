# README_SUMMARY — June2026 Stage stimulus changes

## Goal
Make the TI LightCrafter 4500's **emitted light linear** in the intended stimulus value
(its "Video" mode forces a ~2.2 power-law gamma, mimicking a CRT), and make every
stimulus **fully reproducible and self-describing** for the `Neitz_Analysis_Suite` —
**without changing that suite's processing pipeline.**

## Where the changes live
- **All substantive changes are in THIS repo** (`June2026StageMATLAB`, the stimulus /
  collection side).
- `Neitz_Analysis_Suite` was treated as **read-mostly**: this thread added only additive
  helper modules + tests there and one display-only Data-Explorer line — **no core
  import/store/analysis code was modified** (see *Interface* + *What did NOT change*).

## Stimulus-side changes (this repo)

1. **Gamma linearization** — `lcGammaCorrect.m`. The projector emits light ∝ code^γ
   (γ = 2.2056, measured). We invert it: `code = intended^(1/γ)`, so emitted light is
   **linear in the intended value**, applied **per channel** at every value site (noise
   images + streamed colour LUTs). Black / white / pure primaries are fixed points
   (unchanged); a mid-grey 0.5 now sends **code 186 instead of 128**.

2. **Reproducible noise** — noise is drawn with `norminv(rand(...))` (inverse-CDF)
   instead of `randn`. MATLAB's `mt19937ar` `rand` is bit-identical to numpy's
   `RandomState`, and `norminv` == `scipy.special.ndtri`, so the exact noise regenerates
   in Python **from the seed alone** (`randn`'s ziggurat cannot). Affects the 4 Gaussian
   scripts + the jitter walk.

3. **Per-session manifest** — `writeStimManifest.m`. Each trial appends one JSON line to
   `YYYY_MM_DD_stim_manifest.jsonl`:
   - stimulus + params (`seed, mu, sigma, checks_x/y, n_updates, flicker, ...`),
   - `stim_signature` — a hash of the defining params, so **repeated identical stimuli
     share it** (a 2 Hz square wave presented 3× → one stimulus, 3 epochs),
   - a `rig` block (projector, Video mode, gamma, channel→LED map) — self-describing,
   - `timestamp`.
   This **replaces the old per-cell value CSV** — values regenerate from the seed, so no
   pixel data is shipped.

4. **Rig config + calibration** — `rig_config.json` (single source of truth: projector,
   mode, gamma, channel→LED map [TODO placeholders for the real LED identities]),
   `loadRigConfig.m` (cached reader), `calibrateGamma.m` (power-law fit of measured
   input→output; re-derives γ, optional write-back). `lcGammaCorrect` and the manifest
   both read γ from here, so applied and recorded gamma can never drift.

5. **Session orchestrator** — `runExperiment.m` (config-driven protocol of stimulus
   blocks × epochs; pre-flights the Stage server; aborts a failed epoch so no `.abf` is
   left without its manifest row) + `triggerAcquisition.m` (the existing SendKeys
   Clampex trigger, **factored out, behavior unchanged**). `Experimenter5000.m` is folded
   to use it; **`Experimenter5000_v2.m` is kept unchanged** (student's trial loop).

## What did NOT change
- **Acquisition start/stop** — still the existing SendKeys (`Ctrl+Shift+1`) Clampex
  trigger; the mechanism was **not rebuilt**.
- **The `Neitz_Analysis_Suite` processing pipeline** — import / store / analysis code was
  **not modified by this thread** (see *Interface*).

## Interface with Neitz_Analysis_Suite (the contract)
- The rig writes `YYYY_MM_DD_stim_manifest.jsonl` **alongside** the Clampex `.abf` files.
- The suite pairs each manifest row to a `.abf` **by trial order** and regenerates the
  exact stimulus from the seed. Contract: **one manifest row per presentation, in
  acquisition order**.
- **Additive + backward-compatible**: with no manifest present, the suite imports exactly
  as before (hand-entered stimulus metadata).
- The additive analysis-side helpers this thread contributed (so the suite *can* consume
  the manifest): `neitz/stimulus/reproduce.py` (regenerate noise from seed),
  `neitz/io/stim.py` (manifest reader + `noise_from_record` + `epoch_groups`), their
  tests, and one read-only `Epochs` row in the Data-Explorer detail pane. The actual
  *Import Data* wiring (`apply_session_manifest`) and seed-based STA/STRF dispatch were
  implemented by the separate analysis-side thread, not here.

## Tag
`v0.1.0` on both repos (this repo @ commit `6a285d7`). Key stimulus commits: `ff1188e`
gamma · `b035444` inverse-CDF · `f1b59c2` manifest · `7cfec6f` rig_config+calibration ·
`4b8f820` runExperiment · `ace880e` Experimenter5000 fold · `d97df9f` stim_signature ·
`6a285d7` rig stamp.
