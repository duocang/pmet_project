#!/bin/bash
set -e

function usage () {
    cat >&2 <<EOF
USAGE: PMETindexgenome [options] <genome> <gff3> <memefile>

Creates PMET index for Paired Motif Enrichment Test using genome files.
Required arguments:
-r <PMETindex_path>	: Full path of python scripts called from this file. Required.
-i <gff3_identifier> : gene identifier in gff3 file e.g. gene_id=

Optional arguments:
-o <output_directory> : Output directory for results
-n <topn>	: How many top promoter hits to take per motif. Default=5000
-k <max_k>	: Maximum motif hits allowed within each promoter.  Default: 5
-p <promoter_length>	: Length of promoter in bp used to detect motif hits default: 1000
-v <include_overlaps> :  Remove promoter overlaps with gene sequences. AllowOverlap or NoOverlap, Default : AllowOverlap
-u <include_UTR> : Include 5' UTR sequence? Yes or No, default : No
-f <fimo_threshold> : Specify a minimum quality for hits matched by fimo. Default: 0.05

EOF
}

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


function merge_intervals() {
    local input_file=$1
    local output_file=$2
    local temp_file=$(dirname "$input_file")/temp_sorted.bed

    # 首先对文件进行排序
    sort -k4,4 -k2,2n "$input_file" > "$temp_file"

    # 然后合并区间
    awk 'BEGIN {OFS="\t"} {
        if (gene == $4) {
            if ($2 <= end) {
                if ($3 > end) {
                    end = $3;
                }
            } else {
                if (NR != 1) {
                    print chr, start, end, gene, score, strand;
                }
                chr = $1; start = $2; end = $3; gene = $4; score = $5; strand = $6;
            }
        } else {
            if (NR != 1) {
                print chr, start, end, gene, score, strand;
            }
            chr = $1; start = $2; end = $3; gene = $4; score = $5; strand = $6;
        }
    } END {
        if (NR != 1) {
            print chr, start, end, gene, score, strand;
        }
    }' "$temp_file" > "$output_file"

    # 清理临时文件
    rm -f "$temp_file"
}

process_genomic_element() {
    local item=$1
    local pmetroot=$2
    local indexingOutputDir=$3
    local gff3id=$4

    # 2. 提取注释中的基因行 Extract gene line from annotation
    if [[ "$(uname)" == "Linux" ]]; then
        grep -P "\t${item}\t" "$indexingOutputDir/sorted.gff3" > "$indexingOutputDir/${item}.gff3"
    elif [[ "$(uname)" == "Darwin" ]]; then
        grep "\t${item}\t" "$indexingOutputDir/sorted.gff3" > "$indexingOutputDir/${item}.gff3"
    fi

    # 3. 提取染色体，起始，结束，基因 Extract chromosome, start, end, gene
    python3 "$pmetroot/python/parse_mRNAlines.py" "$gff3id" "$indexingOutputDir/${item}.gff3" "$indexingOutputDir/temp1.bed"

    # 4. 过滤无效的基因 Filter invalid genes
    awk '$2 < $3' "$indexingOutputDir/temp1.bed" > "$indexingOutputDir/temp2.bed"

    # 5. 将异构体名称转换为基因名 Convert isoform name to gene
    awk -v OFS="\t" '{split($4, arr, "."); $4 = arr[1]; print $0}' "$indexingOutputDir/temp2.bed" > "$indexingOutputDir/temp3.bed"

    # 6. 删除重复行 Remove duplicated rows
    awk '!seen[$1,$2,$3,$4]++' "$indexingOutputDir/temp3.bed" > "$indexingOutputDir/temp4.bed"

    # 7. 合并具有相同基因的行 Merge rows with same gene
    merge_intervals "$indexingOutputDir/temp4.bed" "$indexingOutputDir/${item}.bed"
    # 清理临时文件 Clean up temporary files
    rm -rf "$indexingOutputDir"/temp*.bed
    rm -rf "$indexingOutputDir/${item}.gff3"
}
# 调用函数时需要提供 Required when calling the function item, bedfile, pmetroot, indexingOutputDir, gff3id
# process_genomic_element "item" "pmetroot" "indexingOutputDir" "gff3id"



# set up defaults
topn=5000
maxk=5
promlength=1000
fimothresh=0.05
element=mRNA
mrnaFull=No
delete=yes
overlap="AllowOverlap"
utr="No"
gff3id='transcript:'
pmetroot="scripts"
buildDir="build"
threads=4
icthreshold=24

# set up empty variables

indexingOutputDir=
genomefile=
gff3file=
memefile=

# deal with arguments
# if none, exit
if [ $# -eq 0 ]
    then
        echo "No arguments supplied"  >&2
        usage
        exit 1
fi

while getopts ":r:i:o:n:k:p:f:v:u:e:m:t:d:" options; do
    case $options in
        r) pmetroot=$OPTARG;;
        i) gff3id=$OPTARG;;
        o) indexingOutputDir=$OPTARG;;
        n) topn=$OPTARG;;
        k) maxk=$OPTARG;;
        p) promlength=$OPTARG;;
        f) fimothresh=$OPTARG;;
        v) overlap=$OPTARG;;
        u) utr=$OPTARG;;
        e) element=$OPTARG;;
        m) mrnaFull=$OPTARG;;
        t) threads=$OPTARG;;
        d) delete=$OPTARG;;
        \?) print_red  "Invalid option: -$OPTARG" >&2
        exit 1;;
        :)  print_red "Option -$OPTARG requires an argument." >&2
        exit 1;;
    esac
done


shift $((OPTIND - 1))
genomefile=$1
gff3file=$2
memefile=$3
universefile=$indexingOutputDir/universe.txt
bedfile=$indexingOutputDir/${element}.bed


print_white "Genome file                  : "; print_orange $genomefile
print_white "Annotation file              : "; print_orange $gff3file
print_white "Motif meme file              : "; print_orange $memefile

print_white "PMET index path              : "; print_orange "$pmetroot"
print_white "GFF3 identifier              : "; print_orange "$gff3id"
print_white "Genomic element              : "; print_orange "$element"
print_white "Output directory             : "; print_orange "$indexingOutputDir"
print_white "Top n promoters              : "; print_orange "$topn"  # Default to 5000 if not set
print_white "Top k motif hits             : "; print_orange "$maxk"     # Default to 5 if not set
print_white "Length of promoter           : "; print_orange "$promlength"  # Default to 1000 if not set
print_white "Fimo threshold               : "; print_orange "$fimothresh"
print_white "Promoter overlap handling    : "; print_orange "$overlap"
print_white "Include 5' UTR               : "; print_orange "$utr"
print_white "Number of threads            : "; print_orange "$threads"

mkdir -p $indexingOutputDir

start=$SECONDS

print_green "Preparing data for FIMO and PMET index..."

# -------------------------------------------------------------------------------------------
# 1. sort annotaion by gene coordinates
print_fluorescent_yellow "     1. Sorting annotation by gene coordinates"
$pmetroot/gff3sort/gff3sort.pl $gff3file > $indexingOutputDir/sorted.gff3

# -------------------------------------------------------------------------------------------
# 2. extract gene line from annoitation
print_fluorescent_yellow "     2. Extracting gene line from annoitation"
# grep -P '\mRNA\t' $indexingOutputDir/sorted.gff3 > $indexingOutputDir/genelines.gff3
if [[ "$(uname)" == "Linux" ]]; then
    grep -P "\t${element}\t" $indexingOutputDir/sorted.gff3 > $indexingOutputDir/genelines.gff3
elif [[ "$(uname)" == "Darwin" ]]; then
    grep    "\t${element}\t" $indexingOutputDir/sorted.gff3 > $indexingOutputDir/genelines.gff3
else
    print_red "Unsupported operating system."
fi

# -------------------------------------------------------------------------------------------
# 3. extract chromosome , start, end, gene ('gene_id' for input) ...
print_fluorescent_yellow "     3. Extracting chromosome, start, end, gene"
python3 $pmetroot/python/parse_mRNAlines.py $gff3id $indexingOutputDir/genelines.gff3 $bedfile

# -------------------------------------------------------------------------------------------
# 4. filter invalid genes: start should be smaller than end
invalidRows=$(awk '$2 >= $3' $bedfile)
if [[ -n "$invalidRows" ]]; then
    echo "$invalidRows" > $indexingOutputDir/invalid_lines.bed
fi
print_fluorescent_yellow "     4. Extracting genes coordinates: start < end (genelines.bed)"
# 在BED文件格式中，无论是正链（+）还是负链（-），起始位置总是小于终止位置。
# In the BED file format, the start position is always less than the end position for both positive (+) and negative (-) chains.
# 起始和终止位置是指定基因上的物理位置，而不是表达或翻译的方向。
# start and end positions specify the physical location of the gene, rather than the direction of expression or translation.
# starting site < stopped site in bed file
awk '$2 <  $3' $bedfile > temp.bed && mv temp.bed $bedfile


# -------------------------------------------------------------------------------------------
# 5. remove duplicated rows （col4)
print_fluorescent_yellow "     5. Removing duplicated rows (col4) and keepping longgest"
# awk '!seen[$1,$2,$3,$4]++' $bedfile> $indexingOutputDir/6_filtered.bed

# 创建一个临时的 R 脚本 Create a temporary R script
temp_r_script=$(mktemp)

# 将 R 代码写入临时文件 Write R code to temporary file
cat <<EOF >"$temp_r_script"
# R 代码开始
args <- commandArgs(trailingOnly = TRUE)
input_file <- args[1]
output_file <- args[2]

bedfile <- read.table(input_file, header = FALSE, sep = "\t", stringsAsFactors = FALSE)
names(bedfile) <- c("chr", "start", "end", "gene", "score", "strand")

# 计算每行的长度，并添加到数据框中
bedfile\$length <- bedfile\$end - bedfile\$start

# 对每个基因保留长度最大的行
suppressPackageStartupMessages(library(dplyr))
result <- bedfile %>%
  group_by(gene) %>%
  filter(length == max(length)) %>%
  slice(1) # 选择每个组的第一行

# 写入结果到文件
write.table(result[, 1:6], output_file, quote = FALSE, sep = "\t", row.names = FALSE, col.names = FALSE)
# R 代码结束
EOF


Rscript "$temp_r_script" "$bedfile" "$indexingOutputDir/5_filtered.bed"

# 清理临时文件
rm "$temp_r_script"

rm -rf $bedfile
mv $indexingOutputDir/5_filtered.bed $bedfile
rm -rf $indexingOutputDir/5_filtered.bed


# -------------------------------------------------------------------------------------------
# 6. list of all genes found
print_fluorescent_yellow "     6. Extracting all genes found (universe.txt)"
awk '$4 !~ /^__/ {print $4}' "$bedfile" > $indexingOutputDir/universe.txt


# -------------------------------------------------------------------------------------------
# 7. promoter lenfths from promoters.bed
print_fluorescent_yellow "     7. Measuring promoter lengths"
awk '{print $4 "\t" ($3 - $2)}' "$bedfile" > $indexingOutputDir/promoter_lengths.txt


# -------------------------------------------------------------------------------------------
# 8. strip the potential FASTA line breaks. creates genome_stripped.fa
print_fluorescent_yellow "     8. Removing potential FASTA line breaks (genome_stripped.fa)"
awk '/^>/ { if (NR!=1) print ""; printf "%s\n",$0; next;} \
    { printf "%s",$0;} \
    END { print ""; }'  $genomefile > $indexingOutputDir/genome_stripped.fa


# -------------------------------------------------------------------------------------------
# 8. create promoters fasta
print_fluorescent_yellow "     9. Creating FASTA file (promoter_rought.fa)";
bedtools getfasta \
        -fi  $indexingOutputDir/genome_stripped.fa \
        -bed $bedfile                              \
        -fo  $indexingOutputDir/promoter_rought.fa \
        -name

# -------------------------------------------------------------------------------------------
# 11. replace the id of each seq with gene names
print_fluorescent_yellow "    10. Replacing the id of each sequences' with gene names (promoter.fa)"
sed 's/::.*//g' $indexingOutputDir/promoter_rought.fa > $indexingOutputDir/promoter.fa

# check if any duplicated id
grep "^>" $indexingOutputDir/promoter.fa > $indexingOutputDir/ids.txt
sort $indexingOutputDir/ids.txt | uniq -d > $indexingOutputDir/duplicate_ids.txt
if [ ! -s $indexingOutputDir/duplicate_ids.txt ]; then
    rm -rf $indexingOutputDir/ids.txt
    rm -rf $indexingOutputDir/duplicate_ids.txt
fi

# -------------------------------------------------------------------------------------------
# 11. promoter.bg from promoter.fa
print_fluorescent_yellow "    11. fasta-get-markov estimates a Markov model from promoter.fa. (promoter.bg)"
fasta-get-markov $indexingOutputDir/promoter.fa > $indexingOutputDir/promoter.bg

# -------------------------------------------------------------------------------------------
# 12. IC.txt
print_fluorescent_yellow "    12. Generating information content (IC.txt)"
[ ! -d $indexingOutputDir/memefiles ] && mkdir $indexingOutputDir/memefiles
python3 $pmetroot/python/parse_memefile.py $memefile $indexingOutputDir/memefiles/
python3 $pmetroot/python/calculateICfrommeme_IC_to_csv.py \
    $indexingOutputDir/memefiles/                  \
    $indexingOutputDir/IC.txt
rm -rf $indexingOutputDir/memefiles/*

# -------------------------------------------------------------------------------------------
# 13. individual motif files from user's meme file
print_fluorescent_yellow "    13. Spliting motifs into individual meme files (folder memefiles)"
python3 $pmetroot/python/parse_memefile_batches.py $memefile $indexingOutputDir/memefiles/ $threads

# -------------------------------- Run fimo and pmetindex --------------------------
[ ! -d $indexingOutputDir/fimohits ] && mkdir $indexingOutputDir/fimohits

print_green "Running FIMO and PMET index..."
runFimoIndexing () {
    memefile=$1
    indexingOutputDir=$2
    fimothresh=$3
    buildDir=$4
    maxk=$5
    topn=$6
    filename=`basename $memefile .txt`

    $buildDir/fimo                              \
        --no-qvalue                             \
        --text                                  \
        --thresh $fimothresh                    \
        --verbosity 1                           \
        --bgfile $indexingOutputDir/promoter.bg \
        --topn $topn                            \
        --topk $maxk                            \
        --oc $indexingOutputDir/fimohits        \
        $memefile                               \
        $indexingOutputDir/promoter.fa          \
        $indexingOutputDir/promoter_lengths.txt
}
export -f runFimoIndexing

nummotifs=$(grep -c '^MOTIF' "$memefile")
print_orange "    $nummotifs motifs found"

find $indexingOutputDir/memefiles -name \*.txt \
    | parallel --progress --jobs=$threads \
        "runFimoIndexing {} $indexingOutputDir $fimothresh $buildDir $maxk $topn"

mv $indexingOutputDir/fimohits/binomial_thresholds.txt $indexingOutputDir/

# -------------------------------------------------------------------------------------------
# Deleting unnecessary files
lowercase_delete=$(echo "$delete" | tr '[:upper:]' '[:lower:]')
if [[ "$lowercase_delete" == "yes" || "$lowercase_delete" == "y" ]]; then
    print_green "Deleting unnecessary files...\n\n"
    # rm -rf $indexingOutputDir/IC.txt
    # rm -rf $indexingOutputDir/binomial_thresholds.txt
    rm -rf $indexingOutputDir/filtered_bedfile.bed
    # rm -rf $indexingOutputDir/fimohits
    rm -rf $indexingOutputDir/fimohits_
    rm -rf $indexingOutputDir/five_prime_UTR.bed
    rm -rf $indexingOutputDir/genelines.gff3
    rm -rf $indexingOutputDir/genome_stripped.fa
    rm -rf $indexingOutputDir/genome_stripped.fa.fai
    rm -rf $indexingOutputDir/id_duplicated.txt
    rm -rf $indexingOutputDir/mRNA.bed
    # rm -rf $indexingOutputDir/memefiles
    rm -rf $indexingOutputDir/modified_bedfile.bed
    rm -rf $indexingOutputDir/promoter.bg
    rm -rf $indexingOutputDir/promoter.fa
    # rm -rf $indexingOutputDir/promoter_lengths.txt
    rm -rf $indexingOutputDir/promoter_rought.fa
    rm -rf $indexingOutputDir/sorted.gff3
    rm -rf $indexingOutputDir/three_prime_UTR.bed
    # rm -rf $indexingOutputDir/universe.txt
    rm -rf $indexingOutputDir/with_overlapping.bed
fi

# -------------------------------------------------------------------------------------------
# Checking results
print_green "Checking results...\n\n"
# 计算 $indexingOutputDir/fimohits 目录下 .txt 文件的数量
# Count the number of .txt files in the $indexingOutputDir/fimohits directory
file_count=$(find "$indexingOutputDir/fimohits" -maxdepth 1 -type f -name "*.txt" | wc -l)

# 检查文件数量是否等于 meotif的数量 （$nummotifs）
# Check if the number of files equals the number of meotifs ($nummotifs)
if [ "$file_count" -eq "$nummotifs" ]; then
    end=$SECONDS
    elapsed_time=$((end - start))
    days=$((elapsed_time/86400))
    hours=$(( (elapsed_time%86400)/3600 ))
    minutes=$(( (elapsed_time%3600)/60 ))
    seconds=$((elapsed_time%60))
    print_orange "      Time take: $days day $hours hour $minutes minute $seconds seconds"

    print_green "DONE: homotypic search"
else
    print_red "\nError: there are $file_count fimohits files, it should be $nummotifs."
fi

# # next stage needs the following inputs

# #   promoter_lengths.txt        made by parse_promoter_lengths.py from .bed file
# #   bimnomial_thresholds.txt    made by PMETindex
# #   IC.txt                      made by calculateICfrommeme.py from meme file
# #   gene input file             supplied by user
