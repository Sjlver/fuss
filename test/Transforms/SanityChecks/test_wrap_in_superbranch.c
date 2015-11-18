// RUN: clang -Wall -c %s -flto -fsanitize=address -O1 -o %t.o
// RUN: opt -load $(llvm-config --libdir)/SanityChecks.* -debug-only=asap -wrap-in-superbranch %t.o -o %t.wisb.ll -S
// RUN: FileCheck %s < %t.wisb.ll

#include <stdio.h>
#include <stdlib.h>

const int MODULUS = 1000000007;

int main (int argc, char *argv[]) {
  if (argc != 2) {
    fprintf(stderr, "usage: test_wrap_in_superbranch <array_size>\n");
    exit(EXIT_FAILURE);
  }
  
  int array_size = atoi(argv[1]);
  int *array = calloc(array_size, sizeof(int));
  if (array == NULL) {
    fprintf(stderr, "Could not allocate memory\n");
    exit(EXIT_FAILURE);
  }

  for (int i = 0; i < array_size; ++i) {
    array[i] = rand() % MODULUS;
  }

  int sum = 0;
  for (int i = 0; i < array_size; ++i) {
    sum = (sum + array[i]) % MODULUS;
  }

  free(array);
  array = NULL;

  printf("Sum of %d random numbers: %d\n", array_size, sum);
  return EXIT_SUCCESS;
}
