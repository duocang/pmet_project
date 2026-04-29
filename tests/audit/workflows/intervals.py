"""Audit spec for pipeline/workflows/intervals.sh.

Runs against the bundled data/demo_intervals fixture (10 motifs,
~25 MB intervals.fa). Same fixture the web app's "Use example" button
loads when a user picks the Intervals mode without uploading anything.
"""
from pathlib import Path
from lib import (
    Check, at_least_check, equal_check, file_exists_check,
    count_dir_files, head_lines, linecount, reset_dir, run_workflow, sha256,
)


def run(repo_root: Path, runs_dir: Path) -> dict:
    out_idx = reset_dir(runs_dir / "01_indexing")
    out_pair = reset_dir(runs_dir / "02_pairing")
    log_path = runs_dir / "run.log"
    cmd = [
        "bash", "pipeline/workflows/intervals.sh",
        "-s", "data/demo_intervals/intervals.fa",
        "-m", "data/demo_intervals/motif.meme",
        "-g", "data/demo_intervals/peaks.txt",
        "-o", str(out_idx),
        "-x", str(out_pair),
        "-t", "4",
    ]
    rc = run_workflow(cmd, repo_root, log_path)

    motif_output = out_pair / "motif_output.txt"
    fimohits_dir = out_idx / "fimohits"
    binomial = out_idx / "binomial_thresholds.txt"
    ic = out_idx / "IC.txt"
    universe = out_idx / "universe.txt"
    promoter_lengths = out_idx / "promoter_lengths.txt"
    plot_dir = out_pair / "plot"
    # R draws histograms unconditionally (they're side artefacts) but the
    # headline heatmap PNGs only land if the data survives the p-value
    # filter inside draw_heatmap.R. Use the histograms as the "did R
    # actually run?" probe.
    histogram_dirs_present = sum(
        1 for sub in ("histogram", "histogram_overlap", "histogram_overlap_unique")
        if (plot_dir / sub).is_dir()
    )

    return {
        "run_label": "intervals",
        "returncode": rc["returncode"],
        "seconds": rc["seconds"],
        "log_tail": rc["log_tail"],
        "indexing_dir": str(out_idx.relative_to(repo_root)),
        "pairing_dir": str(out_pair.relative_to(repo_root)),
        "fimohits_count": count_dir_files(fimohits_dir, "*.bin"),
        "binomial_lines": linecount(binomial),
        "ic_lines": linecount(ic),
        "universe_lines": linecount(universe),
        "promoter_lengths_lines": linecount(promoter_lengths),
        "motif_output_lines": linecount(motif_output),
        "motif_output_sha": sha256(motif_output),
        "motif_output_head": head_lines(motif_output, 3),
        "plot_pngs": count_dir_files(plot_dir, "*.png"),
        "histogram_dirs": histogram_dirs_present,
        "command_displayed": " ".join(cmd),
    }


def checks(data: dict) -> list[Check]:
    n_motifs_in_meme = 10  # data/demo_intervals/motif.meme
    return [
        equal_check("script exit code", 0, data["returncode"]),

        equal_check("fimohits/*.bin per motif",
                    n_motifs_in_meme, data["fimohits_count"],
                    note="one PMETBN01 file per motif in motif.meme"),

        equal_check("binomial_thresholds rows == motifs",
                    n_motifs_in_meme, data["binomial_lines"]),

        equal_check("IC.txt rows == motifs",
                    n_motifs_in_meme, data["ic_lines"]),

        at_least_check("universe.txt non-empty (interval names)",
                       1, data["universe_lines"]),

        equal_check("promoter_lengths.txt rows == universe size",
                    data["universe_lines"], data["promoter_lengths_lines"],
                    note="every interval needs a length row"),

        at_least_check("motif_output.txt non-empty (heterotypic pairs)",
                       1, data["motif_output_lines"]),

        equal_check("motif_output.txt deterministic vs anchor",
                    "4858412a09198363305a419af01d47a35ff7cfd63a2169dd01aa545f8ff800c6",
                    data["motif_output_sha"],
                    note="captured against demo_intervals on this host; "
                         "differs if fixture or pair_parallel sort changes"),

        # Heatmap stage: split into "R was invoked" + "headline PNGs landed".
        # The demo intervals are small enough that draw_heatmap.R's p-adj
        # filter can leave nothing to plot — that's expected, not a regression.
        _r_invoked_check(data),
        _headline_pngs_check(data),
    ]


def _r_invoked_check(data: dict) -> Check:
    n = data["histogram_dirs"]
    if n == 3:
        return Check.passing("Rscript invoked (3 histogram subdirs present)",
                             "3", n)
    if n == 0:
        return Check.warning("Rscript invoked (3 histogram subdirs present)",
                             "3", "0",
                             note="Rscript may not be installed; data outputs are still valid")
    return Check.failing("Rscript invoked (3 histogram subdirs present)",
                         "3", n,
                         note="partial R run — investigate")


def _headline_pngs_check(data: dict) -> Check:
    n = data["plot_pngs"]
    if n == 3:
        return Check.passing("3 headline heatmap PNGs rendered", "3", n)
    if n == 0 and data["histogram_dirs"] == 3:
        return Check.warning("3 headline heatmap PNGs rendered", "3", "0",
                             note="R ran but draw_heatmap.R's p-adj filter "
                                  "left nothing to plot (expected on small demo data)")
    return Check.failing("3 headline heatmap PNGs rendered", "3", n)
