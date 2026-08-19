#!/bin/bash

set -Eeuo pipefail

readonly version="1.2.0"
readonly source_ref="${OMARCHY_T480_FINGERPRINT_REF:-v${version}}"
readonly raw_base="https://raw.githubusercontent.com/assada/omarchy-t480-fingerprint/${source_ref}"
readonly setup_name="omarchy-setup-security-fingerprint-t480"
readonly remove_name="omarchy-remove-security-fingerprint-t480"
# The setup script copies these three to their system paths.
readonly resume_script_name="omarchy-t480-fingerprint-resume"
readonly resume_unit_name="omarchy-t480-fingerprint-resume.service"
readonly driver_dropin_name="python3-validity-restart.conf"
readonly -a recovery_files=(
  "$resume_script_name"
  "$resume_unit_name"
  "$driver_dropin_name"
)
readonly legacy_sleep_hook_name="omarchy-t480-fingerprint-sleep"

run_setup=true
temporary_dir=""
sources=""

cleanup() {
  if [[ -n "$temporary_dir" && -d "$temporary_dir" ]]; then
    rm -rf -- "$temporary_dir"
  fi
}
trap cleanup EXIT

usage() {
  printf '%s\n' \
    'Usage: install.sh [--no-setup]' \
    '' \
    'Install the local Omarchy integration for the Synaptics 06cb:009a reader.'
}

download_file() {
  local relative_path="$1" destination="$2"
  curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location \
    --output "$destination" "$raw_base/$relative_path"
}

repository_is_complete() {
  local script_directory="$1" recovery_file

  [[ -f "$script_directory/bin/$setup_name" &&
    -f "$script_directory/bin/$remove_name" &&
    -f "$script_directory/scripts/menu.py" ]] || return 1
  for recovery_file in "${recovery_files[@]}"; do
    [[ -f "$script_directory/systemd/$recovery_file" ]] || return 1
  done
}

source_directory() {
  local script_directory recovery_file
  if ! script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd); then
    script_directory=""
  fi
  if [[ -n "$script_directory" ]] && repository_is_complete "$script_directory"; then
    sources="$script_directory"
    return 0
  fi

  temporary_dir=$(mktemp -d)
  mkdir -p "$temporary_dir/bin" "$temporary_dir/scripts" "$temporary_dir/systemd"
  download_file "bin/$setup_name" "$temporary_dir/bin/$setup_name"
  download_file "bin/$remove_name" "$temporary_dir/bin/$remove_name"
  download_file "scripts/menu.py" "$temporary_dir/scripts/menu.py"
  for recovery_file in "${recovery_files[@]}"; do
    download_file "systemd/$recovery_file" "$temporary_dir/systemd/$recovery_file"
  done
  sources="$temporary_dir"
}

main() {
  local sources menu_file state_dir library_dir setup_path

  case "${1:-}" in
  --no-setup) run_setup=false ;;
  --help | -h)
    usage
    return 0
    ;;
  "") ;;
  *)
    usage >&2
    return 2
    ;;
  esac

  for command in curl install python3; do
    if ! command -v "$command" >/dev/null; then
      printf 'The required command is missing: %s\n' "$command" >&2
      return 1
    fi
  done

  source_directory
  menu_file="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
  state_dir="$HOME/.local/state/omarchy-t480-fingerprint"
  library_dir="$HOME/.local/lib/omarchy-t480-fingerprint"
  setup_path="$HOME/.local/bin/$setup_name"

  install -Dm755 "$sources/bin/$setup_name" "$setup_path"
  install -Dm755 "$sources/bin/$remove_name" "$HOME/.local/bin/$remove_name"
  install -Dm755 "$sources/scripts/menu.py" "$library_dir/menu.py"
  install -Dm755 "$sources/systemd/$resume_script_name" "$library_dir/$resume_script_name"
  install -Dm644 "$sources/systemd/$resume_unit_name" "$library_dir/$resume_unit_name"
  install -Dm644 "$sources/systemd/$driver_dropin_name" "$library_dir/$driver_dropin_name"
  # Releases before 1.2.0 shipped a system-sleep hook instead of a resume unit.
  # The setup script removes the installed copy; this removes the source.
  rm -f -- "$library_dir/$legacy_sleep_hook_name"
  python3 "$library_dir/menu.py" install "$menu_file" "$state_dir"

  printf '%s\n' \
    'The local Omarchy fingerprint integration is installed.' \
    'Menu path: Setup > Security > Fingerprint'

  if [[ "$run_setup" == false ]]; then
    return 0
  fi
  if [[ ! -r /dev/tty || ! -w /dev/tty ]]; then
    printf '%s\n' \
      'No interactive terminal is available.' \
      "Run $setup_path from a terminal."
    return 0
  fi

  "$setup_path" </dev/tty
}

main "$@"
