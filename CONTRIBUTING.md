# Contributing

Use a pull request for each change. Keep each pull request limited to one problem.

Before you open a pull request, run these commands:

```bash
bash -n install.sh uninstall.sh bin/* systemd/* .github/test-sleep-hook.sh
shellcheck install.sh uninstall.sh bin/* systemd/* .github/test-sleep-hook.sh
.github/test-sleep-hook.sh
python3 -m py_compile scripts/menu.py
```

For a reader problem, include the USB ID and the output of this command:

```bash
~/.local/bin/omarchy-setup-security-fingerprint-t480 --check
```

Do not include full `python-validity` debug logs. These logs can contain private pairing data.
