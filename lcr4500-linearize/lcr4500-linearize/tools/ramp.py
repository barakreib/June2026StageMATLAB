#!/usr/bin/env python3
"""
ramp.py -- full-screen uniform patch generator for linearity measurement.

Standard library only (tkinter). Draws an exact RGB value with no CSS or
browser colour management in the way, which is why this is preferred over
the HTML fallback.

    python ramp.py                              default 1280x800 at +1920+0
    python ramp.py --geometry 1280x800+1920+0   place on the projector
    python ramp.py --fullscreen                 fullscreen on current monitor

Keys
    Up / Down          +/- 1
    PgUp / PgDn        +/- 16
    Right / Left       next / previous step in the measurement sequence
    Home / End         0 / 255
    digits then Enter  jump to a level
    c                  cycle channel: white -> red -> green -> blue
    h                  hide / show the on-screen readout
    Esc                quit

Every change is echoed to the console, so you can hide the readout and
still know where you are.
"""

import argparse
import sys

try:
    import tkinter as tk
except ImportError:  # pragma: no cover
    raise SystemExit(
        "tkinter is not available in this Python install.\n"
        "Reinstall Python from python.org with the 'tcl/tk and IDLE' option\n"
        "ticked, or use the browser fallback: tools\\ramp.html"
    )

SEQUENCE = list(range(0, 256, 16)) + [255]
CHANNELS = ("white", "red", "green", "blue")


class Ramp:
    def __init__(self, root, args):
        self.root = root
        self.level = args.level
        self.channel = 0
        self.hud_visible = True
        self.seq_index = 0

        root.title("LCr4500 ramp")
        root.configure(bg="black")
        root.config(cursor="none")

        if args.fullscreen:
            root.attributes("-fullscreen", True)
        else:
            root.overrideredirect(True)
            root.geometry(args.geometry)
        root.attributes("-topmost", True)

        self.canvas = tk.Canvas(root, highlightthickness=0, bd=0, bg="black")
        self.canvas.pack(fill="both", expand=True)

        self.hud = tk.Label(root, text="", font=("Consolas", 14),
                            fg="#00ff00", bg="black", justify="left")
        self.hud.place(x=8, y=8)

        for key, fn in (
            ("<Up>", lambda e: self.step(1)),
            ("<Down>", lambda e: self.step(-1)),
            ("<Prior>", lambda e: self.step(16)),
            ("<Next>", lambda e: self.step(-16)),
            ("<Right>", lambda e: self.seq_step(1)),
            ("<Left>", lambda e: self.seq_step(-1)),
            ("<Home>", lambda e: self.set_level(0)),
            ("<End>", lambda e: self.set_level(255)),
            ("<Escape>", lambda e: root.destroy()),
            ("<Key-c>", lambda e: self.cycle_channel()),
            ("<Key-h>", lambda e: self.toggle_hud()),
            ("<Return>", lambda e: self.commit_typed()),
        ):
            root.bind(key, fn)
        root.bind("<Key>", self.on_key)

        self.typed = ""
        self.redraw()

    # -- input -------------------------------------------------------
    def on_key(self, event):
        if event.char.isdigit():
            self.typed = (self.typed + event.char)[-3:]
            self.redraw()

    def commit_typed(self):
        if self.typed:
            self.set_level(int(self.typed))
            self.typed = ""

    def step(self, delta):
        self.set_level(self.level + delta)

    def seq_step(self, direction):
        self.seq_index = max(0, min(len(SEQUENCE) - 1, self.seq_index + direction))
        self.set_level(SEQUENCE[self.seq_index])

    def set_level(self, value):
        self.level = max(0, min(255, int(value)))
        if self.level in SEQUENCE:
            self.seq_index = SEQUENCE.index(self.level)
        self.redraw()
        print(f"level {self.level:3d}  channel {CHANNELS[self.channel]}", flush=True)

    def cycle_channel(self):
        self.channel = (self.channel + 1) % len(CHANNELS)
        self.redraw()
        print(f"level {self.level:3d}  channel {CHANNELS[self.channel]}", flush=True)

    def toggle_hud(self):
        self.hud_visible = not self.hud_visible
        self.redraw()

    # -- render ------------------------------------------------------
    def rgb(self):
        v = self.level
        name = CHANNELS[self.channel]
        r, g, b = (v, v, v)
        if name == "red":
            g = b = 0
        elif name == "green":
            r = b = 0
        elif name == "blue":
            r = g = 0
        return r, g, b

    def redraw(self):
        r, g, b = self.rgb()
        colour = f"#{r:02x}{g:02x}{b:02x}"
        self.canvas.configure(bg=colour)
        if self.hud_visible:
            pending = f"  typing:{self.typed}" if self.typed else ""
            self.hud.configure(
                text=f"level {self.level:3d}   rgb({r},{g},{b})   "
                     f"{CHANNELS[self.channel]}   step "
                     f"{self.seq_index + 1}/{len(SEQUENCE)}{pending}\n"
                     f"[h] hide  [Esc] quit")
            self.hud.lift()
        else:
            self.hud.configure(text="")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--geometry", default="1280x800+1920+0",
                    help="WxH+X+Y placement (default: %(default)s)")
    ap.add_argument("--fullscreen", action="store_true",
                    help="fullscreen on the current monitor instead")
    ap.add_argument("--level", type=int, default=0, help="starting level")
    args = ap.parse_args()

    root = tk.Tk()
    Ramp(root, args)
    print("Ramp window open. Arrow keys change level; Esc quits.", flush=True)
    root.mainloop()
    return 0


if __name__ == "__main__":
    sys.exit(main())
