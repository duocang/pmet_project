#!/bin/bash
# story_03_heterotypic_replay.sh
# ---------------------------------------------------------------------------
# Re-run ONLY the heterotypic motif-pair test + heatmap rendering of
# pipeline 03, against an existing homotypic baseline at
# results/03_promoter/01_homotypic/. Used during the audit because the
# canonical baseline directory had been pruned to homotypic-only at the
# time the audit was run; this script replays only the cheap downstream
# stages so the audit doc can reference real motif_output.txt + PNG hashes.
#
# Diagnostic helper. Does NOT modify any pipeline source.

set -euo pipefail

repo=$(cd -- "$(dirname "$0")/../.." && pwd)
cd "$repo"

homotypic_output=results/03_promoter/01_homotypic
heterotypic_output=results/03_promoter/02_heterotypic
plot_output=results/03_promoter/plot
universefile="$homotypic_output/universe.txt"
gene_input_file=data/genes/genes_cell_type_treatment.txt

# Sanity: required contract files must exist.
for f in "$universefile" \
         "$homotypic_output/promoter_lengths.txt" \
         "$homotypic_output/binomial_thresholds.txt" \
         "$homotypic_output/IC.txt"; do
    [[ -s "$f" ]] || { echo "ERROR: missing $f" >&2; exit 1; }
done
[[ -d "$homotypic_output/fimohits" ]] || {
    echo "ERROR: missing $homotypic_output/fimohits" >&2; exit 1;
}
[[ -s "$gene_input_file" ]] || {
    echo "ERROR: missing $gene_input_file" >&2; exit 1;
}
[[ -x build/pair_parallel ]] || {
    echo "ERROR: missing build/pair_parallel" >&2; exit 1;
}

mkdir -p "$heterotypic_output" "$plot_output"

# Filter the user gene list to the homotypic universe (same logic as 03).
gene_tmp=$(mktemp)
trap 'rm -f "$gene_tmp"' EXIT
grep -Ff "$universefile" "$gene_input_file" > "$gene_tmp"

echo "[1/2] heterotypic via build/pair_parallel"
build/pair_parallel \
    -d .                                            \
    -g "$gene_tmp"                                  \
    -i 4                                            \
    -p "$homotypic_output/promoter_lengths.txt"     \
    -b "$homotypic_output/binomial_thresholds.txt"  \
    -c "$homotypic_output/IC.txt"                   \
    -f "$homotypic_output/fimohits"                 \
    -o "$heterotypic_output"                        \
    -t 4 > "$heterotypic_output/pmet.log" 2>&1

# Aggregate per-cluster outputs into the canonical motif_output.txt.
cat "$heterotypic_output"/*.txt > "$heterotypic_output/motif_output.txt"
rm -f "$heterotypic_output"/temp*.txt

echo "[2/2] three heatmaps via Rscript draw_heatmap.R"
Rscript scripts/r/draw_heatmap.R All     "$plot_output/heatmap.png"                "$heterotypic_output/motif_output.txt" 5 3 6 FALSE
Rscript scripts/r/draw_heatmap.R Overlap "$plot_output/heatmap_overlap_unique.png" "$heterotypic_output/motif_output.txt" 5 3 6 TRUE
Rscript scripts/r/draw_heatmap.R Overlap "$plot_output/heatmap_overlap.png"        "$heterotypic_output/motif_output.txt" 5 3 6 FALSE

echo
echo "Done. Audit references:"
echo "  $heterotypic_output/motif_output.txt   ($(wc -l <"$heterotypic_output/motif_output.txt") rows)"
ls -l "$plot_output"/heatmap*.png 2>/dev/null
echo
echo "SHA-256 of heatmaps:"
shasum -a 256 "$plot_output"/heatmap*.png 2>/dev/null
