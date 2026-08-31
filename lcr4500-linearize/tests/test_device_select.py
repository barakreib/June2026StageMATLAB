"""Hermetic tests for lcr4500.resolve_device -- synthetic dicts only, no USB.

Run with pytest, or directly: python tests/test_device_select.py
(direct runs work because conftest's stubbing is repeated in __main__).
"""

import pytest

from lcr4500 import (AmbiguousDevice, DeviceNotFound, format_device_line,
                     resolve_device)


def dev(path, serial=""):
    return {"path": path, "serial_number": serial}


# Deliberately listed out of path order; bytes paths, as hidapi returns them.
DEVICES = [
    dev(b"\\\\?\\hid#vid_0451&pid_6401#7&2b9a1c&0&0000", serial="B123"),
    dev(b"\\\\?\\hid#vid_0451&pid_6401#7&1f00aa&0&0000", serial=""),
]


def test_index_selects_in_path_sorted_order():
    # sorted by path: 7&1f00aa first, 7&2b9a1c second
    assert resolve_device(DEVICES, "0")["path"].endswith(b"1f00aa&0&0000")
    assert resolve_device(DEVICES, "1")["serial_number"] == "B123"


def test_index_out_of_range_lists_devices():
    with pytest.raises(DeviceNotFound) as e:
        resolve_device(DEVICES, "2")
    assert "out of range" in str(e.value)
    assert "1f00aa" in str(e.value) and "2b9a1c" in str(e.value)


def test_exact_serial_match():
    assert resolve_device(DEVICES, "B123")["serial_number"] == "B123"


def test_empty_selector_rejected_never_matches_empty_serial():
    with pytest.raises(DeviceNotFound) as e:
        resolve_device(DEVICES, "  ")
    assert "Empty device selector" in str(e.value)


def test_duplicate_serials_are_ambiguous():
    dups = [dev(b"path-a", serial="SAME"), dev(b"path-b", serial="SAME")]
    with pytest.raises(AmbiguousDevice) as e:
        resolve_device(dups, "SAME")
    assert "matches 2 units" in str(e.value)


def test_path_substring_case_insensitive():
    assert resolve_device(DEVICES, "7&1F00AA")["serial_number"] == ""


def test_ambiguous_path_substring():
    with pytest.raises(AmbiguousDevice):
        resolve_device(DEVICES, "vid_0451")


def test_no_match_lists_attached():
    with pytest.raises(DeviceNotFound) as e:
        resolve_device(DEVICES, "no-such-unit")
    msg = str(e.value)
    assert "matched no attached unit" in msg
    assert "1f00aa" in msg and "2b9a1c" in msg


def test_empty_device_list():
    with pytest.raises(DeviceNotFound) as e:
        resolve_device([], "anything")
    assert "no LightCrafter HID interfaces" in str(e.value)


def test_string_paths_also_work():
    strs = [dev("/dev/hidraw3", serial=""), dev("/dev/hidraw7", serial="X9")]
    assert resolve_device(strs, "hidraw3")["path"] == "/dev/hidraw3"
    assert resolve_device(strs, "X9")["path"] == "/dev/hidraw7"


def test_format_device_line_shape():
    line = format_device_line(0, DEVICES[0])
    assert line.startswith('DEV index=0 serial="B123" path="')
    assert "2b9a1c" in line


if __name__ == "__main__":
    import sys
    import types
    from pathlib import Path
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    sys.modules.setdefault("hid", types.ModuleType("hid"))
    sys.exit(pytest.main([__file__, "-q"]))
