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


# set up defaults
topn=5000
maxk=5
promlength=1000
fimothresh=0.05
overlap="AllowOverlap"
utr="No"
gff3id='gene_id'
pmetroot="scripts"
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

while getopts ":r:i:o:n:k:p:f:g:v:u:t:" options; do
    case $options in
        r) print_white "Full path of PMET_index                : "; print_orange "$OPTARG" >&2
        pmetroot=$OPTARG;;
        i) print_white "GFF3 feature identifier                : "; print_orange "$OPTARG" >&2
        gff3id=$OPTARG;;
        o) print_white "Output directory for results           : "; print_orange "$OPTARG" >&2
        indexingOutputDir=$OPTARG;;
        n) print_white "Top n promoter hits to take per motif  : "; print_orange "$OPTARG" >&2
        topn=$OPTARG;;
        k) print_white "Top k motif hits within each promoter  : "; print_orange "$OPTARG" >&2
        maxk=$OPTARG;;
        p) print_white "Promoter length                        : "; print_orange "$OPTARG" >&2
        promlength=$OPTARG;;
        f) print_white "Fimo threshold                         : "; print_orange "$OPTARG" >&2
        fimothresh=$OPTARG;;
        v) print_white "Remove promoter overlaps with sequences: "; print_orange "$OPTARG" >&2
        overlap=$OPTARG;;
        u) print_white "Include 5' UTR sequence?               : "; print_orange "$OPTARG" >&2
        utr=$OPTARG;;
        t) print_white "Number of threads                      : "; print_orange "$OPTARG" >&2
        threads=$OPTARG;;
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
bedfile=$indexingOutputDir/genelines.bed

mkdir -p $indexingOutputDir

start=$SECONDS

print_green "Preparing data for FIMO and PMET index..."

# -------------------------------------------------------------------------------------------
# 1. sort annotaion by gene coordinates
print_fluorescent_yellow "     1. Sorting annotation by gene coordinates"
chmod a+x $pmetroot/gff3sort/gff3sort.pl
$pmetroot/gff3sort/gff3sort.pl $gff3file > $indexingOutputDir/sorted.gff3


# -------------------------------------------------------------------------------------------
# 2. extract gene line from annoitation
print_fluorescent_yellow "     2. Extracting gene line from annoitation"
# grep -P '\tgene\t' $indexingOutputDir/sorted.gff3 > $indexingOutputDir/genelines.gff3
if [[ "$(uname)" == "Linux" ]]; then
    grep -P '\tgene\t' $indexingOutputDir/sorted.gff3 > $indexingOutputDir/genelines.gff3
elif [[ "$(uname)" == "Darwin" ]]; then
    grep '\tgene\t' $indexingOutputDir/sorted.gff3 > $indexingOutputDir/genelines.gff3
else
    echo "Unsupported operating system."
fi

# -------------------------------------------------------------------------------------------
# 3. extract chromosome , start, end, gene ('gene_id' for input) ...
print_fluorescent_yellow "     3. Extracting chromosome, start, end, gene ..."

# 使用grep查找字符串 check if gene_id is present
if grep -q "$gff3id" "$indexingOutputDir/genelines.gff3"; then
    python3 $pmetroot/parse_genelines.py $gff3id $indexingOutputDir/genelines.gff3 $bedfile
else
    gff3id='ID='
    python3 $pmetroot/parse_genelines.py $gff3id $indexingOutputDir/genelines.gff3 $bedfile
fi

# -------------------------------------------------------------------------------------------
# 4. filter invalid genes: start should be smaller than end
invalidRows=$(awk '$2 >= $3' $bedfile)
if [[ -n "$invalidRows" ]]; then
    echo "$invalidRows" > $outputdir/invalid_genelines.bed
fi
# awk '$2 >= $3' $bedfile > $outputdir/invalid_genelines.bed

print_fluorescent_yellow "     4. Extracting genes coordinates: start should be smaller than end (genelines.bed)"
awk '$2 <  $3' $bedfile > temp.bed && mv temp.bed $bedfile
# 在BED文件格式中，无论是正链（+）还是负链（-），起始位置总是小于终止位置。
# In the BED file format, the start position is always less than the end position for both positive (+) and negative (-) chains.
# 起始和终止位置是指定基因上的物理位置，而不是表达或翻译的方向。
# start and end positions specify the physical location of the gene, rather than the direction of expression or translation.
# starting site < stopped site in bed file


# -------------------------------------------------------------------------------------------
# 5. list of all genes found
print_fluorescent_yellow "     5. Extracting genes names: complete list of all genes found (universe.txt)"
cut -f 4 $bedfile > $universefile

# -------------------------------------------------------------------------------------------
# 6. strip the potential FASTA line breaks. creates genome_stripped.fa
print_fluorescent_yellow "     6. Removing potential FASTA line breaks (genome_stripped.fa)"
awk '/^>/ { if (NR!=1) print ""; printf "%s\n",$0; next;} \
    { printf "%s",$0;} \
    END { print ""; }'  $genomefile > $indexingOutputDir/genome_stripped.fa
# python3 $pmetroot/strip_newlines.py $genomefile $indexingOutputDir/genome_stripped_py.fa


# -------------------------------------------------------------------------------------------
# 7. create the .genome file which contains coordinates for each chromosome start
print_fluorescent_yellow "     7. Listing chromosome start coordinates (bedgenome.genome)"
samtools faidx $indexingOutputDir/genome_stripped.fa
cut -f 1-2 $indexingOutputDir/genome_stripped.fa.fai > $indexingOutputDir/bedgenome.genome

# -------------------------------------------------------------------------------------------
# 8. create promoters' coordinates from annotation
print_fluorescent_yellow "     8. Creating promoters' coordinates from annotation (promoters.bed)"
# 在bedtools中，flank是一个命令行工具，用于在BED格式的基因组坐标文件中对每个区域进行扩展或缩短。
# In bedtools, flank is a command-line tool used to extend or shorten each region in a BED format genomic coordinate file.
# 当遇到负链（negative strand）时，在区域的右侧进行扩展或缩短，而不是左侧。
# When a negative strand is encountered, it is expanded or shortened on the right side of the region, not the left.
bedtools flank \
    -l $promlength \
    -r 0 -s -i $bedfile \
    -g $indexingOutputDir/bedgenome.genome \
    > $indexingOutputDir/promoters_not_sorted.bed
# Sort by starting coordinate
sortBed -i $indexingOutputDir/promoters_not_sorted.bed > $indexingOutputDir/promoters.bed
rm -rf $indexingOutputDir/promoters_not_sorted.bed
cp $indexingOutputDir/promoters.bed $indexingOutputDir/8_promoters.bed

# -------------------------------------------------------------------------------------------
# 9. remove overlapping promoter chunks
if [[ $overlap == 'NoOverlap' || $overlap == "no" || $overlap == "NO" || $overlap == "No" || $overlap == "N" || $overlap == "n" ]]; then
	print_fluorescent_yellow "     9. Removing overlapping promoter chunks (promoters.bed)"
	sleep 0.1
	bedtools subtract \
        -a $indexingOutputDir/promoters.bed \
        -b $bedfile > $indexingOutputDir/promoters2.bed
	mv $indexingOutputDir/promoters2.bed $indexingOutputDir/promoters.bed
    cp $indexingOutputDir/promoters.bed $indexingOutputDir/9_promoters.bed
else
    print_fluorescent_yellow "     9. (skipped) Removing overlapping promoter chunks (promoters.bed)"
fi


# -------------------------------------------------------------------------------------------
# 10. check split promoters. if so, keep the bit closer to the TSS
print_fluorescent_yellow "    10. Checking split promoter (if so):  keep the bit closer to the TSS (promoters.bed)"
python3 $pmetroot/assess_integrity.py $indexingOutputDir/promoters.bed
cp $indexingOutputDir/promoters.bed $indexingOutputDir/10_promoters.bed

# -------------------------------------------------------------------------------------------
# 11. add 5' UTR
if [ $utr == 'Yes' ]; then
    print_fluorescent_yellow "    11. Adding UTRs...";
	python3 $pmetroot/parse_utrs.py \
        $indexingOutputDir/promoters.bed \
        $indexingOutputDir/sorted.gff3 $universefile
    cp $indexingOutputDir/promoters.bed $indexingOutputDir/11_promoters.bed
else
    print_fluorescent_yellow "    11. (skipped) Adding UTRs...";
fi

# -------------------------------------------------------------------------------------------
# 12. promoter lenfths from promoters.bed
print_fluorescent_yellow "    12. Promoter lengths from promoters.bed (promoter_lengths_all.txt)"
# python3 $pmetroot/parse_promoter_lengths.py \
#     $indexingOutputDir/promoters.bed \
#     $indexingOutputDir/promoter_lengths.txt
awk '{print $4 "\t" ($3 - $2)}' $indexingOutputDir/promoters.bed \
    > $indexingOutputDir/promoter_lengths_all.txt

# -------------------------------------------------------------------------------------------
# 13. filters out the rows with NEGATIVE lengths
print_fluorescent_yellow "    13. Filtering out the rows of promoter_lengths_all.txt with NEGATIVE lengths"
while read -r gene length; do
    # Check if the length is a positive number
    if (( length >= 0 )); then
        # Append rows with positive length to the output file
        echo "$gene $length" >> $indexingOutputDir/promoter_lengths.txt
    else
        # Append rows with negative length to the deleted file
        echo "$gene $length" >> $indexingOutputDir/promoter_length_deleted.txt
    fi
done < $indexingOutputDir/promoter_lengths_all.txt

# -------------------------------------------------------------------------------------------
# 14. remove NEGATIVE genes
if [ -f "$indexingOutputDir/promoter_length_deleted.txt" ]; then
    print_fluorescent_yellow "    14. Finding genes with NEGATIVE promoter lengths (genes_negative.txt)"
    cut -d " " \
        -f1  $indexingOutputDir/promoter_length_deleted.txt \
        > $indexingOutputDir/genes_negative.txt
else
    print_fluorescent_yellow "    14. (skipped) Finding genes with NEGATIVE promoter lengths (genes_negative.txt)"
fi
# -------------------------------------------------------------------------------------------
# 15. filter promoter annotation with negative length
if [ -f "$indexingOutputDir/promoter_length_deleted.txt" ]; then
    print_fluorescent_yellow "    15. Removing promoter with negative length (promoters.bed)"
    grep -v -w -f \
        $indexingOutputDir/genes_negative.txt \
        $indexingOutputDir/promoters.bed \
        > $indexingOutputDir/filtered_promoters.bed

    mv $indexingOutputDir/promoters.bed $indexingOutputDir/promoters_before_filter.bed
    mv $indexingOutputDir/filtered_promoters.bed $indexingOutputDir/promoters.bed
else
    print_fluorescent_yellow "    15. (skipped) Removing promoter with negative length (promoters.bed)"
fi

# -------------------------------------------------------------------------------------------
# 16. update gene list (no NEGATIVE genes)
print_fluorescent_yellow "    16. Updating gene list without NEGATIVE genes (universe.txt)";
cut -d " " -f1  $indexingOutputDir/promoter_lengths.txt > $universefile


# -------------------------------------------------------------------------------------------
# 17. create promoters fasta
print_fluorescent_yellow "    17. Creating promoters file (promoters_rough.fa)";
bedtools getfasta -fi                         \
    $indexingOutputDir/genome_stripped.fa     \
    -bed $indexingOutputDir/promoters.bed     \
    -fo $indexingOutputDir/promoters_rough.fa \
    -name

# -------------------------------------------------------------------------------------------
# 18. replace the id of each seq with gene names
print_fluorescent_yellow "    18. Replacing the id of each sequences' with gene names (promoters.fa)"
# awk 'BEGIN{OFS="\t"} NR==FNR{a[NR]=$4; next} /^>/{$0=">"a[++i]} 1' \
#     $indexingOutputDir/promoters.bed \
#     $indexingOutputDir/promoters_rough.fa \
#     > $indexingOutputDir/promoters.fa
# # python3 $pmetroot/parse_promoters.py \
# #     $indexingOutputDir/promoters_rough.fa \
# #     $indexingOutputDir/promoters.bed \
# #     $indexingOutputDir/promoters.fa
sed 's/::.*//g' $indexingOutputDir/promoters_rough.fa > $indexingOutputDir/promoters.fa

# -------------------------------------------------------------------------------------------
# 19. promoters.bg from promoters.fa
print_fluorescent_yellow "    19. fasta-get-markov estimates a Markov model from promoters.fa. (promoters.bg)"
fasta-get-markov $indexingOutputDir/promoters.fa > $indexingOutputDir/promoters.bg

# -------------------------------------------------------------------------------------------
# 20. individual motif files from user's meme file
print_fluorescent_yellow "    20. Spliting motifs into individual meme files (folder memefiles)"
[ ! -d $indexingOutputDir/memefiles ] && mkdir $indexingOutputDir/memefiles
python3 $pmetroot/parse_memefile.py $memefile $indexingOutputDir/memefiles/

# -------------------------------------------------------------------------------------------
# 21. IC.txt
print_fluorescent_yellow "    21. Generating information content (IC.txt)"
python3 $pmetroot/calculateICfrommeme_IC_to_csv.py \
    $indexingOutputDir/memefiles/ \
    $indexingOutputDir/IC.txt

# -------------------------------- Run fimo and pmetindex --------------------------
print_green "Running FIMO and PMET index..."
[ ! -d $indexingOutputDir/fimo     ] && mkdir $indexingOutputDir/fimo
[ ! -d $indexingOutputDir/fimohits ] && mkdir $indexingOutputDir/fimohits

runFimoIndexing () {
    memefile=$1
    indexingOutputDir=$2
    fimothresh=$3
    pmetroot=$4
    maxk=$5
    topn=$6
    filename=`basename $memefile .txt`

    fimo \
        --no-qvalue \
        --text \
        --thresh $fimothresh \
        --verbosity 1 \
        --bgfile $indexingOutputDir/promoters.bg\
        $memefile \
        $indexingOutputDir/promoters.fa \
        > $indexingOutputDir/fimo/$filename.txt
}
export -f runFimoIndexing

numfiles=$(ls -l $indexingOutputDir/memefiles/*.txt | wc -l)
print_orange "    $numfiles motifs found"

find $indexingOutputDir/memefiles -name \*.txt \
    | parallel --progress  --jobs=$threads \
        "runFimoIndexing {} $indexingOutputDir $fimothresh $pmetroot $maxk $topn"

print_green "Deleting unnecessary files..."

rm -rf $indexingOutputDir/genelines.gff3
rm -rf $indexingOutputDir/bedgenome.genome
rm -rf $bedfile
rm -rf $indexingOutputDir/genome_stripped.fa
rm -rf $indexingOutputDir/genome_stripped.fa.fai
rm -rf $indexingOutputDir/promoters.bed
rm -rf $indexingOutputDir/promoters_rough.fa
rm -rf $indexingOutputDir/genes_negative.txt
rm -rf $indexingOutputDir/promoter_length_deleted.txt
rm -rf $indexingOutputDir/memefiles
rm -rf $indexingOutputDir/promoters.bg
rm -rf $indexingOutputDir/promoters.fa
rm -rf $indexingOutputDir/sorted.gff3

# 计算 $indexingOutputDir/fimohits 目录下 .txt 文件的数量
# Count the number of .txt files in the $indexingOutputDir/fimohits directory
file_count=$(find "$indexingOutputDir/fimo" -maxdepth 1 -type f -name "*.txt" | wc -l)


# 检查文件数量是否等于 meotif的数量 （$numfiles）
# Check if the number of files equals the number of meotifs ($numfiles)
if [ "$file_count" -eq "$numfiles" ]; then
    # touch ${indexingOutputDir}_FLAG

    end=$(date +%s)
    time_taken=$((end - start))
    print_orange "Time taken: $time_taken seconds"

    print_green "DONE"
else
    print_green "Error: there are $file_count fimohits files, it should be $numfiles."
fi