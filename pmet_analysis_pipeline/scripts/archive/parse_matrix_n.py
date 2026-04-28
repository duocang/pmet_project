#!/usr/bin/env python3
"""Parse FIMO hits for one motif: remove overlapping hits per gene, compute geometric binomial p-values on top-k hits per gene, and write top-N gene thresholds plus contributing hits."""

import argparse
import numpy as np
import pandas as pd
import sys


def get_args():
    parser = argparse.ArgumentParser()
    parser.add_argument('fimofile', type=str)
    parser.add_argument('tar', type=int, help='k: number of top hits per gene to keep')
    parser.add_argument('n', type=int, help='N: number of top genes to write out')
    return parser.parse_args()


def overlapcheck(span1, span2):
    """Return True if two closed intervals [start, end] overlap."""
    if span1[0] >= span2[0] and span1[0] <= span2[1]:
        return True
    if span1[1] >= span2[0] and span1[1] <= span2[1]:
        return True
    return False


def geo_mean(iterable):
    """Geometric mean of a numeric iterable."""
    a = np.array(iterable)
    return a.prod() ** (1.0 / len(a))


def geom_binom_test(coin, promsize, mot_len):
    """PMET scoring: for each depth d=1..len(coin), compute the binomial
    probability of observing >= d hits in 2*(promsize - mot_len + 1) Bernoulli
    trials whose success probability is the geometric mean of the top-d FIMO
    p-values. Returns one binomial p-value per depth; the minimum identifies
    the most enriched depth for the gene."""
    binom_p = []
    flips = 2 * (promsize - mot_len + 1)
    for k in range(0, len(coin)):
        vals = np.array(coin[:k + 1], dtype=float)
        geom = geo_mean(vals)
        binom_p.append(1 - binomial_cdf(k, flips, geom))
    return np.asarray(binom_p)


def binomial_cdf(x, n, p):
    """Compute the binomial CDF in log-space; faster than scipy.stats.binom.sf here."""
    cdf = 0
    b = 0
    for k in range(x + 1):
        if k > 0:
            b += + np.log(n - k + 1) - np.log(k)
        log_pmf_k = b + k * np.log(p) + (n - k) * np.log(1 - p)
        cdf += np.exp(log_pmf_k)
    return cdf


def write_threshold_results(writer, topN):
    """Append a `motif<TAB>threshold` line using the weakest (last) gene in topN
    as the cutoff for downstream heterotypic analysis."""
    row = topN.shape[0] - 1
    writer.write(topN[row][2] + '\t' + topN[row][0] + '\n')


args = get_args()

fimo = pd.read_csv(args.fimofile, sep='\t', index_col=None, header=0).values

# Some motifs hit nothing.
if not fimo.size:
    sys.exit(0)

promsize = {}
with open('promoter_lengths.txt', 'r') as fid:
    for line in fid:
        line = line.split()
        promsize[line[0]] = int(line[1])

# Within each gene, drop the worse-scoring hit from any overlapping pair.
# Input is assumed sorted by gene, then by position.
del_inds = []
prev_ind = 0
for i in range(1, fimo.shape[0]):
    if fimo[i, 1] == fimo[prev_ind, 1]:
        if overlapcheck(fimo[i, [2, 3]], fimo[prev_ind, [2, 3]]):
            if fimo[i, 6] < fimo[prev_ind, 6]:
                del_inds.append(prev_ind)
                prev_ind = i
            else:
                del_inds.append(i)
        else:
            prev_ind = i
    else:
        prev_ind = i

fimo = np.delete(fimo, del_inds, 0)

# Per gene: take top-k hits by p-value, compute geometric binomial per depth,
# record the best (min) binomial score and the depth at which it was hit.
start_pos = 0
hitdict = []
allmotifhits = []

for i in range(1, fimo.shape[0]):
    if fimo[i, 1] != fimo[start_pos, 1]:
        print(i)
        motif_hits = fimo[start_pos:i, ]
        motif_hits = motif_hits[np.argsort(motif_hits[:, 6])]
        motif_hits = motif_hits[0:min(args.tar, motif_hits.shape[0]), :]
        motsize = fimo[start_pos, 3] - fimo[start_pos, 2] + 1
        binom_p = geom_binom_test(motif_hits[:, 6], promsize[motif_hits[0, 1]], motsize)
        hitdict.append([np.min(binom_p), np.argmin(binom_p), fimo[start_pos, 0], fimo[start_pos, 1]])
        allmotifhits.extend(motif_hits[range(0, np.argmin(binom_p) + 1), :])
        start_pos = i

# Process the last gene (loop above only fires on gene boundaries).
motif_hits = fimo[start_pos:, ]
if motif_hits.shape[0] != 1:
    motif_hits = motif_hits[np.argsort(motif_hits[:, 6])]
    motif_hits = motif_hits[0:min(args.tar, motif_hits.shape[0]), :]
    motsize = fimo[start_pos, 3] - fimo[start_pos, 2] + 1
    binom_p = geom_binom_test(motif_hits[:, 6], promsize[motif_hits[0, 1]], motsize)
    hitdict.append([np.min(binom_p), np.argmin(binom_p), fimo[start_pos, 0], fimo[start_pos, 1]])
    allmotifhits.extend(motif_hits[range(0, np.argmin(binom_p) + 1), :])

# Keep the N genes with the best binomial scores and the hits that contributed to them.
hitdict.sort(key=lambda x: x[0])
topN = hitdict[:args.n]
print(max(topN))
topN = np.asarray(topN)

allmotifhits = np.asarray(allmotifhits)
allmotifhits2 = allmotifhits[np.nonzero(np.in1d(allmotifhits[:, 1], topN[:, 3]))[0], :]

df = pd.DataFrame(allmotifhits2)
df.to_csv(('fimohits/' + fimo[0, 0] + '.txt'), sep='\t', header=False, index=False)

writer2 = open('binomial_thresholds.txt', 'a')
write_threshold_results(writer2, topN)
writer2.close()
