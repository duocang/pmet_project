#!/usr/bin/env python3
"""Convert GFF3 gene lines to a BED-like file, extracting the gene name from an attribute key (e.g. 'ID=' or 'gene_id=')."""

import argparse
import numpy as np
import pandas as pd
import sys

parser = argparse.ArgumentParser()
parser.add_argument('findstr', type=str)
parser.add_argument('infile', type=str)
parser.add_argument('outfile', type=str)
args = parser.parse_args()

findstr = args.findstr
infile = args.infile
outfile = args.outfile

if findstr[-1] != '=':
    sys.stderr.write(
        'WARNING: The field string does not end with an equal sign. '
        'This might be correct, depending on the GFF3 file, but double check your results'
    )

genelines = pd.read_csv(infile, sep='\t', index_col=None, header=None).values

# Replace the attribute field with just the value of findstr=...
error_toggle = 0
for i in range(genelines.shape[0]):
    line = genelines[i, -1].split(';')
    local_toggle = 0
    for field in line:
        if findstr == field[:len(findstr)]:
            genelines[i, -1] = field[len(findstr):]
            local_toggle = 1
            break
    if local_toggle == 0:
        error_toggle = 1
        sys.stderr.write(
            'Failed to find specified header (' + findstr[:-1] + ') in GFF3 line: '
            + '\t'.join([str(x) for x in genelines[i, :]]) + '\n'
        )

if error_toggle == 1:
    sys.exit(1)

# Project to BED columns: chrom, start, end, name, score placeholder, strand.
# Column 3 (start) is reused as a score placeholder so np.savetxt(%i) accepts it;
# it is overwritten to 1 below.
genelines = genelines[:, [0, 3, 4, 8, 3, 6]]
for i in range(genelines.shape[0]):
    genelines[i, 1] = int(genelines[i, 1]) - 1   # GFF3 1-based → BED 0-based
    genelines[i, -2] = 1

np.savetxt(outfile, genelines, fmt='%s\t%i\t%i\t%s\t%i\t%s')
