"""
SSOT-Hilfen für MoneyMoney Helper Browser-/Safari-Extension.

browser-extension/ ist die Quelle; Safari-Resources und host_permissions werden daraus abgeleitet.
"""

from __future__ import annotations

import json
import pathlib
import re
import shutil
from urllib.parse import urlparse

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

REQUIRED_BANK_KEYS = {
    "label",
    "match_host",
    "origins",
    "session_host",
    "critical",
    "allow_duplicate_names",
    "priority",
}


def assert_true(cond: bool, msg: str) -> None:
    if not cond:
        raise AssertionError(msg)


def load_banks() -> dict:
    banks = json.loads(BANKS.read_text(encoding="utf-8"))
    validate_banks(banks)
    return banks


def origin_hostname(origin: str) -> str:
    parsed = urlparse(origin)
    try:
        port = parsed.port
    except ValueError as exc:
        raise AssertionError(f"{BANKS.name}: ungültige Origin: {origin!r}") from exc
    hostname = parsed.hostname
    assert_true(
        parsed.scheme == "https"
        and hostname is not None
        and parsed.username is None
        and parsed.password is None
        and port is None
        and parsed.netloc.lower() == hostname.lower()
        and not parsed.path
        and not parsed.params
        and not parsed.query
        and not parsed.fragment,
        f"{BANKS.name}: ungültige Origin: {origin!r}",
    )
    return hostname


def validate_banks(banks: dict) -> None:
    """Validiert das vollständige Schema und die Origin-Abdeckung der Bankkonfiguration."""
    assert_true(isinstance(banks, dict) and banks, f"{BANKS.name}: erwartetes Objekt mit Banken")
    for bank_id, entry in banks.items():
        assert_true(isinstance(entry, dict), f"{BANKS.name}: Bank '{bank_id}' ist kein Objekt")
        missing_keys = REQUIRED_BANK_KEYS - entry.keys()
        assert_true(
            not missing_keys,
            f"{BANKS.name}: Bank '{bank_id}' fehlende Keys: {sorted(missing_keys)}",
        )
        assert_true(
            "domains" not in entry,
            f"{BANKS.name}: Bank '{bank_id}' hat veraltetes Feld 'domains' (nur origins nutzen)",
        )
        assert_true(
            isinstance(entry["label"], str) and entry["label"],
            f"{BANKS.name}: Bank '{bank_id}' label ungültig",
        )
        assert_true(
            isinstance(entry["match_host"], str) and entry["match_host"],
            f"{BANKS.name}: Bank '{bank_id}' match_host ungültig",
        )
        try:
            re.compile(entry["match_host"])
        except re.error as exc:
            raise AssertionError(
                f"{BANKS.name}: Bank '{bank_id}' match_host ungültig: {exc}"
            ) from exc
        raw_origins = entry["origins"]
        assert_true(
            isinstance(raw_origins, list) and raw_origins,
            f"{BANKS.name}: Bank '{bank_id}' fehlt nicht-leeres 'origins'",
        )
        origin_hosts: set[str] = set()
        for origin in raw_origins:
            assert_true(
                isinstance(origin, str),
                f"{BANKS.name}: Bank '{bank_id}' hat ungültige Origin: {origin!r}",
            )
            origin_hosts.add(origin_hostname(origin))
        session_host = entry.get("session_host")
        assert_true(
            isinstance(session_host, str) and session_host,
            f"{BANKS.name}: Bank '{bank_id}' session_host ungültig",
        )
        assert_true(
            session_host in origin_hosts,
            f"{BANKS.name}: Bank '{bank_id}' session_host '{session_host}' fehlt in origins "
            f"(jede genutzte Subdomain braucht einen https://-Eintrag — keine Wildcards wegen Safari 27)",
        )
        for key in ("critical", "allow_duplicate_names", "priority"):
            assert_true(
                isinstance(entry[key], list)
                and all(isinstance(value, str) and value for value in entry[key]),
                f"{BANKS.name}: Bank '{bank_id}' {key} ungültig",
            )
        assert_true(
            entry["priority"],
            f"{BANKS.name}: Bank '{bank_id}' priority leer",
        )


def host_permissions_from_banks(banks: dict) -> list[str]:
    validate_banks(banks)
    patterns: list[str] = []
    seen: set[str] = set()
    for entry in banks.values():
        for origin in entry["origins"]:
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
