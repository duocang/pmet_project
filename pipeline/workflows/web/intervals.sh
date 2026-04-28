#!/bin/bash
# ==============================================================================
# intervals (web) — full PMET intervals pipeline
# ==============================================================================
# Runs interval indexing, heterotypic motif-pair enrichment, and heatmaps in
# one go. Used by the web stack's `intervals` mode and as the canonical CLI
# demo for full intervals runs.
#
# Stages:
#   [1] Indexing — interval FASTA + MEME -> promoter lengths, IC, fimohits
#                  (uses build/index_fimo_fused with internal OMP batching)
#   [2] Heterotypic — pair_parallel consumes the index
#   [3] Heatmaps    — three R-rendered views (skipped if Rscript absent)
#
# Usage (CLI dev mode): just run it; defaults below process the bundled
# intervals demo data.
# Usage (web mode): invoked by pmet_backend/services/executor.py with options
# documented below.
# ==============================================================================

set -euo pipefail

script_dir=$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)

usage() {
    cat >&2 <<'EOF'
USAGE: intervals.sh [options] [<genome> <memefile>]

Options:
  -r <root_dir>        override project root (where build/ and scripts/ live)
  -o <indexing_dir>    indexing stage output directory
  -n <topn>            top n hits per motif (default: 5000)
  -k <max_k>           max motif hits per interval (default: 5)
  -f <fimo_threshold>  FIMO p-value threshold (default: 0.05)
  -t <threads>         threads (default: 4)
  -c <ic_threshold>    pairing IC threshold (default: 4)
  -x <pairing_dir>     pairing output dir (heatmaps land in <dir>/plot)
  -g <gene_file>       gene/interval list (overrides positional)
  -e <email>           accepted for compatibility, not used by the script
  -l <result_link>     accepted for compatibility, not used by the script
  -h                   show this help
EOF
}

error_exit() { echo "ERROR: $1" >&2; exit 1; }
check_file() { [[ -f "$1" && -s "$1" ]] || error_exit "${2:-$1} missing or empty"; }
check_dep()  { command -v "$1" &>/dev/null || error_exit "Tool not found: $1"; }

print_elapsed() {
    local s=$1 e=$SECONDS dt
    dt=$((e - s))
    local d=$((dt / 86400)) h=$(((dt % 86400) / 3600)) m=$(((dt % 3600) / 60)) sec=$((dt % 60))
    echo "Time taken: ${d}d ${h}h ${m}m ${sec}s"
}

# ==================== Defaults ====================

genome=data/homotypic_intervals/intervals.fa
meme=data/homotypic_intervals/motif_more.meme
gene_input_file=data/homotypic_intervals/intervals.txt

topn=5000
maxk=5
fimothresh=0.05
icthresh=4
threads=4

res_dir=results/04_intervals
indexing_output=
pairing_output=
project_root=$script_dir

# ==================== Argument parsing ====================

while getopts ":r:o:n:k:f:t:c:x:g:e:l:h" opt; do
    case $opt in
        r) project_root=$OPTARG ;;
        o) indexing_output=$OPTARG ;;
        n) topn=$OPTARG ;;
        k) maxk=$OPTARG ;;
        f) fimothresh=$OPTARG ;;
        t) threads=$OPTARG ;;
        c) icthresh=$OPTARG ;;
        x) pairing_output=$OPTARG ;;
        g) gene_input_file=$OPTARG ;;
        e) : ;;
        l) : ;;
        h) usage; exit 0 ;;
        \?) echo "Invalid option: -$OPTARG" >&2; usage; exit 1 ;;
        :)  echo "Option -$OPTARG requires an argument." >&2; usage; exit 1 ;;
    esac
done
shift $((OPTIND - 1))
[[ $# -ge 1 ]] && genome=$1
[[ $# -ge 2 ]] && meme=$2

cd "$script_dir"

: "${indexing_output:=$res_dir/01_indexing}"
: "${pairing_output:=$res_dir/02_pairing}"
plot_output="$pairing_output/plot"

PY=pipeline/python

# ==================== Locate binaries ====================

BIN_DIR=
for cand in "$project_root/build" "$project_root/pmet_pipeline/build" \
            "$script_dir/build" "$script_dir/pmet_pipeline/build"; do
    if [[ -x "$cand/index_fimo_fused" && -x "$cand/pair_parallel" ]]; then
        BIN_DIR=$cand
        break
    fi
done
[[ -n $BIN_DIR ]] || error_exit "PMET binaries (index_fimo_fused, pair_parallel) not found"
BIN_INDEX="$BIN_DIR/index_fimo_fused"
BIN_PMET="$BIN_DIR/pair_parallel"

# ==================== Preflight ====================

check_file "$genome" "Interval/genome FASTA"
check_file "$meme"   "MEME motif file"
check_file "$gene_input_file" "Gene/interval list"

for cmd in fasta-get-markov python3; do
    check_dep "$cmd"
done

rm -rf "$indexing_output" "$pairing_output" "$plot_output"
mkdir -p "$indexing_output" "$pairing_output" "$plot_output"

grand_start=$SECONDS

# ==============================================================================
# [1] Indexing
# ==============================================================================
# FIMO and pair_parallel's binary fimohits ('PMETBN01' format) can't safely
# carry ':' in sequence names: FIMO mis-parses, and the binary records are
# length-prefixed so a sed-based ':' restore would shift bytes. Sanitize ':'
# to '__COLON__' on the way in, keep the entire indexing namespace
# (promoter_lengths.txt / universe.txt / fimohits/*.bin) in that sanitized
# form, and let stage [2] handle round-tripping the user's gene list and
# restoring ':' on the human-facing pair output at the end.

echo
echo "[1/3] Interval indexing..."
h_start=$SECONDS

genome_sanitized="$indexing_output/genome_sanitized.fa"
sed 's/^\(>.*\):/\1__COLON__/g' "$genome" > "$genome_sanitized"

# Dedupe + per-interval lengths + universe.
python3 "$PY/deduplicate.py" \
    "$genome_sanitized" \
    "$indexing_output/no_duplicates.fa"
python3 "$PY/parse_promoter_lengths_from_fasta.py" \
    "$indexing_output/no_duplicates.fa" \
    "$indexing_output/promoter_lengths.txt"
cut -f1 "$indexing_output/promoter_lengths.txt" > "$indexing_output/universe.txt"
rm -f "$indexing_output/no_duplicates.fa"

# Background model.
fasta-get-markov "$genome_sanitized" > "$indexing_output/genome.bg"

mkdir -p "$indexing_output/fimohits"
python3 "$PY/calculateICfrommeme_IC_to_csv.py" \
    "$meme" \
    "$indexing_output/IC.txt"

nummotifs=$(grep -c '^MOTIF' "$meme")
echo "   └─ $nummotifs motifs"

# index_fimo_fused has internal OpenMP batching; one invocation handles
# every motif. The previous shell-level for-loop forked one process per
# motif each with its own OMP team, oversubscribing cores.
OMP_NUM_THREADS="$threads" \
"$BIN_INDEX"                            \
    --no-qvalue                         \
    --text                              \
    --thresh "$fimothresh"              \
    --verbosity 1                       \
    --bgfile "$indexing_output/genome.bg" \
    --topn "$topn"                      \
    --topk "$maxk"                      \
    --oc "$indexing_output"             \
    "$meme"                             \
    "$genome_sanitized"                 \
    "$indexing_output/promoter_lengths.txt"

# memefiles/ only existed for IC.txt. Sanitized FASTA was a temp.
rm -rf "$indexing_output/memefiles" "$genome_sanitized"

# Validate the indexing-output schema (presence + types).
python3 "$PY/check_homotypic_contract.py" "$indexing_output" \
    || error_exit "Homotypic contract violated; see stderr above"

print_elapsed "$h_start"

# ==============================================================================
# [2] Heterotypic
# ==============================================================================

echo
echo "[2/3] Heterotypic motif search..."

# Stage [1] keeps the index in sanitized form (':' → '__COLON__'). Sanitize
# the user's gene list to match.
universefile="$indexing_output/universe.txt"
gene_sanitized=$(mktemp)
gene_tmp=$(mktemp)
trap 'rm -f "$gene_sanitized" "$gene_tmp"' EXIT
sed 's/:/__COLON__/g' "$gene_input_file" > "$gene_sanitized"
grep -wFf "$universefile" "$gene_sanitized" > "$gene_tmp" || true

if [[ ! -s "$gene_tmp" ]]; then
    error_exit "No intervals from the input list match the index universe"
fi

# Both genes_used and genes_not_found are computed in sanitized space;
# restore ':' afterwards (text files, sed-safe).
cp "$gene_tmp" "$pairing_output/genes_used_PMET.txt"
grep -vwFf "$universefile" "$gene_sanitized" > "$pairing_output/genes_not_found.txt" || true

# pair_parallel resolves -p/-b/-c/-f relative to -d, so feed it the
# index dir as the base and bare filenames for the rest.
"$BIN_PMET" \
    -d "$indexing_output"      \
    -g "$gene_tmp"             \
    -i "$icthresh"             \
    -p promoter_lengths.txt    \
    -b binomial_thresholds.txt \
    -c IC.txt                  \
    -f fimohits                \
    -o "$pairing_output"       \
    -t "$threads" > "$pairing_output/pmet.log"

# pair_parallel writes its results as temp*.txt shards; merge only those.
shopt -s nullglob
shards=("$pairing_output"/temp*.txt)
shopt -u nullglob
if (( ${#shards[@]} == 0 )); then
    error_exit "pair_parallel produced no temp*.txt shards (see $pairing_output/pmet.log)"
fi
cat "${shards[@]}" > "$pairing_output/motif_output.txt"
rm -f "${shards[@]}"

# Restore ':' in the user-facing text outputs (binary fimohits stay sanitized).
for f in motif_output.txt genes_used_PMET.txt genes_not_found.txt; do
    p="$pairing_output/$f"
    if [[ -f "$p" ]]; then
        sed 's/__COLON__/:/g' "$p" > "$p.tmp" && mv "$p.tmp" "$p"
    fi
done

# ==============================================================================
# [3] Heatmaps
# ==============================================================================

echo
echo "[3/3] Generating heatmaps..."

if ! command -v Rscript >/dev/null 2>&1; then
    echo "   Rscript not found — skipping heatmaps. Main output (motif_output.txt) is unaffected." >&2
else
    draw() { Rscript pipeline/r/draw_heatmap.R "$@"; }
    draw All     "$plot_output/heatmap.png"                "$pairing_output/motif_output.txt" 5 3 6 FALSE
    draw Overlap "$plot_output/heatmap_overlap_unique.png" "$pairing_output/motif_output.txt" 5 3 6 TRUE
    draw Overlap "$plot_output/heatmap_overlap.png"        "$pairing_output/motif_output.txt" 5 3 6 FALSE
fi

echo
echo "Done."
print_elapsed "$grand_start"
