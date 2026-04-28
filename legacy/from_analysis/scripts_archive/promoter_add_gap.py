#!/usr/bin/env python3
"""Shift promoter regions away from the TSS by a given distance (adds a gap between promoter and gene body), clamped to chromosome bounds."""

import sys


def read_chromosome_ranges(chromosome_file):
    """Read chromosome boundaries from a GFF3-style file (cols 4,5 = start,end).
    Used to clamp shifted promoter coordinates so they stay on the chromosome."""
    chromosome_ranges = {}
    with open(chromosome_file, 'r') as file:
        for line in file:
            parts = line.strip().split('\t')
            chromosome_id = parts[0]
            start, end = int(parts[3]), int(parts[4])
            chromosome_ranges[chromosome_id] = (start, end)
    return chromosome_ranges

def adjust_promoter_coordinates(promoters_file, chromosome_ranges, distance):
    """Shift each promoter away from its gene (and away from the TSS) by
    `distance` bp, opening a gap between the gene body and the region scanned
    for motifs. + strand promoters move upstream (start/end both decrease);
    - strand promoters move upstream in transcription sense (both increase).
    Coordinates are clamped to chromosome bounds."""
    adjusted_promoters = []
    missing_chroms = set()
    dropped = 0
    with open(promoters_file, 'r') as file:
        for line in file:
            parts = line.strip().split('\t')
            chromosome_id, start, end, strand = parts[0], int(parts[1]), int(parts[2]), parts[5]

            # Drop promoters whose chromosome has no 'chromosome' feature in
            # the GFF3 — we have no bounds to clamp against. Warn once per
            # missing chromosome so silent drops are visible.
            if chromosome_id not in chromosome_ranges:
                if chromosome_id not in missing_chroms:
                    missing_chroms.add(chromosome_id)
                    sys.stderr.write(
                        f"        WARNING: chromosome '{chromosome_id}' has "
                        f"no 'chromosome' feature in the GFF3; dropping its "
                        f"promoters.\n"
                    )
                dropped += 1
                continue

            # Get the chromosome range
            chrom_start, chrom_end = chromosome_ranges[chromosome_id]

            # Adjust coordinates based on strand
            if strand == '+':
                start, end = max(start - distance, chrom_start), max(end - distance, chrom_start)
            else:
                start, end = min(start + distance, chrom_end), min(end + distance, chrom_end)

            adjusted_promoters.append((chromosome_id, start, end, parts[3], parts[4], strand))

    if dropped:
        sys.stderr.write(
            f"        WARNING: total {dropped} promoter(s) dropped for "
            f"missing chromosomes.\n"
        )
    return adjusted_promoters

def main():
    # Parse arguments
    distance = int(sys.argv[1]) if len(sys.argv) > 1 else 500
    chromosome_file = sys.argv[2]
    promoters_file = sys.argv[3]

    # Read chromosome ranges and adjust promoter coordinates
    chromosome_ranges = read_chromosome_ranges(chromosome_file)
    adjusted_promoters = adjust_promoter_coordinates(promoters_file, chromosome_ranges, distance)

    # Print adjusted promoters
    for promoter in adjusted_promoters:
        print('\t'.join(map(str, promoter)))

if __name__ == "__main__":
    main()
