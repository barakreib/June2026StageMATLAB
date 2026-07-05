# experiments/

Saved stimulus protocols, one JSON file per experiment. Written and read by
**stimulusGUI.m** (Save… / Load…). These files are tracked in git so a protocol is
reproducible and reviewable.

## Format (`neitz-experiment/1`)

```json
{
  "format": "neitz-experiment/1",
  "opts":   { "preStim": 2, "postStim": 1, "itp": 3, "seedBase": 2 },
  "blocks": [
    { "stim": "<function name>", "params": { ... }, "epochs": <N>, "label": "<text>" }
  ]
}
```

- **`stim`** — the stimulus function name (must exist in `stimRegistry.m`).
- **`params`** — the stimulus's arguments *by name* (see `stimRegistry.m` for the list and
  order). The **seed is intentionally omitted**: for seeded stimuli `runExperiment` advances
  it by 1 per epoch from `opts.seedBase`, so repeated epochs are independent noise, and each
  seed is recorded in the day's stim manifest.
- **`epochs`** — how many presentations (Clampex sweeps / `.abf` files) of this block.
- **`opts`** — session timing + the seed base, passed straight to `runExperiment`.

To run one without the GUI:

```matlab
[blocks, opts] = deal([]); %#ok<NASGU>   % (loaded internally by the GUI)
stimulusGUI                               % then Load… the file and press Run
```

`example_grey_flicker_and_gaussian.json` is a minimal two-block sample.
