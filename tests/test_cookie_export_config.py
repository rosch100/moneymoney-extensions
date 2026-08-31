#!/usr/bin/env python3
"""
Validiert cookie-export-banks.json (SSOT) und Bank-Origin-Abdeckung.

Ergänzt test_browser_extension_manifest.py um fachliche Bank-Konfigurationsprüfungen.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))

import extension_ssot as ssot  # noqa: E402

MATCH_SAMPLES = {
    "fidelity": "digital.fidelity.com",
    "boa": "secure.bankofamerica.com",
    "mlp": "vue.mlp.de",
}


def assert_invalid_origin(origin: str) -> None:
    try:
        ssot.origin_hostname(origin)
    except AssertionError:
        return
    raise AssertionError(f"ungültige Origin wurde akzeptiert: {origin}")


def main() -> None:
    banks = ssot.load_banks()
    for bank_id, entry in banks.items():
        pattern = re.compile(entry["match_host"])
        if bank_id in MATCH_SAMPLES:
            sample = MATCH_SAMPLES[bank_id]
            ssot.assert_true(
                pattern.search(sample) is not None,
                f"{bank_id}: match_host passt nicht zu {sample}",
            )
    for origin in (
        "https://user:password@example.com",
        "https://example.com:443",
        "https://example.com/",
        "https://example.com/path",
        "https://example.com?query=1",
        "https://example.com#fragment",
    ):
        assert_invalid_origin(origin)
    print("ALL COOKIE EXPORT CONFIG TESTS PASSED")


if __name__ == "__main__":
    try:
        main()
    except AssertionError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
