#!/bin/bash
# Shared body of the genomic-elements pipelines (06_elements_longest.sh
# and 07_elements_merged.sh). Designed to be `source`d by those wrappers
# after they have set:
#
#   strategy       — "longest" or "merged"
#   res_dir        — output root, e.g. results/06_elements_longest
#   delete_temp    — "yes" or "no" (passed to pmet_index_element.sh -d)
#   purpose_text   — banner string printed at start
#
# Everything below is identical between 06 and 07. Extracted in Stage 6
# of the cleanup roadmap; verified byte-identical against the recorded
# 06 / 07 baselines.

source "$script_dir/pipeline/lib/print_colors.sh"
source "$script_dir/pipeline/lib/timer.sh"

data_dir="$script_dir/data"
fetch_script="$script_dir/pipeline/data/fetch_tair10.sh"

echo -e "\n\n"
print_middle "$purpose_text"


########################## 1. Downloading data #######################################
if [[ ! -s "$data_dir/TAIR10.fasta" || ! -s "$data_dir/TAIR10.gff3" ]]; then
    print_fluorescent_yellow "Downloading genome and annotation...\n"
    bash "$fetch_script"
else
    print_green "Genome and annotation are ready!"
fi


start_time=$SECONDS
################################ 2. input parameters ###################################
# tool
toolDir=pipeline
HOMOTYPIC=$toolDir/indexing/pmet_index_element.sh
HETEROTYPIC=build/pair_parallel

threads=8

# homotypic
overlap="NoOverlap"
utr="Yes"
topn=5000
maxk=5
length=1000
fimothresh=0.05
distance=1000
gff3id="gene_id="

# data
genome=data/TAIR10.fasta
anno=data/TAIR10.gff3
meme=data/Franco-Zorrilla_et_al_2014.meme

# Chromosome naming consistency. Without this, a GFF3 using "1" against a
# FASTA using "Chr1" silently produces an empty element BED — every
# downstream step appears to succeed but indexes nothing.
gff3_chr=$(awk -F'\t' '!/^#/ && NF>=9 {print $1; exit}' "$anno")
fasta_chr=$(grep '^>' "$genome" | head -1 | sed 's/^>//' | awk '{print $1}')
if [[ "$gff3_chr" != "$fasta_chr" ]]; then
    print_red "Chromosome name mismatch: GFF3 uses '$gff3_chr' but FASTA uses '$fasta_chr'."
    print_red "Please ensure consistent naming between the genome and the annotation."
    exit 1
fi


# genomic element
echo -e "Select the genomic element:\n    1. 3' UTR\n    2. 5' UTR\n    3. mRNA\n    4. CDS\n    5. Exon"
read -p "Enter your choice (1/2/3/4/5): " choice
case $choice in
    1) genomic_element="three_prime_UTR"; gff3id='Parent=transcript:' ;;
    2) genomic_element="five_prime_UTR"; gff3id='Parent=transcript:' ;;
    3) genomic_element="mRNA"; gff3id='ID=transcript:';;
    4) genomic_element="CDS"; gff3id='Parent=transcript:' ;;
    5) genomic_element="exon"; gff3id='Parent=transcript:' ;;
    *) echo "Invalid choice. Please enter 1-5."; exit 1 ;;
esac
print_fluorescent_yellow "Chosen Genomic Element: $genomic_element"
print_fluorescent_yellow "GFF3 ID format: $gff3id"


# output
homotypic_output=$res_dir/01_homotypic
het_output_base=$res_dir/02_heterotypic
plot_output_base=$res_dir/03_plot
icthresh=4

mkdir -p $homotypic_output

# Indexer + heterotypic binary must be executable. Without this chmod,
# pmet_index_element.sh aborts with Permission denied on a fresh checkout
# (the file is committed mode 0644 in git).
chmod a+x "$HOMOTYPIC" "$HETEROTYPIC"


############################## 3. Running homotypic #################################
print_green "Running homotypic searching...\n"

$HOMOTYPIC               \
    -r $toolDir          \
    -o $homotypic_output \
    -s $strategy         \
    -e $genomic_element  \
    -i $gff3id           \
    -k $maxk             \
    -n $topn             \
    -p $length           \
    -v $overlap          \
    -u $utr              \
    -f $fimothresh       \
    -t $threads          \
    -d $delete_temp      \
    $genome              \
    $anno                \
    $meme

for task in "salt_top300" "random_genes_300" "genes_cell_type_treatment" "gene_cortex_epidermis_pericycle" "heat_top300"; do

    heterotypic_output=${het_output_base}_${task}
    plot_output=${plot_output_base}_${task}
    gene_input_file=data/genes/$task.txt
    mkdir -p $heterotypic_output
    mkdir -p $plot_output

    ############################ 4. Running heterotypic ###############################
    print_green "\n\nSearching for heterotypic motif hits...\n"

    # remove genes not present in pre-computed pmet index
    grep -Ff $homotypic_output/universe.txt $gene_input_file > $heterotypic_output/new_genes_temp.txt

    $HETEROTYPIC                                     \
        -d .                                         \
        -g $heterotypic_output/new_genes_temp.txt    \
        -i $icthresh                                 \
        -p $homotypic_output/promoter_lengths.txt    \
        -b $homotypic_output/binomial_thresholds.txt \
        -c $homotypic_output/IC.txt                  \
        -f $homotypic_output/fimohits                \
        -o $heterotypic_output                       \
        -t $threads > $heterotypic_output/pmet.log

    rm -f $heterotypic_output/new_genes_temp.txt
    # Idempotent aggregate. On a re-run an old motif_output.txt would
    # otherwise be picked up by the *.txt glob (and self-amplify after a
    # mktemp staging step). Remove it first, then aggregate via temp.
    rm -f $heterotypic_output/motif_output.txt
    concat_tmp=$(mktemp)
    cat $heterotypic_output/*.txt > "$concat_tmp"
    # `-f`: pair_parallel does not always emit temp*.txt files (depends on
    # whether any temp scratch survived); without it the rm fails under
    # `set -e` with "No such file or directory".
    rm -f $heterotypic_output/temp*.txt
    mv "$concat_tmp" $heterotypic_output/motif_output.txt

    print_elapsed_time $start_time

    print_green "DONE: heterotypic search"

    ##################################### Heatmap ##################################
    print_green "\n\nCreating heatmap...\n"

    Rscript pipeline/r/draw_heatmap.R            \
        All                                     \
        $plot_output/heatmap.png                \
        $heterotypic_output/motif_output.txt    \
        15                                      \
        3                                       \
        6                                       \
        FALSE

    Rscript pipeline/r/draw_heatmap.R            \
        Overlap                                 \
        $plot_output/heatmap_overlap_unique.png \
        $heterotypic_output/motif_output.txt    \
        15                                      \
        3                                       \
        6                                       \
        TRUE

    Rscript pipeline/r/draw_heatmap.R            \
        Overlap                                 \
        $plot_output/heatmap_overlap.png        \
        $heterotypic_output/motif_output.txt    \
        15                                      \
        3                                       \
        6                                       \
        FALSE
done
