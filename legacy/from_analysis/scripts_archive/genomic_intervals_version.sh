#!/bin/bash
set -e


function usage () {
    cat >&2 <<EOF
#USAGE: PMET_index_ATAC_fasta_peaks.sh [options] <peaks.fa> <peaks.bed> <memefile>
USAGE: PMET_index_ATAC_fasta_peaks.sh [options] <peaks.fa> <memefile>

Creates PMET index for Paired Motif Enrichment Test from ATAC seq data using peaks in fasta and bed files.
Required arguments:
-r <PMETindex_path>	: Full path of PMET_index. Required.

Optional arguments:
-o <output_directory> : Output directory for results
-n <topn>	: How many top promoter hits to take per motif. Default=5000
-k <max_k>	: Maximum motif hits allowed within each promoter.  Default: 5
-j <max_jobs>	: Max number of jobs to run at once.  Default: 1

EOF
}

function error_exit() {
  echo "ERROR: $1" >&2
  usage
  exit 1
}

# set up arguments
topn=5000
maxk=5

fimothresh=0.05
overlap="AllowOverlap"
utr="No"
gff3id='gene_id'
pmetroot="scripts"
progFile="progress/progress"


# check if arguments have been specified
if [ $# -eq 0 ]
  then
    echo "No arguments supplied"  >&2
    usage
    exit 1
fi

# bring in arguments
while getopts ":r:o:k:n:j:" opt; do
  case $opt in
    r) echo "Full path of PMET_index:  $OPTARG" >&2
    pmetroot=$OPTARG;;
    o) echo "Output directory for results: $OPTARG" >&2
    outputdir=$OPTARG;;
    n) echo "Top n promoter hits to take per motif: $OPTARG" >&2
    topn=$OPTARG;;
    k) echo "Top k motif hits within each promoter: $OPTARG" >&2
    maxk=$OPTARG;;
    f) echo "Fimo threshold: $OPTARG" >&2
   fimothresh=$OPTARG;;
   g) echo "Progress file: $OPTARG" >&2
   progFile=$OPTARG;;
   v) echo "Remove promoter overlaps with gene sequences: $OPTARG" >&2
   overlap=$OPTARG;;
   u) echo "Include 5' UTR sequence?: $OPTARG" >&2
   utr=$OPTARG;;
    \?) echo "Invalid option: -$OPTARG" >&2
    exit 1;;
    :)  echo "Option -$OPTARG requires an argument." >&2
    exit 1;;
  esac
done

#rename input file variable
shift $((OPTIND - 1))
date

peaksfasta=$1
memefile=$2

[ ! -d $outputdir ] && mkdir $outputdir
cd $outuptdir;


# get peak lengths
#python3 $pmetroot/parse_promoter_lengths.py peaks.bed

# *** ADD THE DEPUPLICATION OF THE FASTA FILE HERE ****
python3 $pmetroot/python/deduplicate.py $peaksfasta 'peaks_no_duplicates.fa'

# generate the promoter lengths file from the fasta file
python3 $pmetroot/python/parse_promoter_lengths_from_fasta.py 'peaks_no_duplicates.fa' 'promoter_lengths.txt'

#now we can actually FIMO our way to victory
fasta-get-markov peaks.fa > peaks.bg
#FIMO barfs ALL the output. that's not good. time for individual FIMOs
#on individual MEME-friendly motif files too

# this just copies the directory rather than splitting up one memefile, leave for now
#if [ ! -d memefiles ]
#then
#  cp -r $memedir memefiles
#fi

mkdir memefiles

python3 $pmetroot/python/parse_memefile.py $memedir

python3 $pmetroot/python/calculateICfrommeme.py


runIndexing () {
  fid=$1
  echo $fid
  bfid=`basename $fid`
  echo $bfid
  progpath=$4
  # get all the possible motif hits using fimo
  fimo --text --thresh 0.05 --verbosity 1 --bgfile peaks.bg $fid peaks.fa > fimo_$bfid
  # # parse the fimo output to get top n promoters containing top n hits
  python3 $progpath/parse_matrix_n.py fimo_$bfid $2 $3
  rm fimo_$bfid
}
export -f runIndexing

mkdir fimohits
find memefiles -name \*.txt | parallel --jobs=$maxjobs "runIndexing {} $maxk $topn $pmetroot"
wait



#there's a lot of intermediate files that need blanking

rm fimo_*
#rm peaks.bed
rm peaks.bg
rm peaks.fa
date

