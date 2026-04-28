#!/bin/bash

bin/pmetindex \
    -f ../../results/homotypic_promoters/fimo \
    -k 5 \
    -n 5000 \
    -p ../../results/homotypic_promoters/promoter_lengths.txt \
    -o test_result