# elements — full PMET on a chosen genomic element (UTR / CDS / mRNA / exon)

_Audit refreshed 2026-04-29 11:42:12 UTC on this machine — workflow `elements`, exit 0, 163.9s_

**Source:** [`pipeline/workflows/elements.sh`](../../pipeline/workflows/elements.sh)
&nbsp;&nbsp;**Helper sub-workflow:** [`pipeline/workflows/cli/_pmet_index_element.sh`](../../pipeline/workflows/cli/_pmet_index_element.sh)
&nbsp;&nbsp;**Used by:** CLI research runs only (no web entry point)

## Purpose

Same shape as `promoter.sh` — homotypic indexing then heterotypic
pair test then heatmaps — but the indexed unit is **a chosen genomic
element** rather than the canonical 1 kb upstream window. Useful when:

- You're asking whether motif pair-enrichment patterns differ between
  promoters, 5' UTRs, CDS, and exons. (They do — TF binding partners
  in 5' UTRs are not the same set as in promoters.)
- The species you care about has unusual gene architecture and
  "promoter = 1 kb upstream" is a poor model.
- You want to compare longest-isoform vs all-isoforms-merged
  aggregation strategies (the `-s` flag).

This is a **research workflow**, not exposed in the web UI.

## Biological setup

For each gene, multiple isoforms typically share a transcription start
but can have different element boundaries (e.g. 5' UTR length varies
across splice variants). Two strategies:

- **`-s longest`** — pick the single isoform whose total element span
  is greatest, keep every fragment of that isoform. For `-e mRNA -m No`
  also subtracts that isoform's UTRs to leave CDS-spanning fragments.
- **`-s merged`** — take the per-gene UNION of all isoforms' element
  intervals (overlapping intervals merged into a non-redundant set).
  No isoform specificity, no UTR subtraction.

Both strategies typically produce multiple intervals per gene
(e.g. 3 exons → 3 intervals). The script tags each interval as
`__GENE__N` (gene name + 1-based index) so FIMO can scan them
separately, then a **gene-level fold** in step 9 collapses per-interval
hits back to per-gene rows so pair_parallel sees one row per gene.

## What the script does, step by step

| # | Stage | What runs | Why |
|---|---|---|---|
| 1 | Argument + element prompt | `-s longest\|merged`, `-e 3UTR\|5UTR\|mRNA\|CDS\|exon` | Strategy + element are the two axes |
| 2 | TAIR10 fetch (if absent) | `bash pipeline/data/fetch_tair10.sh` | One-shot download |
| 3 | Chromosome-name preflight | GFF3 first chrom vs FASTA first header | Same fail-fast as `promoter.sh` |
| 4 | Element BED extraction | `cli/_pmet_index_element.sh` step 1 — awk over GFF3 column 3 | Filters rows where `feature == element` and pulls `<key>=<id>` from the attributes column |
| 5 | Isoform aggregation | `cli/_pmet_index_element.sh` step 2 — `longest`/`merged` branch | See "biological setup". `longest` picks per gene + may subtract UTRs; `merged` does `bedtools merge` per gene |
| 6 | Interval tagging + length filter | append `__GENE__N`, drop fragments < 30 bp | The tag survives FIMO scanning so step 9 can demangle |
| 7 | Promoter FASTA + universe + lengths | `bedtools getfasta` → `promoter.fa`; `cut -f1` → `universe.txt`; per-interval lengths | Standard indexing inputs |
| 8 | FIMO + indexing | one `index_fimo_fused` call (OpenMP) | Replaces the older two-step (split MEME → parallel fimo → separate pmet indexer) flow that depended on PMET-patched `--topn`/`--topk` flags absent from upstream MEME's `fimo`. See commit `d2663c0` |
| 9 | **Gene-level fold** | `pipeline/python/collapse_element_fimohits.py` | Decodes PMETBN01 binary fimohits, strips `__GENE__N` from sequence names, groups hits by gene, keeps top-`maxk` per gene by ascending p-value, filters against the per-motif binomial threshold, re-encodes. Also normalizes `binomial_thresholds.txt` motif IDs to upper-case to match IC.txt and the fimohits filenames |
| 10 | Indexing contract validation | `pipeline/python/check_homotypic_contract.py <homotypic>` | Catches motif-id case mismatches and missing files |
| 11 | Heterotypic loop over `data/genes/*.txt` | for each task: filter by universe → `pair_parallel` → optional heatmaps | Per-task `02_heterotypic_<task>/motif_output.txt`. Heatmap failures (e.g. ggsave's 50-inch dimension cap on huge tasks) are non-fatal — the loop continues |

## Run snapshot

This audit just ran:

```
bash pipeline/workflows/elements.sh -s longest -e 5UTR -t 4
```

Output root: `results/elements_longest_five_prime_UTR/`.

### Indexing-stage outputs

| File | Rows / count | Meaning |
|---|---|---|
| `01_homotypic/fimohits/*.bin` | 113 files | one PMETBN01 file per motif (113 in Franco-Zorrilla) |
| `01_homotypic/binomial_thresholds.txt` | 113 rows | per-motif p-value cutoff (case-normalized by the collapse step) |
| `01_homotypic/IC.txt` | 113 rows | per-motif positional information content |
| `01_homotypic/universe.txt` | 22733 rows | every gene with a valid 5'UTR |
| `01_homotypic/promoter_lengths.txt` | 22733 rows | should equal `universe.txt` rows after gene-level fold |

### Heterotypic per-task summary

The script loops over every `data/genes/*.txt` file. Per-task results:

| task | motif_output rows | sha (16) |
|---|---|---|
| `gene_cortex_epidermis_pericycle` | 18985 | `821f00782d42e230` |
| `genes_cell_type_treatment` | 37969 | `0c9ca861133e4401` |
| `heat_top300` | 12657 | `8cb976813f466199` |
| `random_genes_300` | 25313 | `325fc7241b23055d` |
| `random_genes_topN` | 189841 | `3bf2de6907d611f7` |
| `salt_top300` | 12657 | `8769c45243a01df2` |

(`missing` rows = the gene list had zero overlap with the 5'UTR
universe, so the script skipped pair_parallel for that task — that's
expected biology, not a failure.)

Total enriched pair rows across all tasks: **297422**.

## Verification

✅ **PASS** — all 9 check(s) passed

| # | Check | Expected | Observed | Verdict |
|---|---|---|---|---|
| 1 | script exit code | `0` | `0` | ✅ PASS |
| 2 | fimohits/*.bin per motif | `113` | `113` | ✅ PASS |
| 3 | binomial_thresholds rows == motifs | `113` | `113` | ✅ PASS |
| 4 | IC.txt rows == motifs | `113` | `113` | ✅ PASS |
| 5 | universe.txt non-empty (genes with 5'UTR) | `>= 1` | `22733` | ✅ PASS — TAIR10 has ~22k genes with annotated 5' UTRs |
| 6 | promoter_lengths.txt rows == universe (post-collapse) | `22733` | `22733` | ✅ PASS — collapse_element_fimohits.py also folds the per-interval promoter_lengths into per-gene sums |
| 7 | one heterotypic dir per gene list | `6` | `6` | ✅ PASS — data/genes/*.txt globbed — bump n_gene_lists in spec if you add/remove files |
| 8 | at least 1 task produced motif_output | `>= 1` | `6` | ✅ PASS — some gene lists have zero overlap with the 5'UTR universe; that's biology, not failure |
| 9 | total enriched pair rows across tasks | `>= 1000` | `297422` | ✅ PASS — lower bound; current canonical run yields ~106k rows total |

### Reproducing this audit

```bash
python3 tests/audit/generate.py elements
```

This audit deliberately uses `-s longest -e 5UTR` (smallest element by
universe size) for fast iteration. To audit the merged strategy or a
larger element, the spec needs another invocation; the architecture
verification (FIMO + collapse + pair) is identical regardless of which
strategy/element pair runs.

### Known limitation

R `ggsave` enforces a hard 50-inch dimension cap. Some gene tasks
(e.g. `random_genes_topN`'s ~190k motif-pair output) blow past that
and the heatmap step exits non-zero for that task. `elements.sh`
catches this with `|| print_orange "..."` so a single heatmap failure
doesn't take down the rest of the loop — the data outputs
(`motif_output.txt`) for that task are unaffected.
