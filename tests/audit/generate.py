#!/usr/bin/env python3
"""Regenerate docs/workflows/<name>.md by running each workflow against
canonical inputs, capturing verification data, and rendering a hand-written
markdown template with that data filled in.

Usage:
    python3 tests/audit/generate.py                  # regenerate all
    python3 tests/audit/generate.py promoter         # just one
    python3 tests/audit/generate.py promoter intervals
"""
from __future__ import annotations

import importlib
import sys
import traceback
from pathlib import Path

THIS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(THIS_DIR))

from lib import (  # noqa: E402
    DOCS_DIR, RUNS_DIR, TEMPLATES_DIR, REPO_ROOT,
    render_check_table, render_template, overall_verdict, run_header,
)

ALL_WORKFLOWS = ("pair_only", "intervals", "promoter", "elements")


def render_one(name: str) -> bool:
    """Run + verify + render a single workflow's audit. Returns success bool."""
    print(f"=== {name} ===", flush=True)
    try:
        mod = importlib.import_module(f"workflows.{name}")
    except ModuleNotFoundError:
        print(f"  no spec under tests/audit/workflows/{name}.py", file=sys.stderr)
        return False

    runs_dir = RUNS_DIR / name
    runs_dir.mkdir(parents=True, exist_ok=True)

    try:
        data = mod.run(REPO_ROOT, runs_dir)
    except Exception as e:
        print(f"  spec.run() raised: {e}", file=sys.stderr)
        traceback.print_exc()
        return False

    try:
        checks = mod.checks(data)
    except Exception as e:
        print(f"  spec.checks() raised: {e}", file=sys.stderr)
        traceback.print_exc()
        return False

    template_path = TEMPLATES_DIR / f"{name}.md"
    if not template_path.exists():
        print(f"  template missing: {template_path}", file=sys.stderr)
        return False

    # Inject the rendered check table + verdict + run header into the
    # variables dict the template uses for substitution.
    label = data.get("run_label", name)
    rc = data.get("returncode", 0)
    secs = data.get("seconds", 0.0)
    variables = dict(data)
    variables["check_table"] = render_check_table(checks)
    variables["overall_verdict"] = overall_verdict(checks)
    variables["run_header"] = run_header(label, rc, secs)

    rendered = render_template(template_path, variables)
    out_path = DOCS_DIR / f"{name}.md"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(rendered)

    fails = sum(1 for c in checks if c.verdict == "FAIL")
    warns = sum(1 for c in checks if c.verdict == "WARN")
    passes = sum(1 for c in checks if c.verdict == "PASS")
    print(f"  -> {out_path.relative_to(REPO_ROOT)}  "
          f"({passes} pass, {warns} warn, {fails} fail)", flush=True)
    return fails == 0


def main(argv: list[str]) -> int:
    targets = argv[1:] if len(argv) > 1 else list(ALL_WORKFLOWS)
    unknown = [t for t in targets if t not in ALL_WORKFLOWS]
    if unknown:
        print(f"unknown workflow(s): {', '.join(unknown)}", file=sys.stderr)
        print(f"available: {', '.join(ALL_WORKFLOWS)}", file=sys.stderr)
        return 2

    all_ok = True
    for name in targets:
        ok = render_one(name)
        all_ok = all_ok and ok
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
