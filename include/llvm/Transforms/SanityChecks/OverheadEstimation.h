// This file is part of ASAP.
// Please see LICENSE.txt for copyright and licensing information.

#ifndef LLVM_TRANSFORMS_SANITYCHECKS_OVERHEADESTIMATION_H
#define LLVM_TRANSFORMS_SANITYCHECKS_OVERHEADESTIMATION_H

#include "llvm/Pass.h"

namespace sanitychecks {
  class GCOVFile;
}

namespace llvm {
  class Instruction;
}

struct SanityCheckInstructions;

struct OverheadEstimation : public llvm::ModulePass {
  static char ID;

  OverheadEstimation() : ModulePass(ID), SCI(nullptr) {}

  virtual bool runOnModule(llvm::Module &M);

  virtual void getAnalysisUsage(llvm::AnalysisUsage &AU) const;

private:
  SanityCheckInstructions *SCI;
};

#endif
