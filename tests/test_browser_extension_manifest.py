#!/usr/bin/env python3
"""
Manifest-Konformität für MoneyMoney Helper Browser-/Safari-Extension.

Nutzt scripts/extension_ssot.py als SSOT für Permissions-Ableitung und Sync-Check.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))

import extension_ssot as ssot  # noqa: E402


def test_sync_helpers() -> None:
    original_paths = (ssot.BROWSER, ssot.SAFARI_RES, ssot.MANIFEST)
    with TemporaryDirectory() as temp_dir:
        root = Path(temp_dir)
        browser = root / "browser"
        safari = root / "safari"
        browser.mkdir()
        safari.mkdir()
        (browser / "icons").mkdir()
        (safari / "icons").mkdir()
        for name in ssot.SHARED_FILES:
            (browser / name).write_text(f"{name}\n", encoding="utf-8")
        manifest = browser / "manifest.json"
        manifest.write_text(
            json.dumps({"permissions": ["cookies"], "host_permissions": []}),
            encoding="utf-8",
        )
        (browser / "icons/icon.png").write_bytes(b"source")
        (safari / "icons/orphan.png").write_bytes(b"orphan")

        ssot.BROWSER = browser
        ssot.SAFARI_RES = safari
        ssot.MANIFEST = manifest
        try:
            expected_permissions = ["https://example.test/*"]
            ssot.assert_true(
                ssot.apply_host_permissions_to_manifest(expected_permissions),
                "Manifest-Update muss Änderungen melden",
            )
            ssot.assert_true(
                not ssot.apply_host_permissions_to_manifest(expected_permissions),
                "Identisches Manifest darf nicht erneut geschrieben werden",
            )
            copied, pruned = ssot.sync_safari_resources()
            ssot.assert_true("icons/icon.png" in copied, "Icon wurde nicht synchronisiert")
            ssot.assert_true("icons/orphan.png" in pruned, "Verwaistes Icon wurde nicht entfernt")
            ssot.assert_safari_resources_synced()
        finally:
            ssot.BROWSER, ssot.SAFARI_RES, ssot.MANIFEST = original_paths


def main() -> None:
    banks = ssot.load_banks()
    manifest = json.loads(ssot.MANIFEST.read_text(encoding="utf-8"))
    expected = ssot.host_permissions_from_banks(banks)
    actual = manifest.get("host_permissions")
    ssot.assert_true(
        manifest.get("permissions") == ["cookies"],
        "Browser-Manifest darf ausschließlich die Cookie-Berechtigung anfordern",
    )
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
    test_sync_helpers()
    print("ALL BROWSER EXTENSION MANIFEST TESTS PASSED")


if __name__ == "__main__":
    try:
        main()
    except AssertionError as e:
        print(f"FAIL: {e}", file=sys.stderr)
        sys.exit(1)
