
//  Created by Paul Brown on 01/07/2019.
//  Copyright © 2019 Paul Brown. All rights reserved.
//

#include "motifComparison.hpp"

#include <math.h>

#include <exception>
#include <fstream>
#include <iostream>
#include <limits>

void motifComparison::reset() {
  genesInUniverseWithBothMotifs.clear();
  genesInClusterWithBothMotifs.clear();
  pval = 1.0;
}

/**
 * Finds genes that have instances of both motif1 and motif2 with minimal overlap between them.
 * The function resets the internal state of the motifComparison object before starting the computation.
 * It first finds genes that are common to both motif1 and motif2.
 * Then, it filters out the instances of these genes that have significant overlap between motif1 and motif2,
 * using the given ICthreshold and the promoter sizes provided in the 'promSizes' map.
 *
 * @param motif1 The first motif to compare.
 * @param motif2 The second motif to compare.
 * @param ICthreshold The threshold for the Information Content (IC) score to consider overlapping instances.
 * @param promSizes A map containing gene names as keys and their corresponding promoter lengths as values.
 *                  It is used to determine whether a gene's promoter is valid (> 0).
 */
void motifComparison::findIntersectingGenes(motif& motif1, motif& motif2, double ICthreshold,
                                            std::unordered_map<std::string, int>& promSizes) {
  // Reset the internal state of the motifComparison object
  reset();
  // genesInUniverseWithBothMotifs is bm_genes in python code

  // Find genes that are common to both motif1 and motif2
  std::vector<std::string> m1Genes, m2Genes, tmpSharedGenes;
  motif1.getListofGenes(m1Genes);
  motif2.getListofGenes(m2Genes);
  tmpSharedGenes.reserve(m1Genes.size());
  std::set_intersection(m1Genes.begin(), m1Genes.end(), m2Genes.begin(), m2Genes.end(),
                        std::inserter(tmpSharedGenes, tmpSharedGenes.begin()));

  // Filter for overlaps and keep genes with minimal overlap between motif1 and motif2
  for (std::vector<std::string>::iterator gene = tmpSharedGenes.begin(); gene != tmpSharedGenes.end(); gene++) {
    if (promSizes[*gene]) {  // Check if gene's promoter is valid (> 0)
      // Remove some instances of this gene based on overlap
      // Perform all pairwise comparisons between instances in motif1 and motif2

      /// Get the number of instances (one line or record of motif/fimo file) with this gene
      // for example, AT1G01230 has 2 records in AHL12_2.txt and 1 record in AHL12.txt
      long numM1Locations = motif1.getNumInstances(*gene);
      long numM2Locations = motif2.getNumInstances(*gene);
      // Initialize vectors to keep track of whether to keep or remove instances for motif1 and motif2
      std::vector<bool> motif1LocationsToKeep(numM1Locations, true);
      std::vector<bool> motif2LocationsToKeep(numM2Locations, true);

      // Check for overlap between motif instances and update the corresponding vectors
      for (long mLoc1 = 0; mLoc1 < numM1Locations; mLoc1++) {
        motifInstance& m1Instance = motif1.getInstance(*gene, mLoc1);
        for (long mLoc2 = 0; mLoc2 < numM2Locations; mLoc2++) {
          motifInstance& m2Instance = motif2.getInstance(*gene, mLoc2);
          // Reject if two motifs overlapped
          if (motifInstancesOverlap(motif1, motif2, m1Instance, m2Instance, ICthreshold)) {
            motif1LocationsToKeep[mLoc1] = false;
            motif2LocationsToKeep[mLoc2] = false;
          }
          // // 是不是应该添加这一句？
          // // motif1的某个位置的hit x 可能和motif2的某个hit y重叠，但是 x可能和 motif 2的某个hit z不重叠
          // // 这个不重叠，是不是可以取消掉直接删除 motif1 x的操作？
          // else {
          //   motif1LocationsToKeep[mLoc1] = true;
          //   motif2LocationsToKeep[mLoc2] = true;
          // }
        }
      }

      // Done all pairwise comparisons. Check if we need to delete some instances

      // After removing some motifs (from motif1 and motif2) due to overlap, check if there are any motifs left
      if ((std::find(motif1LocationsToKeep.begin(), motif1LocationsToKeep.end(), true) != motif1LocationsToKeep.end()) &&
          (std::find(motif2LocationsToKeep.begin(), motif2LocationsToKeep.end(), true) != motif2LocationsToKeep.end())) {
        // Check if no motifs were removed, which means all instances are kept
        if ((std::find(motif1LocationsToKeep.begin(), motif1LocationsToKeep.end(), false) == motif1LocationsToKeep.end()) &&
            (std::find(motif2LocationsToKeep.begin(), motif2LocationsToKeep.end(), false) == motif2LocationsToKeep.end())) {
          /// In fact, keeping all instances without removing any
          genesInUniverseWithBothMotifs.push_back(*gene);

        } else {
          // Some locations were removed, but some were kept, re-calculate binomial test.
          // Instances must have scores below the threshold for both motifs to be kept
          if (geometricBinomialTest(motif1LocationsToKeep, *gene, promSizes[*gene], motif1) &&
              geometricBinomialTest(motif2LocationsToKeep, *gene, promSizes[*gene], motif2))
            genesInUniverseWithBothMotifs.push_back(*gene);  // best score is at or below threshold
        }
      }
    }

  }  // next gene
}

/**
 * Determines if two different motif instances from different FIMO files overlap with each other.
 * This function checks various conditions to determine the overlap between motifs and returns true or false
 * based on specific criteria.
 *
 * @param motif1 The first motif object containing the first motif instance.
 * @param motif2 The second motif object containing the second motif instance.
 * @param m1Instance The first motif instance to be compared.
 * @param m2Instance The second motif instance to be compared.
 * @param ICthreshold The threshold value for Information Content (IC) score, used for filtering out overlapping motifs.
 * @return True if the two motif instances overlap significantly based on the overlap, IC threshold, otherwise false.
 */
bool motifComparison::motifInstancesOverlap(motif& motif1, motif& motif2, motifInstance& m1Instance,
                                            motifInstance& m2Instance, double ICthreshold) {
  // any that return true will be filtered out
  // this is defineOverlapsBetweenTwoMotifs in python code

   // Get the start and end positions of the motif instances
  int m1Start = m1Instance.getStartPos();
  int m2Start = m2Instance.getStartPos();
  int m1End = m1Instance.getEndPos();
  int m2End = m2Instance.getEndPos();

  // Check various conditions to determine overlap between motif instances

  // Case 1: No overlap, both motifs are completely before or after each other
  if ((m1Start < m2Start && m1End < m2Start) || (m2End < m1Start && m2End < m1End))
    return false;
  // Case 2: One motif instance is completely contained within the other, reject as overlapping
  if ((m1Start >= m2Start && m1End <= m2End) || (m2Start >= m1Start && m2End <= m1End))
    return true;

  // Case 3: Overlap occurs in the last part of motif1 and the beginning of motif2
  // Compute the overlap length and check if the minimum IC score of the overlap is greater than the threshold
  if (m2Start > m1Start) {
    int overlapLen = m1End - m2Start + 1;
    return (std::min(motif1.getReverseICScore(overlapLen), motif2.getForwardICScore(overlapLen)) > ICthreshold);
  } else {
    // Case 4: Overlap occurs in the first part of motif1 and the end of motif2
    // Compute the overlap length and check if the minimum IC score of the overlap is greater than the threshold
    int overlapLen = m2End - m1Start + 1;
    return (std::min(motif1.getForwardICScore(overlapLen), motif2.getReverseICScore(overlapLen)) > ICthreshold);
  }
}

/**
 * Performs a geometric binomial test for a given motif in a specific promoter.
 * The function collects p-values for all positions where the motif is found (if motifLocationsToKeep is true),
 * calculates the geometric mean of these p-values, and then computes the binomial test p-value.
 * The smallest p-value for this motif in the promoter is returned as the result of the test.
 *
 * @param motifLocationsToKeep A vector of boolean values indicating which motif locations to include in the test.
 * @param gene The gene identifier for which the motif is being tested.
 * @param promoterLength The length of the promoter sequence.
 * @param mt The motif object containing the motif to be tested.
 * @return True if the smallest binomial test p-value is less than or equal to the motif threshold, otherwise false.
 */
bool motifComparison::geometricBinomialTest(const std::vector<bool>& motifLocationsToKeep, const std::string& gene,
                                            int promoterLength, motif& mt) {
  // Test for one motif in one promoter
  // motifLocations contain p-values. Use if motifLocationsToKeep is true
  // returtn smallest value for this motif in this promoter

  // Collect p-values of all positions where the motif is found
  long numpVals = std::count(motifLocationsToKeep.begin(), motifLocationsToKeep.end(), true);
  std::vector<double> pVals;
  pVals.reserve(numpVals);

  for (int i = 0; i < motifLocationsToKeep.size(); i++) {
    if (motifLocationsToKeep[i]) {
      motifInstance mInst = mt.getInstance(gene, i);
      pVals.push_back(mInst.getPValue());
    }
  }
  // Motif instances have already been sorted, so pVals will be in ascending order
  // Calculate the geometric mean of all included p-values
  double lowestScore     = std::numeric_limits<double>::max();
  long possibleLocations = 2 * (promoterLength - mt.getLength() + 1);

  for (std::vector<double>::iterator i = pVals.begin(); i < pVals.end(); i++) {
    // Calculate the geometric mean of all p-values up to this one
    double gm     = geometricMean(pVals.begin(), i + 1);
    double binomP = 1 - binomialCDF((i + 1 - pVals.begin()), possibleLocations, gm);
    lowestScore   = (binomP < lowestScore) ? binomP : lowestScore;
  }
  // Compare the smallest binomial test p-value with the motif threshold
  return lowestScore <= mt.getThreshold();
}

/**
 * Calculates the geometric mean of a range of values specified by the iterators 'first' and 'last'.
 * The function iterates over the range and computes the sum of the natural logarithms of the values.
 * It then returns the exponential of the sum divided by the number of elements in the range.
 *
 * @param first Iterator to the beginning of the range.
 * @param last Iterator to the end of the range (not inclusive).
 * @return The geometric mean of the values in the specified range.
 */
double motifComparison::geometricMean(std::vector<double>::iterator first, std::vector<double>::iterator last) {
  double sum = 0.0;
  long len = last - first;

  // Calculate the sum of the natural logarithms of the values in the range
  for (std::vector<double>::iterator i = first; i < last; i++)
    sum += log(*i);

  // Calculate the exponential of the sum divided by the number of elements in the range
  return exp(sum / len);
}

/**
 * Calculates the cumulative distribution function (CDF) of a binomial distribution.
 *
 * @param numPVals The total number of counts for calculating the CDF.
 * @param numLocations The total number of possible locations in the binomial distribution.
 * @param gm The geometric mean of the probability.
 * @return The CDF value of the binomial distribution.
 */
double motifComparison::binomialCDF(long numPVals, long numLocations, double gm) {
  double cdf = 0.0;
  double b = 0.0;
  // Calculate the logarithms of gm and (1 - gm) for efficiency
  double logP = log(gm);
  double logOneMinusP = log(1 - gm);

  for (int k = 0; k < numPVals; k++) {
    if (k > 0)
      b += log(numLocations - k + 1) - log(k);
    // Calculate the CDF value using the binomial distribution formula
    cdf += exp(b + k * logP + (numLocations - k) * logOneMinusP);
  }
    return cdf;
}

/**
 * Perform the pairwise hypergeometric test to assess the co-localization of motifs in a cluster of genes.
 *
 * @param universeSize Total number of all genes in the dataset.
 * @param ICthreshold IC threshold used in discarding two motifs on the same gene that partially overlap.
 * @param clusterName Cluster name from the input file.
 * @param genesInCluster Genes in the cluster with the name clusterName (already sorted for efficiency).
 */
void motifComparison::colocTest(long universeSize, double ICthreshold, const std::string& clusterName,
                                std::vector<std::string>& genesInCluster) {
  // universeSize - total of all genes
  // ICthreshold - used in discarding 2 motifs on same gene which partially overlap
  // clusterName - cluster name fromn input file
  // geneInCluster = genes in cluster clusterName. Already sorted to make this more efficient

  // Find intersecting genes that are in this cluster
  long numGenesWithBothMotifs = genesInUniverseWithBothMotifs.size();

  clusterSize = genesInCluster.size();

  std::cout << "打印genesInCluster：" << std::endl;
  // 打印genesInCluster中的前五个元素，同时要确保不超出向量的实际大小
  for (size_t i = 0; i < genesInCluster.size() && i < 5; ++i) {
      std::cout << genesInCluster[i] << std::endl;
  }


  std::cout << "genesInUniverseWithBothMotifs" << std::endl;
  // 计算需要打印的元素数量：向量大小和5之间的较小值
  size_t count = std::min(genesInUniverseWithBothMotifs.size(), size_t(5));

  // 遍历并打印前五个元素（如果存在）
  for (size_t i = 0; i < count; ++i) {
      std::cout << genesInUniverseWithBothMotifs[i] << std::endl;
  }




  if (!numGenesWithBothMotifs || !clusterSize || !universeSize)
    return;

  genesInClusterWithBothMotifs.clear();
  genesInClusterWithBothMotifs.reserve(numGenesWithBothMotifs);

  // std::set_intersection` is used to calculate the intersection of two sorted ranges (sets)
  std::set_intersection(genesInUniverseWithBothMotifs.begin(),
                        genesInUniverseWithBothMotifs.end(),
                        genesInCluster.begin(),
                        genesInCluster.end(),
                        std::inserter(genesInClusterWithBothMotifs, genesInClusterWithBothMotifs.begin()));

  if (!genesInClusterWithBothMotifs.size())
    return;

  // pval = exp(log_hypergeometric( universeSize));

  // hypergeometric test
  // The computation of the log-scale p-value of the pairwise hypergeometric test.
  // Mirrored after Matlab function proposed by Meng et al. (2009).

  // compile their logftable thing within the function and use that as needed
  // it would appear that the largest index of it they ever access is U+1

  // nedd to sum  the log of all numbers up to universize +1
  // Compute the log-scale p-value of the pairwise hypergeometric test using logf table
  std::vector<double> logf(universeSize + 2, 0.0);
  // could just do this once
  logf[1] = log(1);
  for (int i = 2; i < logf.size(); i++) logf[i] = logf[i - 1] + log(i);

  long minSetSize = (clusterSize < numGenesWithBothMotifs) ? clusterSize : numGenesWithBothMotifs;

  long aSize = minSetSize - genesInClusterWithBothMotifs.size() + 1;
  std::vector<double> a(aSize);

  double amax = -std::numeric_limits<double>::max();
  // Calculate the log-scale hypergeometric probabilities and find the maximum value
  for (int i = 0; i < aSize; i++) {
    long hold = genesInClusterWithBothMotifs.size() + i;
    a[i] = (-logf[hold] - logf[clusterSize - hold] - logf[numGenesWithBothMotifs - hold] -
            logf[universeSize + hold - clusterSize - numGenesWithBothMotifs]);
    amax = (a[i] > amax) ? a[i] : amax;
  }
  // Compute the sum of exponentials for normalization
  double aSum = 0.0;
  for (int i = 0; i < aSize; i++) aSum += exp(a[i] - amax);

  pval = exp(logf[clusterSize] + logf[universeSize - clusterSize] + logf[numGenesWithBothMotifs] +
             logf[universeSize - numGenesWithBothMotifs] - logf[universeSize] + amax + log(aSum));
}
