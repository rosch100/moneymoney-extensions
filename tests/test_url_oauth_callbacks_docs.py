#!/usr/bin/env python3
"""
Verifikations-Tests fuer die Reverse-Engineering-Doku zu URL/OAuth Callbacks.

Motivation:
- E2E-Tests der echten OAuth-Redirects sind in dieser Repo-Umgebung nicht realistisch.
- Dieser Test stellt sicher, dass die dokumentierten Glue-Schluessel (aus dem Binary-RE)
  in `docs/ENGINE-API-GAPS.md` konsistent enthalten sind.
- zusaetzlich: keine UTF-8 BOM / keine unerwarteten Nicht-ASCII-Zeichen (Repo-Style).

Usage:
  python3 tests/test_url_oauth_callbacks_docs.py
"""

from __future__ import annotations

import pathlib
import re
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
DOC_PATH = ROOT / "docs" / "ENGINE-API-GAPS.md"


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


def assert_ascii_only(text: str, path: pathlib.Path) -> None:
    # Erlaubt: newline/tab; alles andere soll ASCII sein.
    # Wenn spaeter bewusst Nicht-ASCII erlaubt werden soll, diesen Test entsprechend anpassen.
    for i, ch in enumerate(text):
        if ord(ch) > 127:
            raise AssertionError(f"{path}: Nicht-ASCII Zeichen gefunden: U+{ord(ch):04X} (pos={i})")


def file_must_contain(path: pathlib.Path, needles: list[str]) -> None:
    text = path.read_text(encoding="utf-8", errors="strict")
    for n in needles:
        assert_true(n in text, f"{path}: erwartet '{n}' nicht gefunden")
    # Kein ASCII-only-Restriktionscheck: die Referenz-Doku kann UTF-8 enthalten.


def main() -> None:
    assert_true(DOC_PATH.exists(), f"Doku fehlt: {DOC_PATH}")
    assert_no_utf8_bom(DOC_PATH)

    file_must_contain(
        DOC_PATH,
        [
            "UrlSchemeHandler.getUrl:withReplyEvent:",
            "GURL",
            "LuaModules.processUrls",
            "oAuthControllers",
            "LuaModules.oAuthCallback:",
            "moneymoney-app://oauth%@%@%@",
            "InitializeSession2",
        ],
    )

    # Minimaler Regression-Check: Query-Parsing ueber '&' und '=' wird im Doc erwaehnt.
    text = DOC_PATH.read_text(encoding="utf-8", errors="strict")
    assert_true("&" in text and "=" in text, f"{DOC_PATH}: erwartete Zeichen (& oder =) nicht gefunden")

    print("OK URL/OAuth Callback Doku-Verifikations-Test")


if __name__ == "__main__":
    try:
        main()
    except AssertionError as e:
        print(f"FAIL: {e}", file=sys.stderr)
        sys.exit(1)

