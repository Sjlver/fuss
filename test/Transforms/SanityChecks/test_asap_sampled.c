// RUN: rm -rf %t %t.*

// RUN: clang -Wall -O1 -flto -fsanitize=address -c -o %t.orig.o %s
// RUN: clang -Wall -O1 -flto -fsanitize=address -fsanitize=asap -mllvm -asap-cost-threshold=0 -c -o %t.o %s

// RUN: llvm-dis < %t.orig.o | FileCheck --check-prefix CHECKORIG %s
// RUN: llvm-dis < %t.o | FileCheck --check-prefix CHECKASAP %s

#include <stdio.h>

int main () {
    int a[10] = {1, 4, 9, 16, 25, 36, 49, 64, 81, 100};
    int sum = 0;
    int n_numbers;
    printf("How many numbers to sum up?\n");
    scanf("%d", &n_numbers);
    for (int i = 0; i < n_numbers; ++i) {
        // The original file should have complete checks. With ASAP, no trace of checks should be left.
        // CHECKORIG: call void @__asan_report_load4
        // CHECKASAP-NOT: call void @__asan_report_load4
        // CHECKASAP-NOT: !sanitycheck
        sum += a[i];
    }
    printf("\n%d", sum);
    return 0;
}
