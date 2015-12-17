// This file is part of ASAP.
// Please see LICENSE.txt for copyright and licensing information.

#include "llvm/Pass.h"

namespace sanitychecks {
  class GCOVFile;
}

namespace llvm {
  class Instruction;
}

struct SanityCheckInstructionsPass;

struct OverheadEstimationPass : public llvm::ModulePass {
  static char ID;

  OverheadEstimationPass() : ModulePass(ID), SCI(0) {}

  virtual bool runOnModule(llvm::Module &M);

  virtual void getAnalysisUsage(llvm::AnalysisUsage &AU) const;

private:
  SanityCheckInstructionsPass *SCI;
};
