#!/bin/bash
# ==============================================================================
# Pipeline 03: PMET Promoter Analysis (parameterized)
# ==============================================================================
# Runs homotypic indexing, heterotypic motif-pair enrichment, and heatmaps in
# one script. All data paths and parameters can be overridden via options or
# positional arguments; defaults reproduce the canonical TAIR10 demo run that
# `run.sh` invokes.
#
# Stages:
#   [1] Homotypic — genome/annotation prep -> promoter BED -> FIMO + pmetindex
#       via build/index_fimo_fused (delegated to pipeline/python/run_homotypic.py)
#   [2] Heterotypic — pair_parallel consumes the index
#   [3] Heatmaps — three R-rendered views
# ==============================================================================

set -euo pipefail

script_dir=$(cd -- "$(dirname "$0")/../../.." && pwd)
cd "$script_dir"
source pipeline/lib/print_colors.sh
source pipeline/lib/timer.sh

# ==================== Helpers ====================

error_exit()  { print_red "ERROR: $1" >&2; exit 1; }
check_file()  { [[ -f "$1" && -s "$1" ]] || error_exit "${2:-$1} missing or empty"; }
check_dep()   { command -v "$1" &>/dev/null || error_exit "Tool not found: $1"; }
step()        { print_fluorescent_yellow "   $1. $2"; }

is_yes() {
    local v; v=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    [[ "$v" =~ ^(yes|y|true|t)$ ]]
}

is_no_overlap() {
    local v; v=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    [[ "$v" =~ ^(nooverlap|no|n)$ ]]
}

usage() {
    cat >&2 <<'EOF'
USAGE: 03_promoter.sh [options] [<genome> <gff3> <memefile> <gene_input_file>]

Data (also settable as positional arguments in this order):
  -s <genome>            FASTA genome                 (default: data/TAIR10.fasta)
  -a <gff3>              GFF3 annotation              (default: data/TAIR10.gff3)
  -m <memefile>          MEME motif file              (default: data/Franco-Zorrilla_et_al_2014.meme)
  -g <gene_list>         user gene list               (default: data/genes/genes_cell_type_treatment.txt)

Homotypic parameters:
  -i <gff3_id_key>       GFF3 attribute key, e.g. gene_id= or ID=  (default: gene_id=)
  -F <gene_features>     all | strict                              (default: all)
  -v <overlap_mode>      AllowOverlap | NoOverlap                  (default: NoOverlap)
  -u <include_utr>       Yes | No                                  (default: Yes)
  -n <topn>              top n promoter hits per motif             (default: 5000)
  -k <max_k>             max motif hits per promoter               (default: 5)
  -p <promoter_length>   promoter length in bp                     (default: 1000)
  -f <fimo_threshold>    FIMO p-value threshold                    (default: 0.05)
  -P <isPoisson>         true | false                              (default: false)

Heterotypic / runtime:
  -c <ic_threshold>      pairing IC threshold                      (default: 4)
  -t <threads>           threads                                   (default: 4)
  -K <keep_intermediate> true | false                              (default: false)

Output directories:
  -o <homotypic_dir>     homotypic output dir   (default: results/03_promoter/01_homotypic)
  -x <heterotypic_dir>   heterotypic output dir (default: results/03_promoter/02_heterotypic)
  -y <plot_dir>          plot output dir        (default: results/03_promoter/plot)

  -h                     show this help
EOF
}

# ==================== Defaults ====================

genome=data/TAIR10.fasta
anno=data/TAIR10.gff3
meme=data/Franco-Zorrilla_et_al_2014.meme

task=genes_cell_type_treatment
gene_input_file=data/genes/$task.txt

# Homotypic parameters
gff3id="gene_id="
gene_features=all        # all / strict — see docs/contracts/homotypic.md
                         #   all    → regex 'gene$': gene + ncRNA_gene + pseudogene + …
                         #   strict → regex '^gene$': only canonical 'gene' rows
overlap=NoOverlap        # AllowOverlap | NoOverlap
utr=Yes                  # Yes | No
topn=5000
maxk=5
length=1000
fimothresh=0.05
isPoisson=false

# Heterotypic parameters
icthresh=4

# Runtime
threads=4

# Behavior
keep_intermediate=false  # true: retain all per-stage scratch files

# Output
res_dir=results/03_promoter
homotypic_output=
heterotypic_output=
plot_output=

# ==================== Argument parsing ====================

while getopts ":s:a:m:g:i:F:v:u:n:k:p:f:P:c:t:K:o:x:y:h" opt; do
    case $opt in
        s) genome=$OPTARG ;;
        a) anno=$OPTARG ;;
        m) meme=$OPTARG ;;
        g) gene_input_file=$OPTARG ;;
        i) gff3id=$OPTARG ;;
        F) gene_features=$OPTARG ;;
        v) overlap=$OPTARG ;;
        u) utr=$OPTARG ;;
        n) topn=$OPTARG ;;
        k) maxk=$OPTARG ;;
        p) length=$OPTARG ;;
        f) fimothresh=$OPTARG ;;
        P) isPoisson=$OPTARG ;;
        c) icthresh=$OPTARG ;;
        t) threads=$OPTARG ;;
        K) keep_intermediate=$OPTARG ;;
        o) homotypic_output=$OPTARG ;;
        x) heterotypic_output=$OPTARG ;;
        y) plot_output=$OPTARG ;;
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

: "${homotypic_output:=$res_dir/01_homotypic}"
: "${heterotypic_output:=$res_dir/02_heterotypic}"
: "${plot_output:=$res_dir/plot}"

# Binaries / tools
BIN_DIR=build
BIN_INDEX="$BIN_DIR/index_fimo_fused"
BIN_PMET="$BIN_DIR/pair_parallel"
PY=scripts/python

# Derived paths (inside homotypic_output)
universefile="$homotypic_output/universe.txt"
bedfile="$homotypic_output/genelines.bed"
promoters="$homotypic_output/promoters.bed"
stripped="$homotypic_output/genome_stripped.fa"

# ==================== Preflight ====================

if [[ ! -s "$genome" || ! -s "$anno" ]]; then
    print_green "Downloading genome and annotation..."
    bash pipeline/data/fetch_tair10.sh
fi

check_file "$genome" "Genome"
check_file "$anno"   "GFF3 annotation"
check_file "$meme"   "MEME motif file"
check_file "$gene_input_file" "Gene list"

for cmd in samtools bedtools sortBed fasta-get-markov parallel python3; do
    check_dep "$cmd"
done
[[ -f "$BIN_INDEX" ]] || error_exit "Binary not found: $BIN_INDEX"
[[ -f "$BIN_PMET"  ]] || error_exit "Binary not found: $BIN_PMET"

# ---- Chromosome naming consistency ----
# Catch GFF3 vs FASTA naming mismatches early (e.g. "1" vs "Chr1")
gff3_chr=$(awk -F'\t' '!/^#/ && NF>=9 {print $1; exit}' "$anno")
fasta_chr=$(grep '^>' "$genome" | head -1 | sed 's/^>//' | awk '{print $1}')
if [[ "$gff3_chr" != "$fasta_chr" ]]; then
    error_exit "Chromosome name mismatch: GFF3 uses '$gff3_chr' but FASTA uses '$fasta_chr'. Please ensure consistent naming."
fi
print_fluorescent_yellow "   Preflight OK — chromosome naming consistent ('$gff3_chr')"

rm -rf "$homotypic_output" "$heterotypic_output" "$plot_output"
mkdir -p "$homotypic_output" "$heterotypic_output" "$plot_output"

grand_start=$SECONDS

# ==============================================================================
# [1] Homotypic: genome → promoter index (delegated to run_homotypic.py)
# ==============================================================================

print_green "\n[1/3] Homotypic motif search..."
h_start=$SECONDS

overlap_arg=AllowOverlap; is_no_overlap "$overlap" && overlap_arg=NoOverlap
utr_arg=No; is_yes "$utr" && utr_arg=Yes
poisson_flag=""
is_yes "$isPoisson" && poisson_flag="--poisson"
keep_flag=""
[[ "$keep_intermediate" == true ]] && keep_flag="--keep-intermediate"

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

print_elapsed_time "$h_start"

# ==============================================================================
# [2] Heterotypic: pair_parallel consumes the homotypic index
# ==============================================================================

print_green "\n[2/3] Heterotypic motif search..."

# Word-boundary match: avoid AT1G01010 spuriously matching AT1G010100 / AT1G01010.1
gene_tmp=$(mktemp)
trap 'rm -f "$gene_tmp"' EXIT
grep -wFf "$universefile" "$gene_input_file" > "$gene_tmp" || true

if [[ ! -s "$gene_tmp" ]]; then
    error_exit "No genes from the input list match the universe (homotypic stage filtered them all out)"
fi

# Record which input genes survived / dropped for downstream consumers.
# Written BEFORE pair_parallel so any later failure still leaves diagnostics.
cp "$gene_tmp" "$heterotypic_output/genes_used_PMET.txt"
grep -vwFf "$universefile" "$gene_input_file" > "$heterotypic_output/genes_not_found.txt" || true

"$BIN_PMET" \
    -d .                                            \
    -g "$gene_tmp"                                  \
    -i "$icthresh"                                  \
    -p "$homotypic_output/promoter_lengths.txt"     \
    -b "$homotypic_output/binomial_thresholds.txt"  \
    -c "$homotypic_output/IC.txt"                   \
    -f "$homotypic_output/fimohits"                 \
    -o "$heterotypic_output"                        \
    -t "$threads" > "$heterotypic_output/pmet.log"

# Merge ONLY pair_parallel's temp*.txt shards — naive `cat *.txt` would now
# also concatenate genes_used_PMET.txt / genes_not_found.txt.
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

print_green "\n[3/3] Generating heatmaps..."

draw() { Rscript pipeline/r/draw_heatmap.R "$@"; }

draw All     "$plot_output/heatmap.png"                "$heterotypic_output/motif_output.txt" 5 3 6 FALSE
draw Overlap "$plot_output/heatmap_overlap_unique.png" "$heterotypic_output/motif_output.txt" 5 3 6 TRUE
draw Overlap "$plot_output/heatmap_overlap.png"        "$heterotypic_output/motif_output.txt" 5 3 6 FALSE

print_green "\nDone."
print_elapsed_time "$grand_start"
