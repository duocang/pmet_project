# Homotypic Output Contract

The "homotypic stage" of every PMET pipeline produces a directory of artefacts
that the downstream heterotypic binary (`build/pair_parallel`,
`build/pmetParallel`, `build/pmet`) consumes. The schema below is the source
of truth — `scripts/python/check_homotypic_contract.py` enforces it; any
refactor that touches stage A must keep the contract intact.

The contract is *flat*: five files at the top of `$homotypic_output/`, plus
one subdirectory `fimohits/`. Subdirectories that some pipelines additionally
write (`memefiles/`, `genome_stripped.fa`, etc.) are *intermediate* and must
not be relied on by anything outside the pipeline that wrote them.

```
$homotypic_output/
├── promoter_lengths.txt          required, deterministic
├── binomial_thresholds.txt       required, deterministic
├── IC.txt                        required, deterministic
├── universe.txt                  required, deterministic
└── fimohits/
    └── <motif>.txt               required, one file per motif in MEME
```

## File contracts

### `promoter_lengths.txt`

- Columns (TAB-separated, no header):
  1. `gene_id` — string, must appear in `universe.txt`.
  2. `length` — positive integer (number of basepairs of the gene's contribution
     to the homotypic search space, gene-level after collapsing per-fragment
     lengths if applicable).
- Lines: one per gene; gene IDs unique.
- Used by: `-p` argument to PMET pairing binaries.

### `binomial_thresholds.txt`

- Columns (TAB-separated, no header):
  1. `motif` — string, matches the basename of one file under `fimohits/`.
  2. `threshold` — float; the binomial p-value cutoff used during indexing.
  3. `extra` — float; pipeline-specific extra value (e.g. corrected threshold).
- Lines: one per motif; motif names unique.
- Used by: `-b` argument to PMET pairing binaries.
- Row order: not enforced by the contract (downstream binaries do not
  depend on it). Pipelines using parallel FIMO batches (`02`, `06`, `07`
  via `pmet_index_element.sh`) sort the file with `sort -o` to remove a
  race-induced nondeterminism; pipelines using `index_fimo_fused` (`03`,
  `08`) produce a deterministic order from the serial batch loop and do
  not need to sort.

### `IC.txt`

- Columns (SPACE-separated, no header):
  1. `motif` — string; matches column 1 of `binomial_thresholds.txt`.
  2..N. `ic_<i>` — float; information-content per position (one value per
  motif column).
- Lines: one per motif; motif names unique.
- Used by: `-c` argument to PMET pairing binaries.
- **Row order**: stable; produced by
  `scripts/python/calculateICfrommeme_IC_to_csv.py` in `mode='w'` so subsequent
  runs do not append.

### `universe.txt`

- Format: one gene ID per line, no header, ASCII.
- Lines: unique gene IDs that survived the homotypic indexing's universe
  filter (length ≥ minimum, valid coordinates, etc.).
- Used by: `grep -Ff universe.txt user_genes` filtering before invoking the
  heterotypic binary.

### `fimohits/<motif>.txt`

- One file per motif listed in `binomial_thresholds.txt` (and therefore in
  `IC.txt`).
- FIMO TSV format with the homotypic pipeline's per-gene top-k filtering and
  binomial thresholding already applied.
- Columns relevant to downstream:
  - column 2 — `gene_id` (must be in `universe.txt`).
  - column 7 — `p-value` (float; must be < the motif's threshold from
    `binomial_thresholds.txt`).
- Used by: `-f $homotypic_output/fimohits` argument to PMET pairing binaries.

## Cross-file invariants

These hold across the contract and are checked by the Python validator:

1. `set(motifs in binomial_thresholds.txt)` ==
   `set(motifs in IC.txt)` ==
   `set(basenames of fimohits/*.txt)`.
2. `set(genes in promoter_lengths.txt)` ⊆ `set(genes in universe.txt)`.
3. Every gene mentioned in any `fimohits/<motif>.txt` (column 2) is in
   `universe.txt`.
4. No empty files; no duplicate motif names; no duplicate gene names within a
   single file.

## Heterotypic output contract (separate)

`$heterotypic_output/motif_output.txt` is the result of the pairing binary; it
has its own 11-column TSV header documented at the top of
`scripts/r/process_pmet_result.R`. The `_AFTER_FIXES` notes and individual
verification log entries record the canonical hash for each pipeline.

## Plotting output (heatmap PNGs)

Pipelines that render heatmaps (`03`, `06`, `07`, `08`) produce three PNGs
per task: `heatmap.png`, `heatmap_overlap.png`, `heatmap_overlap_unique.png`.
Histogram subdirectories (`histogram/`, `histogram_overlap/`,
`histogram_overlap_unique/`) sit beside them. When a task has insufficient
significant pairs after R filtering, only the histograms are written (R
prints `No meaningfull data left after filtering!`); this is data-driven and
not a regression.
