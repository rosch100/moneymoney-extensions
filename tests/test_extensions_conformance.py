#!/usr/bin/env python3
"""
Konformitätstests für MoneyMoney Lua-Extensions.

Ziel:
- Frühzeitig in CI erkennen, wenn eine Extension Pflichtfunktionen nicht definiert.
- Verhindern von Laufzeitfehlern wie:
  "Extension.lua: missing function 'InitializeSession'"

Usage:
  python3 tests/test_extensions_conformance.py
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
EXT_DIR = ROOT / "extensions"


def assert_true(cond: bool, msg: str) -> None:
    if cond:
        return
    raise AssertionError(msg)


def read_bytes(path: pathlib.Path) -> bytes:
    return path.read_bytes()


def assert_no_utf8_bom(path: pathlib.Path) -> None:
    raw = read_bytes(path)
    bom = b"\xef\xbb\xbf"
    assert_true(not raw.startswith(bom), f"{path}: UTF-8 BOM verboten")


def file_contains(path: pathlib.Path, pattern: str) -> bool:
    text = path.read_text(encoding="utf-8", errors="replace")
    return re.search(pattern, text, flags=re.M | re.S) is not None


def assert_extension_conformance(lua_path: pathlib.Path) -> None:
    assert_true(lua_path.suffix == ".lua", f"{lua_path}: nur .lua erlaubt")

    assert_no_utf8_bom(lua_path)

    # Basic WebBanking declaration (common for our extensions)
    assert_true(
        file_contains(lua_path, r"\bWebBanking\s*\{"),
        f"{lua_path}: fehlendes WebBanking{{...}}",
    )

    assert_true(
        file_contains(lua_path, r"\bfunction\s+SupportsBank\s*\("),
        f"{lua_path}: missing function 'SupportsBank'",
    )

    has_init = file_contains(lua_path, r"\bfunction\s+InitializeSession\s*\(")
    has_init2 = file_contains(lua_path, r"\bfunction\s+InitializeSession2\s*\(")
    assert_true(
        has_init or has_init2,
        f"{lua_path}: missing 'InitializeSession' und 'InitializeSession2'",
    )


def main() -> None:
    assert_true(EXT_DIR.exists(), f"extensions-Verzeichnis fehlt: {EXT_DIR}")
    lua_files = sorted(EXT_DIR.glob("*.lua"))
    assert_true(len(lua_files) >= 1, f"Keine Lua-Extensions gefunden in {EXT_DIR}")

    for p in lua_files:
        assert_extension_conformance(p)

    print("ALL EXTENSIONS CONFORMANCE TESTS PASSED")


if __name__ == "__main__":
    try:
        main()
    except AssertionError as e:
        print(f"FAIL: {e}", file=sys.stderr)
        sys.exit(1)

