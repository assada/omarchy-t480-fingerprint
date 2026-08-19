#!/bin/bash

# Exercise the resume script against fake systemctl, gdbus, and logger commands.

set -Eeuo pipefail

repository_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly repository_root
readonly resume_script="$repository_root/systemd/omarchy-t480-fingerprint-resume"

work_root=$(mktemp -d)
readonly work_root

cleanup() {
  rm -rf -- "$work_root"
}
trap cleanup EXIT

failures=0
scenario=""
scenario_dir=""
call_log=""
exit_status=0

pass() {
  printf 'ok - %s: %s\n' "$scenario" "$*"
}

fail() {
  printf 'not ok - %s: %s\n' "$scenario" "$*" >&2
  failures=$((failures + 1))
}

write_fakes() {
  local fake_bin="$work_root/bin"
  mkdir -p "$fake_bin"

  cat >"$fake_bin/logger" <<'EOF'
#!/bin/bash
printf 'logger %s\n' "$*" >>"$CALL_LOG"
EOF

  # The scenario directory carries the state: which services answer, and whether
  # a restart brings the backend back.
  cat >"$fake_bin/systemctl" <<'EOF'
#!/bin/bash
printf 'systemctl %s\n' "$*" >>"$CALL_LOG"
case "$*" in
"is-active --quiet python3-validity.service")
  [[ -f "$SCENARIO_DIR/driver-running" ]] || exit 3
  ;;
restart*)
  if [[ -f "$SCENARIO_DIR/restart-recovers" ]]; then
    : >"$SCENARIO_DIR/driver-running"
    : >"$SCENARIO_DIR/backend-device"
  fi
  ;;
esac
exit 0
EOF

  cat >"$fake_bin/gdbus" <<'EOF'
#!/bin/bash
printf 'gdbus %s\n' "$*" >>"$CALL_LOG"
case "$*" in
*Manager.GetDevices*)
  if [[ -f "$SCENARIO_DIR/backend-device" ]]; then
    printf "([objectpath '/net/reactivated/Fprint/Device/0'],)\n"
  else
    printf '(@ao [],)\n'
  fi
  ;;
*Manager.Resume*)
  [[ -f "$SCENARIO_DIR/resume-fails" ]] && exit 1
  ;;
esac
exit 0
EOF

  chmod 755 "$fake_bin"/*
}

# Each flag is a file the fakes read. sensor-present also builds the sysfs tree.
run_scenario() {
  scenario="$1"
  shift
  scenario_dir="$work_root/$scenario"
  call_log="$scenario_dir/calls"

  mkdir -p "$scenario_dir/sysfs"
  : >"$call_log"

  local flag
  for flag in "$@"; do
    : >"$scenario_dir/$flag"
  done

  if [[ -f "$scenario_dir/sensor-present" ]]; then
    mkdir -p "$scenario_dir/sysfs/1-9"
    printf '06cb\n' >"$scenario_dir/sysfs/1-9/idVendor"
    printf '009a\n' >"$scenario_dir/sysfs/1-9/idProduct"
  fi

  exit_status=0
  CALL_LOG="$call_log" \
    SCENARIO_DIR="$scenario_dir" \
    PATH="$work_root/bin:$PATH" \
    OMARCHY_T480_FINGERPRINT_SYSFS_ROOT="$scenario_dir/sysfs" \
    OMARCHY_T480_FINGERPRINT_SENSOR_ATTEMPTS=2 \
    OMARCHY_T480_FINGERPRINT_BACKEND_ATTEMPTS=2 \
    OMARCHY_T480_FINGERPRINT_POLL_INTERVAL=0 \
    "$resume_script" || exit_status=$?
}

assert_status() {
  if [[ "$exit_status" == "$1" ]]; then
    pass "the script exits with $1"
  else
    fail "expected exit status $1, got $exit_status"
  fi
}

assert_logged() {
  if grep -Fq -- "$1" "$call_log"; then
    pass "calls include \"$1\""
  else
    fail "calls do not include \"$1\": $(tr '\n' '|' <"$call_log")"
  fi
}

refute_logged() {
  if grep -Fq -- "$1" "$call_log"; then
    fail "calls should not include \"$1\": $(tr '\n' '|' <"$call_log")"
  else
    pass "calls do not include \"$1\""
  fi
}

write_fakes

# A healthy reader is re-opened in place. Restarting the services would drop the
# claim of the lock screen's live PAM session, so it must not happen here.
run_scenario healthy sensor-present driver-running backend-device
assert_status 0
assert_logged 'Manager.Resume'
refute_logged 'systemctl restart'
assert_logged 'The fingerprint reader is ready after sleep.'

# The driver exits when an interrupted verify fails inside libusb. Re-opening the
# sensor cannot work without it, so the backend restart is the only way back.
run_scenario driver-died sensor-present restart-recovers
assert_status 0
assert_logged 'The fingerprint driver is not running.'
assert_logged 'systemctl restart open-fprintd.service python3-validity.service'
refute_logged 'Manager.Resume'
assert_logged 'The fingerprint reader is ready after sleep.'

run_scenario resume-failed sensor-present driver-running backend-device resume-fails restart-recovers
assert_status 0
assert_logged 'Manager.Resume'
assert_logged 'The reader did not re-open.'
assert_logged 'systemctl restart open-fprintd.service python3-validity.service'
assert_logged 'The fingerprint reader is ready after sleep.'

run_scenario unrecoverable sensor-present driver-running resume-fails
assert_status 1
assert_logged 'systemctl restart open-fprintd.service python3-validity.service'
assert_logged 'The fingerprint backend has no device after sleep.'

# A reader that never returns is reported, and the recovery still runs to
# completion within the bounded waits.
run_scenario sensor-missing driver-running backend-device
assert_status 0
assert_logged 'The fingerprint reader did not return after sleep.'
assert_logged 'Manager.Resume'

# The unit, the setup script, and the remove script must agree on where the
# resume script lives. A rename that misses one of them installs a unit that
# never runs, and the resume path is not covered by any of the cases above.
scenario="paths"
readonly unit_file="$repository_root/systemd/omarchy-t480-fingerprint-resume.service"
readonly setup_file="$repository_root/bin/omarchy-setup-security-fingerprint-t480"
readonly remove_file="$repository_root/bin/omarchy-remove-security-fingerprint-t480"

script_name=$(sed -n 's/^readonly resume_script_name="\(.*\)"$/\1/p' "$setup_file")
# The pattern matches the literal name of the shell variable in the setup script.
# shellcheck disable=SC2016
script_directory=$(sed -n 's|^readonly resume_script_target="\(.*\)/\$resume_script_name"$|\1|p' "$setup_file")
expected_path="$script_directory/$script_name"

for expectation in \
  "ExecStart=$expected_path" \
  "ConditionFileIsExecutable=$expected_path"; do
  if grep -Fqx -- "$expectation" "$unit_file"; then
    pass "the unit declares \"$expectation\""
  else
    fail "the unit does not declare \"$expectation\""
  fi
done

if grep -Fq -- "\"$expected_path\"" "$remove_file"; then
  pass "the remove script deletes $expected_path"
else
  fail "the remove script does not delete $expected_path"
fi

if [[ "$script_name" == "$(basename -- "$resume_script")" ]]; then
  pass "the setup script installs $script_name"
else
  fail "the setup script installs $script_name, the repository ships $(basename -- "$resume_script")"
fi

if ((failures)); then
  printf '%d assertion(s) failed\n' "$failures" >&2
  exit 1
fi

printf 'All resume assertions passed.\n'
