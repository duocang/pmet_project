#!/bin/bash

mkdir -p test_result

# remove genes not present in pre-computed pmet index (universe.txt)
grep -Ff ../../data/homotypic_promoters/universe.txt ../../data/homotypic_promoters/gene.txt > test_result/gene.txttemp

bin/pmet \
    -d  . \
    -g test_result/gene.txttemp \
    -i 4 \
    -p ../../data/homotypic_promoters/promoter_lengths.txt  \
    -b ../../data/homotypic_promoters/binomial_thresholds.txt  \
    -c ../../data/homotypic_promoters/IC.txt  \
    -f ../../data/homotypic_promoters/fimohits  \
    -o test_result

rm test_result/gene.txttemp
