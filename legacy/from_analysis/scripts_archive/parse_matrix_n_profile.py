#!/usr/bin/env python3
"""Profiling variant of parse_matrix_n.py with time printouts and hard-coded input paths (fimo_ZAT18.txt, top-5 / top-5000). Kept for development only; not wired into current pipelines."""

import numpy as np
import pandas as pd
import sys
import time


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
    """PMET scoring: binomial p-value at each depth 1..k using the geometric
    mean of the top-d FIMO p-values as success probability and
    2*(promsize - mot_len + 1) as the number of trials (both strands).
    The minimum across depths identifies the most enriched depth per gene."""
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
    """Append a `motif<TAB>threshold` line using the weakest (last) gene in topN."""
    row = topN.shape[0] - 1
    writer.write(topN[row][2] + '\t' + topN[row][0] + '\n')


t0 = time.time()
fimo = pd.read_csv('fimo_ZAT18.txt', sep='\t', index_col=None, header=0).values
print(fimo[0, 0])

if not fimo.size:
    sys.exit(0)

promsize = {}
with open('promoter_lengths.txt', 'r') as fid:
    for line in fid:
        line = line.split()
        promsize[line[0]] = int(line[1])

print("load files: %.2f s." % (time.time() - t0))

# Drop worse-scoring member of each overlapping pair within a gene.
t0 = time.time()
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
print("remove overlaps: %.2f s." % (time.time() - t0))

start_pos = 0
hitdict = []
allmotifhits = []

for i in range(1, fimo.shape[0]):
    if fimo[i, 1] != fimo[start_pos, 1]:
        motif_hits = fimo[start_pos:i, ]
        motif_hits = motif_hits[np.argsort(motif_hits[:, 6])]
        motif_hits = motif_hits[0:min(5, motif_hits.shape[0]), :]
        motsize = fimo[start_pos, 3] - fimo[start_pos, 2] + 1
        binom_p = geom_binom_test(motif_hits[:, 6], promsize[motif_hits[0, 1]], motsize)
        hitdict.append([np.min(binom_p), np.argmin(binom_p), fimo[start_pos, 0], fimo[start_pos, 1]])
        allmotifhits.extend(motif_hits[range(0, np.argmin(binom_p) + 1), :])
        start_pos = i

# Process the last gene (loop above only fires on gene boundaries).
motif_hits = fimo[start_pos:, ]
if motif_hits.shape[0] != 1:
    motif_hits = motif_hits[np.argsort(motif_hits[:, 6])]
    motif_hits = motif_hits[0:min(5, motif_hits.shape[0]), :]
    motsize = fimo[start_pos, 3] - fimo[start_pos, 2] + 1
    binom_p = geom_binom_test(motif_hits[:, 6], promsize[motif_hits[0, 1]], motsize)
    hitdict.append([np.min(binom_p), np.argmin(binom_p), fimo[start_pos, 0], fimo[start_pos, 1]])
    allmotifhits.extend(motif_hits[range(0, np.argmin(binom_p) + 1), :])

hitdict.sort(key=lambda x: x[0])
topN = hitdict[:5000]
topN = np.asarray(topN)

df2 = pd.DataFrame(topN)
df2.to_csv(('fimohits/' + fimo[0, 0] + '_topN.txt'), sep='\t', header=False, index=False)

t0 = time.time()
allmotifhits = np.asarray(allmotifhits)
allmotifhits2 = allmotifhits[np.nonzero(np.in1d(allmotifhits[:, 1], topN[:, 3]))[0], :]
print("extract top n promoters: %.2f s." % (time.time() - t0))

t0 = time.time()
df = pd.DataFrame(allmotifhits2)
df.to_csv(('fimohits/' + fimo[0, 0] + '.txt'), sep='\t', header=False, index=False)
print("write file: %.2f s." % (time.time() - t0))

writer2 = open('binomial_thresholds.txt', 'a')
write_threshold_results(writer2, topN)
writer2.close()
