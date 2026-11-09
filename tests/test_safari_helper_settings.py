#!/usr/bin/env python3
"""
Regression: „Quit and Open Safari Settings…“ muss die Safari-Einstellungen öffnen.

Der Button darf ausschließlich `SFSafariApplication.showPreferencesForExtension`
verwenden. Das Schema `x-apple.systempreferences:` öffnet dagegen die
macOS-Systemeinstellungen, in denen es seit macOS 13 kein Safari-Pane mehr gibt.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP_DIR = ROOT / "safari-extension" / "MoneyMoney Helper" / "MoneyMoney Helper"
VIEW_CONTROLLER = APP_DIR / "ViewController.swift"
PROJECT_FILE = ROOT / "safari-extension" / "MoneyMoney Helper" / "MoneyMoney Helper.xcodeproj" / "project.pbxproj"

EXTENSION_IDENTIFIER = '"com.yourCompany.MoneyMoney-Helper.Extension"'
SETTINGS_FUNCTION = "func openSafariExtensionsSettings()"
SAFARI_SETTINGS_CALL = (
    "SFSafariApplication.showPreferencesForExtension("
    "withIdentifier: extensionBundleIdentifier"
)
# Nur das String-Literal zählt: Das Schema öffnet die Systemeinstellungen und
# darf nirgends als zu öffnende URL im Code stehen (Doku-Erwähnungen sind ok).
SYSTEM_SETTINGS_URL = '"x-apple.systempreferences:'
ERROR_BRANCH = re.compile(r"if let error \{(.*?)return \}")
TERMINATE_CALL = "NSApplication.shared.terminate(nil)"


def assert_true(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def normalize(source: str) -> str:
    """Fasst Whitespace zusammen, damit Formatierung den Test nicht bricht."""
    return re.sub(r"\s+", " ", source)


def function_body(source: str, signature: str) -> str:
    """Gibt den Körper der Funktion ab der Signatur bis zur passenden Klammer zurück."""
    start = source.find(signature)
    assert_true(start >= 0, f"{signature} fehlt in {VIEW_CONTROLLER.name}")
    body_start = source.index("{", start)
    depth = 0
    for index in range(body_start, len(source)):
        char = source[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return source[body_start : index + 1]
    raise AssertionError(f"Funktionskörper von {signature} ist nicht abgeschlossen")


def check_sources() -> None:
    swift_files = sorted(APP_DIR.rglob("*.swift"))
    assert_true(bool(swift_files), f"Keine Swift-Quellen unter {APP_DIR}")
    for swift_file in swift_files:
        content = swift_file.read_text(encoding="utf-8")
        assert_true(
            SYSTEM_SETTINGS_URL not in content,
            f"{swift_file.name}: {SYSTEM_SETTINGS_URL} öffnet die Systemeinstellungen "
            "und darf die Safari-Einstellungen nicht ersetzen",
        )
        assert_true(
            "NSWorkspace" not in content,
            f"{swift_file.name}: Safari-Einstellungen dürfen nicht per URL über "
            "NSWorkspace geöffnet werden",
        )


def check_extension_identifier(source: str) -> None:
    normalized = normalize(source)
    assert_true(
        f"private let extensionBundleIdentifier = {EXTENSION_IDENTIFIER}" in normalized,
        "extensionBundleIdentifier muss die Bundle-ID der Safari-Erweiterung sein",
    )
    project = PROJECT_FILE.read_text(encoding="utf-8")
    identifiers = re.findall(r"PRODUCT_BUNDLE_IDENTIFIER = \"?([^;\"]+)\"?;", project)
    assert_true(
        EXTENSION_IDENTIFIER.strip('"') in identifiers,
        "Die Bundle-ID der Safari-Erweiterung fehlt in project.pbxproj",
    )


def check_message_wiring(source: str) -> None:
    normalized = normalize(source)
    assert_true(
        'userContentController.add(self, name: "controller")' in normalized,
        "Der Meldungskanal der Oberfläche muss registriert sein",
    )
    body = normalize(function_body(source, "func userContentController("))
    assert_true(
        'body == "open-preferences"' in body and "openSafariExtensionsSettings()" in body,
        'Die Meldung "open-preferences" muss openSafariExtensionsSettings auslösen',
    )
    guard = re.search(r'body == "open-preferences"\s*else \{ return \}(.*)', body)
    assert_true(
        guard is not None and "openSafariExtensionsSettings()" in guard.group(1),
        "openSafariExtensionsSettings darf nur nach der Prüfung auf "
        '"open-preferences" aufgerufen werden',
    )


def check_settings_function(source: str) -> None:
    body = normalize(function_body(source, SETTINGS_FUNCTION))
    assert_true(
        SAFARI_SETTINGS_CALL in body,
        "openSafariExtensionsSettings muss die Safari-Einstellungen über "
        "SFSafariApplication.showPreferencesForExtension öffnen",
    )
    error_branch = ERROR_BRANCH.search(body)
    assert_true(
        error_branch is not None,
        "openSafariExtensionsSettings muss den Fehler des API-Aufrufs prüfen",
    )
    assert_true(
        "terminate" not in error_branch.group(1),
        "Im Fehlerfall darf sich die App nicht beenden",
    )
    assert_true(
        TERMINATE_CALL in body[error_branch.end() :],
        "Die App darf sich erst im Erfolgsfall hinter der Fehlerprüfung beenden",
    )
    assert_true(
        body.count(TERMINATE_CALL) == 1,
        "Die App darf sich genau einmal beenden",
    )


def main() -> None:
    source = VIEW_CONTROLLER.read_text(encoding="utf-8")
    check_sources()
    check_extension_identifier(source)
    check_message_wiring(source)
    check_settings_function(source)
    print("ALL SAFARI HELPER SETTINGS TESTS PASSED")


if __name__ == "__main__":
    try:
        main()
    except AssertionError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
