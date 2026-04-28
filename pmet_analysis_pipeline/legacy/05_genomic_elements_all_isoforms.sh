#!/bin/bash

function error_exit() {
    echo "ERROR: $1" >&2
    usage
    exit 1
}
print_red(){
    RED='\033[0;31m'
    NC='\033[0m' # No Color
    printf "${RED}$1${NC}\n"
}
print_green(){
    GREEN='\033[0;32m'
    NC='\033[0m' # No Color
    printf "${GREEN}$1${NC}\n"
}
print_orange(){
    ORANGE='\033[0;33m'
    NC='\033[0m' # No Color
    printf "${ORANGE}$1${NC}\n"
}
print_fluorescent_yellow(){
    FLUORESCENT_YELLOW='\033[1;33m'
    NC='\033[0m' # No Color
    printf "${FLUORESCENT_YELLOW}$1${NC}\n"
}
print_white(){
    WHITE='\033[1;37m'
    NC='\033[0m' # No Color
    printf "${WHITE}$1${NC}"
}
print_middle(){
    FLUORESCENT_YELLOW='\033[1;33m'
    NC='\033[0m' # No Color
    # 获取终端的宽度
    COLUMNS=$(tput cols)
    # 遍历每一行
    while IFS= read -r line; do
        # 计算需要的空格数来居中文本
        padding=$(( (COLUMNS - ${#line}) / 2 ))
        printf "%${padding}s" ''
        printf "${FLUORESCENT_YELLOW}${line}${NC}\n"
    done <<< "$1"
}

script_dir=$(cd -- "$(dirname "$0")/.." && pwd)
cd "$script_dir"
data_dir="$script_dir/data"
fetch_script="$script_dir/scripts/fetch_tair10.sh"


# Give execute permission to all users for the file.
find . -type f \( -name "*.sh" -o -name "*.pl" \) -exec chmod a+x {} \;


echo -e "\n\n"
print_middle "The purpose of this script is to                                      \n"
print_middle "  1. List all isoforms of genes in each cluster you provide             "
print_middle "  2. Search motif pairs on each isoform of any genomic elemet           "
print_middle "                                                                      \n"



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
toolDir=scripts
HOMOTYPIC=$toolDir/indexing/genomic_element_all_isoforms.sh
HETEROTYPIC=build/pmetParallel

chmod a+x $HOMOTYPIC
chmod a+x $HETEROTYPIC

threads=8
res_dir=results/05_genomic_elements_all_isoforms

# homotypic
overlap="NoOverlap"
utr="Yes"
topn=5000
maxk=5
length=1000
fimothresh=0.05
distance=1000
gff3id="gene_id="
delete_temp=no

# data
genome=data/TAIR10.fasta
anno=data/TAIR10.gff3
meme=data/Franco-Zorrilla_et_al_2014.meme


# genomic element
echo -e "Select the genomic element:\n    1. 3' UTR\n    2. 5' UTR\n    3. mRNA\n    4. CDS\n    5. Exon"
read -p "Enter your choice (1/2/3/4): " choice
case $choice in
    1) genomic_element="three_prime_UTR"; gff3id='Parent=transcript:' ;;
    2) genomic_element="five_prime_UTR"; gff3id='Parent=transcript:' ;;
    3) genomic_element="mRNA"; gff3id='ID=transcript:';;
    4) genomic_element="CDS"; gff3id='Parent=transcript:' ;;
    5) genomic_element="exon"; gff3id='Parent=transcript:' ;;
    *) echo "Invalid choice. Please enter 1, 2, or 3."; exit 1 ;;
esac
print_fluorescent_yellow "Chosen Genomic Element: $genomic_element"
print_fluorescent_yellow "GFF3 ID format: $gff3id"

# output
homotypic_output=$res_dir/01_homotypic

# heterotypic
task=salt_top300
gene_input_file=data/genes/$task.txt
heterotypic_output=$res_dir/02_heterotypic
icthresh=4

# plot output
plot_output=$res_dir/03_plot

mkdir -p $homotypic_output

############################## 3. Running homotypic #################################
print_green "Running homotypic searching...\n"

$HOMOTYPIC               \
    -r $toolDir          \
    -o $homotypic_output \
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


############################ 4. Running heterotypic ###############################
print_green "\nSearching for heterotypic motif hits..."

# 创建一个临时的 R 脚本 Creating a Temporary R Script
# R 脚本的目的是列出所有的基因isoform The purpose of the R script is to extend all gene isoform
temp_r_script=$(mktemp)
# 将 R 代码写入临时文件 Write R code to a temporary file
cat <<EOF >"$temp_r_script"
suppressPackageStartupMessages(library(dplyr))

args            <- commandArgs(trailingOnly = TRUE)
input_file      <- args[1]
output_file     <- args[2]
max_num_isoform <- as.integer(args[3])
universe        <- args[4]

full_genes    <- read.table(universe)\$V1
genes_cluster <- read.table(input_file, header = FALSE, stringsAsFactors = FALSE)

# 扩展基因列表 Expand the gene isoforms
expanded_genes <- lapply(genes_cluster\$V2, function(gene) {
    paste0(gene, ".", seq_len(max_num_isoform))
}) %>% unlist()

expanded_clustter <- lapply(genes_cluster\$V1, function(x){rep(x, max_num_isoform)}) %>% unlist()

df <- data.frame(expanded_clustter, expanded_genes) %>%
  filter(expanded_genes %in% full_genes)

write.table(df, file = output_file, quote = FALSE, row.names = FALSE, col.names = FALSE)
EOF

# 从universe.txt中获取所有基因中isoform的最大数值
# Get the maximum value of isoform in all genes from universe.txt
max_num_isoform=0
while read -r line; do
    num=${line##*.}
    if (( num > max_num_isoform )); then
        max_num_isoform=$num
    fi
done < $homotypic_output/universe.txt

# Perform pmet analysis on different types of gene clusters
for task in "salt_top300" "random_genes_300" "genes_cell_type_treatment" "gene_cortex_epidermis_pericycle" "heat_top300"; do
    print_orange "Gens: $task"

    # Per-task paths (avoid mutating the shared variables so iteration i+1
    # does not see `${heterotypic_output}_task_i_task_{i+1}`).
    het_out=${heterotypic_output}_${task}
    plot_out=${plot_output}_${task}
    gene_input_file=data/genes/$task.txt
    mkdir -p $het_out
    mkdir -p $plot_out
    # create gene with all possible isofrms in clusters
    Rscript "$temp_r_script"                     \
        "$gene_input_file"                       \
        "$het_out/new_genes_temp.txt"            \
        "$max_num_isoform"                        \
        "$homotypic_output/universe.txt"

    ##################################### PMET ##################################
    $HETEROTYPIC                                     \
        -d .                                         \
        -g $het_out/new_genes_temp.txt               \
        -i $icthresh                                 \
        -p $homotypic_output/promoter_lengths.txt    \
        -b $homotypic_output/binomial_thresholds.txt \
        -c $homotypic_output/IC.txt                  \
        -f $homotypic_output/fimohits                \
        -o $het_out                                  \
        -t $threads > $het_out/pmet.log

    rm $het_out/new_genes_temp.txt
    # merge pmet result
    cat $het_out/*.txt > $het_out/motif_output.txt
    rm $het_out/temp*.txt

    end_time=$SECONDS
    elapsed_time=$((end_time - start_time))
    days=$((elapsed_time/86400))
    hours=$(( (elapsed_time%86400)/3600 ))
    minutes=$(( (elapsed_time%3600)/60 ))
    seconds=$((elapsed_time%60))
    print_orange "      Time taken: $days day $hours hour $minutes minute $seconds second\n"

    ##################################### Heatmap ##################################
    print_green "Creating heatmap..."

    Rscript scripts/r/draw_heatmap.R   \
        All                            \
        $plot_out/heatmap.png          \
        $het_out/motif_output.txt      \
        15                             \
        3                              \
        6                              \
        FALSE > $plot_out/motifs.txt

    Rscript scripts/r/draw_heatmap.R       \
        Overlap                            \
        $plot_out/heatmap_overlap_unique.png \
        $het_out/motif_output.txt          \
        15                                 \
        3                                  \
        6                                  \
        TRUE > $plot_out/log.txt

    Rscript scripts/r/draw_heatmap.R   \
        Overlap                        \
        $plot_out/heatmap_overlap.png  \
        $het_out/motif_output.txt      \
        15                             \
        3                              \
        6                              \
        FALSE > $plot_out/log.txt
    rm -f "$plot_out/log.txt"
done

rm "$temp_r_script"
