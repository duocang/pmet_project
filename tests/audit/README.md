# tests/audit

Generates the per-workflow audit docs at [`docs/workflows/`](../../docs/workflows/)
by **actually running each workflow** against canonical inputs and
filling a hand-written markdown template with verification data
captured from that run.

## Layout

```
tests/audit/
├── generate.py           driver: python3 tests/audit/generate.py [<name> ...]
├── lib.py                shared helpers (sha, run, render check table, …)
├── workflows/            one spec per workflow
│   ├── pair_only.py
│   ├── intervals.py
│   ├── promoter.py
│   └── elements.py
├── templates/            one markdown template per workflow
│   ├── pair_only.md      (uses <<PLACEHOLDER>> slots that the spec fills in)
│   ├── intervals.md
│   ├── promoter.md
│   └── elements.md
└── runs/                 each spec runs into runs/<name>/ (gitignored — see below)
```

Output lands at `docs/workflows/<name>.md`, which IS committed.

## How a single audit works

Each spec under `workflows/<name>.py` exports two functions:

```python
def run(repo_root: Path, runs_dir: Path) -> dict:
    """Execute the workflow against canonical inputs.
    Return a dict whose keys feed BOTH the verification checks and
    the template <<PLACEHOLDER>> substitutions."""

def checks(data: dict) -> list[Check]:
    """Render the verification table from the run dict."""
```

The driver:

1. Imports `workflows.<name>`, calls `spec.run()`. The workflow executes
   in a clean `runs/<name>/` subdir.
2. Calls `spec.checks(data)`. Each check produces a `(name, expected,
   actual, verdict)` row — verdicts are `PASS`, `FAIL`, or `WARN`.
3. Reads `templates/<name>.md`, substitutes every `<<KEY>>`
   placeholder with the corresponding `data[key]`. Two synthetic
   placeholders are always available: `<<CHECK_TABLE>>` (the rendered
   markdown table) and `<<OVERALL_VERDICT>>` (the one-line summary).
4. Writes the rendered markdown to `docs/workflows/<name>.md`.

## Running

```bash
python3 tests/audit/generate.py                  # all four
python3 tests/audit/generate.py promoter         # just one
python3 tests/audit/generate.py promoter intervals  # any subset
```

Wall time: pair_only ~15s, intervals ~16s, promoter ~2 min, elements ~5 min.

## Anchors and determinism

Some checks (`motif_output.txt deterministic vs anchor`) compare an
actual SHA-256 against a hard-coded "anchor" string captured on this
machine. These are **regression sentinels**: if the workflow's
implementation drifts, the SHA changes and the check FAILs. To bless
a new SHA after an intentional change, edit the anchor in the spec.

The anchors currently committed:

| workflow | anchor file | sha (first 16) |
|---|---|---|
| pair_only | `data/pairing/demo` → `motif_output.txt` | `0af5b936606fd3` |
| intervals | `data/demo_intervals` → `motif_output.txt` | `4858412a091983` |
| promoter | TAIR10 + Franco-Zorrilla → `motif_output.txt` | `4b24906abfe55e` |
| elements | (no anchor — output varies per run on TAIR10 due to a known C-engine non-determinism documented in `tests/baseline/README.md`; the audit verifies structure + counts instead) |

## Adding a workflow

1. Create `tests/audit/workflows/<name>.py` with `run()` and `checks()`.
2. Create `tests/audit/templates/<name>.md` with `<<PLACEHOLDER>>` slots
   for everything `run()` returns. Always include `<<CHECK_TABLE>>` and
   `<<OVERALL_VERDICT>>`.
3. Add `<name>` to `ALL_WORKFLOWS` in `generate.py`.
4. Run `python3 tests/audit/generate.py <name>` and verify the output
   markdown reads cleanly + every `<<UNRESOLVED:KEY>>` is gone.

## Why not pytest

The audit's purpose is **a human-readable, reviewable narrative** of
each workflow — purpose, biology, design intuition, observed results —
not a one-shot pass/fail signal. pytest would conflate the
verification checks with what's really a documentation generator. The
workflow audit and the regression baseline (`tests/baseline/`) live
side-by-side: the baseline is the machine-readable fingerprint set,
the audit is the prose explanation of what those fingerprints encode.

## What's NOT audited here

- `pipeline/workflows/cli/05_promoter_gap.sh` and the perf benchmarks
  (`01_perf_cpu`, `02_perf_params`) — these are research/perf scripts
  with one or two known callers; adding them to the audit is mechanical
  but low-priority.
- `apps/cli/scripts/*` (the lower-level `run_indexing.sh` /
  `run_pairing.sh` etc) — already covered by `tests/baseline/` which
  hashes their outputs against an anchor.
- `apps/pmet_backend/test_api.py` — covered separately by `pytest`
  inside the backend's docker image.
