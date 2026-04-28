#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Calculate IC per position for each per-motif MEME file in a directory and append one line per motif (name + space-separated IC values) to a TSV output file."""

import numpy as np
import math
import os
import re
import pandas as pd
import argparse


def get_args():
    parser = argparse.ArgumentParser()
    parser.add_argument('folderpath', type=str,
                        help="Directory of per-motif MEME files; pass '' to use ./memefiles")
    parser.add_argument('outfile', type=str)
    return parser.parse_args()


def getMotifLength(memefile):
    """Return the motif length (w=) parsed from a MEME file."""
    for i in range(len(memefile)):
        if memefile[i].find('letter-probability matrix') > -1:
            match = re.search(r'w= (\d+)', memefile[i])
            motif_length = int(match.group(1))
    return motif_length


def extractMatrixfromMeme(memefile, motif_length):
    """Return the letter-probability matrix as an (motif_length, 4) float array."""
    for i in range(len(memefile)):
        if memefile[i].find('letter-probability matrix') > -1:
            mat_start = i + 1
            mat_end = mat_start + motif_length
    mat = memefile[mat_start:mat_end]

    for j in range(0, mat.shape[0]):
        # Use whitespace split (not tab) because MEME matrices can be space-padded.
        newthing = mat[j].replace("\n", "").split()[0:4]
        if j == 0:
            new_mat = np.asarray(newthing)
        else:
            new_mat = np.append(new_mat, newthing)

    final_mat = np.asarray([float(num) for num in new_mat])
    final_mat = final_mat.reshape((motif_length, 4))
    return final_mat


def calculateIC(meme_as_matrix):
    """Return IC per position as a list of length motif_length."""
    meme = meme_as_matrix
    motif_length = meme.shape[0]
    IC_vec = [None] * motif_length
    # nansum is slower than sum, so only use it when NaNs are present.
    if np.isnan(meme).any():
        for i in range(0, motif_length):
            meme_row_no_zeros = [j for j in meme[i, :] if j != 0]
            IC_vec[i] = 2 + np.nansum([x * math.log2(x) for x in meme_row_no_zeros])
    else:
        for i in range(0, motif_length):
            # Drop zeros; log2(0) would raise a math error.
            meme_row_no_zeros = [j for j in meme[i, :] if j != 0]
            IC_vec[i] = 2 + sum([x * math.log2(x) for x in meme_row_no_zeros])
    return IC_vec


if __name__ == "__main__":
    args = get_args()

    memefolder = args.folderpath if args.folderpath != '' else 'memefiles'

    memefiles = os.listdir(memefolder)
    # Drop hidden files (e.g. macOS .DS_Store).
    memefiles = [f for f in memefiles if not f[0] == '.']

    IC_data = np.empty((len(memefiles), 1), dtype="object")

    mf_count = 0
    for file in memefiles:
        with open(memefolder + '/' + file) as w:
            k = np.asarray(w.readlines())
        mot_length = getMotifLength(k)
        meme = extractMatrixfromMeme(k, mot_length)
        IC = calculateIC(meme)

        icLine = file
        for i in range(0, mot_length):
            icLine = icLine + ' ' + str(IC[i])
        IC_data[mf_count] = icLine.replace('.txt', '')
        mf_count = mf_count + 1

    df = pd.DataFrame(IC_data)
    # Write mode (was append): every active caller invokes this script once
    # per IC.txt and immediately consumes the result. Append mode silently
    # duplicated motifs whenever a stale IC.txt was left in place by an
    # interrupted run; truncating is idempotent and matches the contract.
    df.to_csv(args.outfile, mode='w', sep='\t', header=False, index=False)
