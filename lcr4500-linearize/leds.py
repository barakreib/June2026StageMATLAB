#!/usr/bin/env python3
"""
leds.py -- inspect LED enable state, and hand the LEDs back to the sequencer.

    python leds.py read     show LED enable state and drive currents
    python leds.py auto     restore sequencer control (the power-on default)

In video mode the DMD displays the red, green and blue bit planes in
sequence, and the sequencer strobes the matching LED for each sub-frame.
That is what makes a colour image. If LED control is switched to MANUAL,
the wrong LEDs are lit during each sub-frame -- and with all three held on,
every sub-frame is lit white, so the projector collapses the image to grey.

'auto' writes 0x08 to LED Enable Outputs (CMD2 0x1A / CMD3 0x07): bit 3 set
means sequencer controlled, which is the reset default.

This tool never writes LED drive currents. That is the command TI attaches a
damage warning to, and nothing in this package touches it.
"""

import sys

from lcr4500 import LCr4500, DeviceNotFound


def show(led, cur):
    print(f"  LED enable raw      0x{led['raw']:02X}")
    print(f"  Control             "
          f"{'sequencer (automatic) -- normal for video' if led['sequencer_controlled'] else 'MANUAL'}")
    if not led["sequencer_controlled"]:
        for c in ("red", "green", "blue"):
            print(f"    {c:<16} {'on' if led[c] else 'off'}")
    print(f"  Drive currents      R={cur['red']} G={cur['green']} B={cur['blue']}"
          f"   (defaults 151, 120, 125)")


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("read", "auto"):
        print(__doc__)
        return 3
    action = sys.argv[1]

    try:
        with LCr4500() as p:
            led = p.led_enable()
            cur = p.led_currents()
            print("before:")
            show(led, cur)

            if action == "read":
                return 0

            if led["sequencer_controlled"]:
                print("\nAlready sequencer controlled -- nothing to change.")
                return 0

            after = p.set_led_sequencer()
            print("\nafter:")
            show(after, p.led_currents())

            if not after["sequencer_controlled"]:
                print("\n*** Write did not take. Close the TI GUI and retry. ***",
                      file=sys.stderr)
                return 1
            print("\nOK. LEDs are back under sequencer control; colour should return.")
            print("Gamma is a separate register and is unaffected by this.")
            return 0

    except DeviceNotFound as exc:
        print(exc, file=sys.stderr)
        return 2
    except (IOError, OSError) as exc:
        print(f"Communication error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
