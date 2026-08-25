#!/usr/bin/env python3
"""
Leitet host_permissions aus cookie-export-banks.json ab und synchronisiert Safari-Resources.

SSOT: browser-extension/
"""

from __future__ import annotations

import sys
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))

import extension_ssot as ssot  # noqa: E402


def main() -> None:
    banks = ssot.load_banks()
    permissions = ssot.host_permissions_from_banks(banks)
    ssot.assert_no_subdomain_wildcards(permissions)
    changed = ssot.apply_host_permissions_to_manifest(permissions)
    copied, pruned = ssot.sync_safari_resources()
    print(
        f"host_permissions={'updated' if changed else 'unchanged'} "
        f"({len(permissions)}); safari synced={len(copied)} pruned={len(pruned)}"
    )


if __name__ == "__main__":
    try:
        main()
    except AssertionError as e:
        print(f"FAIL: {e}", file=sys.stderr)
        sys.exit(1)
