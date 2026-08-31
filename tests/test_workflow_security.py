#!/usr/bin/env python3
"""Regressionstests für fail-closed CI- und Workflow-Berechtigungen."""

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def assert_true(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> None:
    ci = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
    assert_true(
        "git ls-files" in ci and "|| true" not in ci,
        "CI-Dateiermittlung muss Git-Fehler propagieren",
    )
    assert_true(
        "< <(git ls-files" not in ci,
        "Exitcodes von git ls-files dürfen nicht in Process-Substitution verloren gehen",
    )

    security = (ROOT / ".github/workflows/security.yml").read_text(encoding="utf-8")
    pr_job = re.search(r"(?ms)^  secrets-pr:\n(?P<body>.*?)(?=^  [a-zA-Z0-9_-]+:|\Z)", security)
    readonly_job = re.search(
        r"(?ms)^  secrets-readonly:\n(?P<body>.*?)(?=^  [a-zA-Z0-9_-]+:|\Z)",
        security,
    )
    assert_true(pr_job is not None, "separater Gitleaks-PR-Job fehlt")
    assert_true(readonly_job is not None, "schreibgeschützter Gitleaks-Job fehlt")
    assert_true(
        "github.event_name == 'pull_request'" in pr_job.group("body")
        and "pull-requests: write" in pr_job.group("body"),
        "PR-Schreibrecht darf nur im Pull-Request-Job liegen",
    )
    assert_true(
        "github.event_name != 'pull_request'" in readonly_job.group("body")
        and "pull-requests: write" not in readonly_job.group("body"),
        "Push-/Schedule-Gitleaks muss ohne PR-Schreibrecht laufen",
    )
    assert_true(
        security.count("pull-requests: write") == 1,
        "pull-requests: write darf nur einmal und nur im PR-Job vorkommen",
    )
    print("ALL WORKFLOW SECURITY TESTS PASSED")


if __name__ == "__main__":
    try:
        main()
    except AssertionError as exc:
        print(f"FAIL: {exc}")
        raise SystemExit(1) from exc
