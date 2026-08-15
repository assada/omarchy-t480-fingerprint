#!/usr/bin/env python3

"""Add or remove the local Omarchy menu entries for this project."""

from __future__ import annotations

import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import shutil
import tempfile


SETUP_KEY = "setup.security.fingerprint"
REMOVE_KEY = "remove.security.fingerprint"
MANAGED_KEYS = (SETUP_KEY, REMOVE_KEY)
START_MARKER = "  // omarchy-t480-fingerprint:start"
END_MARKER = "  // omarchy-t480-fingerprint:end"

ENTRIES = {
    SETUP_KEY: {
        "icon": "󰈷",
        "label": "Fingerprint",
        "description": "ThinkPad T480 (06cb:009a)",
        "when": "lsusb -d 06cb:009a >/dev/null 2>&1",
        "action": (
            'omarchy-launch-floating-terminal-with-presentation '
            '"$HOME/.local/bin/omarchy-setup-security-fingerprint-t480"'
        ),
    },
    REMOVE_KEY: {
        "icon": "󰈷",
        "label": "Fingerprint",
        "description": "ThinkPad T480 (06cb:009a)",
        "when": "omarchy-pkg-present python-validity",
        "action": (
            'omarchy-launch-floating-terminal-with-presentation '
            '"$HOME/.local/bin/omarchy-remove-security-fingerprint-t480"'
        ),
    },
}


def remove_comments(text: str) -> str:
    result: list[str] = []
    index = 0
    in_string = False
    escaped = False

    while index < len(text):
        char = text[index]
        next_char = text[index + 1] if index + 1 < len(text) else ""

        if in_string:
            result.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
            continue

        if char == '"':
            in_string = True
            result.append(char)
            index += 1
            continue

        if char == "/" and next_char == "/":
            index += 2
            while index < len(text) and text[index] not in "\r\n":
                index += 1
            continue

        if char == "/" and next_char == "*":
            index += 2
            while index + 1 < len(text) and text[index : index + 2] != "*/":
                if text[index] in "\r\n":
                    result.append(text[index])
                index += 1
            if index + 1 >= len(text):
                raise ValueError("The menu file contains an incomplete comment.")
            index += 2
            continue

        result.append(char)
        index += 1

    if in_string:
        raise ValueError("The menu file contains an incomplete string.")
    return "".join(result)


def remove_trailing_commas(text: str) -> str:
    result: list[str] = []
    index = 0
    in_string = False
    escaped = False

    while index < len(text):
        char = text[index]
        if in_string:
            result.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
            continue

        if char == '"':
            in_string = True
            result.append(char)
            index += 1
            continue

        if char == ",":
            look_ahead = index + 1
            while look_ahead < len(text) and text[look_ahead].isspace():
                look_ahead += 1
            if look_ahead < len(text) and text[look_ahead] in "}]":
                index += 1
                continue

        result.append(char)
        index += 1

    return "".join(result)


def parse_menu(text: str) -> dict[str, object]:
    normalized = remove_trailing_commas(remove_comments(text)).strip()
    if not normalized:
        return {}
    menu = json.loads(normalized)
    if not isinstance(menu, dict):
        raise ValueError("The menu file must contain one JSON object.")
    return menu


def is_managed_entry(value: object) -> bool:
    if not isinstance(value, dict):
        return False
    action = value.get("action")
    return isinstance(action, str) and "fingerprint-t480" in action


def menu_block(separator_required: bool) -> str:
    encoded = json.dumps(ENTRIES, ensure_ascii=False, indent=2).splitlines()
    body = encoded[1:-1]
    lines = [START_MARKER]
    if separator_required:
        lines.append("  ,")
    lines.extend(body)
    lines.append(END_MARKER)
    return "\n".join(lines)


def marker_span(text: str) -> tuple[int, int] | None:
    start = text.find(START_MARKER)
    end = text.find(END_MARKER)
    if start == -1 and end == -1:
        return None
    if start == -1 or end == -1 or end < start:
        raise ValueError("The menu file contains an incomplete project marker.")
    end += len(END_MARKER)
    if end < len(text) and text[end] == "\n":
        end += 1
    return start, end


def closing_brace_index(text: str) -> int:
    normalized = text.rstrip()
    if not normalized.endswith("}"):
        raise ValueError("The menu file must end with a JSON object.")
    return text.rfind("}", 0, len(normalized))


def prefix_has_trailing_comma(prefix: str) -> bool:
    return remove_comments(prefix).rstrip().endswith(",")


def install_entries(text: str, menu: dict[str, object]) -> tuple[str, bool]:
    span = marker_span(text)
    if span:
        start, end = span
        other_entries = [key for key in menu if key not in MANAGED_KEYS]
        prefix = text[:start]
        block = menu_block(bool(other_entries) and not prefix_has_trailing_comma(prefix))
        updated = prefix + block + "\n" + text[end:]
        return updated, updated != text

    for key in MANAGED_KEYS:
        if key in menu:
            if is_managed_entry(menu[key]):
                raise ValueError(
                    "This installation uses old unmarked menu entries. "
                    "Remove these entries, then run the installer again."
                )
            raise ValueError(
                f'The menu contains a custom "{key}" entry. '
                "Remove or rename that entry, then run this installer again."
            )

    close = closing_brace_index(text)
    prefix = text[:close]
    if prefix and not prefix.endswith("\n"):
        prefix += "\n"
    separator_required = bool(menu) and not prefix_has_trailing_comma(prefix)
    updated = prefix + menu_block(separator_required) + "\n" + text[close:]
    parse_menu(updated)
    return updated, True


def uninstall_entries(text: str) -> tuple[str, bool]:
    span = marker_span(text)
    if not span:
        return text, False
    start, end = span
    updated = text[:start] + text[end:]
    parse_menu(updated)
    return updated, True


def backup_menu(path: Path, state_dir: Path) -> Path | None:
    if not path.exists():
        return None
    state_dir.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    backup = state_dir / f"omarchy-menu.{timestamp}.jsonc"
    shutil.copy2(path, backup)
    return backup


def write_menu(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = path.stat().st_mode if path.exists() else 0o100644
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=path.parent, delete=False
    ) as temporary:
        temporary.write(content)
        temporary_path = Path(temporary.name)

    os.chmod(temporary_path, mode & 0o777)
    try:
        os.replace(temporary_path, path)
    except Exception:
        temporary_path.unlink(missing_ok=True)
        raise


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("operation", choices=("install", "uninstall"))
    parser.add_argument("menu_file", type=Path)
    parser.add_argument("state_dir", type=Path)
    args = parser.parse_args()

    try:
        original = (
            args.menu_file.read_text(encoding="utf-8")
            if args.menu_file.exists()
            else "{\n}\n"
        )
        menu = parse_menu(original)
        updated, changed = (
            install_entries(original, menu)
            if args.operation == "install"
            else uninstall_entries(original)
        )
        if not changed:
            print(f"Menu entries are already {args.operation}ed.")
            return 0

        backup = backup_menu(args.menu_file, args.state_dir)
        write_menu(args.menu_file, updated)
        if backup:
            print(f"Menu backup: {backup}")
        print(f"Menu entries {args.operation}ed.")
        return 0
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"Menu update failed: {error}", file=os.sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
