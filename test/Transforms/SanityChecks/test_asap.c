// RUN: rm -rf %t %t.*

// Initial build
// RUN: ASAP_STATE_PATH=%t.state asap-clang -asap-init
// RUN: ASAP_STATE_PATH=%t.state asap-clang -Wall -O1 -fsanitize=address -c -o %t.o  %s
// RUN: ASAP_STATE_PATH=%t.state asap-clang -Wall -O1 -fsanitize=address -o %t %t.o

// Coverage build
// RUN: ASAP_STATE_PATH=%t.state asap-clang -asap-coverage
// RUN: ASAP_STATE_PATH=%t.state asap-clang -Wall -O1 -fsanitize=address -c -o %t.o  %s
// RUN: ASAP_STATE_PATH=%t.state asap-clang -Wall -O1 -fsanitize=address -o %t %t.o

// RUN: echo 10 | %t
// RUN: ASAP_STATE_PATH=%t.state asap-clang -asap-compute-costs

// Optimized build
// RUN: ASAP_STATE_PATH=%t.state asap-clang -asap-optimize -asap-cost-level=0
// RUN: ASAP_STATE_PATH=%t.state asap-clang -Wall -O1 -fsanitize=address -c -o %t.o  %s
// RUN: ASAP_STATE_PATH=%t.state asap-clang -Wall -O1 -fsanitize=address -o %t %t.o

// RUN: llvm-dis < %t.state/objects/$(basename %t).orig.o | FileCheck --check-prefix CHECKORIG %s
// RUN: llvm-dis < %t.state/objects/$(basename %t).asap.o | FileCheck --check-prefix CHECKASAP %s
// RUN: llvm-dis < %t.state/objects/$(basename %t).asap.opt.o | FileCheck --check-prefix CHECKASAPOPT %s

#include <stdio.h>

int main () {
    int a[10] = {1, 4, 9, 16, 25, 36, 49, 64, 81, 100};
    int sum = 0;
    int n_numbers;
    printf("How many numbers to sum up?\n");
    scanf("%d", &n_numbers);
    for (int i = 0; i < n_numbers; ++i) {
        // The original file should have complete checks. After ASAP runs, the
        // calls to the reporting functions have been removed, but check
        // dependencies remain. The subsequent optimization step should get rid
        // of all of them.
        // CHECKORIG: call void @__asan_report_load4
        // CHECKASAP: !sanitycheck
        // CHECKASAP-NOT: call void @__asan_report_load4
        // CHECKASAPOPT-NOT: !sanitycheck
        sum += a[i];
    }
    printf("\n%d", sum);
    return 0;
}
