#!/bin/bash
set -e

# cl_tool wrapper which takes individual files from a fimohits folder
# Last edit: 5/2/18
# Last upload to server: 22.1.18 12:47

#### this script is now superceded by cl_tool_parallel.sh as a wrapper. ####


function usage () {
    cat >&2 <<EOF
USAGE: $progname [options] <gene_inputs>
Perform Paired Motif Enrichment Test on gene sets, using PMET-index outputs.

-i <IC_threshold>	: Information Contnent threshold.  Default: 4
-t <mtc>	: Multiple Testing Correction threshold.  Default: 0.05
-m <motif_names>	: File containing motif IDs and names. Optional
-p <pmet_index_path>	: Full Path to PMET Index outputs. Default: current wd
-r <PMET_path>	: Full path of PMET_tool. Required.
-o <output_directory> : path to results
EOF
}

function error_exit() {
    echo "ERROR: $1" >&2
    usage
    exit 1
}

function check_file() {
    file=$1
    name=$2
    flag=$3

    if [ ! -f "$file" ]
    then error_exit "$name is not a file.  $flag flag is required"
    #then echo 'this is not a file'
    fi
}

function check_set() {
    value=$1
    name=$2
    flag=$3

    # -z string  = True if the length of string is zero.
    # exits if a string has not been specified
    if [ -z "$value" ]
    then error_exit "$name has not been specified.  $flag flag is required"
    fi

}

ic=4
mtc=0.05
inputfile=
pmetindex=
pmetroot=
outputdir=`pwd`

# deal with arguments
# if none, exit
if [ $# -eq 0 ]
  then
    echo "No arguments supplied"
    usage
    exit 1
fi

while getopts ":i:t:j:m:p:r:o:" options; do
  case $options in
    i ) echo "IC threshold: $OPTARG" >&2
    ic=$OPTARG;;
    t ) echo "Multiple Testing Correction Threshold: $OPTARG" >&2
    mtc=$OPTARG;;
    m ) echo "Path to motif names: $OPTARG" >&2
    motifnames=$OPTARG;;
    p ) echo "Path to PMET index folder: $OPTARG" >&2
    pmetindex=$OPTARG;;
    r ) echo "Path to PMET scripts: $OPTARG" >&2
    pmetroot=$OPTARG;;
    o ) echo "Output directory: $OPTARG" >&2
    outputdir=$OPTARG;;
    \? ) usage
         exit 1;;
    * ) usage
          exit 1;;
  esac
done


shift $(($OPTIND - 1))
inputfile=$1
echo "Gene input file: $inputfile"

# check pmet scripts path is specified
check_set "$pmetroot" "PMET scripts path" "-r"
# check gene input file is a file
check_file "$inputfile" "test gene sets input file" ""

# check if output is specified, if it is check it already exists, if not create it
# and enter that directory
# if a motif_found_final.txt file is already in the folder exit to avoid overwriting data.
if [ -n $outputdir ]; then
  if [ -d $outputdir ]; then
    cd $outputdir
    if [ -f motif_found_final.txt ]; then
      error_exit "Output directory already exists and containing PMET data, exiting to avoid overwriting"
    fi
  else
    echo "Output directory does not exist, creating directory"
    mkdir $outputdir
    cp $inputfile $outputdir
    cd $outputdir
  fi
fi


universe_size=`cat $pmetindex/promoter_lengths.txt | wc -l`
python3 $pmetroot/python/colocalisationTest.py $ic $universe_size $pmetindex $inputfile

## Apply three different multiple testing corrections: BH, Bonferroni (within each cluster)
# and Global Bonferroni (across clusters)
python3 $pmetroot/MTC.py $mtc
#
# ## Make the files more user friendly by adding helpful headers.
 python3 $pmetroot/headers.py


 #replace this with call to C++ binary


 ## remove temp files
 # if [ -f motif_found_final.txt ]
 # then
 # 	rm motif_found.txt
 # fi

 # # if $motifnames is not an empty string
 # # then motif names files will be used to convert motif ids into names on the plots.
 # if [ ! -z $motifnames ]
 # then
 #   # make PMET heatmap will plot a heatmap in R, using ggplot colouring only significant values
 #   # above threshold $mtc using BH and bonferoni multiple corrections.
 # 	Rscript $pmetroot/makePMETheatmaps.R \
 # 	-f motif_found_final.txt \
 # 	-m 'BH' \
 # 	-t $mtc \
 # 	-n $motifnames
 #
 # 	Rscript $pmetroot/makePMETheatmaps.R \
 # 	-f motif_found_final.txt \
 # 	-m 'bonf' \
 # 	-t $mtc \
 # 	-n $motifnames
 # else
 # 	Rscript $pmetroot/makePMETheatmaps.R \
 # 	-f motif_found_final.txt \
 # 	-m 'BH' \
 # 	-t $mtc
 #
 # 	Rscript $pmetroot/makePMETheatmaps.R \
 # 	-f motif_found_final.txt \
 # 	-m 'bonf' \
 # 	-t $mtc
 # fi
 #

echo 'Done'
