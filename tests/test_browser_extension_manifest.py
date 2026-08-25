#!/usr/bin/env python3
"""
Manifest-Konformität für MoneyMoney Helper Browser-/Safari-Extension.

Nutzt scripts/extension_ssot.py als SSOT für Permissions-Ableitung und Sync-Check.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))

import extension_ssot as ssot  # noqa: E402


def main() -> None:
    banks = ssot.load_banks()
    manifest = json.loads(ssot.MANIFEST.read_text(encoding="utf-8"))
    expected = ssot.host_permissions_from_banks(banks)
    actual = manifest.get("host_permissions")
    ssot.assert_true(isinstance(actual, list), "host_permissions fehlt oder ist kein Array")
    ssot.assert_true(
        actual == expected,
        "host_permissions müssen 1:1 aus cookie-export-banks.json origins stammen:\n"
        f"  erwartet: {expected}\n"
        f"  aktuell: {actual}\n"
        "  Hinweis: python3 scripts/sync_safari_extension_resources.py",
    )
    ssot.assert_no_subdomain_wildcards(actual)
    ssot.assert_safari_resources_synced()
    print("ALL BROWSER EXTENSION MANIFEST TESTS PASSED")


if __name__ == "__main__":
    try:
        main()
    except AssertionError as e:
        print(f"FAIL: {e}", file=sys.stderr)
        sys.exit(1)
