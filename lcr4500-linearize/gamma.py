#!/usr/bin/env python3
"""
gamma.py -- turn the DLPC350 de-gamma table on or off.

    python gamma.py read     show the current setting
    python gamma.py off      disable degamma  -> LINEAR light output
    python gamma.py on       restore the TI video degamma table

This writes a VOLATILE register (CMD2 0x1A / CMD3 0x0E, bit 7).
Nothing is written to flash. A power cycle restores the factory
default (enabled), so re-run "off" after every power-up.
"""

import sys

from lcr4500 import LCr4500, DeviceNotFound, describe_gamma


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("read", "off", "on"):
        print(__doc__)
        return 2

    action = sys.argv[1]

    try:
        with LCr4500() as p:
            before = p.get_gamma()
            print(f"before : {describe_gamma(before)}")

            if action == "read":
                st = p.main_status()
                print(f"status : gamma bit in Main Status = "
                      f"{'enabled' if st['gamma_enabled'] else 'disabled'}")
                return 0

            want_enabled = (action == "on")
            written = p.set_gamma(want_enabled)

            after = p.get_gamma()
            print(f"after  : {describe_gamma(after)}")

            if (after & 0x80) != (written & 0x80):
                print("\n*** WARNING: read-back does not match what was written. ***",
                      file=sys.stderr)
                return 1

            st = p.main_status()
            if st["gamma_enabled"] != want_enabled:
                print("\n*** WARNING: Main Status gamma bit disagrees with the "
                      "register read-back. ***", file=sys.stderr)
                return 1

            print("\nOK." + ("" if want_enabled else
                  "  Output should now be linear in code value.\n"
                  "  Remember: this resets when the projector is power cycled."))
            return 0

    except DeviceNotFound as exc:
        print(exc, file=sys.stderr)
        return 3
    except IOError as exc:
        print(f"Communication error: {exc}", file=sys.stderr)
        return 4


if __name__ == "__main__":
    sys.exit(main())
