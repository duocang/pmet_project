### PMET Software Workflow Explanation

PMET (Paired Motif Enrichment Software) is a bioinformatics tool designed for analyzing homotypic and heterotypic motifs in gene promoter regions. Its process is divided into two main steps: indexing (search for homotypic motifs) and pairing (search for heterotypic motifs).

#### Indexing (Search for Homotypic Motifs)

1. **Promoter Extraction:** Using FASTA formatted genome files and gff3 annotation files, extract a region of 1000 base pairs preceding the Transcription Start Site (TSS) of each gene as the promoter region, including the 3' UTR area. Thus, each promoter's length is 1000 base pairs plus the length of the 3' UTR.

2. **Elimination of Overlaps:** Since the extracted promoters might extend into other genes, overlapping parts are removed to ensure each gene’s promoter is independent, and these are saved in the `promoter.fa` file.

3. **Motif Information Retrieval:** Motifs information is obtained from databases, stored in .meme format files. For instance, a file might contain 113 different motifs.

4. **Motif Matching:** Using the MEME suite's FIMO software, motifs are matched to each promoter, searching for homotypic sequences.

5. Probability Calculation:

    For each motif and promoter pairing, select the matches with the smallest p-values, up to a maximum number (default maxk is 5), and calculate their geometric mean probability (p_geo). Calculate the potential match locations as 

   ```
   possibleLocations = 2 * (promoterLength - motifLength + 1)
   ```

   . Using the binomial distribution, calculate the probability of at least n occurrences (0 ≤ n ≤ maxk). These probability values are recorded in 

   ```
   binomial_thresholds.txt
   ```

   .

   1. **Selecting Optimal Matches (Hits):** For each motif paired with a specific promoter, FIMO software provides a series of matches (hits) with p-values and physical binding coordinates. The matches with the smallest p-values, up to maxk (default maxk is 5), are selected. These chosen matches represent the most probable binding sites of the motif to the promoter.
   2. **Calculating Geometric Mean Probability (p_geo):** Calculate the geometric mean of the p-values for these selected maxk matches. This mean value, p_geo, is used as the probability of the motif randomly matching that promoter for subsequent binomial distribution testing.
   3. **Determining Potential Match Locations (possibleLocations):** Considering that transcription factors can bind to DNA in two directions, calculate the possible match locations for the motif. This is achieved with the formula `possibleLocations = 2 * (promoterLength - motifLength + 1)`.
   4. **Binomial Distribution Probability Calculation:** Using p_geo and possibleLocations, calculate the cumulative probability P(X ≥ n) for each n (0 ≤ n ≤ maxk), i.e., the probability of at least n matches occurring. This is done by calculating the cumulative distribution function of the binomial distribution.
   5. **Selecting the Number of Matches to Retain:** Review these cumulative probability values and identify the smallest P(X ≥ n) value. If this minimum probability value corresponds to an n that is not maxk, then choose to retain that number of motif a and promoter matches. This means that if a lower probability for a smaller number of matches is found within the maxk matches, the system will select this smaller number as the final result.
   6. **Recording the Minimum Threshold:** Record the smallest calculated probability value (P(X ≥ n)) in the `binomial_thresholds.txt` file for subsequent analysis.

6. **Selecting Top Promoters:** For each motif, calculate its minimum threshold across all promoters, rank all promoters by this threshold, and select the top n promoters with the smallest probability (default topn is 5000).

7. **Recording Results:** For example, `CCA1.txt` contains data on the matches between motif CCA1 and Arabidopsis promoters.

#### Pairing (Search for Heterotypic Motifs)

1. **Comparing Motifs:** Each pair of different motifs is compared once, without repetition.

2. **Finding Intersections:** Determine if there are intersections among the top n promoters for two motifs.

3. **Checking Overlapping Coordinates:** For each promoter in the intersection, check if the binding coordinates of motif a overlap with those of motif b.

4. **Recalculating Probability:** If an overlap is found, and it exceeds a preset threshold (ICthresh), recalculate the binomial distribution probability and compare it with the threshold value for the corresponding motif recorded in the `binomial_thresholds.txt` file. If the new value exceeds the saved threshold, discard that motif pair.

5. **Intersection with Functional Groups:** Calculate the intersection of a specific functional group (such as a cluster of 400 cell cycle genes) with genes containing both motifs.

6. Hypergeometric Distribution Test:

    Perform a hypergeometric distribution test on the three sets (functional group, the gene group with both motifs, and their intersection) to calculate the p-value.

   1. Defining Sets:
      1. **Functional Group Gene Set:** This is a predefined specific functional group, such as 400 cell cycle-related genes.
      2. **Gene Group with Both Motifs:** Obtained from previous steps, these genes contain both motif a and motif b in their promoter regions.
      3. **Intersection Gene Group:** The intersection of the functional group gene set and the gene group with both motifs.
   2. **Purpose of the Hypergeometric Distribution Test:** The test aims to evaluate the probability of observing a specific number of functional group genes within the gene group containing both motifs. This reveals the potential correlation of the two motifs in regulating specific functional genes.
   3. Calculating Hypergeometric Distribution Probability (p-value):
      - **Population Size (N):** Total number of genes in the genome.
      - **Number of Successes in Population (K):** Total number of genes in the functional group (e.g., 400 cell cycle genes).
      - **Sample Size (n):** Size of the gene group with both motifs.
      - **Observed Successes in Sample (k):** Size of the intersection gene group.
      - **Calculating the p-value:** Using these parameters, calculate the probability of observing at least k functional group genes in the gene group with both motifs under the assumption that there is no specific relationship between functional group genes and genes with both motifs.
   4. **Determining Statistical Significance:** A lower p-value suggests that the observed intersection is unlikely to be a random event, implying that the two motifs may work synergistically in regulating genes in that specific functional group.

7. **Outputting Results:** All the pairwise comparison results for motifs, along with related p-values and lists of intersecting genes, are recorded and outputted.

Through these two steps, PMET accurately determines the likelihood of specific motifs binding in promoter regions and selects the promoters most likely to contain these binding sites. This is crucial for understanding how transcription factors regulate gene expression, especially in the context of homotypic and heterotypic motifs.