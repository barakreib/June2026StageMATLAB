#!/usr/bin/env python3
"""
watch_linear.py -- keep the projector linear for a whole session.

    python watch_linear.py                 poll every 10 s
    python watch_linear.py --interval 5
    python watch_linear.py --log watch.txt

Polls the gamma register and re-applies the bypass whenever it finds the
register back at 0x80 -- which is what happens if the projector is power
cycled, or if the TI GUI pushes its settings. Leave it running in its own
window for the duration of a measurement session. Ctrl-C to stop.

The device is opened and closed around each poll rather than held open, so
you can still use other tools between polls.
"""

import argparse
import datetime
import sys
import time

from lcr4500 import LCr4500, DeviceNotFound


def stamp():
    return datetime.datetime.now().strftime("%H:%M:%S")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--interval", type=float, default=10.0,
                    help="seconds between polls (default 10)")
    ap.add_argument("--log", help="also append events to this file")
    args = ap.parse_args()

    logfile = open(args.log, "a", buffering=1) if args.log else None

    def emit(msg):
        line = f"[{stamp()}] {msg}"
        print(line, flush=True)
        if logfile:
            logfile.write(line + "\n")

    emit(f"watching, every {args.interval:g}s -- Ctrl-C to stop")
    reapplied = 0
    last_state = None

    try:
        while True:
            try:
                with LCr4500() as p:
                    value = p.get_gamma()
                    if value & 0x80:
                        p.set_gamma(False)
                        confirm = p.get_gamma()
                        if confirm & 0x80:
                            emit("REVERTED to 0x80 and the re-apply FAILED "
                                 "-- is the TI GUI open?")
                        else:
                            reapplied += 1
                            emit(f"REVERTED to 0x80 -- bypass re-applied "
                                 f"(#{reapplied}). Any data taken since the "
                                 f"last OK line is suspect.")
                        last_state = "reverted"
                    else:
                        if last_state != "ok":
                            emit("OK, linear (0x00)")
                        last_state = "ok"
            except DeviceNotFound:
                if last_state != "gone":
                    emit("projector unreachable -- powered off, unplugged, "
                         "or the GUI has the handle")
                last_state = "gone"
            except (IOError, OSError) as exc:
                if last_state != "err":
                    emit(f"communication error: {exc}")
                last_state = "err"

            time.sleep(args.interval)

    except KeyboardInterrupt:
        emit(f"stopped. re-applied {reapplied} time(s) this session.")
        return 0
    finally:
        if logfile:
            logfile.close()


if __name__ == "__main__":
    sys.exit(main())
