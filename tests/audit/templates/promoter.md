# promoter — full PMET on gene promoters

<<RUN_HEADER>>

**Source:** [`pipeline/workflows/promoter.sh`](../../pipeline/workflows/promoter.sh)
&nbsp;&nbsp;**Used by:** CLI research runs · web `promoters` mode

## Purpose

The canonical PMET pipeline. Given a genome FASTA, a GFF3 annotation,
a MEME motif file, and a gene-cluster list, it asks:

> **Within the promoters of the user's gene clusters, which pairs of
> transcription-factor motifs co-occur more than expected by chance?**

Co-occurrence above null is a fingerprint of TF cooperativity — most TFs
don't bind alone; partner TFs land at neighbouring sites and the
combination drives the regulatory output. PMET uses a binomial test
against an empirically-built null distribution from the indexing stage,
not a generic background.

This script is the longest of the four (~2 minutes wall on TAIR10 +
Franco-Zorrilla at 4 threads, dominated by FIMO scanning the 113-motif
set against ~30k 1 kb promoters).

## Biological setup

- **"Promoter"** here means the user-configurable upstream window of
  the gene's transcription start (default 1000 bp), optionally plus
  the gene's 5' UTR. Overlapping windows from neighbouring genes are
  trimmed so each base is attributed to at most one promoter (controlled
  by `-v NoOverlap`).
- **"Universe"** is every gene that survives the promoter-extraction
  filters (size ≥ 20 bp, valid sequence). This is the null background
  the pair test compares against.
- **"Cluster"** is one row of the gene-list file: `<cluster_label>
  <gene_id>`. Each cluster is tested independently for pair enrichment.

The deeper biology and stage-by-stage construction of the promoter set
is documented separately in
[`docs/methods/promoter-extraction.md`](../methods/promoter-extraction.md).

## What the script does, step by step

| # | Stage | What runs | Why |
|---|---|---|---|
| 1 | Argument + binary preflight | locate `build/{index_fimo_fused, pair_parallel}` | Single failure point if either binary is missing |
| 2 | TAIR10 fetch (if absent) | `bash pipeline/data/fetch_tair10.sh` | One-shot ~220 MB download; subsequent runs find the file and skip |
| 3 | Chromosome-name preflight | compare GFF3 first chrom vs FASTA first header | Catches the `'1'` vs `'Chr1'` mismatch that silently produces empty BED downstream — quick fail beats a 2-minute "everything succeeded but indexed nothing" run |
| 4 | Homotypic indexing | `pipeline/python/run_homotypic.py` (delegates: `gff3sort` → BED → bedtools flank → fasta extract → IC.txt → `index_fimo_fused`) | The expensive scan; produces the universe + per-motif binary fimohits + per-motif binomial thresholds. See [`pipeline/python/run_homotypic.py`](../../pipeline/python/run_homotypic.py) for the chain |
| 5 | Heterotypic gene filter | `grep -wFf universe.txt <gene_list>` | Drop user-list genes that aren't in the indexed universe (no promoter passed extraction) |
| 6 | Pair test | `build/pair_parallel -d <homotypic> -g <kept> ...` → temp shards | Per-cluster binomial pair enrichment |
| 7 | Shard aggregation | `cat temp*.txt > motif_output.txt` then `rm temp*.txt` | pair_parallel doesn't unify shards itself |
| 8 | Heatmaps (optional) | three `Rscript pipeline/r/draw_heatmap.R` calls | Skipped silently if `Rscript` is absent |

## Run snapshot

This audit just ran:

```
<<COMMAND_DISPLAYED>>
```

Indexing landed at `<<HOMOTYPIC_DIR>>/`,
pairing at `<<HETEROTYPIC_DIR>>/`,
plots at `<<PLOT_DIR>>/`.

### Indexing-stage outputs

| File | Rows / count | Meaning |
|---|---|---|
| `fimohits/*.bin` | <<FIMOHITS_COUNT>> files | one PMETBN01 file per motif (113 in Franco-Zorrilla) |
| `binomial_thresholds.txt` | <<BINOMIAL_LINES>> rows | per-motif p-value cutoff for `--topn 5000` |
| `IC.txt` | <<IC_LINES>> rows | per-motif positional information content |
| `universe.txt` | <<UNIVERSE_LINES>> rows | every gene with a valid extracted promoter |
| `promoter_lengths.txt` | <<PROMOTER_LENGTHS_LINES>> rows | should equal `universe.txt` rows |

### Pairing-stage output preview

`motif_output.txt` first 3 rows (cluster ⟶ motif1 ⟶ motif2 ⟶ ...):

```
<<MOTIF_OUTPUT_HEAD>>
```

Total enriched pair rows: **<<MOTIF_OUTPUT_LINES>>** — these are the
per-cluster motif pairs that survived pair_parallel's binomial test
at the canonical IC and FIMO thresholds.

## Verification

<<OVERALL_VERDICT>>

<<CHECK_TABLE>>

### Reproducing this audit

```bash
python3 tests/audit/generate.py promoter
```

The motif_output.txt sha anchor `4b24906a...` was independently
verified against the recorded `cli/03_promoter.sh` baseline (cf.
commit `d2663c0`'s message). pair_only.sh against this same homotypic
index produces the same sha — that's the cross-validation that ties
the pair_only audit to the promoter audit.

### Cost

This run took **<<SECONDS>>s** at 4 threads. The dominant cost is
stage 4 (FIMO scanning 113 motifs across ~30k 1 kb promoters); pair
testing in stage 6 takes <30s of that.
