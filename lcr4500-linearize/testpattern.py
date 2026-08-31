#!/usr/bin/env python3
"""
testpattern.py -- drive the DLPC350's OWN internal pattern generator.

This takes the PC, the GPU, the HDMI link and your stimulus software
completely out of the loop. The pattern is generated inside the controller
and displayed through the same DMD and the same LED sequencer as normal
video. So:

    colour bars come out in COLOUR  -> the projector's colour path is fine,
                                       and the problem is upstream (PC side)
    colour bars come out in GREY    -> the fault is inside the projector

    python testpattern.py colorbars
    python testpattern.py rgbramp
    python testpattern.py checker
    python testpattern.py list
    python testpattern.py off          <-- back to HDMI. ALWAYS run this after.

Switching the input source is a volatile register write, exactly like the
gamma bit. 'off' restores the parallel/HDMI input; so does a power cycle.
Gamma is a separate register and is not touched by any of this.
"""

import sys

from lcr4500 import (LCr4500, DeviceNotFound, TEST_PATTERNS,
                     SRC_PARALLEL, SRC_TESTPATTERN, describe_gamma)


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 3
    arg = sys.argv[1].lower()

    if arg == "list":
        print("Patterns:")
        for name, val in TEST_PATTERNS.items():
            print(f"  {name:<12} 0x{val:X}")
        print("\n  colorbars is the one you want for a colour-path check.")
        return 0

    if arg != "off" and arg not in TEST_PATTERNS:
        print(f"Unknown pattern '{arg}'.\n")
        print(__doc__)
        return 3

    try:
        with LCr4500() as p:
            print(f"before : input source = {p.input_source()}")

            if arg == "off":
                p.set_input_source(SRC_PARALLEL)
                print(f"after  : input source = {p.input_source()}")
                print("\nBack on the HDMI input.")
            else:
                p.set_test_pattern(TEST_PATTERNS[arg])
                p.set_input_source(SRC_TESTPATTERN)
                print(f"after  : input source = {p.input_source()}")
                print(f"\nDisplaying internal pattern: {arg}")
                if arg == "colorbars":
                    print("\n  Look at the projected image.")
                    print("  COLOUR bars -> projector is fine, problem is PC-side.")
                    print("  GREY bars   -> the fault is inside the projector.")
                print("\n  Run 'testpattern.py off' when done to restore HDMI.")

            # gamma is untouched -- show it so that is obvious
            print(f"\ngamma  : {describe_gamma(p.get_gamma())}")
            return 0

    except DeviceNotFound as exc:
        print(exc, file=sys.stderr)
        return 2
    except (IOError, OSError) as exc:
        print(f"Communication error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
