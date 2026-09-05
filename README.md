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
bash <(curl -fsSL https://raw.githubusercontent.com/assada/omarchy-t480-fingerprint/v1.2.0/install.sh)
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

The setup enables the `python-validity` service. It also installs the resume recovery described below.

Some readers remain busy after an interrupted first calibration. The setup resets only the matching `06cb:009a` USB device in this case.

If the reader still does not start, the setup offers a one-time repair. This repair extracts the Lenovo firmware and pairs the reader.

CAUTION: The one-time repair erases the internal fingerprint database. It does not change the laptop firmware or disk data.

## Sleep and resume

`python-validity` keeps a TLS session with the sensor. A suspend resets the USB device under that session, so the next verify fails inside `libusb`.

The driver reports that failure as a finger that does not match, and then it exits. The lock screen shows an unrecognized finger for a reader that is no longer there. This is the reason the reader worked after some resumes and not after others.

`open-fprintd` publishes the repair call for this case. `Manager.Resume()` makes `python-validity` reset the session and re-open the sensor in place. A live PAM session keeps working, because no service restarts.

After each resume, `omarchy-t480-fingerprint-resume.service` runs these steps:

1. It waits for the `06cb:009a` device to return to the USB bus.
2. It calls `Manager.Resume()`.
3. It restarts `open-fprintd` and `python3-validity` only when the driver is gone or the sensor did not re-open.

The unit is ordered after the sleep targets, so each wait happens once the resume is complete. A script in `/usr/lib/systemd/system-sleep` cannot do this, because `systemd-sleep` waits for every hook before it finishes the resume.

The driver exits with status `0` when a libusb call fails, so the packaged `Restart=on-failure` never brings it back. The setup adds this drop-in, which makes systemd the recovery path:

```text
/etc/systemd/system/python3-validity.service.d/omarchy-t480-restart.conf
```

The setup also disables three competing mechanisms:

- `python3-validity-suspend-hotfix.service` restarts both services after every resume, which drops the claim of a live PAM session.
- `open-fprintd-suspend.service` and `open-fprintd-resume.service` carry no ordering against the suspend itself, so their calls can land after the resume unit already repaired the reader.

Read the recovery log with this command:

```bash
journalctl -b -u omarchy-t480-fingerprint-resume
```

### Known limit

A verify that is in flight when the machine suspends still fails once. Omarchy starts a new fingerprint scan by itself, so the next touch works. The lock screen part of this problem is not specific to this reader, and fixes for it are proposed upstream in [basecamp/omarchy#7158](https://github.com/basecamp/omarchy/pull/7158) and [basecamp/omarchy#7179](https://github.com/basecamp/omarchy/pull/7179).

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
Resume recovery:    installed
Driver restart:     configured
Backend device:     available
Enrolled finger:    yes
Omarchy PAM:        configured
```

## Remove fingerprint authentication

Use this menu path:

```text
Remove > Security > Fingerprint
```

This action removes the community packages, the PAM entries, and the resume recovery. It keeps the PAM backups and internal fingerprint records.

## Remove this integration

Run this command to remove the packages, PAM entries, local commands, and menu entries:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/assada/omarchy-t480-fingerprint/v1.2.0/uninstall.sh)
```

Run this command to keep fingerprint authentication:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/assada/omarchy-t480-fingerprint/v1.2.0/uninstall.sh) --keep-auth
```

## Files

The installation adds these local files:

```text
~/.local/bin/omarchy-setup-security-fingerprint-t480
~/.local/bin/omarchy-remove-security-fingerprint-t480
~/.local/lib/omarchy-t480-fingerprint/menu.py
~/.local/lib/omarchy-t480-fingerprint/omarchy-t480-fingerprint-resume
~/.local/lib/omarchy-t480-fingerprint/omarchy-t480-fingerprint-resume.service
~/.local/lib/omarchy-t480-fingerprint/python3-validity-restart.conf
```

It also updates this user configuration file:

```text
~/.config/omarchy/extensions/omarchy-menu.jsonc
```

The menu update keeps other menu entries. It creates a backup before each change.

The setup installs these system files:

```text
/usr/local/lib/omarchy-t480-fingerprint/omarchy-t480-fingerprint-resume
/etc/systemd/system/omarchy-t480-fingerprint-resume.service
/etc/systemd/system/python3-validity.service.d/omarchy-t480-restart.conf
```

An upgrade from a release before 1.2.0 removes the old hook at
`/usr/lib/systemd/system-sleep/omarchy-t480-fingerprint-sleep`.

## License

[MIT](LICENSE)
