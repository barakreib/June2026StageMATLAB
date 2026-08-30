#!/usr/bin/env python3
"""
log_measurements.py -- walk a level sequence and record what your
radiometer reads, into a CSV you can hand to check_linearity.py.

    python log_measurements.py before_degamma_off.csv
    python log_measurements.py after.csv --levels 0,16,32,64,128,192,255
    python log_measurements.py after.csv --repeats 3

For each level it prompts you. Set that level in ramp.py, take the
reading, type the number, press Enter. Blank input skips, "q" stops
early and still writes the file.
"""

import argparse
import csv
import datetime
import sys

DEFAULT_LEVELS = list(range(0, 256, 16)) + [255]


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("outfile")
    ap.add_argument("--levels", default=None,
                    help="comma separated code values (default 0,16,...,240,255)")
    ap.add_argument("--repeats", type=int, default=1,
                    help="readings per level (default 1)")
    ap.add_argument("--channel", default="white",
                    help="label written into the CSV (default white)")
    ap.add_argument("--units", default="cd/m^2", help="label only")
    args = ap.parse_args()

    levels = ([int(x) for x in args.levels.split(",")] if args.levels
              else DEFAULT_LEVELS)

    rows = []
    stamp = datetime.datetime.now().isoformat(timespec="seconds")

    print(f"Logging {len(levels)} levels x {args.repeats} reading(s), "
          f"channel={args.channel}, units={args.units}")
    print("Set the level in ramp.py, read the meter, type the value, Enter.")
    print("Blank = skip, q = stop early.\n")

    try:
        for level in levels:
            for rep in range(args.repeats):
                tag = f"  (rep {rep + 1}/{args.repeats})" if args.repeats > 1 else ""
                raw = input(f"level {level:3d}{tag} -> ").strip()
                if raw.lower() in ("q", "quit", "exit"):
                    raise KeyboardInterrupt
                if not raw:
                    continue
                try:
                    value = float(raw)
                except ValueError:
                    print("   not a number, skipped")
                    continue
                rows.append({"level": level, "reading": value,
                             "channel": args.channel, "units": args.units,
                             "rep": rep + 1, "timestamp": stamp})
    except KeyboardInterrupt:
        print("\nstopped early")

    if not rows:
        print("Nothing recorded, no file written.")
        return 1

    with open(args.outfile, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=["level", "reading", "channel",
                                           "units", "rep", "timestamp"])
        w.writeheader()
        w.writerows(rows)

    print(f"\nWrote {len(rows)} rows to {args.outfile}")
    print(f"Now run:  python check_linearity.py {args.outfile}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
