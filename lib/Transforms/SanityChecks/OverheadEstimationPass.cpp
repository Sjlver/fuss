// This file is part of ASAP.
// Please see LICENSE.txt for copyright and licensing information.

#include "OverheadEstimationPass.h"
#include "SanityCheckInstructionsPass.h"
#include "utils.h"

#include "llvm/IR/BasicBlock.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Module.h"
#include "llvm/Support/Debug.h"
#define DEBUG_TYPE "asap"

using namespace llvm;

bool OverheadEstimationPass::runOnModule(Module &M) {

  Type *ty = Type::getInt64Ty(M.getContext());
  GlobalVariable *sanity_counter = new GlobalVariable(M,
      ty, false, GlobalValue::ExternalLinkage,
      0, "__asap_num_cycles");

  for (auto &func : M) {
    if (func.isDeclaration()) continue;

    SCI = &getAnalysis<SanityCheckInstructionsPass>(func);
    for (auto sc : SCI->getSanityCheckRoots()) {
      auto &instrs = SCI->getInstructionsBySanityCheck(sc);
      Instruction *begin = nullptr;
      getRegionFromInstructionSet(instrs, &begin, nullptr);

      if (!begin) {
        DEBUG(
          dbgs() << "[!] The first instruction is not found\n";
          dbgs() << "Sanitycheck: " << *sc << "\n";
        );
        continue;
      }

      // Insert counter incrementation instructions
      IRBuilder<> builder(begin);
      LoadInst *load = builder.CreateLoad(sanity_counter);
      Value *inc = builder.CreateAdd(builder.getInt64(1), load);
      builder.CreateStore(inc, sanity_counter);
    }
  }

  return false;
}

void OverheadEstimationPass::getAnalysisUsage(AnalysisUsage &AU) const {
  AU.addRequired<SanityCheckInstructionsPass>();
}

char OverheadEstimationPass::ID = 0;
static RegisterPass<OverheadEstimationPass> X("overhead-estimation",
    "Computes the number of checks reached at runtime", false, false);
