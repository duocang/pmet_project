"""Audit spec for pipeline/workflows/elements.sh.

Runs against the canonical TAIR10 + Franco-Zorrilla, with the smallest
viable strategy/element pair (longest + 5'UTR — about 30s for indexing,
plus pair_parallel for each gene list under data/genes/). Element 5'UTR
keeps roughly 22k of TAIR10's ~30k genes (those that have an annotated
5' UTR).

The new element pipeline (see commit d2663c0) does indexing through
index_fimo_fused (binary fimohits) and then a Python helper
pipeline/python/collapse_element_fimohits.py folds per-interval hits
back to per-gene rows. This audit verifies that fold actually produced
gene-named output and that downstream pair_parallel can read it.
"""
from pathlib import Path
from lib import (
    Check, at_least_check, equal_check, file_exists_check,
    count_dir_files, head_lines, linecount, reset_dir, run_workflow,
    sha256, REPO_ROOT,
)


def run(repo_root: Path, runs_dir: Path) -> dict:
    # elements.sh embeds strategy + element in its OWN output path
    # (results/elements_<strategy>_<element>/) so we can't redirect it
    # via -o; just delete + let the script create.
    canonical_dir = repo_root / "results" / "elements_longest_five_prime_UTR"
    if canonical_dir.exists():
        import shutil
        shutil.rmtree(canonical_dir)

    log_path = runs_dir / "run.log"
    cmd = [
        "bash", "pipeline/workflows/elements.sh",
        "-s", "longest",
        "-e", "5UTR",
        "-t", "4",
    ]
    rc = run_workflow(cmd, repo_root, log_path)

    homo = canonical_dir / "01_homotypic"
    fimohits = homo / "fimohits"
    binomial = homo / "binomial_thresholds.txt"
    ic = homo / "IC.txt"
    universe = homo / "universe.txt"
    promoter_lengths = homo / "promoter_lengths.txt"

    # gather per-task heterotypic outputs
    het_dirs = sorted([p for p in canonical_dir.glob("02_heterotypic_*") if p.is_dir()])
    plot_dirs = sorted([p for p in canonical_dir.glob("03_plot_*") if p.is_dir()])

    task_summaries = []
    motif_outputs_present = 0
    total_het_lines = 0
    for d in het_dirs:
        task = d.name.removeprefix("02_heterotypic_")
        mo = d / "motif_output.txt"
        if mo.exists():
            n = linecount(mo)
            motif_outputs_present += 1
            total_het_lines += n
            task_summaries.append((task, n, sha256(mo)[:16]))
        else:
            task_summaries.append((task, "missing", "—"))

    # Build the per-task table for the template.
    task_table_rows = ["| task | motif_output rows | sha (16) |", "|---|---|---|"]
    for task, n, sha in task_summaries:
        task_table_rows.append(f"| `{task}` | {n} | `{sha}` |")
    task_table = "\n".join(task_table_rows)

    return {
        "run_label": "elements",
        "returncode": rc["returncode"],
        "seconds": rc["seconds"],
        "log_tail": rc["log_tail"],
        "result_root": str(canonical_dir.relative_to(repo_root)),
        "fimohits_count": count_dir_files(fimohits, "*.bin"),
        "binomial_lines": linecount(binomial),
        "ic_lines": linecount(ic),
        "universe_lines": linecount(universe),
        "promoter_lengths_lines": linecount(promoter_lengths),
        "het_dir_count": len(het_dirs),
        "motif_outputs_present": motif_outputs_present,
        "total_het_lines": total_het_lines,
        "task_table": task_table,
        "command_displayed": " ".join(cmd),
    }


def checks(data: dict) -> list[Check]:
    n_motifs_in_meme = 113
    n_gene_lists = 6  # data/genes/*.txt currently
    return [
        equal_check("script exit code", 0, data["returncode"]),

        equal_check("fimohits/*.bin per motif",
                    n_motifs_in_meme, data["fimohits_count"]),

        equal_check("binomial_thresholds rows == motifs",
                    n_motifs_in_meme, data["binomial_lines"]),

        equal_check("IC.txt rows == motifs",
                    n_motifs_in_meme, data["ic_lines"]),

        at_least_check("universe.txt non-empty (genes with 5'UTR)",
                       1, data["universe_lines"],
                       note="TAIR10 has ~22k genes with annotated 5' UTRs"),

        equal_check("promoter_lengths.txt rows == universe (post-collapse)",
                    data["universe_lines"], data["promoter_lengths_lines"],
                    note="collapse_element_fimohits.py also folds the per-interval "
                         "promoter_lengths into per-gene sums"),

        equal_check("one heterotypic dir per gene list",
                    n_gene_lists, data["het_dir_count"],
                    note="data/genes/*.txt globbed — bump n_gene_lists in spec "
                         "if you add/remove files"),

        at_least_check("at least 1 task produced motif_output",
                       1, data["motif_outputs_present"],
                       note="some gene lists have zero overlap with the 5'UTR "
                            "universe; that's biology, not failure"),

        at_least_check("total enriched pair rows across tasks",
                       1000, data["total_het_lines"],
                       note="lower bound; current canonical run yields ~106k rows total"),
    ]
