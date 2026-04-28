#!/bin/bash
# ==============================================================================
# promoters_only_pair — heterotypic enrichment + heatmaps on a pre-built index
# ==============================================================================
# Used by the web stack's `promoters_pre` mode. Mirrors stages [2] and [3]
# of scripts/pipeline/03_promoter.sh; the homotypic stage has already been
# run upstream and lives at -d <pmetindex_dir>.
#
# Stages:
#   [1] Heterotypic — pair_parallel consumes the pre-built index
#   [2] Heatmaps    — three R-rendered views (skipped if Rscript absent)
# ==============================================================================

set -euo pipefail

script_dir=$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

usage() {
    cat >&2 <<'EOF'
USAGE: promoters_only_pair.sh -d <pmetindex_dir> -g <gene_file> -o <output_dir> [options]

Options:
  -d <pmetindex_dir>   pre-built homotypic index. Must contain:
                       promoter_lengths.txt, binomial_thresholds.txt,
                       IC.txt, fimohits/, universe.txt
  -g <gene_file>       gene list (one gene per line)
  -i <ic_threshold>    pairing IC threshold (default: 24)
  -t <threads>         threads (default: 4)
  -o <output_dir>      pairing output dir (heatmaps land in <dir>/plot)
  -e <email>           accepted for compatibility, not used by the script
  -l <result_link>     accepted for compatibility, not used by the script
  -h                   show this help
EOF
}

error_exit() { echo "ERROR: $1" >&2; exit 1; }
check_file() { [[ -f "$1" && -s "$1" ]] || error_exit "${2:-$1} missing or empty"; }

print_elapsed() {
    local s=$1 e=$SECONDS dt
    dt=$((e - s))
    local d=$((dt / 86400)) h=$(((dt % 86400) / 3600)) m=$(((dt % 3600) / 60)) sec=$((dt % 60))
    echo "Time taken: ${d}d ${h}h ${m}m ${sec}s"
}

# ==================== Defaults ====================

pmetindex=
genefile=
outputdir=
icthresh=24
threads=4

# ==================== Argument parsing ====================

while getopts ":d:g:i:t:o:e:l:h" opt; do
    case $opt in
        d) pmetindex=$OPTARG ;;
        g) genefile=$OPTARG ;;
        i) icthresh=$OPTARG ;;
        t) threads=$OPTARG ;;
        o) outputdir=$OPTARG ;;
        e) : ;;
        l) : ;;
        h) usage; exit 0 ;;
        \?) echo "Invalid option: -$OPTARG" >&2; usage; exit 1 ;;
        :)  echo "Option -$OPTARG requires an argument." >&2; usage; exit 1 ;;
    esac
done

[[ -n $pmetindex ]] || { usage; error_exit "-d <pmetindex_dir> required"; }
[[ -n $genefile  ]] || { usage; error_exit "-g <gene_file> required"; }
[[ -n $outputdir ]] || { usage; error_exit "-o <output_dir> required"; }

cd "$script_dir"

# ==================== Locate binary ====================

BIN_DIR=
for cand in "$script_dir/build" "$script_dir/pmet_pipeline/build"; do
    if [[ -x "$cand/pair_parallel" ]]; then
        BIN_DIR=$cand
        break
    fi
done
[[ -n $BIN_DIR ]] || error_exit "PMET binary pair_parallel not found"
BIN_PMET="$BIN_DIR/pair_parallel"

# ==================== Preflight ====================

universefile="$pmetindex/universe.txt"
check_file "$universefile"                       "Index universe.txt"
check_file "$pmetindex/promoter_lengths.txt"     "Index promoter_lengths.txt"
check_file "$pmetindex/binomial_thresholds.txt"  "Index binomial_thresholds.txt"
check_file "$pmetindex/IC.txt"                   "Index IC.txt"
[[ -d "$pmetindex/fimohits" ]] || error_exit "Index fimohits/ directory missing"
check_file "$genefile" "Gene list"

mkdir -p "$outputdir"
plot_output="$outputdir/plot"
mkdir -p "$plot_output"

grand_start=$SECONDS

# ==============================================================================
# [1] Heterotypic
# ==============================================================================

echo
echo "[1/2] Heterotypic motif search..."

gene_tmp=$(mktemp)
trap 'rm -f "$gene_tmp"' EXIT
grep -wFf "$universefile" "$genefile" > "$gene_tmp" || true

if [[ ! -s "$gene_tmp" ]]; then
    error_exit "No genes from the input list match the index universe"
fi

# Record which input genes survived / dropped (web UI consumes these).
cp "$gene_tmp" "$outputdir/genes_used_PMET.txt"
grep -vwFf "$universefile" "$genefile" > "$outputdir/genes_not_found.txt" || true

# pair_parallel resolves -p/-b/-c/-f relative to -d, so feed it the
# index dir as the base and bare filenames for the rest.
"$BIN_PMET" \
    -d "$pmetindex"            \
    -g "$gene_tmp"             \
    -i "$icthresh"             \
    -p promoter_lengths.txt    \
    -b binomial_thresholds.txt \
    -c IC.txt                  \
    -f fimohits                \
    -o "$outputdir"            \
    -t "$threads" > "$outputdir/pmet.log"

# pair_parallel writes its results as temp*.txt shards; merge only those.
shopt -s nullglob
shards=("$outputdir"/temp*.txt)
shopt -u nullglob
if (( ${#shards[@]} == 0 )); then
    error_exit "pair_parallel produced no temp*.txt shards (see $outputdir/pmet.log)"
fi
cat "${shards[@]}" > "$outputdir/motif_output.txt"
rm -f "${shards[@]}"

# ==============================================================================
# [2] Heatmaps
# ==============================================================================

echo
echo "[2/2] Generating heatmaps..."

if ! command -v Rscript >/dev/null 2>&1; then
    echo "   Rscript not found — skipping heatmaps. Main output (motif_output.txt) is unaffected." >&2
else
    draw() { Rscript scripts/r/draw_heatmap.R "$@"; }
    draw All     "$plot_output/heatmap.png"                "$outputdir/motif_output.txt" 5 3 6 FALSE
    draw Overlap "$plot_output/heatmap_overlap_unique.png" "$outputdir/motif_output.txt" 5 3 6 TRUE
    draw Overlap "$plot_output/heatmap_overlap.png"        "$outputdir/motif_output.txt" 5 3 6 FALSE
fi

echo
echo "Done."
print_elapsed "$grand_start"
