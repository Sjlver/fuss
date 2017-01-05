// Tests whether costs are computed correctly based on coverage

// RUN: rm -rf %t %t.*

// Compile the program with trace_pc_guard
// RUN: clang -Wall -g -O2 -fsanitize-coverage=trace-pc-guard -flto -c -o %t.o %s
// RUN: clang -Wall -g -O2 -fsanitize-coverage=trace-pc-guard -flto -o %t %t.o

// Get locations of all calls to trace_pc_guard
// RUN: llvm-objdump -d %t | grep 'call.*__sanitizer_cov_trace_pc_guard>' | awk '{print "0x"$1}' | tr -d : > %t.pcs

// Compute check costs
// RUN: opt -sanity-check-coverage-cost -asap-module-name=%t -asap-coverage-file=%t.pcs -analyze %t.o | FileCheck -check-prefix CHECK-PCS %s

// Perform the same computation, but with bogus values for covered PCs
// RUN: echo -e "0x12345\n0x23456\n0x34567" >> %t.nopcs
// RUN: opt -sanity-check-coverage-cost -asap-module-name=%t -asap-coverage-file=%t.nopcs -analyze %t.o | FileCheck -check-prefix CHECK-NOPCS %s

#include <stdio.h>

int foo(int *a, int n) {
    int sum = 0;
    for (int i = 0; i < n; ++i) {
        sum += a[i];
    }
    return sum;
}

int a[] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10};


// Verify that the checks that were inlined from function foo have the right cost
// CHECK: Printing analysis 'Finds costs of sanity checks' for function 'main':
// CHECK-PCS: 1 {{.*}}:24:16
// CHECK-NOPCS: 0 {{.*}}:24:16
int main(int argc, char *argv[]) {
    if (foo(a, argc) == argc * (argc + 1) / 2) {
        return 0;
    } else {
        return 1;
    }
}
