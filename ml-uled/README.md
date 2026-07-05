# MATLAB LED-driver client

RS-232 driver for the PFM_RGB MachXO3D LED-driver FPGA. This is the intended
replacement for the C# `uLED` GUI — set LED intensities directly from `.m`
scripts, alongside the OpenGL/Stage projector stimuli in
`~/Neitz_Stimulus_Suite/June2026StageMATLAB`.

## Files

- `NeitzLedRig.m` — `handle` class wrapping the serial link. Auto-detects the
  FTDI COM port, speaks the framed `[TYPE|LEN|PAYLOAD|CKSUM]` protocol
  (see `../PORT_RS232.md`), and darks + closes the port on `clear`/`delete`.
- `demoLedRig.m` — minimal end-to-end example / template.

## Quick start

```matlab
rig = NeitzLedRig();              % auto-detect (or NeitzLedRig("/dev/cu.usbserial-XXXX"))
rig.allOff();
rig.setIntensity(0, 0, 0.75);    % LED0, colour-field state ST0, 75% linear duty
rig.setIntensity(1, 0, 0.75);    % LED1, ST0
rig.outputEnable(true);
% ... run stimulus ...
rig.outputEnable(false);
clear rig                        % closes the port
```

## Model

- `led` = 0..1 (two physical PFM output channels)
- `state` = 0..3 (colour-field states ST0..ST3, selected live by the
  LightCrafter's `externalTTLin` strobes — the host only loads the registers)
- intensity is `0..1` **linear duty** (`intensityToCounts`). For light that is
  linear *at the eye*, pre-distort the same way `lcGammaCorrect.m` does for the
  projector before calling `setIntensity`.

Requires MATLAB with the serial interface (`serialport`, R2019b+; tested
against R2023b). No toolboxes or vendor drivers needed.
