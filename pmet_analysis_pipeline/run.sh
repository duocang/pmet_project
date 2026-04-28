#!/bin/bash
# ==============================================================================
# PMET Analysis Pipeline Runner
# ==============================================================================
# Interactive menu to select and run analysis pipelines
# ==============================================================================

set -euo pipefail

script_dir=$(cd -- "$(dirname "$0")" && pwd)
pipeline_dir="$script_dir/scripts/pipeline"

# Load color helpers
if [ -f "$script_dir/scripts/lib/print_colors.sh" ]; then
    source "$script_dir/scripts/lib/print_colors.sh"
else
    print_green()  { printf "\033[32m%s\033[0m\n" "$1"; }
    print_orange() { printf "\033[33m%s\033[0m\n" "$1"; }
    print_yellow() { printf "\033[93m%s\033[0m\n" "$1"; }
    print_red()    { printf "\033[31m%s\033[0m\n" "$1"; }
    print_white()  { printf "\033[37m%s\033[0m" "$1"; }
fi

# ==============================================================================
# Pipeline Descriptions
# ==============================================================================

get_description() {
    case "$1" in
        00_requirements.sh)         echo "Check system requirements and setup PMET environment" ;;
        01_benchmark_cpu.sh)        echo "Benchmark heterotypic analysis (single CPU vs parallel)" ;;
        02_benchmark_parameters.sh) echo "Benchmark PMET parameters on promoters" ;;
        03_promoter.sh)             echo "Run PMET on promoter regions" ;;
        04_intervals.sh)            echo "Run PMET on genomic intervals (e.g., ATAC-seq peaks)" ;;
        05_promoter_gap.sh)         echo "Run PMET on promoters with a TSS-proximal gap" ;;
        06_elements_longest.sh)     echo "Run PMET on a genomic element (longest isoform per gene)" ;;
        07_elements_merged.sh)      echo "Run PMET on a genomic element (merged isoforms per gene)" ;;
        08_pair_only.sh)            echo "Re-pair an existing index (skips homotypic; needs 03 output by default)" ;;
        *) echo "No description available" ;;
    esac
}

# ==============================================================================
# Functions
# ==============================================================================

show_header() {
    clear
    print_yellow "╔══════════════════════════════════════════════════════════════════╗"
    print_yellow "║              PMET Analysis Pipeline Runner                       ║"
    print_yellow "╚══════════════════════════════════════════════════════════════════╝"
    echo
}

show_menu() {
    print_orange "Available Pipelines:"
    print_orange "────────────────────────────────────────────────────────────────────"
    echo

    local i=0
    for script in "${pipelines[@]}"; do
        local desc=$(get_description "$script")
        print_white "  [$i] "
        print_green "$script"
        print_orange "      $desc"
        echo
        i=$((i + 1))
    done

    print_orange "────────────────────────────────────────────────────────────────────"
    print_white "  [q] "
    echo "Quit"
    echo
}

run_pipeline() {
    local script="$1"
    local script_path="$pipeline_dir/$script"

    if [ ! -f "$script_path" ]; then
        print_red "Error: Script not found: $script_path"
        return 1
    fi

    echo
    print_yellow "══════════════════════════════════════════════════════════════════"
    print_green "Running: $script"
    print_yellow "══════════════════════════════════════════════════════════════════"
    echo

    local start_time=$SECONDS
    case "$script" in
        03_promoter.sh)
            # Explicitly pass the canonical TAIR10 demo data and parameters.
            # 03_promoter.sh accepts overrides via getopts; defaults inside
            # the script match these values.
            bash "$script_path" \
                -s "data/TAIR10.fasta"                         \
                -a "data/TAIR10.gff3"                          \
                -m "data/Franco-Zorrilla_et_al_2014.meme"      \
                -g "data/genes/genes_cell_type_treatment.txt"  \
                -i "gene_id="                                  \
                -F "all"                                       \
                -v "NoOverlap"                                 \
                -u "Yes"                                       \
                -n 5000                                        \
                -k 5                                           \
                -p 1000                                        \
                -f 0.05                                        \
                -P "false"                                     \
                -c 4                                           \
                -t 4                                           \
                -K "false"                                     \
                -o "results/03_promoter/01_homotypic"          \
                -x "results/03_promoter/02_heterotypic"        \
                -y "results/03_promoter/plot"
            ;;
        04_intervals.sh)
            # Explicitly pass the canonical bundled intervals demo data
            # and parameters. Defaults inside the script match these values.
            bash "$script_path" \
                -s "data/homotypic_intervals/intervals.fa"     \
                -m "data/homotypic_intervals/motif_more.meme"  \
                -g "data/homotypic_intervals/intervals.txt"    \
                -n 5000                                        \
                -k 5                                           \
                -f 0.05                                        \
                -c 4                                           \
                -t 1                                           \
                -o "results/04_intervals/01_homotypic"         \
                -x "results/04_intervals/02_heterotypic"
            ;;
        08_pair_only.sh)
            # Reuses pipeline 03's homotypic index and the same canonical
            # gene list. Requires 03 to have been run first (preflight will
            # fail with a clear error otherwise — run option [3] first).
            bash "$script_path" \
                -d "results/03_promoter/01_homotypic"           \
                -g "data/genes/genes_cell_type_treatment.txt"   \
                -o "results/08_pair_only/cell_type_treatment_ic4" \
                -i 4                                            \
                -t 4
            ;;
        *)
            bash "$script_path"
            ;;
    esac
    local exit_code=$?
    local elapsed=$(( SECONDS - start_time ))
    local hours=$(( elapsed / 3600 ))
    local minutes=$(( (elapsed % 3600) / 60 ))
    local seconds=$(( elapsed % 60 ))

    echo
    if [ $exit_code -eq 0 ]; then
        print_green "✓ Pipeline completed successfully!"
    else
        print_red "✗ Pipeline exited with code: $exit_code"
    fi
    printf "  Elapsed time: %02d:%02d:%02d (hh:mm:ss)\n" "$hours" "$minutes" "$seconds"

    echo
    print_white "Press Enter to continue..."
    read -r
}

# ==============================================================================
# Main
# ==============================================================================

# Get list of pipelines. Skip files starting with `_` — those are
# library bodies that pipeline wrappers `source`; not standalone
# entrypoints.
pipelines=()
for f in "$pipeline_dir"/*.sh; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    [[ "$name" == _* ]] && continue
    pipelines+=("$name")
done

if [ ${#pipelines[@]} -eq 0 ]; then
    print_red "No pipeline scripts found in $pipeline_dir"
    exit 1
fi

# Check if running with command line arguments
if [ $# -gt 0 ]; then
    arg="$1"

    # Try to match by index number
    if [[ "$arg" =~ ^[0-9]+$ ]]; then
        if [ "$arg" -ge 0 ] && [ "$arg" -lt ${#pipelines[@]} ]; then
            run_pipeline "${pipelines[$arg]}"
            exit $?
        else
            print_red "Error: Invalid pipeline index: $arg"
            print_orange "Valid range: 0-$((${#pipelines[@]}-1))"
            exit 1
        fi
    fi

    # Try to match by script name (exact match)
    for script in "${pipelines[@]}"; do
        if [ "$script" = "$arg" ]; then
            run_pipeline "$script"
            exit $?
        fi
    done

    # Try to match by partial name or keyword
    matches=()
    for i in "${!pipelines[@]}"; do
        if [[ "${pipelines[$i]}" == *"$arg"* ]]; then
            matches+=("$i")
        fi
    done

    if [ ${#matches[@]} -eq 1 ]; then
        run_pipeline "${pipelines[${matches[0]}]}"
        exit $?
    elif [ ${#matches[@]} -gt 1 ]; then
        print_red "Error: Ambiguous match for '$arg'. Multiple pipelines found:"
        for idx in "${matches[@]}"; do
            print_orange "  [$idx] ${pipelines[$idx]}"
        done
        exit 1
    else
        print_red "Error: No pipeline found matching '$arg'"
        print_orange "Available pipelines:"
        for i in "${!pipelines[@]}"; do
            print_orange "  [$i] ${pipelines[$i]}"
        done
        exit 1
    fi
fi

# Main loop (interactive mode)
while true; do
    show_header
    show_menu

    print_white "Select a pipeline [0-$((${#pipelines[@]}-1))] or [q]uit: "
    read -r choice

    case "$choice" in
        q|Q)
            print_green "Goodbye!"
            exit 0
            ;;
        [0-9]*)
            if [ "$choice" -ge 0 ] 2>/dev/null && [ "$choice" -lt ${#pipelines[@]} ] 2>/dev/null; then
                run_pipeline "${pipelines[$choice]}"
            else
                print_red "Invalid selection: $choice"
                sleep 1
            fi
            ;;
        *)
            print_red "Invalid input. Enter a number or 'q' to quit."
            sleep 1
            ;;
    esac
done
