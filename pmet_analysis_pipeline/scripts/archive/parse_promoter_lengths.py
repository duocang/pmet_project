#!/usr/bin/env python3
"""Write a two-column TSV mapping promoter name (column 4) to promoter length (end - start) from a BED file."""

import pandas as pd
import numpy as np
import argparse


def get_args():
    parser = argparse.ArgumentParser()
    parser.add_argument('filepath', type=str)
    parser.add_argument('outfile', type=str)
    return parser.parse_args()


args = get_args()

prom = pd.read_csv(args.filepath, header=None, index_col=None, sep='\t').values
fid = open(args.outfile, 'w')
toggle = ''

for i in np.arange(prom.shape[0]):
    fid.write(toggle + prom[i, 3] + '\t' + str(prom[i, 2] - prom[i, 1]))
    toggle = '\n'

fid.close()
