# stimulusGUI / monitor regression suite

Covers the 2026-08-29 work on `stimulusGUI.m`, `stimulusMonitor.m`, `stimProgress.m`,
`runExperiment.m`, `playAndLogTrial.m` and `finalizeStimBlock.m` — plus the generated
stimulus scripts (`generateStimScript.m`, `stageClientShared.m`, `ledSession.m`,
`stageHoldScreen.m`): `test_generator` runs every generated script against a
`FakeStageClient` and replays its controllers frame by frame against the AA algorithms
recomputed independently; `test_phases` covers the per-phase LED switching, the
inter-stim / end-of-run backdrops, and the final-LED handoff.

```matlab
cd June2026StageMATLAB/tests
runTests
```

Verified green on **both R2023b and R2026a** — run both, they have caught different bugs
(estimator lag, layout sizing):

```bash
/Applications/MATLAB_R2023b.app/bin/matlab -batch "cd('<repo>/tests'); runTests"
/Applications/MATLAB_R2026a.app/bin/matlab -batch "cd('<repo>/tests'); runTests"
```

## RIG SAFETY — read before adding a test

**Nothing in here may reach the real rig.** `rig_config.json`'s `stage_host` points at the
actual Stage server (`192.168.0.51`), and it is reachable from this Mac. A GUI test that
presses **Run experiment** *will* open a TCP connection to it — Stage is **single-client**,
so that can disturb a live session at the rig. This nearly happened once during development.

Three tiers, each with its own guard:

| Tier | What it drives | Guard |
|---|---|---|
| 1 | Pure logic, the monitor, the GUI without running | Never calls `runExperiment` with `preflight` on; `test_play_unblocked` uses `FakeStageClient` |
| 2 | The real **Run experiment** button | `tests/rigsafe/` is **first on the path**, so a stub `runExperiment` shadows the real one — the GUI cannot reach the network at all |
| 3 | The real pre-flight, timing out | Runs against a **copy** of the repo whose `rig_config.json` says `127.0.0.1`, with a socket that accepts and never answers |

`runTests` asserts the tier-2 shadow is actually in place before running those tests.

Additional nets: `tests/stageHost.m` shadows the repo's `stageHost` with `127.0.0.1` for
the whole suite, so even a bug that constructs a real `StageClient` gets an instant local
refusal instead of the live rig; and the tier-2 tests `cd` into a scratch dir before
pressing Run, because Run now writes the generated stimulus script into
`<pwd>/generated_stimuli/`.

Also: **never `delete` the GUI's saved session.** `stimulusGUI` persists it to `prefdir`,
which is the user's *real* MATLAB preferences directory — deleting it throws away their
restored state (this happened). Use `guiStateGuard()`, which moves it aside and puts it back
on any exit.

## Tier 3 — the Stage pre-flight test (manual)

```bash
SP=/tmp/stimgui_sandbox        # anywhere outside the repo
REPO=/Users/j/Neitz_Stimulus_Suite/June2026StageMATLAB
rm -rf "$SP" && mkdir -p "$SP"
cp "$REPO"/*.m "$REPO"/rig_config.json "$SP"/
cp "$REPO"/tests/*.m "$SP"/
python3 -c "
import json,io; p='$SP/rig_config.json'; c=json.load(open(p))
c['stage_host']='127.0.0.1'; io.open(p,'w').write(json.dumps(c,indent=2))"
nohup python3 "$REPO/tests/silent_server.py" >/tmp/silent.log 2>&1 &   # accepts, never answers
/Applications/MATLAB_R2026a.app/bin/matlab -batch "cd('$SP'); addpath('$SP'); test_preflight_cancel"
pkill -f silent_server.py; rm -rf "$SP"
```

Asserts: the failure is shown *in the monitor* with its reason; both Cancel buttons are live
during the 10 s pre-flight; each aborts in ~2.6 s instead of waiting it out; the GUI is fully
restored afterwards.

## What each test pins down

| Test | Guards against |
|---|---|
| `stimulusGUI('__selftest__')` | duration↔stimFrames, epoch rows, one-stimulus-per-protocol, `Update epochs`, nested manifest + multi-block discard |
| `test_cancel` | Cancel only at clean epoch boundaries; a triggered sweep always completes and logs; no seed consumed by a cancelled epoch |
| `test_cancel_async` | a callback firing mid-wait actually stops the run (the real interrupt path) |
| `test_protocol_complete` | the Keep/Discard hook fires **once per run**, not per block, even with per-epoch parameters |
| `test_play_unblocked` | `playAndLogTrial` waits out the presentation *outside* `getPlayInfo`, so callbacks run during it; frame-sync telemetry unchanged |
| `test_monitor` | monitor message shapes, LED/stimulus readout, duration correction, a throwing listener is dropped |
| `test_timeline_drift` | the timeline models the **real** epoch length; the marker never pins at the right edge early |
| `test_prep_landing` | after the un-repaintable setup pause, the marker resumes exactly on the stimulus band |
| `test_gui_edits` | table buttons gated on an empty protocol; `Update selected` per-epoch; live timeline preview |
| `test_gui_smoke` | builds the real window and drives the real callbacks end to end |
| `test_gui_lock` | every control except Cancel is dead mid-run, and all are restored after |
| `test_gui_runfail` | a **failed** run leaves the GUI fully usable (no restart needed) |
| `test_preflight_cancel` | tier 3, above |

## MATLAB gotchas these tests were written around

- **Anonymous functions capture by value.** `@() flag` freezes `flag` at creation. Any live
  flag (cancel, counters) must be a handle to a **nested function**. This silently broke the
  Cancel button once and two tests twice.
- `uitable` row `Selection` must be a **1×N row vector**, not a column.
- Deadline-based waits, not `pause`-per-tick: `runExperiment`'s `waitFn` keeps a phase to its
  nominal length with redraws *inside* the window. A test harness that pauses *and* redraws
  makes every phase run long and ends up measuring itself.
- Screenshots: `exportapp(fig, 'x.png')` renders a `uifigure` headlessly — the fastest way to
  catch clipped tables and off-screen layout.
