# Session summary — linearizing the LightCrafter 4500

A narrative record of what was attempted, what failed, and why. The technical
reference is in `LCR4500-HANDOFF.md`; this is the story behind it, kept because
most of the time went into diagnosis rather than into the fix.

---

## The goal

Make a TI DLP LightCrafter 4500 produce light output linear in code value while
running as an ordinary projector on its mini-HDMI input. In stock video mode the
DLPC350 applies a de-gamma table, so 0–255 maps to light with an exponent around
2.2. Needed for photometric work where code value must be proportional to
luminance.

## The fix itself

One byte. `CMD2 0x1A` / `CMD3 0x0E`, bit 7 cleared. The TI GUI doesn't expose it,
so it goes over USB HID directly. A Windows toolkit was built around it — see the
handoff doc for the inventory.

Total time on the actual fix: minutes. Everything else was diagnosis.

## What went wrong, in order

**1. Wrong Python.** `python gamma.py` picked up the system Python 3.9.9 instead of
the project venv and reported `hid` missing. Cosmetic, but it cost a round trip.
The .bat files select the venv; typing `python` directly does not.

**2. The TI GUI holding the USB handle.** Produced `Communication error: read
error`. The GUI polls continuously when "Auto Update Status" is ticked. It must be
*fully* closed, not minimized.

**3. The real one — the register is volatile, and this was not understood.**
The projector was power cycled immediately after the bypass was written, which
silently restored the default. Two complete measurement sessions were taken on a
projector that had reverted, with no error anywhere to indicate it. The TI GUI can
revert it too.

**4. Measurement chain problems that masked the above.**
   * Before-run on a UPRtek MK350S, after-run on a phone lux app — two different
     instruments measuring two halves of one comparison, which is not a comparison.
   * Both instruments read wildly unstable values. This turned out to be the
     projector, not the instruments: DMD PWM plus sequential RGB LEDs defeat any
     detector integrating less than several frame periods.
   * The MK350S battery died mid-session, twice.
   * One sweep was non-monotonic at the top — output *falling* as code rose, which
     the projector cannot do. Instrument saturation, and that run was discarded.

## The reasoning that cracked it

Two sweeps were taken, believed to be before and after the bypass. Both fitted an
exponent near 2.3.

Gamma stages compose multiplicatively. If the bypass had been active for one run
and not the other, the measured exponents *must* differ by a factor of ~2.2 — no
matter what else is in the chain, no matter how bad the meter is. They didn't.
That proved the projector was in the same state for both runs, which pointed
straight at the reverted register rather than at a failed bypass.

A direct read confirmed `0x80`. The user then recalled power cycling the projector
right after the write.

**The lesson worth carrying:** when two measurements that should differ by a known
factor don't, suspect the state, not the instrument.

## Evidence the fix works

Phone-sensor run with the bypass genuinely active, against the MK350S baseline,
compared by doubling ratios (which cancel calibration):

| | baseline (de-gamma on) | bypassed |
|---|---|---|
| 64 → 128 ratio | 6.00 | 2.46 |
| 96 → 192 ratio | 5.80 | 2.40 |
| implied γ | ≈ 2.55 | ≈ 1.28 |
| straight-line R² | 0.909 | 0.982 |

Linear would be 2.0, de-gamma-enabled ~4.9. Unambiguous. The residual γ≈1.3 is not
resolvable with a phone ambient-light sensor and remains open.

## The colour scare

With the projector linearized, a yellow stimulus (red on R, green on G) projected
as white, raising the question of whether linear mode had cost colour.

It had not. De-gamma is a single 1-D transfer curve with no colour-path
involvement. Confirmed empirically by running the DLPC350's *internal* colour-bar
generator while the gamma register read `0x00` — colour bars rendered in full
colour, with the PC, GPU, HDMI and stimulus software entirely out of the loop.

A full read-only register dump also came back clean: LED enable `0x08` (sequencer
controlled), RGB 4:4:4, factory LED currents, sequencer running.

The likely explanation is a downstream consequence of linearization rather than a
fault: removing de-gamma amplifies the bottom of the range by 12–60×, so a small
nonzero blue that was previously invisible becomes enough to wash yellow toward
white. Unresolved at handoff; next step is to read the stimulus's actual RGB
integers rather than judging from the preview window.

## Guard rails built as a result

* `ensure_linear.py` — applies the bypass, verifies via **two independent
  registers**, and reports through its exit code.
* `matlab/ensureLightCrafterLinear.m` — throws rather than returning a flag, so an
  experiment on a non-linear projector halts instead of collecting bad data.
  Intended use is to bracket every run: apply before, `'require',true` after.
* `watch_linear.py` — polls and re-applies on revert, with a timestamped log that
  identifies exactly which readings to distrust.
* `diagnose.py` — read-only dump of the whole video path with interpretation.
* `testpattern.py` — internal pattern generator, the split-half diagnostic that
  separates projector faults from PC-side faults in ten seconds.

## Honest status

* Bypass works and is verified two ways. **Confirmed.**
* Linear and RGB coexist. **Confirmed on hardware.**
* Degree of residual nonlinearity. **Unknown** — needs one clean sweep with a
  properly integrating detector, including code 0.
* Stimulus rendering white. **Open**, isolated to the PC side.
