// This benchmark should establish ground truth for PGO data. It contains
// various variants of the same code. These should have roughly the same cost.

// RUN: clang -Wall -g -O2 -fsanitize-coverage=trace-pc-guard -fprofile-sample-use=%s.llvm_prof -o %t -fsanitize=asap -mllvm -asap-cost-threshold=1000000 -mllvm -asap-verbose %s >%t.costs 2>&1 
// RUN: FileCheck %s < %t.costs

#include <stdlib.h>
#include <stdio.h>

volatile unsigned int counter;

const unsigned int N_CASES = 12;
unsigned int case_counts[N_CASES] = {0};

// Just some random operation that should take a bit of time
#define LITTLE_WORK do { \
  counter += 1;          \
} while (0)

// Another random operation that should take a bit more time
#define MUCH_WORK do {                                     \
  counter += 1; counter += 1; counter += 1; counter += 1;  \
  counter += 1; counter += 1; counter += 1; counter += 1;  \
  counter += 1; counter += 1; counter += 1; counter += 1;  \
  counter += 1; counter += 1; counter += 1; counter += 1;  \
} while (0)

// We test different variants of the same code, to see whether profiling
// handles it correctly. If all goes well, checks in these parts should have
// roughly the same cost.

// Variant 1: the code resides in a function
__attribute__((noinline))
void code_in_function() {
  if (rand() % 2 == 0) {
    if (rand() % 2 == 0) {
      // This case should have a `trace_pc_guard` call with a cost of approx. 1,000-2,999
      // However, because of MUCH_WORK, its cost is inflated :(
      // CHECK-DAG: {{.*}}:[[@LINE+1]]:22:0: asap action:keeping cost:{{[56][0-9][0-9][0-9]}} type:__sanitizer_cov_trace_pc_guard
      case_counts[0] += 1;
      MUCH_WORK;
    } else {
      // This case should have a `trace_pc_guard` call with a cost of approx. 1,000-2,999
      // CHECK-DAG: {{.*}}:[[@LINE+1]]:22:0: asap action:keeping cost:{{[12][0-9][0-9][0-9]}} type:__sanitizer_cov_trace_pc_guard
      case_counts[1] += 1;
    }
  } else {
    if (rand() % 2 == 0) {
      // This case should have a `trace_pc_guard` call with a cost of approx. 1,000-2,999
      // CHECK-DAG: {{.*}}:[[@LINE+1]]:22:0: asap action:keeping cost:{{[12][0-9][0-9][0-9]}} type:__sanitizer_cov_trace_pc_guard
      case_counts[2] += 1;
      LITTLE_WORK;
    } else {
      // This case should have a `trace_pc_guard` call with a cost of approx. 1,000-2,999
      // CHECK-DAG: {{.*}}:[[@LINE+1]]:22:0: asap action:keeping cost:{{[12][0-9][0-9][0-9]}} type:__sanitizer_cov_trace_pc_guard
      case_counts[3] += 1;
    }
  }
}

// Variant 2: Use a macro, to test discriminators
#define CODE_IN_MACRO              \
  do {                             \
    if (rand() % 2 == 0) {         \
      if (rand() % 2 == 0) {       \
        case_counts[4] += 1;       \
        MUCH_WORK;                 \
      } else {                     \
        case_counts[5] += 1;       \
      }                            \
    } else {                       \
      if (rand() % 2 == 0) {       \
        case_counts[6] += 1;       \
        LITTLE_WORK;               \
      } else {                     \
        case_counts[7] += 1;       \
      }                            \
    }                              \
  } while (0)


int main() {
  for (int i = 0; i < 10000000; ++i) {
    code_in_function();

    // The following lines should use discriminators to distinguish four different `trace_pc_guard` calls.
    // CHECK-DAG: {{.*}}:[[@LINE+4]]:5:3: asap action:keeping cost:{{[34][0-9][0-9][0-9]}} type:__sanitizer_cov_trace_pc_guard
    // CHECK-DAG: {{.*}}:[[@LINE+3]]:5:7: asap action:keeping cost:{{[12][0-9][0-9][0-9]}} type:__sanitizer_cov_trace_pc_guard
    // CHECK-DAG: {{.*}}:[[@LINE+2]]:5:10: asap action:keeping cost:{{[12][0-9][0-9][0-9]}} type:__sanitizer_cov_trace_pc_guard
    // CHECK-DAG: {{.*}}:[[@LINE+1]]:5:14: asap action:keeping cost:{{[12][0-9][0-9][0-9]}} type:__sanitizer_cov_trace_pc_guard
    CODE_IN_MACRO;

    // Variant 3: The code resides directly inside main()
    if (rand() % 2 == 0) {
      if (rand() % 2 == 0) {
        // This case should have a `trace_pc_guard` call with a cost of approx. 1,000-2,999
        // However, because of MUCH_WORK, its cost is inflated :(
        // CHECK-DAG: {{.*}}:[[@LINE+1]]:24:0: asap action:keeping cost:{{[34][0-9][0-9][0-9]}} type:__sanitizer_cov_trace_pc_guard
        case_counts[8] += 1;
        MUCH_WORK;
      } else {
        // This case should have a `trace_pc_guard` call with a cost of approx. 1,000-2,999
        // CHECK-DAG: {{.*}}:[[@LINE+1]]:24:0: asap action:keeping cost:{{[12][0-9][0-9][0-9]}} type:__sanitizer_cov_trace_pc_guard
        case_counts[9] += 1;
      }
    } else {
      if (rand() % 2 == 0) {
        // This case should have a `trace_pc_guard` call with a cost of approx. 1,000-2,999
        // CHECK-DAG: {{.*}}:[[@LINE+1]]:25:0: asap action:keeping cost:{{[12][0-9][0-9][0-9]}} type:__sanitizer_cov_trace_pc_guard
        case_counts[10] += 1;
        LITTLE_WORK;
      } else {
        // This case should have a `trace_pc_guard` call with a cost of approx. 1,000-2,999
        // CHECK-DAG: {{.*}}:[[@LINE+1]]:25:0: asap action:keeping cost:{{[12][0-9][0-9][0-9]}} type:__sanitizer_cov_trace_pc_guard
        case_counts[11] += 1;
      }
    }
  }

  for (int i = 0; i < N_CASES; ++i) {
    printf("case_counts[%d] = %d\n", i, case_counts[i]);
  }

  return 0;
}
