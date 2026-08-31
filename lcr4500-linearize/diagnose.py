#!/usr/bin/env python3
"""
diagnose.py -- read-only dump of everything in the DLPC350 video path that
can affect what comes out of the projector. Sends no writes.

Run this when the image is wrong in a way the gamma setting cannot explain
-- no colour, wrong colour, nothing at all.
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
    problems = []
    try:
        with LCr4500(device=args.device) as p:
            print("LightCrafter 4500 / DLPC350 -- full video path")
            print("=" * 62)

            for name, ver in p.firmware_version().items():
                print(f"  {name:<20} {ver}")

            print("\n  -- pipeline ---------------------------------------")
            mode = p.display_mode()
            src = p.input_source()
            pix = p.pixel_format()
            csc = p.csc_input()
            print(f"  {'Display mode':<20} {mode}")
            print(f"  {'Input source':<20} {src}")
            print(f"  {'Pixel data format':<20} {pix}")
            print(f"  {'CSC input attribute':<20} {csc}")
            print(f"  {'Port clock':<20} {p.port_clock()}")

            gam = p.get_gamma()
            print(f"  {'Gamma register':<20} {describe_gamma(gam)}")

            print("\n  -- illumination -----------------------------------")
            led = p.led_enable()
            cur = p.led_currents()
            print(f"  {'LED enable raw':<20} 0x{led['raw']:02X}")
            print(f"  {'LED control':<20} "
                  f"{'sequencer (automatic) -- normal' if led['sequencer_controlled'] else 'MANUAL'}")
            if not led["sequencer_controlled"]:
                on = [c for c in ("red", "green", "blue") if led[c]]
                print(f"  {'Manually enabled':<20} {', '.join(on) if on else 'none'}")
            print(f"  {'LED currents R/G/B':<20} "
                  f"{cur['red']}, {cur['green']}, {cur['blue']}  "
                  f"(defaults 151, 120, 125)")

            st = p.main_status()
            print("\n  -- status -----------------------------------------")
            print(f"  {'Sequencer running':<20} {st['sequencer_running']}")
            print(f"  {'DMD parked':<20} {st['dmd_parked']}")
            print(f"  {'Buffer frozen':<20} {st['buffer_frozen']}")
            print(f"  {'Gamma status bit':<20} "
                  f"{'enabled' if st['gamma_enabled'] else 'disabled'}")

            # ---- interpretation -------------------------------------
            if not led["sequencer_controlled"]:
                allon = led["red"] and led["green"] and led["blue"]
                problems.append(
                    "LED control is MANUAL, not sequencer controlled.\n"
                    "     This is almost certainly your colour problem. In video mode\n"
                    "     the DMD shows the red, green and blue bit planes in sequence\n"
                    "     and the sequencer strobes the matching LED for each. Under\n"
                    "     manual control the wrong LEDs are lit during each sub-frame."
                    + ("\n     With all three LEDs held on, every sub-frame is lit white,\n"
                       "       so the projector sums R+G+B into a single grey image --\n"
                       "       a yellow stimulus comes out white. That matches your\n"
                       "       symptom exactly."
                       if allon else "")
                    + "\n     Fix:  10-leds-auto.bat  (or: python leds.py auto)")
            if mode != "video":
                problems.append(f"Display mode is '{mode}', not video.")
            if "YCrCb" in pix:
                problems.append(
                    f"Pixel data format is {pix}, not RGB 4:4:4. Colours from an\n"
                    "     RGB source will be decoded wrongly.")
            if "YCrCb" in csc:
                problems.append(
                    f"CSC input attribute is {csc}, not RGB 4:4:4.")
            if not st["sequencer_running"]:
                problems.append("Sequencer is not running.")
            if st["dmd_parked"]:
                problems.append("DMD is parked -- no image will be produced.")
            if st["buffer_frozen"]:
                problems.append("Frame buffer is frozen -- the image will not update.")
            if 0 in (cur["red"], cur["green"], cur["blue"]):
                zeros = [c for c in ("red", "green", "blue") if cur[c] == 0]
                problems.append(
                    f"LED current is zero for: {', '.join(zeros)}. That channel\n"
                    "     produces no light at all.")

            print("\n" + "=" * 62)
            if problems:
                print("FINDINGS\n")
                for i, msg in enumerate(problems, 1):
                    print(f"  {i}. {msg}\n")
            else:
                print("Nothing wrong found in the video path. Every register that\n"
                      "affects colour or illumination is at a sane value.\n\n"
                      "If the projected image is still wrong, the cause is upstream:\n"
                      "  - is another window covering the projector display?\n"
                      "    ramp.py sets itself always-on-top -- press Esc to close it\n"
                      "  - is your stimulus actually being rendered to that display?\n"
                      "  - check pure R, G and B fields with 4-ramp.bat (press 'c')")
            return 1 if problems else 0

    except DeviceNotFound as exc:
        print(exc, file=sys.stderr)
        return 2
    except (IOError, OSError) as exc:
        print(f"Communication error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
