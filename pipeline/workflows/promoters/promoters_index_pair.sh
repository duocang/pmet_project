#!/bin/bash
# ==============================================================================
# promoters_index_pair — full PMET promoters pipeline
# ==============================================================================
# Runs homotypic indexing, heterotypic motif-pair enrichment, and heatmaps in
# one go. Used by the web stack's `promoters` mode and as the canonical CLI
# demo for full-pipeline runs.
#
# Stages:
#   [1] Homotypic — genome/annotation prep -> promoter BED -> FIMO + pmetindex
#       via build/index_fimo_fused (delegated to scripts/python/run_homotypic.py)
#   [2] Heterotypic — pair_parallel consumes the index
#   [3] Heatmaps — three R-rendered views
#
# Usage (CLI dev mode): just run it; defaults below process TAIR10 demo data.
# Usage (web mode): invoked by pmet_backend/services/executor.py with options
# documented below.
# ==============================================================================

set -euo pipefail

script_dir=$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)

usage() {
    cat >&2 <<'EOF'
USAGE: 03_promoter.sh [options] [<genome> <gff3> <memefile> <gene_input_file>]

Options:
  -r <root_dir>          override project root (where build/ and scripts/ live)
  -i <gff3_id_key>       GFF3 attribute key, e.g. gene_id= or ID=
  -o <homotypic_dir>     homotypic stage output directory
  -n <topn>              top n promoter hits per motif (default: 5000)
  -k <max_k>             max motif hits per promoter (default: 5)
  -p <promoter_length>   promoter length, bp (default: 1000)
  -f <fimo_threshold>    FIMO p-value threshold (default: 0.05)
  -v <overlap_mode>      AllowOverlap | NoOverlap (default: NoOverlap)
  -u <include_utr>       Yes | No (default: Yes)
  -t <threads>           threads (default: 4)
  -c <ic_threshold>      pairing IC threshold (default: 4)
  -x <heterotypic_dir>   pairing output directory (heatmaps land in <dir>/plot)
  -g <gene_file>         gene list (overrides positional)
  -e <email>             accepted for compatibility, not used by the script
  -l <result_link>       accepted for compatibility, not used by the script
  -h                     show this help
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

is_yes()        { local v; v=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]'); [[ "$v" =~ ^(yes|y|true|t)$ ]]; }
is_no_overlap() { local v; v=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]'); [[ "$v" =~ ^(nooverlap|no|n)$ ]]; }

# ==================== Defaults ====================

genome=data/TAIR10.fasta
anno=data/TAIR10.gff3
meme=data/Franco-Zorrilla_et_al_2014.meme

task=genes_cell_type_treatment
gene_input_file=data/genes/$task.txt

gff3id="gene_id="
gene_features=all        # all / strict — see docs/contracts/homotypic.md
overlap=NoOverlap        # AllowOverlap | NoOverlap
utr=Yes                  # Yes | No
topn=5000
maxk=5
length=1000
fimothresh=0.05
isPoisson=false
icthresh=4

threads=4
keep_intermediate=false

res_dir=results/03_promoter
homotypic_output=
heterotypic_output=
project_root=$script_dir

# ==================== Argument parsing ====================

while getopts ":r:i:o:n:k:p:f:g:v:u:t:c:x:e:l:h" opt; do
    case $opt in
        r) project_root=$OPTARG ;;
        i) gff3id=$OPTARG ;;
        o) homotypic_output=$OPTARG ;;
        n) topn=$OPTARG ;;
        k) maxk=$OPTARG ;;
        p) length=$OPTARG ;;
        f) fimothresh=$OPTARG ;;
        v) overlap=$OPTARG ;;
        u) utr=$OPTARG ;;
        t) threads=$OPTARG ;;
        c) icthresh=$OPTARG ;;
        x) heterotypic_output=$OPTARG ;;
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
[[ $# -ge 2 ]] && anno=$2
[[ $# -ge 3 ]] && meme=$3
[[ $# -ge 4 ]] && gene_input_file=$4

cd "$script_dir"

: "${homotypic_output:=$res_dir/01_homotypic}"
: "${heterotypic_output:=$res_dir/02_heterotypic}"
plot_output="$heterotypic_output/plot"

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

PY=pipeline/python

# ==================== Preflight ====================

if [[ ! -s "$genome" || ! -s "$anno" ]]; then
    if [[ -f pipeline/data/fetch_tair10.sh ]]; then
        echo "Downloading genome and annotation..."
        bash pipeline/data/fetch_tair10.sh
    fi
fi

check_file "$genome" "Genome"
check_file "$anno"   "GFF3 annotation"
check_file "$meme"   "MEME motif file"
check_file "$gene_input_file" "Gene list"

for cmd in samtools bedtools sortBed fasta-get-markov parallel python3; do
    check_dep "$cmd"
done

# Catch GFF3 vs FASTA naming mismatches early (e.g. "1" vs "Chr1")
gff3_chr=$(awk -F'\t' '!/^#/ && NF>=9 {print $1; exit}' "$anno")
fasta_chr=$(grep '^>' "$genome" | head -1 | sed 's/^>//' | awk '{print $1}')
if [[ "$gff3_chr" != "$fasta_chr" ]]; then
    error_exit "Chromosome name mismatch: GFF3='$gff3_chr' vs FASTA='$fasta_chr'. Ensure consistent naming."
fi
echo "   Preflight OK — chromosome naming consistent ('$gff3_chr')"

rm -rf "$homotypic_output" "$heterotypic_output" "$plot_output"
mkdir -p "$homotypic_output" "$heterotypic_output" "$plot_output"

grand_start=$SECONDS

# ==============================================================================
# [1] Homotypic
# ==============================================================================

echo
echo "[1/3] Homotypic motif search..."
h_start=$SECONDS

overlap_arg=AllowOverlap; is_no_overlap "$overlap" && overlap_arg=NoOverlap
utr_arg=No;                is_yes "$utr"          && utr_arg=Yes
poisson_flag=""; is_yes "$isPoisson" && poisson_flag="--poisson"
keep_flag="";    [[ "$keep_intermediate" == true ]] && keep_flag="--keep-intermediate"

python3 "$PY/run_homotypic.py" \
    --genome      "$genome"     \
    --anno        "$anno"       \
    --meme        "$meme"       \
    --output-dir  "$homotypic_output" \
    --length      "$length"     \
    --gap         0             \
    --maxk        "$maxk"       \
    --topn        "$topn"       \
    --fimothresh  "$fimothresh" \
    --overlap     "$overlap_arg"\
    --utr           "$utr_arg"      \
    --gff3-id-key   "$gff3id"       \
    --gene-features "$gene_features" \
    --threads     "$threads"    \
    --bin-index   "$BIN_INDEX"  \
    $poisson_flag $keep_flag

print_elapsed "$h_start"

# ==============================================================================
# [2] Heterotypic
# ==============================================================================

echo
echo "[2/3] Heterotypic motif search..."

universefile="$homotypic_output/universe.txt"
gene_tmp=$(mktemp)
trap 'rm -f "$gene_tmp"' EXIT
grep -wFf "$universefile" "$gene_input_file" > "$gene_tmp" || true

if [[ ! -s "$gene_tmp" ]]; then
    error_exit "No genes from the input list match the universe (homotypic stage filtered them all out)"
fi

# Record which input genes survived / dropped for downstream consumers.
cp "$gene_tmp" "$heterotypic_output/genes_used_PMET.txt"
grep -vwFf "$universefile" "$gene_input_file" > "$heterotypic_output/genes_not_found.txt" || true

# pair_parallel resolves -p/-b/-c/-f relative to -d, so feed it the
# index dir as the base and bare filenames for the rest.
"$BIN_PMET" \
    -d "$homotypic_output"            \
    -g "$gene_tmp"                    \
    -i "$icthresh"                    \
    -p promoter_lengths.txt           \
    -b binomial_thresholds.txt        \
    -c IC.txt                         \
    -f fimohits                       \
    -o "$heterotypic_output"          \
    -t "$threads" > "$heterotypic_output/pmet.log"

# pair_parallel writes its results as temp*.txt shards; merge only those.
shopt -s nullglob
shards=("$heterotypic_output"/temp*.txt)
shopt -u nullglob
if (( ${#shards[@]} == 0 )); then
    error_exit "pair_parallel produced no temp*.txt shards (see $heterotypic_output/pmet.log)"
fi
cat "${shards[@]}" > "$heterotypic_output/motif_output.txt"
rm -f "${shards[@]}"

# ==============================================================================
# [3] Heatmaps
# ==============================================================================

echo
echo "[3/3] Generating heatmaps..."

if ! command -v Rscript >/dev/null 2>&1; then
    echo "   Rscript not found — skipping heatmaps. Main output (motif_output.txt) is unaffected." >&2
else
    draw() { Rscript pipeline/r/draw_heatmap.R "$@"; }
    draw All     "$plot_output/heatmap.png"                "$heterotypic_output/motif_output.txt" 5 3 6 FALSE
    draw Overlap "$plot_output/heatmap_overlap_unique.png" "$heterotypic_output/motif_output.txt" 5 3 6 TRUE
    draw Overlap "$plot_output/heatmap_overlap.png"        "$heterotypic_output/motif_output.txt" 5 3 6 FALSE
fi

echo
echo "Done."
print_elapsed "$grand_start"
