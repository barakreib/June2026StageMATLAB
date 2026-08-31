"""lcr_agent tests.

Grammar tests are pure. The end-to-end test starts the real agent on
localhost with a stub `hid` module on PYTHONPATH, so the whole chain
(socket -> whitelist -> ensure_linear.py subprocess -> EXIT line) runs
with no hardware and no hidapi installed.
"""

import os
import socket
import subprocess
import sys
import time
from pathlib import Path

import pytest

from lcr_agent import BadRequest, build_argv

TOOLKIT = Path(__file__).resolve().parent.parent


# ---- grammar --------------------------------------------------------------

def test_ping_is_no_subprocess():
    assert build_argv("ping") is None


def test_plain_commands():
    assert build_argv("list") == ["--list"]
    assert build_argv("query") == ["--query"]
    assert build_argv("require") == ["--require"]
    assert build_argv("ensure") == []


def test_device_selector_passthrough():
    assert build_argv("query --device 7&2b9a1c") == ["--query", "--device", "7&2b9a1c"]
    assert build_argv("ensure --device 0") == ["--device", "0"]


@pytest.mark.parametrize("bad", [
    "", "  ", "reboot", "query --device", "query extra words here",
    "ensure --quiet", "ping now", "list --device x",
    "query --device " + "x" * 300,
])
def test_bad_requests_refused(bad):
    with pytest.raises(BadRequest):
        build_argv(bad)


def test_newline_smuggling_refused():
    with pytest.raises(BadRequest):
        build_argv("query --device a\rb")


# ---- end to end -----------------------------------------------------------

def _free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def _ask(port, request, timeout=30):
    with socket.create_connection(("127.0.0.1", port), timeout=timeout) as c:
        c.sendall(request.encode() + b"\n")
        c.settimeout(timeout)
        buf = b""
        while b"EXIT=" not in buf:
            chunk = c.recv(4096)
            if not chunk:
                break
            buf += chunk
    return buf.decode()


@pytest.fixture()
def agent(tmp_path):
    # Stub hid: enumerates nothing, opens nothing -> DeviceNotFound -> exit 2.
    (tmp_path / "hid.py").write_text(
        "def enumerate(*a, **k):\n    return []\n"
        "class device:\n"
        "    def open(self, *a): raise OSError('no device (stub)')\n"
        "    def open_path(self, *a): raise OSError('no device (stub)')\n"
        "    def set_nonblocking(self, *a): pass\n"
        "    def close(self): pass\n")
    env = dict(os.environ)
    env["PYTHONPATH"] = str(tmp_path)
    port = _free_port()
    proc = subprocess.Popen(
        [sys.executable, str(TOOLKIT / "lcr_agent.py"),
         "--host", "127.0.0.1", "--port", str(port)],
        env=env, cwd=str(TOOLKIT),
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    deadline = time.time() + 15
    while time.time() < deadline:      # wait for the socket to come up
        try:
            socket.create_connection(("127.0.0.1", port), timeout=1).close()
            break
        except OSError:
            time.sleep(0.1)
    else:
        proc.kill()
        pytest.fail("agent never started listening")
    yield port
    proc.terminate()
    proc.wait(timeout=10)


def test_ping(agent):
    out = _ask(agent, "ping")
    assert "PONG" in out and "EXIT=0" in out


def test_query_no_device_is_unreachable(agent):
    out = _ask(agent, "query")
    assert "LCR4500 GAMMA=??" in out
    assert out.rstrip().endswith("EXIT=2")


def test_bad_request_exit_3(agent):
    out = _ask(agent, "reboot")
    assert out.rstrip().endswith("EXIT=3")


def test_list_reports_zero_devices(agent):
    out = _ask(agent, "list")
    assert "LCR4500 DEVICES=0" in out
    assert out.rstrip().endswith("EXIT=2")
