// This file is part of ASAP.
// Please see LICENSE.txt for copyright and licensing information.

#include "llvm/Pass.h"

#include <utility>
#include <vector>

namespace llvm {
class BlockFrequencyInfo;
class Instruction;
class raw_ostream;
}

struct SanityCheckSampledCost : public llvm::FunctionPass {
  static char ID;

  SanityCheckSampledCost() : FunctionPass(ID) {
    initializeSanityCheckSampledCostPass(*llvm::PassRegistry::getPassRegistry());
  }

  virtual bool runOnFunction(llvm::Function &F);

  virtual void getAnalysisUsage(llvm::AnalysisUsage &AU) const;

  virtual void print(llvm::raw_ostream &O, const llvm::Module *M) const;

  // A pair that stores a sanity check and its cost.
  typedef std::pair<llvm::Instruction *, uint64_t> CheckCost;

  const std::vector<CheckCost> &getCheckCosts() const { return CheckCosts; };

private:
  // Checks in the current function, with their cost.
  std::vector<CheckCost> CheckCosts;

  // Estimates the execution count for the given instruction
  double getExecutionCount(const llvm::Instruction *I, const llvm::BlockFrequencyInfo &BFI) const;
};
