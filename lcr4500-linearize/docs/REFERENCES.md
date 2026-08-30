# Reference material — every URL used to build this package

Run `GET-DOCS.bat` (in this folder) to download items marked **[auto]**
straight into `docs\`. Items marked **[browser]** sit behind a TI landing
page or a login and have to be fetched by hand.

---

## Primary specifications

### DLPC350 Programmer's Guide — DLPU010 **[auto]**
<https://www.ti.com/lit/ug/dlpu010f/dlpu010f.pdf>

**The one that matters.** Every register and command used by this package
comes from here: the Gamma Correction command (`CMD2 0x1A` / `CMD3 0x0E`),
the Main Status bit definitions, the USB HID packet layout, the firmware
version read, display-mode and input-source selection. If you read one
document, read this one. Sections worth bookmarking:

* §2 command tables — the "Reset" column is the power-on default
* §2.3.4.3 Input Pixel Data Format
* Appendix A.3 programming-mode commands — **the dangerous ones**

### DLP LightCrafter 4500 EVM User's Guide — DLPU011 **[auto]**
<https://www.ti.com/lit/ug/dlpu011f/dlpu011f.pdf>

Board-level: connectors, DIP switches, power, the GUI walkthrough, and the
description of what video mode's image pipeline applies (scaling, gamma
correction, colour coordinate adjustment). Confirms the GUI exposes no
gamma control — which is why this package exists.

### DLP4500 DMD datasheet — DLPS151B **[auto]**
<https://www.ti.com/lit/ds/symlink/dlp4500.pdf>

Micromirror array spec: 912×1140 array, 7.6 µm diagonal micromirror pitch, optical and thermal
limits. Relevant if you care about the fill factor and diffraction
behaviour of what you're measuring.

### DLPC350 controller datasheet — DLPS029F **[auto]**
<https://www.ti.com/lit/ds/symlink/dlpc350.pdf>

The controller silicon itself — bit-depth handling, video timing support,
and the pipeline block diagram that shows where de-gamma sits.

### DLP LightCrafter 4500 Flash Programming Guide — DLPU017B **[auto]**
<https://www.ti.com/lit/ug/dlpu017a/dlpu017a.pdf>

**Reference only — you do not need this.** Included so you know what the
risky path looks like and can recognise it if someone suggests it. This is
the procedure that can brick the unit. Note that reflashing resets the
gamma register to its default, so a bypass has to be re-applied afterward.

---

## TI software

### DLPLCR4500EVM-GUI — official control software **[browser]**
<https://www.ti.com/tool/DLPLCR4500EVM>

Optional but useful as a cross-check: system status, video ↔ pattern mode
switching, pattern sequences, LED currents, firmware upload. Needs .NET
Framework 4.x (already on Windows 11).

* It does **not** expose the gamma register.
* It holds the USB HID handle while open — **close it** before running
  `2-degamma-OFF.bat`, and close these scripts before using it.
* Match the GUI version to the firmware revision that
  `1-check-connection.bat` reports. Mismatches are the usual cause of
  "Control Software cannot detect the projector over USB".

### DLPR350 firmware images **[browser]**
Linked from the same tool page. Only needed for reflashing. See the warning
under DLPU017 above.

### DLP-ALC-LightCrafter-SDK-WIN — **not for this device**
<https://www.ti.com/tool/DLP-ALC-LIGHTCRAFTER-SDK-WIN>

This is the DLPC900 SDK (LightCrafter 6500 / 9000). Wrong controller, and it
requires export approval. Listed here only so it can be ruled out.

---

## Source code and community tools

### Stage-VSS/matlab-lcr — `dlpc350_api.cpp`
<https://github.com/Stage-VSS/matlab-lcr/blob/master/api/dlpc350_api.cpp>

TI's C API as used from MATLAB. This is where the packet byte order was
confirmed: the command is packed as `(CMD2 << 8) | CMD3` into a
little-endian `uint16`, so **CMD3 goes on the wire before CMD2**. If you
ever doubt `lcr4500.py`, diff it against this.

### jakobwilm/slstudio — `LC4500API`
<https://github.com/jakobwilm/slstudio/tree/master/src/projector/LC4500API>

Another working C++ mirror of the same API, in a structured-light codebase.
Useful as a second opinion on command sequencing.

### SivyerLab/pyCrafter4500
<https://github.com/SivyerLab/pyCrafter4500> · <https://pypi.org/project/pycrafter4500/>

Python controller for the LCr4500, including a `set_gamma_correction()`.
It is **pyusb/libusb** based, so on Windows it needs a WinUSB filter driver
(Zadig) — which will break the TI GUI. This package deliberately uses
hidapi instead, which rides on the built-in Windows HID driver and needs no
driver install at all. Worth reading for its pattern-sequence handling if
you ever move to pattern mode.

### WallaceIT/dlpc350
<https://github.com/WallaceIT/dlpc350/blob/master/dlpc350.py>

A compact single-file Python implementation. Good cross-reference.

### hidapi (the library this package depends on)
<https://pypi.org/project/hidapi/> · <https://github.com/libusb/hidapi>

Prebuilt Windows wheels with hidapi statically linked. Userspace only.

---

## Background threads

* [Is gamma correction recommended for the LightCrafter 4500?](https://e2e.ti.com/support/dlp-products-group/dlp/f/dlp-products-forum/388894/is-gamma-correction-recommended-for-dlp-light-crafter-4500)
* [DLPC350: disabling gamma correction in firmware](https://e2e.ti.com/support/dlp-products-group/dlp/f/dlp-products-forum/812134/dlpc350-desabling-gamma-correction-in-firmware)
* [Control Software 2.0.0 cannot detect the projector through USB](https://e2e.ti.com/support/dlp-products-group/dlp/f/dlp-products-forum/419306/dlp-lightcrafter-4500-control-software-2-0-0-cannot-detect-the-projector-through-usb)
* [DLP LightCrafter 4500 Development Platform forum](https://e2e.ti.com/support/dlp-products-group/dlp/f/dlp-products-forum)

TI's E2E servers are slow and time out often. If a link hangs, try again
later rather than assuming it's dead.

---

## Verified

Every URL above was checked while this package was assembled — all five PDF
links resolve and serve the current revision (the DLPU017 link serves rev B
despite the `dlpu017a` path). TI occasionally bumps a revision letter and
retires the old path; if `GET-DOCS.bat` reports a 404 on one file, search the
literature number on ti.com and the current revision will come up.
