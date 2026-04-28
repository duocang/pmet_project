#!/bin/bash
# ==============================================================================
# Pipeline 08: PMET pair-only (heterotypic + heatmaps on a pre-built index)
# ==============================================================================
# Skips the expensive homotypic indexing stage and consumes an existing
# `01_homotypic/` directory produced by pipeline 03 (or any other pipeline
# that emits the canonical homotypic contract — see docs/contracts/homotypic.md).
#
# Use case: re-pair the same index against a different gene list or with a
# different IC threshold without redoing the ~110s indexing — a single run
# finishes in ~2-5s on TAIR10.
#
# Stages:
#   [1] Heterotypic — pair_parallel consumes the pre-built index
#   [2] Heatmaps    — three R-rendered views (skipped if Rscript absent)
#
# Mirrors pmet_shiny_app/scripts/pipeline/promoters_only_pair.sh.
#
# Baseline:
#   `scripts/tests/baselines/08_baseline.hashes.txt` — recorded against
#   `results/03_promoter/01_homotypic/` + `data/genes/genes_cell_type_treatment.txt`
#   at `-i 4 -t 4`. Cross-validated to produce a `motif_output.txt` byte-
#   identical to pipeline 03's (sha256 4b24906a…), as expected — 08 is
#   the [2]+[3] tail of 03 detached.
# ==============================================================================

set -euo pipefail

script_dir=$(cd -- "$(dirname "$0")/../.." && pwd)
cd "$script_dir"
source scripts/lib/print_colors.sh
source scripts/lib/timer.sh

# ==================== Helpers ====================

error_exit() { print_red "ERROR: $1" >&2; exit 1; }
check_file() { [[ -f "$1" && -s "$1" ]] || error_exit "${2:-$1} missing or empty"; }
check_dep()  { command -v "$1" &>/dev/null || error_exit "Tool not found: $1"; }

usage() {
    cat >&2 <<'EOF'
USAGE: 08_pair_only.sh -d <homotypic_dir> -g <gene_list> -o <output_dir> [options]

Required:
  -d <homotypic_dir>     pre-built homotypic index (the 01_homotypic/ dir
                         from pipeline 03/04/05). Must contain:
                           promoter_lengths.txt, binomial_thresholds.txt,
                           IC.txt, fimohits/, universe.txt
  -g <gene_list>         gene list (one gene per line; cluster prefix
                         optional, must match the index universe entries)
  -o <output_dir>        pairing output dir (heatmaps land in <dir>/plot)

Optional:
  -i <ic_threshold>      pairing IC threshold (default: 4)
  -t <threads>           threads (default: 4)
  -h                     show this help

Example (after running pipeline 03):
  bash scripts/pipeline/08_pair_only.sh \
      -d results/03_promoter/01_homotypic \
      -g data/genes/genes_cell_type_treatment.txt \
      -o results/08_pair_only/cell_type_treatment_ic4
EOF
}

# ==================== Defaults ====================

homotypic_dir=
gene_input_file=
output_dir=
icthresh=4
threads=4

# ==================== Argument parsing ====================

while getopts ":d:g:o:i:t:h" opt; do
    case $opt in
        d) homotypic_dir=$OPTARG ;;
        g) gene_input_file=$OPTARG ;;
        o) output_dir=$OPTARG ;;
        i) icthresh=$OPTARG ;;
        t) threads=$OPTARG ;;
        h) usage; exit 0 ;;
        \?) echo "Invalid option: -$OPTARG" >&2; usage; exit 1 ;;
        :)  echo "Option -$OPTARG requires an argument." >&2; usage; exit 1 ;;
    esac
done

[[ -n $homotypic_dir   ]] || { usage; error_exit "-d <homotypic_dir> required"; }
[[ -n $gene_input_file ]] || { usage; error_exit "-g <gene_list> required"; }
[[ -n $output_dir      ]] || { usage; error_exit "-o <output_dir> required"; }

# Tools
BIN_PMET=build/pair_parallel
PY=scripts/python

# ==================== Preflight ====================

[[ -d "$homotypic_dir" ]] || error_exit "Homotypic dir not found: $homotypic_dir"

universefile="$homotypic_dir/universe.txt"
check_file "$universefile"                          "Index universe.txt"
check_file "$homotypic_dir/promoter_lengths.txt"    "Index promoter_lengths.txt"
check_file "$homotypic_dir/binomial_thresholds.txt" "Index binomial_thresholds.txt"
check_file "$homotypic_dir/IC.txt"                  "Index IC.txt"
[[ -d "$homotypic_dir/fimohits" ]] || error_exit "Index fimohits/ directory missing: $homotypic_dir/fimohits"
check_file "$gene_input_file" "Gene list"

[[ -f "$BIN_PMET" ]] || error_exit "Binary not found: $BIN_PMET"

# Optional contract validator (presence-only check; treats unknown helper as advisory).
if [[ -f "$PY/check_homotypic_contract.py" ]]; then
    python3 "$PY/check_homotypic_contract.py" "$homotypic_dir" \
        || error_exit "Homotypic contract violated for $homotypic_dir; see stderr above"
fi

mkdir -p "$output_dir"
plot_output="$output_dir/plot"
mkdir -p "$plot_output"

grand_start=$SECONDS

# ==============================================================================
# [1] Heterotypic
# ==============================================================================

print_green "\n[1/2] Heterotypic motif search..."
echo "Homotypic index : $homotypic_dir"
echo "Gene list       : $gene_input_file"
echo "Output dir      : $output_dir"
echo "IC threshold    : $icthresh"
echo "Threads         : $threads"

# Word-boundary filter against the index universe — defends against substring
# matches and produces a clean used/dropped split for diagnostics.
gene_tmp=$(mktemp)
trap 'rm -f "$gene_tmp"' EXIT
grep -wFf "$universefile" "$gene_input_file" > "$gene_tmp" || true

if [[ ! -s "$gene_tmp" ]]; then
    error_exit "No genes from the input list match the index universe ($universefile)"
fi

# Diagnostic outputs (written before pair_parallel so failures still leave them).
cp "$gene_tmp" "$output_dir/genes_used_PMET.txt"
grep -vwFf "$universefile" "$gene_input_file" > "$output_dir/genes_not_found.txt" || true

# pair_parallel resolves -p/-b/-c/-f relative to -d, so feed it the
# index dir as the base and bare filenames for the rest.
"$BIN_PMET" \
    -d "$homotypic_dir"        \
    -g "$gene_tmp"             \
    -i "$icthresh"             \
    -p promoter_lengths.txt    \
    -b binomial_thresholds.txt \
    -c IC.txt                  \
    -f fimohits                \
    -o "$output_dir"           \
    -t "$threads" > "$output_dir/pmet.log"

# Merge ONLY pair_parallel's temp*.txt shards — naive `cat *.txt` would now
# also concatenate the diagnostic files we just wrote.
shopt -s nullglob
shards=("$output_dir"/temp*.txt)
shopt -u nullglob
if (( ${#shards[@]} == 0 )); then
    error_exit "pair_parallel produced no temp*.txt shards (see $output_dir/pmet.log)"
fi
cat "${shards[@]}" > "$output_dir/motif_output.txt"
rm -f "${shards[@]}"

# ==============================================================================
# [2] Heatmaps
# ==============================================================================

print_green "\n[2/2] Generating heatmaps..."

if ! command -v Rscript >/dev/null 2>&1; then
    print_orange "   Rscript not found — skipping heatmaps. Main output (motif_output.txt) is unaffected."
else
    draw() { Rscript scripts/r/draw_heatmap.R "$@"; }
    draw All     "$plot_output/heatmap.png"                "$output_dir/motif_output.txt" 5 3 6 FALSE
    draw Overlap "$plot_output/heatmap_overlap_unique.png" "$output_dir/motif_output.txt" 5 3 6 TRUE
    draw Overlap "$plot_output/heatmap_overlap.png"        "$output_dir/motif_output.txt" 5 3 6 FALSE
fi

print_green "\nDone."
print_elapsed_time "$grand_start"
