#!/usr/bin/env python3
"""
info.py -- read-only sanity check. Confirms the USB link works and
reports the state that matters for a linearity measurement.
Sends no writes at all.
"""

import argparse
import sys

from lcr4500 import LCr4500, DeviceNotFound, describe_gamma


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--device", metavar="SEL", default=None,
                    help="select one unit when several are attached: index, "
                         "exact serial, or HID-path substring")
    args = ap.parse_args()
    try:
        with LCr4500(device=args.device) as p:
            print("LightCrafter 4500 / DLPC350")
            print("-" * 58)

            for name, ver in p.firmware_version().items():
                print(f"  {name:<18} {ver}")

            print()
            print(f"  Display mode       {p.display_mode()}")
            print(f"  Input source       {p.input_source()}")

            st = p.main_status()
            print(f"  DMD parked         {st['dmd_parked']}")
            print(f"  Sequencer running  {st['sequencer_running']}")
            print(f"  Buffer frozen      {st['buffer_frozen']}")

            print()
            print(f"  Gamma register     {describe_gamma(p.get_gamma())}")
            print(f"  Gamma status bit   "
                  f"{'enabled' if st['gamma_enabled'] else 'disabled'}")

            print("-" * 58)
            if p.display_mode() != "video":
                print("NOTE: not in video mode -- the degamma setting only "
                      "affects video mode.")
            return 0

    except DeviceNotFound as exc:
        print(exc, file=sys.stderr)
        return 3
    except IOError as exc:
        print(f"Communication error: {exc}", file=sys.stderr)
        return 4


if __name__ == "__main__":
    sys.exit(main())
