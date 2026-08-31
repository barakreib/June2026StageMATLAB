#!/usr/bin/env python3
"""
ensure_linear.py -- make the projector linear, prove it, and report via
exit code. Built to be called from an experiment script rather than typed.

    python ensure_linear.py              apply the bypass if needed, verify
    python ensure_linear.py --require    verify only; never writes
    python ensure_linear.py --quiet      print only on failure

Always prints one machine-readable line to stdout:

    LCR4500 GAMMA=0x00 LINEAR=1 CHANGED=0 MODE=video

Exit codes:
    0   projector is verified linear
    1   not linear (register would not take, or --require and it was enabled)
    2   projector unreachable, or a USB communication failure
    3   bad usage

Verification is deliberately belt-and-braces: the gamma register is read
back AND the independent gamma bit in the DLPC350's Main Status word is
checked. Both must agree before this exits 0. A write that appears to
succeed but doesn't reach the pipeline fails here rather than silently
corrupting a day of data.
"""

import argparse
import sys

from lcr4500 import LCr4500, DeviceNotFound, describe_gamma


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--require", action="store_true",
                    help="verify only, never write (assert mid-experiment)")
    ap.add_argument("--quiet", action="store_true",
                    help="suppress output unless something is wrong")
    args = ap.parse_args()

    def say(msg, error=False):
        if error:
            print(msg, file=sys.stderr)
        elif not args.quiet:
            print(msg)

    try:
        with LCr4500() as p:
            before = p.get_gamma()
            changed = False

            if before & 0x80:
                if args.require:
                    print("LCR4500 GAMMA=0x%02X LINEAR=0 CHANGED=0" % before)
                    say("De-gamma is ENABLED and --require forbids changing it.\n"
                        "The projector is not linear. Run 2-degamma-OFF.bat, or drop\n"
                        "--require to let this apply the bypass itself.", error=True)
                    return 1
                p.set_gamma(False)
                changed = True

            after = p.get_gamma()
            status = p.main_status()
            mode = p.display_mode()

            linear = (after & 0x80) == 0 and not status["gamma_enabled"]

            print("LCR4500 GAMMA=0x%02X LINEAR=%d CHANGED=%d MODE=%s"
                  % (after, int(linear), int(changed), mode))

            if not linear:
                say("\nThe de-gamma bypass did NOT take.\n"
                    f"  register  : {describe_gamma(after)}\n"
                    f"  status bit: {'enabled' if status['gamma_enabled'] else 'disabled'}\n"
                    "Close the TI LightCrafter GUI if it is open -- it can push the\n"
                    "setting back -- then try again.", error=True)
                return 1

            if mode != "video":
                say(f"\nNote: display mode is '{mode}', not video. The de-gamma\n"
                    "setting only affects the video pipeline.", error=True)

            say("\n" + describe_gamma(after))
            say("Projector verified linear." +
                ("  (bypass applied just now)" if changed else "  (already set)"))
            return 0

    except DeviceNotFound as exc:
        print("LCR4500 GAMMA=?? LINEAR=0 CHANGED=0 MODE=?")
        say(str(exc), error=True)
        return 2
    except (IOError, OSError) as exc:
        print("LCR4500 GAMMA=?? LINEAR=0 CHANGED=0 MODE=?")
        say(f"Communication failure: {exc}", error=True)
        return 2


if __name__ == "__main__":
    sys.exit(main())
