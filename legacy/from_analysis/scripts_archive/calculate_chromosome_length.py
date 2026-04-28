#!/usr/bin/env python3
"""Extract chromosome lengths from GFF3 sequence-region headers and save to a file."""

import argparse
import sys


def extract_chromosome_lengths_from_gff3(gff3_file):
    """Extract chromosome lengths from GFF3 sequence-region headers."""
    chromosome_lengths = {}
    with open(gff3_file, 'r') as f:
        for line in f:
            if line.startswith('##sequence-region'):
                parts = line.strip().split()
                if len(parts) < 4:
                    continue
                seqid = parts[1]
                start = int(parts[2])
                end = int(parts[3])
                length = end - start + 1
                chromosome_lengths[seqid] = length
    return chromosome_lengths


def extract_chromosome_lengths_from_txt(txt_file):
    """Extract chromosome lengths from tab-separated txt file (chr\tlength)."""
    chromosome_lengths = {}
    with open(txt_file, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            parts = line.split('\t')
            if len(parts) >= 2:
                seqid = parts[0]
                length = int(parts[1])
                chromosome_lengths[seqid] = length
    return chromosome_lengths


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Extract chromosome lengths from GFF3 or txt file."
    )
    parser.add_argument("input_file", help="Path to input file (GFF3 or txt)")
    parser.add_argument("output", help="Path to output text file to save chromosome lengths")
    parser.add_argument("-f", "--format", choices=["gff3", "txt", "auto"],
                       default="auto", help="Input file format (default: auto-detect)")
    args = parser.parse_args(argv)

    # Auto-detect format based on file extension or content
    if args.format == "auto":
        if args.input_file.endswith(('.gff3', '.gff')):
            args.format = "gff3"
        else:
            args.format = "txt"  # Default to txt for other extensions

    if args.format == "gff3":
        lengths = extract_chromosome_lengths_from_gff3(args.input_file)
    else:
        lengths = extract_chromosome_lengths_from_txt(args.input_file)

    # Write results to the output file
    with open(args.output, 'w') as outfile:
        for seqid, length in lengths.items():
            outfile.write(f"{seqid}\t{length}\n")

    # print(f"Chromosome lengths have been written to {args.output}")


if __name__ == "__main__":
    sys.exit(main())
