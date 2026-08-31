#!/usr/bin/env python3
"""Regressionstests für fail-closed CI- und Workflow-Berechtigungen."""

import itertools
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def assert_true(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> None:
    workflow_dir = ROOT / ".github/workflows"
    workflow_texts = {
        path.name: path.read_text(encoding="utf-8")
        for path in itertools.chain(
            workflow_dir.glob("*.yml"),
            workflow_dir.glob("*.yaml"),
        )
    }
    for workflow_name, workflow in workflow_texts.items():
        action_refs = re.findall(r"(?m)^\s*uses:\s*[^@\s]+@([^\s#]+)", workflow)
        assert_true(
            all(re.fullmatch(r"[0-9a-f]{40}", ref) for ref in action_refs),
            f"{workflow_name}: alle Actions müssen auf vollständige SHAs gepinnt sein",
        )
        checkout_count = len(re.findall(r"(?m)^\s*uses:\s*actions/checkout@", workflow))
        assert_true(
            workflow.count("persist-credentials: false") == checkout_count,
            f"{workflow_name}: jeder Checkout muss persist-credentials deaktivieren",
        )

    ci = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
    assert_true(
        "git ls-files" in ci and "|| true" not in ci,
        "CI-Dateiermittlung muss Git-Fehler propagieren",
    )
    assert_true(
        "< <(git ls-files" not in ci,
        "Exitcodes von git ls-files dürfen nicht in Process-Substitution verloren gehen",
    )
    assert_true(
        ci.count("git ls-files -z") == 5
        and ci.count("mapfile -d '' -t files") == 5,
        "CI-Dateilisten müssen nullsicher verarbeitet werden",
    )
    assert_true(
        "loadfile('$file')" not in ci,
        "Lua-Syntaxcheck darf Dateipfade nicht in Lua-Quelltext interpolieren",
    )
    assert_true(
        'LUA_FILE="${file}" lua -e \'assert(loadfile(os.getenv("LUA_FILE")))\''
        in ci,
        "Lua-Syntaxcheck darf geprüfte Dateien nicht ausführen",
    )

    security = (ROOT / ".github/workflows/security.yml").read_text(encoding="utf-8")
    assert_true(
        "git ls-files '*.py' || true" not in security,
        "Security-Dateiermittlung muss Git-Fehler propagieren",
    )
    assert_true(
        "python3 -m pip install bandit==1.9.4" in security,
        "Bandit muss auf die aktuelle geprüfte Version festgelegt sein",
    )
    assert_true(
        'git ls-files -z \'*.py\'' in security
        and 'bandit -q "${files[@]}"' in security,
        "Bandit muss exakt alle getrackten Python-Dateien nullsicher scannen",
    )
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
