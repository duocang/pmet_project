"""Shared helpers for tests/audit/ workflow audit generation.

Each workflow under tests/audit/workflows/<name>.py defines:

  RUN_LABEL     short string used for the run subdirectory and headings
  TEMPLATE      filename under tests/audit/templates/
  def run(repo_root: Path, runs_dir: Path) -> dict:
      Execute the workflow against canonical inputs and return a flat
      dict of (str, anything) — the keys feed both the verification
      checks and the template substitutions.

  def checks(data: dict) -> list[Check]:
      The list of expected-vs-observed assertions to render in the
      audit's verification table.

The driver (generate.py) renders the template with the data dict and
the checks table, then writes the result to docs/workflows/<name>.md.
"""
from __future__ import annotations

import hashlib
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
RUNS_DIR = REPO_ROOT / "tests" / "audit" / "runs"
TEMPLATES_DIR = REPO_ROOT / "tests" / "audit" / "templates"
DOCS_DIR = REPO_ROOT / "docs" / "workflows"


# ---------------------------------------------------------------------------
# Verification check primitives
# ---------------------------------------------------------------------------
@dataclass
class Check:
    name: str
    expected: str
    actual: str
    verdict: str  # "PASS" | "FAIL" | "WARN"
    note: str = ""

    @classmethod
    def passing(cls, name, expected, actual="ok", note=""):
        return cls(name, str(expected), str(actual), "PASS", note)

    @classmethod
    def failing(cls, name, expected, actual, note=""):
        return cls(name, str(expected), str(actual), "FAIL", note)

    @classmethod
    def warning(cls, name, expected, actual, note=""):
        return cls(name, str(expected), str(actual), "WARN", note)


def equal_check(name: str, expected, actual, note: str = "") -> Check:
    if str(expected) == str(actual):
        return Check.passing(name, expected, actual, note)
    return Check.failing(name, expected, actual, note)


def at_least_check(name: str, lower_bound: int, actual: int, note: str = "") -> Check:
    if actual >= lower_bound:
        return Check.passing(name, f">= {lower_bound}", actual, note)
    return Check.failing(name, f">= {lower_bound}", actual, note)


def file_exists_check(name: str, path: Path, must_be_nonempty: bool = True) -> Check:
    if not path.exists():
        return Check.failing(name, "exists", "missing")
    if must_be_nonempty and path.stat().st_size == 0:
        return Check.failing(name, "non-empty", "empty (0 bytes)")
    size = path.stat().st_size
    return Check.passing(name, "non-empty" if must_be_nonempty else "exists",
                         f"{size:,} bytes")


# ---------------------------------------------------------------------------
# Subprocess + file inspection helpers
# ---------------------------------------------------------------------------
def run_workflow(cmd: list[str], cwd: Path, log_path: Path) -> dict:
    """Run a workflow command, time it, capture full output to log_path.

    Returns a dict with `returncode`, `seconds`, `log_tail` (last 12 lines).
    Raises RuntimeError if the workflow exits non-zero — callers can
    catch and embed the failure into the audit instead of crashing the
    whole generator.
    """
    log_path.parent.mkdir(parents=True, exist_ok=True)
    start = time.monotonic()
    with log_path.open("w") as fh:
        proc = subprocess.run(cmd, cwd=cwd, stdout=fh, stderr=subprocess.STDOUT)
    elapsed = time.monotonic() - start
    log_text = log_path.read_text(errors="replace")
    return {
        "returncode": proc.returncode,
        "seconds": elapsed,
        "log_tail": "\n".join(log_text.splitlines()[-12:]),
    }


def sha256(path: Path) -> str:
    """16-char SHA-256 prefix (full hash too noisy for the audit table)."""
    if not path.exists() or not path.is_file():
        return "missing"
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def linecount(path: Path) -> int:
    if not path.exists():
        return 0
    n = 0
    with path.open("rb") as fh:
        for _ in fh:
            n += 1
    return n


def head_lines(path: Path, n: int = 3) -> str:
    if not path.exists():
        return "(missing)"
    out = []
    with path.open("r", errors="replace") as fh:
        for i, line in enumerate(fh):
            if i >= n:
                break
            out.append(line.rstrip())
    return "\n".join(out)


def filesize_human(path: Path) -> str:
    if not path.exists():
        return "missing"
    n = path.stat().st_size
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} TB"


def count_dir_files(path: Path, glob: str = "*") -> int:
    if not path.is_dir():
        return 0
    return sum(1 for p in path.glob(glob) if p.is_file())


def reset_dir(path: Path) -> Path:
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)
    return path


# ---------------------------------------------------------------------------
# Template rendering
# ---------------------------------------------------------------------------
def render_check_table(checks: list[Check]) -> str:
    """Format a list of Check into a markdown table."""
    if not checks:
        return "_(no checks recorded)_"
    badge = {"PASS": "✅ PASS", "FAIL": "❌ FAIL", "WARN": "⚠️ WARN"}
    rows = ["| # | Check | Expected | Observed | Verdict |",
            "|---|---|---|---|---|"]
    for i, c in enumerate(checks, 1):
        note_part = f" — {c.note}" if c.note else ""
        rows.append(f"| {i} | {c.name} | `{c.expected}` | `{c.actual}` | {badge[c.verdict]}{note_part} |")
    return "\n".join(rows)


def render_template(template_path: Path, variables: dict[str, str]) -> str:
    """Substitute <<KEY>> placeholders in a markdown template.

    Keys are case-insensitive on the placeholder side: <<MOTIF_OUTPUT_SHA>>
    looks up `motif_output_sha` (lowercased) in `variables`. Any
    unsubstituted placeholder is left as `<<UNRESOLVED:KEY>>` so it
    surfaces in review rather than silently rendering empty.
    """
    text = template_path.read_text()
    import re
    PLACEHOLDER = re.compile(r"<<([A-Z0-9_]+)>>")

    def sub(match: re.Match) -> str:
        key = match.group(1).lower()
        if key in variables:
            return str(variables[key])
        return f"<<UNRESOLVED:{match.group(1)}>>"

    return PLACEHOLDER.sub(sub, text)


def overall_verdict(checks: list[Check]) -> str:
    fails = sum(1 for c in checks if c.verdict == "FAIL")
    warns = sum(1 for c in checks if c.verdict == "WARN")
    passes = sum(1 for c in checks if c.verdict == "PASS")
    if fails:
        return f"❌ **FAIL** — {fails} check(s) failed, {warns} warning(s), {passes} pass(es)"
    if warns:
        return f"⚠️ **PASS WITH WARNINGS** — {warns} warning(s), {passes} pass(es)"
    return f"✅ **PASS** — all {passes} check(s) passed"


# ---------------------------------------------------------------------------
# Convenience: stamp the run header
# ---------------------------------------------------------------------------
def run_header(label: str, returncode: int, seconds: float) -> str:
    """One-line "ran on <date>, exit=N, took Xs" stamp."""
    import datetime as _dt
    timestamp = _dt.datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC")
    rc_part = f"exit {returncode}" if returncode != 0 else "exit 0"
    return f"_Audit refreshed {timestamp} on this machine — workflow `{label}`, {rc_part}, {seconds:.1f}s_"
