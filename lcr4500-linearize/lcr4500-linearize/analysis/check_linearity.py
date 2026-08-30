#!/usr/bin/env python3
"""
check_linearity.py -- how linear is the ramp, really.

    python check_linearity.py after.csv
    python check_linearity.py before.csv after.csv     compare two runs
    python check_linearity.py after.csv --plot         PNG, needs matplotlib

Reports, per file:
  * best-fit line through (code, reading) after subtracting the level-0
    black offset, with R^2
  * worst deviation from that line, in % of full scale -- the number that
    actually matters for a calibration
  * a fitted power-law exponent. Near 1.0 means linear. Near 2.2 means
    the degamma table is still in circuit.

Standard library only unless you pass --plot.
"""

import argparse
import csv
import math
import sys
from collections import defaultdict


def load(path):
    by_level = defaultdict(list)
    with open(path, newline="") as fh:
        for row in csv.DictReader(fh):
            by_level[int(row["level"])].append(float(row["reading"]))
    return sorted((lvl, sum(v) / len(v)) for lvl, v in by_level.items())


def linear_fit(xs, ys):
    n = len(xs)
    mx = sum(xs) / n
    my = sum(ys) / n
    sxx = sum((x - mx) ** 2 for x in xs)
    sxy = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    slope = sxy / sxx if sxx else float("nan")
    intercept = my - slope * mx
    ss_tot = sum((y - my) ** 2 for y in ys)
    ss_res = sum((y - (slope * x + intercept)) ** 2 for x, y in zip(xs, ys))
    r2 = 1 - ss_res / ss_tot if ss_tot else float("nan")
    return slope, intercept, r2


def power_fit(xs, ys):
    """log-log fit of normalised code vs normalised (black-subtracted) output."""
    black = ys[0] if xs[0] == 0 else 0.0
    top = ys[-1] - black
    pts = []
    for x, y in zip(xs, ys):
        if x <= 0 or top <= 0:
            continue
        nx = x / xs[-1]
        ny = (y - black) / top
        if ny > 0:
            pts.append((math.log(nx), math.log(ny)))
    if len(pts) < 3:
        return float("nan")
    lx = [p[0] for p in pts]
    ly = [p[1] for p in pts]
    slope, _, _ = linear_fit(lx, ly)
    return slope


def report(path, data):
    xs = [d[0] for d in data]
    ys = [d[1] for d in data]
    black = ys[0] if xs[0] == 0 else 0.0
    ys_c = [y - black for y in ys]
    full = ys_c[-1] if ys_c[-1] else 1.0

    slope, intercept, r2 = linear_fit(xs, ys_c)
    resid = [(y - (slope * x + intercept)) for x, y in zip(xs, ys_c)]
    worst = max(resid, key=abs)
    worst_level = xs[resid.index(worst)]
    gamma = power_fit(xs, ys)

    print(f"\n{path}")
    print("=" * len(path))
    print(f"  points               {len(xs)}")
    print(f"  black offset (L=0)   {black:.6g}")
    print(f"  full scale (L=255)   {ys[-1]:.6g}")
    print(f"  slope                {slope:.6g} per code")
    print(f"  intercept            {intercept:.6g}")
    print(f"  R^2                  {r2:.6f}")
    print(f"  worst deviation      {worst / full * 100:+.2f} % of full scale "
          f"(at level {worst_level})")
    print(f"  fitted exponent      {gamma:.3f}")

    if gamma == gamma:  # not nan
        if abs(gamma - 1.0) < 0.05:
            verdict = "LINEAR -- degamma is bypassed"
        elif gamma > 1.6:
            verdict = ("NOT linear -- exponent near 2.2 means the degamma table "
                       "is still applied, or something upstream is re-encoding")
        else:
            verdict = "partially linear -- check the display chain upstream"
        print(f"  verdict              {verdict}")

    print("\n  level   reading      residual (% FS)")
    for x, y, r in zip(xs, ys, resid):
        print(f"  {x:5d}   {y:11.6g}  {r / full * 100:+8.2f}")
    return xs, ys, slope, intercept, black


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="+")
    ap.add_argument("--plot", action="store_true", help="write linearity.png")
    args = ap.parse_args()

    results = []
    for path in args.files:
        try:
            data = load(path)
        except OSError as exc:
            print(f"cannot read {path}: {exc}", file=sys.stderr)
            return 1
        if len(data) < 3:
            print(f"{path}: need at least 3 levels", file=sys.stderr)
            return 1
        results.append((path, report(path, data)))

    if args.plot:
        try:
            import matplotlib
            matplotlib.use("Agg")
            import matplotlib.pyplot as plt
        except ImportError:
            print("\nmatplotlib not installed -- skipping the plot "
                  "(pip install matplotlib)", file=sys.stderr)
            return 0

        fig, ax = plt.subplots(figsize=(7, 5))
        for path, (xs, ys, slope, intercept, black) in results:
            ax.plot(xs, ys, "o-", label=path)
            ax.plot(xs, [slope * x + intercept + black for x in xs], "--",
                    linewidth=1, alpha=0.6)
        ax.set_xlabel("code value")
        ax.set_ylabel("measured output")
        ax.set_title("LightCrafter 4500 transfer function")
        ax.grid(alpha=0.3)
        ax.legend(fontsize=8)
        fig.tight_layout()
        fig.savefig("linearity.png", dpi=150)
        print("\nwrote linearity.png")

    return 0


if __name__ == "__main__":
    sys.exit(main())
