"""
SSOT-Hilfen für MoneyMoney Helper Browser-/Safari-Extension.

browser-extension/ ist die Quelle; Safari-Resources und host_permissions werden daraus abgeleitet.
"""

from __future__ import annotations

import json
import pathlib
import shutil

ROOT = pathlib.Path(__file__).resolve().parents[1]
BROWSER = ROOT / "browser-extension"
SAFARI_RES = (
    ROOT
    / "safari-extension"
    / "MoneyMoney Helper"
    / "MoneyMoney Helper Extension"
    / "Resources"
)
BANKS = BROWSER / "cookie-export-banks.json"
MANIFEST = BROWSER / "manifest.json"

SHARED_FILES = (
    "README.md",
    "config.js",
    "cookie-export-banks.json",
    "cookie-export.js",
    "manifest.json",
    "popup.html",
    "popup.js",
)


def assert_true(cond: bool, msg: str) -> None:
    if not cond:
        raise AssertionError(msg)


def load_banks() -> dict:
    banks = json.loads(BANKS.read_text(encoding="utf-8"))
    assert_true(isinstance(banks, dict) and banks, f"{BANKS.name}: erwartetes Objekt mit Banken")
    return banks


def host_permissions_from_banks(banks: dict) -> list[str]:
    patterns: list[str] = []
    seen: set[str] = set()
    for bank_id, entry in banks.items():
        assert_true(isinstance(entry, dict), f"{BANKS.name}: Bank '{bank_id}' ist kein Objekt")
        assert_true(
            "domains" not in entry,
            f"{BANKS.name}: Bank '{bank_id}' hat veraltetes Feld 'domains' (nur origins nutzen)",
        )
        raw_origins = entry.get("origins")
        assert_true(
            isinstance(raw_origins, list) and len(raw_origins) > 0,
            f"{BANKS.name}: Bank '{bank_id}' fehlt nicht-leeres 'origins'",
        )
        for origin in raw_origins:
            assert_true(
                isinstance(origin, str) and origin.startswith("https://"),
                f"{BANKS.name}: Bank '{bank_id}' hat ungültige Origin: {origin!r}",
            )
            pattern = f"{origin.rstrip('/')}/*"
            if pattern in seen:
                continue
            seen.add(pattern)
            patterns.append(pattern)
    return patterns


def assert_no_subdomain_wildcards(host_permissions: list[str]) -> None:
    for pattern in host_permissions:
        assert_true("://" in pattern, f"host_permissions ohne Schema: {pattern}")
        host = pattern.split("://", 1)[1].split("/", 1)[0]
        assert_true("*." not in host, f"Safari-unsicherer Host-Wildcard: {pattern}")
        assert_true(not pattern.startswith("*://"), f"Safari-unsicherer Schema-Wildcard: {pattern}")


def shared_browser_files() -> list[pathlib.Path]:
    paths = [BROWSER / name for name in SHARED_FILES]
    icons_dir = BROWSER / "icons"
    assert_true(icons_dir.is_dir(), f"fehlt: {icons_dir}")
    paths.extend(sorted(path for path in icons_dir.rglob("*") if path.is_file()))
    return paths


def managed_safari_files() -> list[pathlib.Path]:
    """Dateien unter Safari-Resources, die vom Sync verwaltet werden."""
    files: list[pathlib.Path] = []
    for name in SHARED_FILES:
        path = SAFARI_RES / name
        if path.is_file():
            files.append(path)
    icons_dir = SAFARI_RES / "icons"
    if icons_dir.is_dir():
        files.extend(sorted(path for path in icons_dir.rglob("*") if path.is_file()))
    return files


def apply_host_permissions_to_manifest(host_permissions: list[str]) -> bool:
    """Schreibt host_permissions in manifest.json. True wenn geändert."""
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if manifest.get("host_permissions") == host_permissions:
        return False
    manifest["host_permissions"] = host_permissions
    MANIFEST.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    return True


def prune_empty_dirs(root: pathlib.Path) -> None:
    if not root.is_dir():
        return
    for path in sorted(root.rglob("*"), reverse=True):
        if path.is_dir() and not any(path.iterdir()):
            path.rmdir()


def sync_safari_resources() -> tuple[list[str], list[str]]:
    """
    Kopiert Shared Resources und entfernt verwaiste Safari-Dateien.
    Returns: (copied_rel_paths, pruned_rel_paths)
    """
    assert_true(SAFARI_RES.is_dir(), f"fehlt: {SAFARI_RES}")
    browser_paths = shared_browser_files()
    expected = {str(path.relative_to(BROWSER)) for path in browser_paths}
    copied: list[str] = []
    for browser_path in browser_paths:
        rel = browser_path.relative_to(BROWSER)
        safari_path = SAFARI_RES / rel
        safari_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(browser_path, safari_path)
        copied.append(str(rel))

    pruned: list[str] = []
    for safari_path in managed_safari_files():
        rel = str(safari_path.relative_to(SAFARI_RES))
        if rel in expected:
            continue
        safari_path.unlink()
        pruned.append(rel)
    prune_empty_dirs(SAFARI_RES / "icons")
    return copied, pruned


def assert_safari_resources_synced() -> None:
    expected = {str(path.relative_to(BROWSER)) for path in shared_browser_files()}
    for browser_path in shared_browser_files():
        rel = browser_path.relative_to(BROWSER)
        safari_path = SAFARI_RES / rel
        assert_true(browser_path.is_file(), f"fehlt: {browser_path}")
        assert_true(safari_path.is_file(), f"Safari-Resource fehlt: {safari_path}")
        assert_true(
            safari_path.read_bytes() == browser_path.read_bytes(),
            f"Safari-Resource driftet von browser-extension: {rel}",
        )
    for safari_path in managed_safari_files():
        rel = str(safari_path.relative_to(SAFARI_RES))
        assert_true(
            rel in expected,
            f"Verwaiste Safari-Resource (nicht in browser-extension): {rel}",
        )
