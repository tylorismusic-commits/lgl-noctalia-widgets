<div align="center">

# LGL Gamepad Display

**Live controller artwork, inputs, and battery for Noctalia desktop.**

[![Version](https://img.shields.io/badge/version-1.2.0-purple)](dualsense/plugin.toml)
[![Plugin API](https://img.shields.io/badge/Noctalia_API-17-blue)](dualsense/plugin.toml)
[![License](https://img.shields.io/badge/license-MIT-yellow)](LICENSE)

</div>

---

## Overview

LGL Gamepad Display is a Noctalia v5 desktop widget and two headless services
for PlayStation and 8BitDo controllers. It shows the pad you are using, draws
model-specific artwork, and mirrors buttons, sticks, triggers and the D-pad live
as you play.

The input reader uses the kernel evdev nodes (`/dev/input/event*`) only. It
never opens hidraw, so it runs alongside `ds4u`, Steam Input, and the plugin's
own battery service without fighting over HID reports.

| Field | Value |
| --- | --- |
| Plugin ID | `deadYokai/dualsense` |
| Display name | `Gamepad Display` |
| Version | `1.2.0` |
| Entries | Services `battery` + `listener`, desktop widget `inputs` |
| Plugin API | 17 |
| License | MIT |

Tested live on KineticWE's `noctalia-kwe` v5.3.0. Upstream Noctalia uses the
same v5 plugin API and is supported by the install scripts.

## Supported controllers

| Controller | Connection | Notes |
| --- | --- | --- |
| DualSense (`054c:0ce6`) | USB, Bluetooth | PlayStation glyphs, DualSense artwork |
| DualSense Edge (`054c:0df2`) | USB, Bluetooth | PlayStation glyphs, DualSense artwork |
| DualShock 4 (`054c:05c4`, `054c:09cc`) | USB | Use USB; Bluetooth discovery is unreliable |
| 8BitDo Ultimate 2C (`2dc8:301b`, `2dc8:310a`) | Bluetooth, 2.4 GHz receiver | Xbox letters, automatic face-button remap over Bluetooth |
| Generic XInput-style pad | USB, Bluetooth | Xbox letters, capability-driven axes |

The last controller you touch is the one displayed. Plugging a pad in also takes
over. Virtual pads and Sony motion/touchpad nodes are filtered out.

## Features

- **Live input display** — face buttons, shoulders, analog triggers, both
  sticks with `L3`/`R3`, D-pad, `Create`, `Options`, `PS`, touchpad click and
  mute. Refreshes up to 50 Hz while input changes.
- **Model-specific artwork** — DualSense, DualShock 4 and Xbox-style drawings
  generated from SVG templates and tinted from your settings.
- **Battery in the header** — percentage plus charging and connection glyphs,
  read from kernel `power_supply` or BlueZ `Battery1`.
- **Capability-driven mapping** — correct axes on the 8BitDo's non-standard
  `ABS_Z`/`ABS_RZ`/`ABS_GAS`/`ABS_BRAKE` layout.
- **8BitDo Bluetooth fix** — Switch-ordered face buttons remapped automatically.
- **Optional low-battery notifications** from the separate battery service.
- **Centered header** with controller art, model name and battery above the
  inputs; the widget appears as **Gamepad Display** in the picker.
- **Coexists with `ds4u`** — the battery service can use its IPC while the input
  reader stays on evdev.

## Install

From this directory (`apps/lgl-dualsense`):

```bash
# KineticWE's noctalia-kwe fork
./install-kwe.sh

# Upstream Noctalia
./install.sh
```

Then enable **Gamepad Display** in **Settings → Plugins** if the installer did
not, and add the widget from **Settings → Desktop → Toggle Editor**.

For KWE, you can also enable the plugin from a terminal:

```bash
noctalia-kwe msg plugins enable deadYokai/dualsense
noctalia-kwe msg plugins list | grep deadYokai/dualsense
```

The service must say `enabled` before the widget can receive input state.

### Permissions

The live display needs read access to `/dev/input/event*` — normally granted to
the active seat through `uaccess`. If no controller is detected, test with
`sudo evtest /dev/input/eventN`, or add your user to the `input` group:

```bash
sudo usermod -aG input "$USER"
```

The optional DualSense hidraw udev rule is only needed for the battery
service's direct HID reads. It is documented in the
[technical reference](dualsense/README.md#optional-dualsense-hidraw-rule-battery-service).

`install-kwe.sh` links the plugin into
`~/.local/share/noctalia-kwe/plugins`; `install.sh` uses
`~/.local/share/noctalia/plugins`. Both honour `NOCTALIA_DATA_HOME` and
`XDG_DATA_HOME`.

## Configuration

The desktop widget exposes:

- accent colour for sticks, triggers and pressed highlights
- primary and muted text colours
- battery visibility in the header
- controller line colour, body colour, body opacity and outline thickness
- plugin-level low-battery threshold and notification toggle

Colour settings accept hex values or Noctalia palette roles. A box of roughly
**240 × 152** logical pixels shows the full card at 100% scale; the widget
scales down to fit smaller boxes.

See the [full settings table](dualsense/README.md#settings).

## Project Layout

| Path | What it is |
| --- | --- |
| `dualsense/` | The plugin: `plugin.toml`, services, input widget, daemons, art, translations |
| `install-kwe.sh` | Install for KineticWE's `noctalia-kwe` fork |
| `install.sh` | Install for upstream Noctalia |
| `uninstall-kwe.sh` | Remove from `noctalia-kwe` |
| `uninstall.sh` | Remove from upstream Noctalia |
| `remove-plugin-widgets.py` | Safely removes this plugin's desktop-widget instances from `settings.toml` |
| `catalog.toml` | Noctalia source catalog (the repo can be added as a plugin source) |

## Uninstall

```bash
./uninstall-kwe.sh   # KWE
./uninstall.sh       # upstream
```

The uninstall scripts disable the plugin, stop both daemons, remove its
desktop-widget instances (with a timestamped settings backup), and clean its
runtime and plugin data. Use `--yes` for non-interactive removal.

## Requirements

- Noctalia Shell with plugin API 17 or newer (upstream or `noctalia-kwe`)
- Python 3 (standard library only)
- Read access to Linux evdev input nodes
- Optional: `ds4u` for Sony battery IPC and profile features

Full protocol notes, diagnostics, supported IDs and troubleshooting are in
[`dualsense/README.md`](dualsense/README.md).

## Credits and License

Controller protocol and `ds4u` integration informed by deadYokai's
[ds4u](https://git.yokai.digital/deadYokai/ds4u). The desktop-card approach was
inspired by Jahrek's
[Steam Controller Plasma widget](https://github.com/jahrekza/steam-controller-plasma-widget).
LGL adapted and integrated these ideas for Noctalia and Noctalia KWE.

MIT — see [LICENSE](LICENSE).
