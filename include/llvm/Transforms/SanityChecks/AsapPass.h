// This file is part of ASAP.
// Please see LICENSE.txt for copyright and licensing information.

#include "llvm/Pass.h"

namespace llvm {
class Instruction;
}

struct SanityCheckSampledCost;
struct SanityCheckInstructions;

struct AsapPass : public llvm::FunctionPass {
  static char ID;

  AsapPass() : FunctionPass(ID), SCC(0), SCI(0) {
    initializeAsapPassPass(*llvm::PassRegistry::getPassRegistry());
  }

  virtual bool runOnFunction(llvm::Function &F);

  virtual void getAnalysisUsage(llvm::AnalysisUsage &AU) const;

private:
  SanityCheckSampledCost *SCC;
  SanityCheckInstructions *SCI;

  // Tries to remove a sanity check; returns true if it worked.
  bool optimizeCheckAway(llvm::Instruction *Inst);
};

llvm::FunctionPass *createAsapPass();
