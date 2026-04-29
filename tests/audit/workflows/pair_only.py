"""Audit spec for pipeline/workflows/pair_only.sh.

Runs against the bundled data/pairing/demo fixture (a partial Arabidopsis
index with 6 fimohits files matching the AHL12/AHL20 motif family). This
is the same fixture apps/cli/scripts/run_pairing.sh uses, so the audit's
verification anchors to a deterministic small dataset rather than the
full TAIR10 + Franco-Zorrilla index.
"""
from pathlib import Path
from lib import (
    Check, at_least_check, equal_check, file_exists_check,
    head_lines, linecount, reset_dir, run_workflow, sha256,
)


def run(repo_root: Path, runs_dir: Path) -> dict:
    out_dir = reset_dir(runs_dir / "out")
    log_path = runs_dir / "run.log"
    cmd = [
        "bash", "pipeline/workflows/pair_only.sh",
        "-d", "data/pairing/demo",
        "-g", "data/pairing/demo/gene.txt",
        "-o", str(out_dir),
        "-i", "4",
        "-t", "4",
    ]
    rc = run_workflow(cmd, repo_root, log_path)

    motif_output = out_dir / "motif_output.txt"
    pmet_log = out_dir / "pmet.log"
    genes_used = out_dir / "genes_used_PMET.txt"

    return {
        "run_label": "pair_only",
        "returncode": rc["returncode"],
        "seconds": rc["seconds"],
        "log_tail": rc["log_tail"],
        "out_dir": str(out_dir.relative_to(repo_root)),
        "motif_output_path": str(motif_output.relative_to(repo_root)),
        "motif_output_sha": sha256(motif_output),
        "motif_output_lines": linecount(motif_output),
        "motif_output_head": head_lines(motif_output, 3),
        "genes_used_lines": linecount(genes_used),
        "pmet_log_lines": linecount(pmet_log),
        "command_displayed": " ".join(cmd),
    }


def checks(data: dict) -> list[Check]:
    return [
        equal_check("script exit code", 0, data["returncode"]),
        at_least_check("motif_output.txt non-empty", 1, data["motif_output_lines"],
                       note="rows = enriched motif pairs after pair_parallel filtering"),
        equal_check("motif_output deterministic vs anchor",
                    "0af5b936606fd30f3e4989c3658170e93e208d1277fa97882a2e83c130a83d8f",
                    data["motif_output_sha"],
                    note="captured against data/pairing/demo on this host; "
                         "will differ if the fixture changes"),
        at_least_check("genes_used_PMET.txt non-empty",
                       1, data["genes_used_lines"],
                       note="genes from -g that survived the universe filter"),
        at_least_check("pmet.log non-empty",
                       1, data["pmet_log_lines"]),
    ]
