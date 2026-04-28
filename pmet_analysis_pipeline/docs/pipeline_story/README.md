# PMET Pipeline Execution Audit (Story Pack)

This folder is a step-by-step bioinformatics audit of the active PMET
pipelines:

| Doc | Pipeline script | Purpose |
| --- | --- | --- |
| [03_promoter.md](03_promoter.md) | `scripts/pipeline/03_promoter.sh` | Standard promoter PMET on TAIR10 |
| [04_intervals.md](04_intervals.md) | `scripts/pipeline/04_intervals.sh` | Interval-based PMET (no GFF3) |
| [05_promoter_gap.md](05_promoter_gap.md) | `scripts/pipeline/05_promoter_gap.sh` | Promoter PMET with TSS-proximal gap |
| [06_elements_longest.md](06_elements_longest.md) | `scripts/pipeline/06_elements_longest.sh` | Genomic-element PMET on the longest isoform |
| [07_elements_merged.md](07_elements_merged.md) | `scripts/pipeline/07_elements_merged.sh` | Genomic-element PMET on per-gene UNION |

It is **not** a runtime log. Each pipeline gets a Markdown that walks
every stage and records:

- the command or code path that ran;
- what it was supposed to do (purpose / biology);
- what its inputs and outputs look like (truncated samples);
- the structural / scientific properties expected of the output;
- whether the observed output satisfied them, with a verdict.

Verdicts are a small fixed vocabulary:

- **PASS** — output exists and matches every expected property.
- **WARNING** — output exists but has a documented caveat, or a check
  that depends on data we did not inspect.
- **FAIL** — output is missing, malformed, or violates an expected
  property; needs a fix.
- **NOT CHECKED** — the step was not exercised in this audit; the doc
  states why and what would be required to verify.

## Audit method

1. Read the pipeline script and any helpers it `source`s.
2. Use the pipeline's existing baseline outputs under `results/<NN>_*`.
   Re-run only the cheap downstream stages (heterotypic + heatmap) when
   the baseline lacks them, never the full homotypic stage.
3. For sub-pipeline-internal artefacts (intermediate BED/FASTA that
   the pipeline cleans up by default), re-derive them in a sandbox at
   `results/pipeline_story/` using the same Python entrypoint
   (`scripts/python/run_homotypic.py --keep-intermediate`).
4. Sample inputs/outputs and check structural invariants with `awk`,
   `samtools`, `bedtools`, `find`, `wc`, `shasum`.

No pipeline source code was modified. No baseline hash file was
overwritten. The sandbox at `results/pipeline_story/` is gitignored
(under `results/`) and exists only so the audit can reference real BED
coordinates without needing to re-run the full pipeline.

## Run environment

| | |
| --- | --- |
| OS | Darwin 24.6.0 (macOS, arm64) |
| Shell | zsh, /bin/bash 3.2 in scripts |
| Python | 3.14.3 |
| Rscript | 4.5.2 (2025-10-31) |
| samtools | 1.23 |
| bedtools | v2.31.1 |
| Branch | dev |

Genome reference: `data/TAIR10.fasta` (chromosomes `1..5,Mt,Pt`,
unwrapped via `samtools faidx`).

Annotation: `data/TAIR10.gff3` (32833 GFF3 rows match `gene$`, of which
27655 are canonical `gene`).

Motif file: `data/Franco-Zorrilla_et_al_2014.meme` — 113 motifs
(`grep -c '^MOTIF'`).

## Common output contract

Every homotypic stage must populate `<homotypic_output>/`:

- `universe.txt` — one gene id per line.
- `promoter_lengths.txt` — `<gene_id>\t<int_length>` (FIMO sequence id
  for 04 and the per-interval indexer; gene id elsewhere).
- `binomial_thresholds.txt` — `<motif>\t<float_threshold>\t...`.
- `IC.txt` — `<motif> <ic1> <ic2> ...`.
- `fimohits/<motif>.txt` — FIMO TSV per motif.

`universe.txt` and the gene set of `promoter_lengths.txt` must be
identical; the count of `fimohits/*.txt` must equal the count of
`MOTIF` lines in the input MEME. These two contract checks are run by
`scripts/python/check_homotypic_contract.py`, which the pipelines call
at the end of the homotypic stage.

The heterotypic stage must produce `motif_output.txt` — the
11-column PMET TSV consumed by `scripts/r/draw_heatmap.R` and
`scripts/r/process_pmet_result.R`.

The plotting stage produces three PNGs:

- `heatmap.png` (mode `All`)
- `heatmap_overlap.png` (mode `Overlap`, `unique=FALSE`)
- `heatmap_overlap_unique.png` (mode `Overlap`, `unique=TRUE`)

## Truncation rules

To keep this audit readable:

- Text files: ≤ 10 first lines.
- FASTA: ≤ 2 records, sequence trimmed to the first ~60 bp.
- BED / GFF3: 5 first rows + a one-line column legend.
- FIMO hits: 5 first rows + column legend.
- Large tables: row count, column count, ≤ 5 first rows.
- PNG: never inlined; recorded as path + size + SHA-256.

## Reproducing the audit

The audit uses two driver scripts under `scripts/pipeline_story/`:

- `story_03_05_homotypic_sandbox.sh` — re-runs only the
  homotypic stage of pipelines 03 and 05 to a sandbox directory with
  `--keep-intermediate`, so intermediate BED/FASTA are inspectable
  without disturbing the canonical baseline.
- `story_03_heterotypic_replay.sh` — re-runs only the heterotypic +
  heatmap stages of pipeline 03 against an existing homotypic baseline
  (used because the canonical 03 baseline directory had been pruned to
  homotypic-only at audit time).

Neither script modifies a tracked baseline, and neither alters the
pipelines. They are diagnostic helpers for this audit only.
