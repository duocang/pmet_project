#!/bin/bash

index_out=../../results/01_PMET_promoter/01_homotypic/

mkdir -p test_result

# remove genes not present in pre-computed pmet index (universe.txt)
grep -Ff $index_out/universe.txt ../../data/gene.txt > test_result/gene.txttemp

# Run PMET
bin/pmetParallel                          \
    -x true                               \
    -d .                                  \
    -g test_result/gene.txttemp           \
    -i 4                                  \
    -p $index_out/promoter_lengths.txt    \
    -b $index_out/binomial_thresholds.txt \
    -c $index_out/IC.txt                  \
    -f $index_out/fimohits                \
    -t 8                                  \
    -o test_result

rm test_result/gene.txttemp

cat test_result/*.txt > test_result/motif_output.txt
rm test_result/temp*.txt
