// This file is part of ASAP.
// Please see LICENSE.txt for copyright and licensing information.

#ifndef LLVM_TRANSFORMS_SANITYCHECKS_SANITYCHECKSAMPLEDCOST_H
#define LLVM_TRANSFORMS_SANITYCHECKS_SANITYCHECKSAMPLEDCOST_H

#include "llvm/Transforms/SanityChecks/SanityCheckCost.h"
#include "llvm/Pass.h"

#include <utility>
#include <vector>

namespace llvm {
class BlockFrequencyInfo;
class Instruction;
class raw_ostream;
}

// Determines the cost of a check based on data from a sampling profiler.
struct SanityCheckSampledCost : public llvm::FunctionPass, public SanityCheckCost {
  static char ID;

  SanityCheckSampledCost() : FunctionPass(ID) {
    initializeSanityCheckSampledCostPass(*llvm::PassRegistry::getPassRegistry());
  }

  virtual bool runOnFunction(llvm::Function &F) override;

  virtual void getAnalysisUsage(llvm::AnalysisUsage &AU) const override;

  virtual void print(llvm::raw_ostream &O, const llvm::Module *M) const override;

private:
  // Estimates the execution count for the given instruction
  double getExecutionCount(const llvm::Instruction *I, const llvm::BlockFrequencyInfo &BFI) const;
};

#endif
