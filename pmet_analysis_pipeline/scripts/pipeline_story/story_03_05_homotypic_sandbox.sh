#!/bin/bash
# story_03_05_homotypic_sandbox.sh
# ---------------------------------------------------------------------------
# Re-run only the homotypic stage of pipelines 03 and 05 into a sandbox
# directory under results/pipeline_story/, with --keep-intermediate, so the
# audit doc (docs/pipeline_story/) can reference real BED / FASTA /
# chrom-sizes files without disturbing the canonical baseline at
# results/03_promoter/ and results/05_promoter_gap/.
#
# This is a diagnostic helper for the audit. It does NOT modify any
# pipeline source, baseline directory, or contract file.

set -euo pipefail

repo=$(cd -- "$(dirname "$0")/../.." && pwd)
cd "$repo"

genome=data/TAIR10.fasta
anno=data/TAIR10.gff3
meme=data/Franco-Zorrilla_et_al_2014.meme

[[ -s "$genome" && -s "$anno" && -s "$meme" ]] || {
    echo "ERROR: required reference data missing under data/" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# 03 sandbox: gap=0, utr=Yes, NoOverlap, length=1000  (matches pipeline 03)
sandbox_03=results/pipeline_story/03_homotypic_sample
mkdir -p "$sandbox_03"
echo "[1/2] homotypic sandbox for pipeline 03 → $sandbox_03"
python3 scripts/python/run_homotypic.py \
    --genome      "$genome"     \
    --anno        "$anno"       \
    --meme        "$meme"       \
    --output-dir  "$sandbox_03" \
    --length      1000          \
    --gap         0             \
    --maxk        5             \
    --topn        5000          \
    --fimothresh  0.05          \
    --overlap     NoOverlap     \
    --utr         Yes           \
    --gff3-id-key "gene_id="    \
    --gene-features all         \
    --threads     4             \
    --bin-index   build/index_fimo_fused \
    --keep-intermediate

# ---------------------------------------------------------------------------
# 05 sandbox: gap=100 (which forces utr=No in the production script).
# Run with --gap 100 and --utr No to mirror that effective configuration.
sandbox_05=results/pipeline_story/05_homotypic_sample
mkdir -p "$sandbox_05"
echo "[2/2] homotypic sandbox for pipeline 05 → $sandbox_05"
python3 scripts/python/run_homotypic.py \
    --genome      "$genome"     \
    --anno        "$anno"       \
    --meme        "$meme"       \
    --output-dir  "$sandbox_05" \
    --length      1000          \
    --gap         100           \
    --maxk        5             \
    --topn        5000          \
    --fimothresh  0.05          \
    --overlap     NoOverlap     \
    --utr         No            \
    --gff3-id-key "gene_id="    \
    --gene-features all         \
    --threads     4             \
    --bin-index   build/index_fimo_fused \
    --keep-intermediate

echo
echo "Done. Audit references can now read:"
echo "  $sandbox_03/{genelines,promoters,promoters_removed_lt10,promoters_removed_lt20}.bed"
echo "  $sandbox_03/promoters.fa  (linearised, strand-aware)"
echo "  $sandbox_03/bedgenome.genome"
echo "  $sandbox_05/promoters.bed  (gap-shrunk; max length 900)"
