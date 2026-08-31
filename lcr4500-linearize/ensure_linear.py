#!/usr/bin/env python3
"""
ensure_linear.py -- make the projector linear, prove it, and report via
exit code. Built to be called from an experiment script rather than typed.

    python ensure_linear.py                 apply the bypass if needed, verify
    python ensure_linear.py --require       verify only; never writes
    python ensure_linear.py --query         read-only state report; never writes
    python ensure_linear.py --list          list attached units, one DEV line each
    python ensure_linear.py --device SEL    pick a unit: index, exact serial, or
                                            case-insensitive HID-path substring
    python ensure_linear.py --quiet         print only on failure

Always prints one machine-readable line to stdout:

    LCR4500 GAMMA=0x00 LINEAR=1 CHANGED=0 MODE=video

(--list instead prints "LCR4500 DEVICES=N" followed by one DEV line per
unit, index-ordered the same way --device index selection is.)

Exit codes:
    0   projector is verified linear (--query: is linear; --list: >=1 unit)
    1   not linear (register would not take, --require and it was enabled,
        or --query found de-gamma active)
    2   projector unreachable, a USB communication failure, or --list
        finding no units
    3   bad usage

Verification is deliberately belt-and-braces: the gamma register is read
back AND the independent gamma bit in the DLPC350's Main Status word is
checked. Both must agree before this exits 0. A write that appears to
succeed but doesn't reach the pipeline fails here rather than silently
corrupting a day of data.
"""

import argparse
import sys

from lcr4500 import (LCr4500, DeviceNotFound, describe_gamma,
                     format_device_line, list_devices)


class _Parser(argparse.ArgumentParser):
    def error(self, message):  # usage errors exit 3, never colliding with 2
        self.print_usage(sys.stderr)
        print(f"error: {message}", file=sys.stderr)
        sys.exit(3)


def main():
    ap = _Parser(description=__doc__,
                 formatter_class=argparse.RawDescriptionHelpFormatter)
    mode_group = ap.add_mutually_exclusive_group()
    mode_group.add_argument("--require", action="store_true",
                            help="verify only, never write (assert mid-experiment)")
    mode_group.add_argument("--query", action="store_true",
                            help="read-only state report, never write")
    ap.add_argument("--device", metavar="SEL", default=None,
                    help="select one unit when several are attached: index, "
                         "exact serial, or HID-path substring")
    ap.add_argument("--list", action="store_true",
                    help="list attached units and exit (enumeration only -- "
                         "works even while another program holds the handle)")
    ap.add_argument("--quiet", action="store_true",
                    help="suppress output unless something is wrong")
    args = ap.parse_args()

    def say(msg, error=False):
        if error:
            print(msg, file=sys.stderr)
        elif not args.quiet:
            print(msg)

    if args.list:
        devices = list_devices()
        print(f"LCR4500 DEVICES={len(devices)}")
        for i, d in enumerate(devices):
            print(format_device_line(i, d))
        return 0 if devices else 2

    try:
        with LCr4500(device=args.device) as p:
            if args.query:
                g = p.get_gamma()
                status = p.main_status()
                mode = p.display_mode()
                linear = (g & 0x80) == 0 and not status["gamma_enabled"]
                print("LCR4500 GAMMA=0x%02X LINEAR=%d CHANGED=0 MODE=%s"
                      % (g, int(linear), mode))
                if ((g & 0x80) == 0) == status["gamma_enabled"]:
                    say("The gamma register and the Main Status gamma bit "
                        "DISAGREE -- treat the projector state as unknown.",
                        error=True)
                return 0 if linear else 1

            before = p.get_gamma()
            changed = False

            if before & 0x80:
                if args.require:
                    mode = p.display_mode()
                    print("LCR4500 GAMMA=0x%02X LINEAR=0 CHANGED=0 MODE=%s"
                          % (before, mode))
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
