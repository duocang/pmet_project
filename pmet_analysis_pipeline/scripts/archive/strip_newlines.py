#!/usr/bin/env python3
"""Collapse multi-line FASTA sequences onto a single line per record so each entry is a header followed by one sequence line."""

import argparse

parser = argparse.ArgumentParser()
parser.add_argument('infile',type=str)
parser.add_argument('outfile',type=str)

args = parser.parse_args()

infile = args.infile
outfile = args.outfile


fid = open(infile, 'r')
fid2 = open(outfile, 'w')
toggle = ''
for line in iter(fid):
    line = line.rstrip()
    if not line:
        continue
    if line[0] == '>':
        # Header: emit a newline before it (except the first) so each record
        # ends up as "header\nsequence" with no internal line breaks.
        line = toggle + line + '\n'
        toggle = '\n'
    print(line, end='', file=fid2)
fid.close()
fid2.close()
