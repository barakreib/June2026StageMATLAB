#!/usr/bin/env python3
"""
lcr_agent.py -- tiny TCP bridge so a REMOTE machine can run the gamma
check/apply against a LightCrafter whose USB is plugged into THIS machine
(the rig case: the projector hangs off the Stage-server box, MATLAB runs
on the client).

    python lcr_agent.py                     listen on 0.0.0.0:5676
    python lcr_agent.py --port N --host H   override

Port 5676 sits directly under the rig's wake listener (5677) and the Stage
server itself (5678). This agent NEVER touches those -- it opens its own
socket only. Allow inbound TCP 5676 in Windows Firewall on the projector
machine, and start the agent at logon (see README / 13-start-agent.bat).

Protocol: one request line per connection, agent replies and closes.
Requests (anything else is refused; arguments are whitelisted, never
handed to a shell):

    ping                     -> PONG
    list                     -> the ensure_linear.py --list output
    query  [--device SEL]    -> read-only state report
    require [--device SEL]   -> verify only, never writes
    ensure [--device SEL]    -> apply the de-gamma bypass + verify

The reply is the exact stdout+stderr of ensure_linear.py (so the client
parses the same 'LCR4500 GAMMA=...' line it would locally), terminated by
one final line:

    EXIT=<n>

with ensure_linear.py's exit code (0 linear, 1 not linear, 2 unreachable,
3 bad usage). A malformed request or agent-side failure reports EXIT=3 /
EXIT=2 the same way, so the client needs exactly one code path.

Each request shells out to ensure_linear.py with THIS interpreter
(sys.executable -- run the agent with the toolkit venv so hidapi is
present). One request at a time, on purpose: the projector is a single
HID endpoint, and two concurrent opens would fight.
"""

import argparse
import socket
import subprocess
import sys
import time
from pathlib import Path

DEFAULT_PORT = 5676
REQUEST_TIMEOUT_S = 10      # reading the request line
SUBPROCESS_TIMEOUT_S = 25   # ensure_linear.py round trip

HERE = Path(__file__).resolve().parent


class BadRequest(Exception):
    pass


def build_argv(request):
    """Whitelist-parse one request line into ensure_linear.py arguments.

    Returns None for 'ping' (handled without a subprocess). Raises
    BadRequest for anything not in the tiny grammar above -- this is the
    only parser between the network and a subprocess, so it accepts
    nothing it does not recognize.
    """
    words = request.strip().split()
    if not words:
        raise BadRequest("empty request")
    cmd, rest = words[0].lower(), words[1:]

    if cmd == "ping":
        if rest:
            raise BadRequest("ping takes no arguments")
        return None
    if cmd == "list":
        if rest:
            raise BadRequest("list takes no arguments")
        return ["--list"]
    if cmd not in ("query", "require", "ensure"):
        raise BadRequest(f"unknown command '{cmd}'")

    argv = [] if cmd == "ensure" else [f"--{cmd}"]
    if rest:
        if len(rest) != 2 or rest[0] != "--device":
            raise BadRequest(f"'{cmd}' accepts only: --device SEL")
        sel = rest[1]
        if not sel or len(sel) > 256 or any(c in sel for c in "\r\n\x00"):
            raise BadRequest("bad --device selector")
        argv += ["--device", sel]
    return argv


def run_request(argv):
    """Run ensure_linear.py with argv; return (text, exit_code)."""
    script = HERE / "ensure_linear.py"
    try:
        p = subprocess.run([sys.executable, str(script)] + argv,
                           capture_output=True, text=True,
                           timeout=SUBPROCESS_TIMEOUT_S, cwd=str(HERE))
        return (p.stdout + p.stderr), p.returncode
    except subprocess.TimeoutExpired:
        return ("LCR4500 GAMMA=?? LINEAR=0 CHANGED=0 MODE=?\n"
                "agent: ensure_linear.py timed out -- is another program "
                "holding the USB handle?\n"), 2
    except OSError as exc:
        return ("LCR4500 GAMMA=?? LINEAR=0 CHANGED=0 MODE=?\n"
                f"agent: could not launch ensure_linear.py: {exc}\n"), 2


def handle(conn, addr, log):
    conn.settimeout(REQUEST_TIMEOUT_S)
    try:
        buf = b""
        while b"\n" not in buf and len(buf) < 1024:
            chunk = conn.recv(256)
            if not chunk:
                break
            buf += chunk
        request = buf.decode("utf-8", errors="replace").splitlines()[0] if buf else ""

        try:
            argv = build_argv(request)
        except BadRequest as exc:
            log(f"{addr[0]} bad request ({exc}): {request!r}")
            conn.sendall(f"agent: {exc}\nEXIT=3\n".encode())
            return

        if argv is None:                          # ping
            conn.sendall(b"PONG\nEXIT=0\n")
            return

        text, code = run_request(argv)
        log(f"{addr[0]} {request.strip()} -> exit {code}")
        conn.sendall(text.encode("utf-8", errors="replace")
                     + f"EXIT={code}\n".encode())
    except socket.timeout:
        log(f"{addr[0]} timed out mid-request")
    except OSError as exc:
        log(f"{addr[0]} socket error: {exc}")
    finally:
        try:
            conn.close()
        except OSError:
            pass


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=DEFAULT_PORT)
    ap.add_argument("--host", default="0.0.0.0")
    args = ap.parse_args()

    def log(msg):
        print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        srv.bind((args.host, args.port))
    except OSError as exc:
        print(f"cannot bind {args.host}:{args.port}: {exc}", file=sys.stderr)
        return 1
    srv.listen(1)
    log(f"lcr_agent listening on {args.host}:{args.port} -- Ctrl-C to stop")
    log(f"serving ensure_linear.py from {HERE} with {sys.executable}")

    try:
        while True:
            conn, addr = srv.accept()
            handle(conn, addr, log)               # one at a time, by design
    except KeyboardInterrupt:
        log("stopped.")
        return 0
    finally:
        srv.close()


if __name__ == "__main__":
    sys.exit(main())
