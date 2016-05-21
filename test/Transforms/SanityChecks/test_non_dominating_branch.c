// RUN: clang -Wall -c %s -flto -fsanitize=address -O1 -o %t.o
// RUN: opt -load $(llvm-config --libdir)/SanityChecks.* -sanity-check-instructions %t.o -o %t.ll -S
// RUN: FileCheck %s < %t.ll

int foo (int n, int *ptr) {
  // The test `if (n == 1)` should not be recognized as a sanity check, even
  // though the then-branch goes to a block which contains only sanity check
  // instructions.
  //
  // CHECK: icmp eq i32 %n, 1
  // CHECK-NOT: !sanitycheck
  // CHECK: br i1
  if (n == 1) {
    // On the other hand, there should be a sanity check verifying the access
    // to `ptr`.
    //
    // CHECK: ptrtoint i32* %ptr to i64, !sanitycheck
    return *ptr;
  }

  return 0;
}
