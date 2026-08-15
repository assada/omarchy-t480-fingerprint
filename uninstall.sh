#!/bin/bash

set -Eeuo pipefail

readonly version="1.0.0"
readonly source_ref="${OMARCHY_T480_FINGERPRINT_REF:-v${version}}"
readonly raw_base="https://raw.githubusercontent.com/assada/omarchy-t480-fingerprint/${source_ref}"
readonly setup_name="omarchy-setup-security-fingerprint-t480"
readonly remove_name="omarchy-remove-security-fingerprint-t480"

keep_auth=false
temporary_dir=""
helper_path=""

cleanup() {
  if [[ -n "$temporary_dir" && -d "$temporary_dir" ]]; then
    rm -rf -- "$temporary_dir"
  fi
}
trap cleanup EXIT

usage() {
  printf '%s\n' \
    'Usage: uninstall.sh [--keep-auth]' \
    '' \
    'Remove this integration. Use --keep-auth to keep fingerprint authentication.'
}

download_file() {
  local relative_path="$1" destination="$2"
  curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location \
    --output "$destination" "$raw_base/$relative_path"
}

get_helper() {
  local installed_path="$1" relative_path="$2"
  if [[ -f "$installed_path" ]]; then
    helper_path="$installed_path"
    return 0
  fi

  if [[ -z "$temporary_dir" ]]; then
    temporary_dir=$(mktemp -d)
  fi
  mkdir -p "$temporary_dir/$(dirname -- "$relative_path")"
  download_file "$relative_path" "$temporary_dir/$relative_path"
  chmod 755 "$temporary_dir/$relative_path"
  helper_path="$temporary_dir/$relative_path"
}

main() {
  local menu_file state_dir menu_helper remove_helper

  case "${1:-}" in
  --keep-auth) keep_auth=true ;;
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

  for command in curl python3; do
    if ! command -v "$command" >/dev/null; then
      printf 'The required command is missing: %s\n' "$command" >&2
      return 1
    fi
  done

  if [[ "$keep_auth" == false ]]; then
    if [[ ! -r /dev/tty || ! -w /dev/tty ]]; then
      printf '%s\n' 'Run this command from an interactive terminal.' >&2
      return 1
    fi
    get_helper \
      "$HOME/.local/bin/$remove_name" \
      "bin/$remove_name"
    remove_helper="$helper_path"
    "$remove_helper" </dev/tty
  fi

  menu_file="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
  state_dir="$HOME/.local/state/omarchy-t480-fingerprint"
  get_helper \
    "$HOME/.local/lib/omarchy-t480-fingerprint/menu.py" \
    "scripts/menu.py"
  menu_helper="$helper_path"
  python3 "$menu_helper" uninstall "$menu_file" "$state_dir"

  rm -f -- \
    "$HOME/.local/bin/$setup_name" \
    "$HOME/.local/bin/$remove_name" \
    "$HOME/.local/lib/omarchy-t480-fingerprint/menu.py"
  rmdir -- "$HOME/.local/lib/omarchy-t480-fingerprint" 2>/dev/null || true

  printf '%s\n' 'The local Omarchy fingerprint integration is removed.'
}

main "$@"
