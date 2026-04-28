#include <stdio.h>
#include <assert.h>
#include <string.h>

#include "FileRead.h"
#include "MotifHit.h"
#include "MotifHitVector.h"
#include "PromoterLength.h"

#include "FimoFile.h"
#include "HashTable.h"
#include "MemCheck.h"

size_t TABLE_SIZE = 175447;

void testCreateFimoFile()
{
  printf("Testing creation:\n");

  FimoFile *file = createFimoFile();

  assert(file->numLines    == 0);
  assert(file->motifName   == NULL);
  assert(file->motifLength == 0);
  assert(file->fileName    == NULL);
  assert(file->outDir      == NULL);
  assert(file->binScore    == false);
  assert(file->hasMotifAlt == false);
  assert(file->ht          != NULL);

  deleteFimoFile(file);
  printf("Test passed for createFimoFile!\n\n\n\n");
}

void testInitFimoFile()
{
  printf("\n\nTesting ininatization:\n");
  // 创建一个FimoFile对象的指针
  FimoFile *testFile = new_malloc(sizeof(FimoFile));
  if (!testFile)
  {
    fprintf(stderr, "Failed to allocate memory for testFile.\n");
    exit(1);
  }

  // 调用初始化函数
  initFimoFile(testFile, 10, "motif_test", 5, "file_test", "dir_test", true, true);

  // 进行断言测试
  assert(testFile->numLines    == 10);
  assert(testFile->motifLength == 5);
  assert(testFile->hasMotifAlt == true);
  assert(testFile->binScore    == true);

  assert(strcmp(testFile->motifName, "motif_test") == 0);
  assert(strcmp(testFile->fileName , "file_test" ) == 0);
  assert(strcmp(testFile->outDir   , "dir_test"  ) == 0);

  assert(testFile->ht != NULL);

  deleteFimoFile(testFile);

  printf("All tests for initFimoFile passed!\n\n\n");
}

void testReadFimoFile()
{
  printf("\n\nTesting reading fimo file:\n");
  // const char *mockFileName = "test_data/mock_fimo.txt";
  // createMockFimoFile(mockFileName);
  const char *mockFileName = "test_data/MYB46_2_short.txt";

  FimoFile *testFile = createFimoFile();
  printf("Value of file->ht: %p\n", testFile->ht);

  testFile->fileName  = new_strdup(mockFileName);
  testFile->motifName = new_strdup(mockFileName);
  testFile->outDir    = new_strdup(mockFileName);
  testFile->binScore  = false; // 请根据模拟文件内容进行设置

  assert(readFimoFile(testFile) == true);
  assert(testFile->numLines     == 8);
  assert(testFile->motifLength  == 8);

  printf("\n\nSearching for AT1G01020 motif hits\n");
  MotifHitVector *vec = getHashTable(testFile->ht, "AT1G01020");
  printMotifHitVector(vec);


  printf("\n\nSearching for AT1G01010 motif hits\n");
  vec = getHashTable(testFile->ht, "AT1G01010");
  printMotifHitVector(vec);


  printf("\n\nPrinting complete hash table:\n\n");
  printHashTable(testFile->ht, adapterPrintFunction);


  printf("\n\nReleasing Hash Table and FimoFile...\n");
  deleteFimoFile(testFile);

  printf("All tests in testReadFimoFile passed!\n");
}

void testProcess()
{
  printf("Testing testProcess...\n");
  FimoFile *myFimoFile = new_malloc(sizeof(FimoFile));

  // 使用参数初始化FimoFile结构体
  initFimoFile(myFimoFile,
               0,                     // numLines
               "MYB46_2",               // motifName
               0,                     // motifLength
               "test_data/MYB46_2_short.txt", // fileName
               "./test_result",       // outDir
               false,                 // hasMotifAlt
               false                  // binScore
  );

  if (!readFimoFile(myFimoFile))
  {
    fprintf(stderr, "Error reading fimo.txt!\n");
    deleteFimoFile(myFimoFile);
  }

  // Iterate to print all the contents of the hash table
  HashTable *ht = myFimoFile->ht;

  for (size_t i = 0; i < TABLE_SIZE; i++)
  {
    struct kv *current = myFimoFile->ht->table[i];
    while (current != NULL)
    {
      printf("Key: %s, Value:\n", current->key);
      printMotifHitVector(current->value);
      current = current->next;
    }
  }

  PromoterList *list = new_malloc(sizeof(PromoterList));
  readPromoterLengthFile(list, "test_data/promoter_lengths.txt");
  printf("Length of AT1G01010: %ld\n", findPromoterLength(list, "AT1G01010"));


  printf("\n\nProcessing fimo file..\n");
  processFimoFile(myFimoFile, 5, 5000, list);


  printf("\n\nPrinting complete hash table:\n\n");
  printHashTable(ht, adapterPrintFunction);

  for (size_t i = 0; i < TABLE_SIZE; i++)
  {
    struct kv *current = myFimoFile->ht->table[i];
    while (current != NULL)
    {
      printf("Key: %s, Value:\n", current->key);
      printMotifHitVector(current->value);
      current = current->next;
    }
  }


  printf("\n\nReleasing...\n");
  deletePromoterLenList(list);
  deleteFimoFile(myFimoFile);

  printf("All tests in testReadFimoFile passed!\n");
}

int main()
{
#ifdef DEBUG
  atexit(show_block); // 在程序结束后显示内存泄漏报告 Display memory leak report after program ends.
#endif
  testCreateFimoFile();
  testInitFimoFile();
  testReadFimoFile();
  testProcess();
  return 0;
}

/*
clang -DDEBUG \
      -o test \
      TestFimoFile.c  \
      FimoFile.c  \
      FileRead.c  \
      HashTable.c  \
      MemCheck.c  \
      MotifHit.c  \
      MotifHitVector.c  \
      PromoterLength.c  \
      ScoreLabelPairVector.c  \
      utils.c
*/
