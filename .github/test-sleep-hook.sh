#!/bin/bash

set -Eeuo pipefail

readonly repository_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly test_directory=$(mktemp -d)
readonly fake_bin="$test_directory/bin"
readonly fake_sysfs="$test_directory/sysfs"
readonly fake_run="$test_directory/run"
readonly call_log="$test_directory/calls"

cleanup() {
  rm -rf -- "$test_directory"
}
trap cleanup EXIT

mkdir -p "$fake_bin" "$fake_sysfs/1-9"
printf '06cb\n' >"$fake_sysfs/1-9/idVendor"
printf '009a\n' >"$fake_sysfs/1-9/idProduct"
: >"$call_log"

cat >"$fake_bin/systemctl" <<'EOF'
#!/bin/bash
printf 'systemctl %s\n' "$*" >>"$CALL_LOG"
exit 0
EOF

cat >"$fake_bin/gdbus" <<'EOF'
#!/bin/bash
printf 'gdbus %s\n' "$*" >>"$CALL_LOG"
printf "([objectpath '/net/reactivated/Fprint/Device/0'],)\n"
EOF

for command in logger udevadm; do
  cat >"$fake_bin/$command" <<'EOF'
#!/bin/bash
printf '%s %s\n' "${0##*/}" "$*" >>"$CALL_LOG"
EOF
done
chmod 755 "$fake_bin"/*

export CALL_LOG="$call_log"
export OMARCHY_T480_FINGERPRINT_SYSFS_ROOT="$fake_sysfs"
export OMARCHY_T480_FINGERPRINT_RUN_DIR="$fake_run"
export PATH="$fake_bin:$PATH"

hook="$repository_root/systemd/omarchy-t480-fingerprint-sleep"
"$hook" pre suspend
test -f "$fake_run/resume-backend"
"$hook" post suspend
test ! -e "$fake_run/resume-backend"

python3 - "$call_log" <<'PY'
from pathlib import Path
import sys

calls = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
required = [
    "systemctl stop python3-validity.service",
    "systemctl stop open-fprintd.service",
    "systemctl start open-fprintd.service",
    "systemctl start python3-validity.service",
]
positions = [calls.index(call) for call in required]
if positions != sorted(positions):
    raise SystemExit(f"Incorrect service order: {calls}")
if not any(call.startswith("gdbus call --system") for call in calls):
    raise SystemExit(f"The readiness call is missing: {calls}")
PY
