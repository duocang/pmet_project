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

start_time=$SECONDS

################################ fimo + pmex indexing ########################################
output=results/04_FIMO_old_and_new/fimo_old
mkdir -p $output/fimo

print_green "Running old fimo...\n"
fimo                                               \
    --text                                         \
    --no-qvalue                                    \
    --thresh 0.05                                  \
    --verbosity 3                                  \
    --bgfile src/meme-5.5.3/fimo_test/promoters.bg \
    src/meme-5.5.3/fimo_test/motif.meme            \
    src/meme-5.5.3/fimo_test/promoters.fa          \
    > $output/a.txt

# split fimo result into results with motif name
awk -F '\t' -v output="$output/fimo" 'NR>1 {print > (output "/" $1 ".txt")}' $output/a.txt
rm -rf $output/a.txt


print_green "Running pmet indexing...\n"
# run pmet index
mkdir -p $output/fimohits

scripts/pmetindex                                    \
    -f $output/fimo                                  \
    -k 5                                             \
    -n 5000                                          \
    -p src/meme-5.5.3/fimo_test/promoter_lengths.txt \
    -o $output



# individual motif files from user's meme file
mkdir -p $output/memefiles
python3 scripts/python/parse_memefile.py src/meme-5.5.3/fimo_test/motif.meme $output/memefiles/

# IC.txt
python3 scripts/python/calculateICfrommeme_IC_to_csv.py \
    $output/memefiles/                          \
    $output/IC.txt


# # remove results of fimo to save sapce
rm -rf $output/fimo
rm -rf $output//memefiles/

###################################### new fimo ##############################################
print_green "Running new fimo is running ..."

chmod a+x scripts/fimo


output=results/04_FIMO_old_and_new/fimo_new

mkdir -p $output/fimohits


scripts/fimo                                       \
    --topk 5                                       \
    --topn 5000                                    \
    --text                                         \
    --no-qvalue                                    \
    --thresh 0.05                                  \
    --verbosity 3                                  \
    --oc $output/fimohits                          \
    --bgfile src/meme-5.5.3/fimo_test/promoters.bg \
    src/meme-5.5.3/fimo_test/motif.meme            \
    src/meme-5.5.3/fimo_test/promoters.fa          \
    src/meme-5.5.3/fimo_test/promoter_lengths.txt

mv $output/fimohits/binomial_thresholds.txt       $output
cp src/meme-5.5.3/fimo_test/universe.txt          $output
cp src/meme-5.5.3/fimo_test/promoter_lengths.txt  $output
cp src/meme-5.5.3/fimo_test/IC.txt                $output

end_time=$SECONDS
elapsed_time=$((end_time - start_time))
days=$((elapsed_time/86400))
hours=$(( (elapsed_time%86400)/3600 ))
minutes=$(( (elapsed_time%3600)/60 ))
seconds=$((elapsed_time%60))
print_orange "      Time taken: $days day $hours hour $minutes minute $seconds second\n"
print_red "Time taken: $time_taken seconds"

print_fluorescent_yellow "You can view results in '$output'"

print_green "done"
