#!/bin/bash
# ==============================================================================
# Pipeline 04: PMET on genomic intervals (parameterized)
# ==============================================================================
# Runs interval indexing, heterotypic motif-pair enrichment, and a heatmap in
# one script. All data paths and parameters can be overridden via options or
# positional arguments; defaults reproduce the canonical bundled-intervals
# demo run that `run.sh` invokes.
#
# Stages:
#   [1] Indexing — interval FASTA + MEME -> universe / promoter_lengths /
#       IC / fimohits (inlined: dedupe, lengths, bg model, IC, single OMP-
#       batched index_fimo_fused call, contract validation)
#   [2] Heterotypic — build/pair_parallel consumes the index
#   [3] Heatmap   — single Overlap heatmap from motif_output.txt
# ==============================================================================

set -euo pipefail

script_dir=$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$script_dir"
source pipeline/lib/print_colors.sh
source pipeline/lib/timer.sh

PY=scripts/python

# ==================== Helpers ====================

error_exit() { print_red "ERROR: $1" >&2; exit 1; }
check_file() { [[ -f "$1" && -s "$1" ]] || error_exit "${2:-$1} missing or empty"; }
check_dep()  { command -v "$1" &>/dev/null || error_exit "Tool not found: $1"; }

usage() {
    cat >&2 <<'EOF'
USAGE: 04_intervals.sh [options] [<genome> <memefile>]

Data (also settable as positional arguments in this order):
  -s <genome>            interval FASTA (default: data/homotypic_intervals/intervals.fa)
  -m <memefile>          MEME motif file (default: data/homotypic_intervals/motif_more.meme)
  -g <gene_list>         user interval list (default: data/homotypic_intervals/intervals.txt)

Indexing parameters:
  -n <topn>              top n hits per motif       (default: 5000)
  -k <max_k>             max motif hits per interval (default: 5)
  -f <fimo_threshold>    FIMO p-value threshold     (default: 0.05)

Heterotypic / runtime:
  -c <ic_threshold>      pairing IC threshold       (default: 4)
  -t <threads>           threads                    (default: 1)

Output directories:
  -o <indexing_dir>      indexing output dir    (default: results/04_intervals/01_homotypic)
  -x <heterotypic_dir>   heterotypic output dir (default: results/04_intervals/02_heterotypic)

  -h                     show this help
EOF
}

# ==================== Defaults ====================

genome=data/homotypic_intervals/intervals.fa
meme=data/homotypic_intervals/motif_more.meme
gene_input_file=data/homotypic_intervals/intervals.txt

topn=5000
maxk=5
fimothresh=0.05

icthresh=4
threads=1

res_dir=results/04_intervals
homotypic_output=
heterotypic_output=

# ==================== Argument parsing ====================

while getopts ":s:m:g:n:k:f:c:t:o:x:h" opt; do
    case $opt in
        s) genome=$OPTARG ;;
        m) meme=$OPTARG ;;
        g) gene_input_file=$OPTARG ;;
        n) topn=$OPTARG ;;
        k) maxk=$OPTARG ;;
        f) fimothresh=$OPTARG ;;
        c) icthresh=$OPTARG ;;
        t) threads=$OPTARG ;;
        o) homotypic_output=$OPTARG ;;
        x) heterotypic_output=$OPTARG ;;
        h) usage; exit 0 ;;
        \?) echo "Invalid option: -$OPTARG" >&2; usage; exit 1 ;;
        :)  echo "Option -$OPTARG requires an argument." >&2; usage; exit 1 ;;
    esac
done
shift $((OPTIND - 1))
[[ $# -ge 1 ]] && genome=$1
[[ $# -ge 2 ]] && meme=$2

: "${homotypic_output:=$res_dir/01_homotypic}"
: "${heterotypic_output:=$res_dir/02_heterotypic}"

# Tools
BIN_INDEX=build/index_fimo_fused
BIN_PMET=build/pair_parallel

# ==================== Preflight ====================

check_file "$genome" "Interval FASTA"
check_file "$meme"   "MEME motif file"
check_file "$gene_input_file" "Interval list"

[[ -f "$BIN_INDEX" ]] || error_exit "Binary not found: $BIN_INDEX"
[[ -f "$BIN_PMET"  ]] || error_exit "Binary not found: $BIN_PMET"

for cmd in fasta-get-markov python3; do
    check_dep "$cmd"
done

rm -rf "$homotypic_output" "$heterotypic_output"
mkdir -p "$homotypic_output" "$heterotypic_output"

grand_start=$SECONDS

# ==============================================================================
# [1] Indexing  (inlined, mirrors pmet_shiny_app/scripts/pipeline/intervals_index_pair.sh)
# ==============================================================================
# FIMO and pair_parallel's binary fimohits ('PMETBN01' format) can't safely
# carry ':' in sequence names: FIMO mis-parses, and the binary records are
# length-prefixed so a sed-based ':' restore would shift bytes. Sanitize ':'
# to '__COLON__' on the way in, keep the entire indexing namespace
# (promoter_lengths.txt / universe.txt / fimohits/*.bin) in that sanitized
# form, and restore ':' only on the human-facing pair output at the end.

print_green "\n[1/3] Indexing intervals..."
echo "Indexing output: $homotypic_output"
h_start=$SECONDS

genome_sanitized="$homotypic_output/genome_sanitized.fa"
sed 's/^\(>.*\):/\1__COLON__/g' "$genome" > "$genome_sanitized"

# Dedupe + per-interval lengths + universe.
python3 "$PY/deduplicate.py" \
    "$genome_sanitized" \
    "$homotypic_output/no_duplicates.fa"
python3 "$PY/parse_promoter_lengths_from_fasta.py" \
    "$homotypic_output/no_duplicates.fa" \
    "$homotypic_output/promoter_lengths.txt"
cut -f1 "$homotypic_output/promoter_lengths.txt" > "$homotypic_output/universe.txt"
rm -f "$homotypic_output/no_duplicates.fa"

# Background model.
fasta-get-markov "$genome_sanitized" > "$homotypic_output/genome.bg"

mkdir -p "$homotypic_output/fimohits"
python3 "$PY/calculateICfrommeme_IC_to_csv.py" \
    "$meme" \
    "$homotypic_output/IC.txt"

nummotifs=$(grep -c '^MOTIF' "$meme")
echo "   └─ $nummotifs motifs"

# index_fimo_fused has internal OpenMP batching; one invocation handles
# every motif. Replaces a previous shell-level for-loop that forked one
# process per motif each with its own OMP team, oversubscribing cores.
OMP_NUM_THREADS="$threads" \
"$BIN_INDEX"                              \
    --no-qvalue                           \
    --text                                \
    --thresh "$fimothresh"                \
    --verbosity 1                         \
    --bgfile "$homotypic_output/genome.bg" \
    --topn "$topn"                        \
    --topk "$maxk"                        \
    --oc "$homotypic_output"              \
    "$meme"                               \
    "$genome_sanitized"                   \
    "$homotypic_output/promoter_lengths.txt"

# Sanitized FASTA was a temp.
rm -f "$genome_sanitized"

# Validate the indexing-output schema (presence + types).
python3 "$PY/check_homotypic_contract.py" "$homotypic_output" \
    || error_exit "Homotypic contract violated; see stderr above"

print_elapsed_time "$h_start"

# ==============================================================================
# [2] Heterotypic
# ==============================================================================

print_green "\n[2/3] Searching for heterotypic motif hits..."
echo "Heterotypic output: $heterotypic_output"

# Stage [1] keeps the index in sanitized form (':' → '__COLON__'). Sanitize
# the user gene list to match, then restore ':' on the final user-facing
# text outputs after pair_parallel.
universefile="$homotypic_output/universe.txt"
gene_sanitized=$(mktemp)
gene_tmp=$(mktemp)
trap 'rm -f "$gene_sanitized" "$gene_tmp"' EXIT
sed 's/:/__COLON__/g' "$gene_input_file" > "$gene_sanitized"
grep -wFf "$universefile" "$gene_sanitized" > "$gene_tmp" || true

if [[ ! -s "$gene_tmp" ]]; then
    error_exit "No intervals from the input list match the index universe"
fi

# Diagnostic outputs (written before pair_parallel so failures still leave them).
# Computed in sanitized space; ':' is restored together with motif_output below.
cp "$gene_tmp" "$heterotypic_output/genes_used_PMET.txt"
grep -vwFf "$universefile" "$gene_sanitized" > "$heterotypic_output/genes_not_found.txt" || true

# pair_parallel resolves -p/-b/-c/-f relative to -d, so feed it the
# index dir as the base and bare filenames for the rest.
"$BIN_PMET" \
    -d "$homotypic_output"     \
    -g "$gene_tmp"             \
    -i "$icthresh"             \
    -p promoter_lengths.txt    \
    -b binomial_thresholds.txt \
    -c IC.txt                  \
    -f fimohits                \
    -o "$heterotypic_output"   \
    -t "$threads" > "$heterotypic_output/pmet.log"

# Merge ONLY pair_parallel's temp*.txt shards — naive `cat *.txt` would now
# also concatenate the diagnostic files we just wrote.
shopt -s nullglob
shards=("$heterotypic_output"/temp*.txt)
shopt -u nullglob
if (( ${#shards[@]} == 0 )); then
    error_exit "pair_parallel produced no temp*.txt shards"
fi
cat "${shards[@]}" > "$heterotypic_output/motif_output.txt"
rm -f "${shards[@]}"

# Restore ':' in user-facing text outputs (binary fimohits stay sanitized).
for f in motif_output.txt genes_used_PMET.txt genes_not_found.txt; do
    p="$heterotypic_output/$f"
    [[ -f "$p" ]] && sed 's/__COLON__/:/g' "$p" > "$p.tmp" && mv "$p.tmp" "$p"
done

# ==============================================================================
# [3] Heatmap
# ==============================================================================

print_green "\n[3/3] Generating heatmap..."

Rscript pipeline/r/draw_heatmap.R                       \
    Overlap                                \
    "$heterotypic_output/heatmap.png"      \
    "$heterotypic_output/motif_output.txt" \
    5                                      \
    3                                      \
    6                                      \
    FALSE

print_green "\nDone."
print_elapsed_time "$grand_start"
