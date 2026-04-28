#!/usr/bin/env python3
"""Trim promoter regions that overlap neighbouring gene bodies. Legacy: not referenced by any active pipeline."""

import sys


def read_bed_file(file_path):
    with open(file_path, 'r') as file:
        return [line.strip().split('\t') for line in file]

def remove_overlaps(genelines, promoters):
    adjusted_promoters = []
    for i, promoter in enumerate(promoters):
        chrom, start, end, name, num , strand = promoter[:6]

        # print(chrom, start, end, name, num , strand)
        start, end = int(start), int(end)


        if i == 0 or i == len(genelines) - 1:
            print("")
            if i == 0:
                gene_chrom, gene_start, gene_end = genelines[i + 1][:3]
            else:
                gene_chrom, gene_start, gene_end = genelines[i - 1][:3]

            gene_start, gene_end = int(gene_start), int(gene_end)
            if chrom == gene_chrom and (end < gene_start or start > gene_end):
                adjusted_promoters.append(promoter)
            else:
                adjusted_promoter = promoter
                if start < gene_start and end > gene_start and end < gene_end:

                    adjusted_promoter = [chrom, str(start), str(gene_start - 1), name,num,  strand]
                    adjusted_promoters.append(adjusted_promoter)
                elif start > gene_start and start < gene_end and end > gene_end:
                    adjusted_promoter = [chrom, str(gene_end + 1), str(end), name,num,  strand]
                    adjusted_promoters.append(adjusted_promoter)
        else:
            gene_chrom_1, gene_start_1, gene_end_1 = genelines[i - 1][:3]
            gene_chrom_2, gene_start_2, gene_end_2 = genelines[i + 1][:3]

            gene_start_1, gene_end_1 = int(gene_start_1), int(gene_end_1)
            gene_start_2, gene_end_2 = int(gene_start_2), int(gene_end_2)

            new_start = 0
            new_end   = 0


            if chrom == gene_chrom_1 and (end < gene_start_1 or start > gene_end_1):
                new_start = start
                new_end   = end
                if chrom == gene_chrom_2 and (new_end < gene_start_2 or new_start > gene_end_2):
                    adjusted_promoter = [chrom, str(new_start), str(new_end), name,num,  strand]
                    adjusted_promoters.append(adjusted_promoter)
            else:
                if start >= gene_start_1 and end >= gene_start_1 and end <= gene_end_1:
                    new_start = start
                    new_end = gene_start_1 - 1

                elif start >= gene_start_1 and start <= gene_end_1 and end >= gene_end_1:

                    new_start = gene_end_1 + 1
                    new_end = end

                if chrom == gene_chrom_2 and (new_end < gene_start_2 or new_start > gene_end_2):
                    adjusted_promoter = [chrom, str(new_start), str(new_end), name,num,  strand]
                    adjusted_promoters.append(adjusted_promoter)

            if new_start < gene_start_2 and new_end > gene_start_2 and new_end < gene_end_2:

                new_end = gene_start_2 - 1

                adjusted_promoter = [chrom, str(new_start), str(new_end), name,num,  strand]
                adjusted_promoters.append(adjusted_promoter)
            elif new_start > gene_start_2 and new_start < gene_end_2 and new_end > gene_end_2:

                new_start = gene_end_2 + 1

                adjusted_promoter = [chrom, str(new_start), str(new_end), name,num,  strand]
                adjusted_promoters.append(adjusted_promoter)





    return adjusted_promoters

def main(genelines_file, promoters_file):
    genelines = read_bed_file(genelines_file)
    promoters = read_bed_file(promoters_file)

    adjusted_promoters = remove_overlaps(genelines, promoters)

    for promoter in adjusted_promoters:
        print('\t'.join(promoter))

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python script.py <genelines.bed> <promoters.bed>")
        sys.exit(1)

    main(sys.argv[1], sys.argv[2])
