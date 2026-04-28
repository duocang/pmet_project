#!/usr/bin/env python3
"""Rewrite FASTA headers in a promoter FASTA using the name column of a matching BED file (assumes 1:1, same order)."""

import numpy as np
import pandas as pd
import argparse
from os.path import basename


def get_args():
    parser = argparse.ArgumentParser()
    parser.add_argument('fasta_path', type=str)
    parser.add_argument('bed_path', type=str)
    parser.add_argument('outfile', type=str)
    return parser.parse_args()


args = get_args()

reader = open(args.fasta_path, 'r')
bedfile = pd.read_csv(args.bed_path, sep='\t', index_col=None, header=None)

bedfile = bedfile.values
bedfile = bedfile[:, 3]
bedfile = np.asarray(['>' + bed + '\n' for bed in bedfile])
fafile = np.asarray(reader.readlines())
reader.close()

# Overwrite every other line (the FASTA headers) with the BED names.
# Assumes the FASTA and BED have the same record order and no wrapped sequence lines.
fafile[np.arange(0, len(fafile), 2)] = bedfile

writer = open(args.outfile, 'w')
writer.writelines(fafile)
writer.close()
