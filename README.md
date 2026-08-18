# ThinkPad T480 fingerprint support for Omarchy

[![Checks](https://github.com/assada/omarchy-t480-fingerprint/actions/workflows/checks.yml/badge.svg)](https://github.com/assada/omarchy-t480-fingerprint/actions/workflows/checks.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

This project adds Omarchy fingerprint authentication for the Synaptics `06cb:009a` reader in the ThinkPad T480.

The integration uses the normal Omarchy menu, PAM configuration, lock screen, and package commands.

## Compatibility

This project supports the USB device `06cb:009a` only. If this device is not present, installation stops.

Run this command to identify the reader:

```bash
lsusb -d 06cb:009a
```

The command must show a Synaptics fingerprint reader.

## Install

Run this command from an Omarchy terminal:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/assada/omarchy-t480-fingerprint/v1.1.1/install.sh)
```

The installer asks for the `sudo` password. Then it asks you to enroll and verify your right index finger.

After installation, use this menu path:

```text
Setup > Security > Fingerprint
```

## What this fixes

The Omarchy hardware test detects the reader. Stock `libfprint` does not expose `06cb:009a` as an available device.

As a result, the normal Omarchy fingerprint setup stops before enrollment. This project installs the following community backend:

- [`fprintd-clients-git`](https://gitlab.freedesktop.org/uunicorn/fprintd)
- [`open-fprintd`](https://github.com/uunicorn/open-fprintd)
- [`python-validity`](https://github.com/uunicorn/python-validity)

The setup enables the `python-validity` service. It also installs a sleep recovery hook.

The package resume service can start before the USB reader is ready. This race can leave the reader in an invalid state.

The recovery hook stops the fingerprint services before sleep. After resume, it waits for the reader and starts each service in order.

The lock screen can keep an old PAM session across sleep. This session does not connect to the new fingerprint backend.

The hook resets this PAM session after the reader is ready. Omarchy then starts a new fingerprint scan when systemd unfreezes the user session.

Some readers remain busy after an interrupted first calibration. The setup resets only the matching `06cb:009a` USB device in this case.

If the reader still does not start, the setup offers a one-time repair. This repair extracts the Lenovo firmware and pairs the reader.

CAUTION: The one-time repair erases the internal fingerprint database. It does not change the laptop firmware or disk data.

## Authentication changes

The setup enrolls and verifies a finger before it changes PAM. A failed enrollment leaves the PAM configuration unchanged.

After a successful verification, the setup adds fingerprint authentication to:

- `sudo`
- polkit
- the Omarchy lock screen

The password remains available as a fallback. When the laptop lid is closed, Omarchy uses the password.

The setup stores each PAM backup in this directory:

```text
/var/lib/omarchy-fingerprint-t480/
```

The project does not change files in `/usr/share/omarchy`. It installs local commands in `~/.local/bin`.

## Status

Run this command without `sudo`:

```bash
~/.local/bin/omarchy-setup-security-fingerprint-t480 --check
```

The expected result contains these values:

```text
Backend device:     available
Enrolled finger:    yes
Omarchy PAM:        configured
Resume recovery:    installed
```

## Remove fingerprint authentication

Use this menu path:

```text
Remove > Security > Fingerprint
```

This action removes the community packages and the PAM entries. It keeps the PAM backups and internal fingerprint records.

## Remove this integration

Run this command to remove the packages, PAM entries, local commands, and menu entries:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/assada/omarchy-t480-fingerprint/v1.1.1/uninstall.sh)
```

Run this command to keep fingerprint authentication:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/assada/omarchy-t480-fingerprint/v1.1.1/uninstall.sh) --keep-auth
```

## Files

The installation adds these local files:

```text
~/.local/bin/omarchy-setup-security-fingerprint-t480
~/.local/bin/omarchy-remove-security-fingerprint-t480
~/.local/lib/omarchy-t480-fingerprint/menu.py
~/.local/lib/omarchy-t480-fingerprint/omarchy-t480-fingerprint-sleep
```

It also updates this user configuration file:

```text
~/.config/omarchy/extensions/omarchy-menu.jsonc
```

The menu update keeps other menu entries. It creates a backup before each change.

The setup installs this system-sleep hook:

```text
/usr/lib/systemd/system-sleep/omarchy-t480-fingerprint-sleep
```

## License

[MIT](LICENSE)
