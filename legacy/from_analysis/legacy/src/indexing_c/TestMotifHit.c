#include "MotifHit.h"
#include "MemCheck.h"
#include <stdio.h>

int main()
{
#ifdef DEBUG
  atexit(show_block); // 在程序结束后显示内存泄漏报告
#endif

  // Sample data
  const char *motif_id = "AHL12";
  const char *motif_alt_id = "孙悟空";
  const char *sequence_name = "AT1G01020";
  long startPos = 614;
  long stopPos = 621;
  char strand = '+';
  double score = 7.85401;
  double pVal = 0.000559;
  const char *sequence = "AAATAATT";
  double binScore = 0; // Assume this is the binScore as it was not explicitly provided

  // Initialize a MotifHit instance using the init function
  MotifHit hit;
  initMotifHit(&hit, motif_id, motif_alt_id, sequence_name, startPos, stopPos, strand, score, pVal, sequence, binScore);

  // Test the initialization
  assert(strcmp(hit.motif_id, motif_id) == 0);
  assert(strcmp(hit.motif_alt_id, motif_alt_id) == 0);
  assert(strcmp(hit.sequence_name, sequence_name) == 0);
  assert(hit.startPos == startPos);
  assert(hit.stopPos == stopPos);
  assert(hit.strand == strand);
  assert(hit.score == score);
  assert(hit.pVal == pVal);
  assert(strcmp(hit.sequence, sequence) == 0);
  assert(hit.binScore == binScore);
  printf("Initialization test passed!\n");

  // Test printing the MotifHit
  printf("\nExpected Output:\n");
  printf("AHL12\t孙悟空\tAT1G01020\t614\t621\t+\t7.85401\t0.000559\tAAATAATT\t0\n");

  printf("\nActual Output:\n");
  printMotifHit(&hit);

  deleteMotifHitContents(&hit);
  printf("\n\n");

  // Simulate a sample motif hit data
  MotifHit sampleHit;
  sampleHit.motif_id      = "MOTIF_ID1";
  sampleHit.motif_alt_id  = "MOTIF_ALT_ID1";
  sampleHit.sequence_name = "SEQUENCE_NAME2";
  sampleHit.startPos      = 10;
  sampleHit.stopPos       = 20;
  sampleHit.strand        = '+';
  sampleHit.score         = 0.95;
  sampleHit.pVal          = 0.05;
  sampleHit.sequence      = "AAATAATT";
  sampleHit.binScore      = 0.8;

  // Print the sample motif hit data
  printf("Printing sampleHit:\n");
  printMotifHit(&sampleHit);

  // For the sake of this example, let's create another motif hit and compare them
  MotifHit* anotherHit = new_malloc(sizeof(MotifHit));

  // using string literals to initialize `char*` pointers
  // no need to free them
  anotherHit->motif_id      = "MOTIF_ID2";
  anotherHit->motif_alt_id  = "MOTIF_ALT_ID2";
  anotherHit->sequence_name = "SEQUENCE_NAME2";
  anotherHit->startPos      = 15;
  anotherHit->stopPos       = 25;
  anotherHit->strand        = '-';
  anotherHit->score         = 0.90;
  anotherHit->pVal          = 0.10;
  anotherHit->sequence      = "AAATAATT";
  anotherHit->binScore      = 0.75;

  printf("Printing anotherHit:\n");
  printMotifHit(anotherHit);

  // Compare the p-values of the two hits using sortHits function
  if (sortHits(&sampleHit, anotherHit)) {
      printf("\nThe sampleHit has a lower pVal than anotherHit.\n");
  } else {
      printf("\nThe anotherHit has a lower pVal than sampleHit.\n");
  }

  // sampleHit were initialized without allocating ram, no need to free
  deleteMotifHitContents(&hit);
  new_free(anotherHit);
  return 0;
}

// clang -DDEBUG -o test TestMotifHit.c MotifHit.c MemCheck.c
