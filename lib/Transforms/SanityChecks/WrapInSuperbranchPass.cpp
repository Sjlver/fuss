// This file is part of ASAP.
// Please see LICENSE.txt for copyright and licensing information.

#include "WrapInSuperbranchPass.h"
#include "utils.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/Statistic.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/MDBuilder.h"
#include "llvm/IR/Module.h"
#include "llvm/Support/Debug.h"

#define DEBUG_TYPE "asap"

using namespace llvm;

STATISTIC(NumSanityChecksWrapped, "Number of sanity checks wrapped in superbranches");
STATISTIC(NumSanityChecksSkipped, "Number of sanity checks skipped");

// FIXME: fix LLVM var names. Is it still "M" with capital M? If yes, I need to
// adjust my other vars.

bool WrapInSuperbranchPass::runOnModule(Module &M) {
  SCI = &getAnalysis<SanityCheckInstructionsPass>();

  // Add a global variable called `__superbranch_enabled` to the module. It is
  // used as a branch condition in superbranches. Note that we use an i8
  // instead of i1 because the compiler generates unnecessary masking code
  // otherwise.
  Type *sb_enabled_ty = Type::getInt8Ty(M.getContext());
  GlobalVariable *superbranch_enabled = new GlobalVariable(M,
      sb_enabled_ty, false, GlobalValue::WeakODRLinkage,
      Constant::getNullValue(sb_enabled_ty), "__superbranch_enabled");

  for (auto &func : M) {
    for (auto sc : SCI->getSanityCheckRoots(&func)) {
      auto &instrs = SCI->getInstructionsBySanityCheck(sc);
      Instruction *begin = nullptr;
      Instruction *end = nullptr;
      getRegionFromInstructionSet(instrs, &begin, &end);

      DEBUG(
        dbgs() << "Sanitycheck: " << *sc << "\n";
        if (begin) {
          dbgs() << "  Begin: " << *begin << "\n";
        }
        if (end) {
          dbgs() << "  End: " << *end << "\n";
        }
      );

      if (!begin || !end) {
        NumSanityChecksSkipped += 1;
        continue;
      }

      // Create new basic blocks for the code before, in, and after the
      // instrumentation.
      BasicBlock *preBB = begin->getParent();
      BasicBlock *instrumentationBB = preBB->splitBasicBlock(begin, "sb_instrumentation");
      BasicBlock *postBB = end->getParent()->splitBasicBlock(end, "sb_post");

      // Modify the terminator before the instrumentation, so that it skips the
      // instrumentation.
      preBB->getTerminator()->eraseFromParent();
      IRBuilder<> builder(preBB);
      MDBuilder mdBuilder(M.getContext());
      Value *sb_enabled = builder.CreateLoad(superbranch_enabled);
      Value *cond = builder.CreateICmpEQ(sb_enabled,
          ConstantInt::getNullValue(sb_enabled_ty));
      builder.CreateCondBr(cond, postBB, instrumentationBB,
          mdBuilder.createBranchWeights(100000, 1));
      NumSanityChecksWrapped += 1;
    }
  }

  return false;
}

void WrapInSuperbranchPass::getAnalysisUsage(AnalysisUsage &AU) const {
  AU.addRequired<SanityCheckInstructionsPass>();
}

char WrapInSuperbranchPass::ID = 0;
static RegisterPass<WrapInSuperbranchPass>
    X("wrap-in-superbranch", "Wraps instrumentation in superbranches", false,
      false);
