// This file is part of ASAP.
// Please see LICENSE.txt for copyright and licensing information.

#ifndef LLVM_TRANSFORMS_SANITYCHECKS_SANITYCHECKGCOVCOST_H
#define LLVM_TRANSFORMS_SANITYCHECKS_SANITYCHECKGCOVCOST_H

#include "llvm/Transforms/SanityChecks/SanityCheckCost.h"
#include "llvm/Pass.h"
#include "GCOV.h"

#include <utility>
#include <vector>

namespace llvm {
class Instruction;
class raw_ostream;
}

// Determines the cost of a check based on data from GCOV.
struct SanityCheckGcovCost : public llvm::FunctionPass, public SanityCheckCost {
  static char ID;

  SanityCheckGcovCost() : FunctionPass(ID) {
    initializeSanityCheckGcovCostPass(*llvm::PassRegistry::getPassRegistry());
  }

  virtual bool doInitialization(llvm::Module &M) override;

  virtual bool runOnFunction(llvm::Function &F) override;

  virtual void getAnalysisUsage(llvm::AnalysisUsage &AU) const override;

  virtual void print(llvm::raw_ostream &O, const llvm::Module *M) const override;

private:
  // The GCOVFile for the module being compiled. This is shared accross calls
  // to runOnFunction. Since it's read-only, I hope this is OK.
  std::unique_ptr<sanitychecks::GCOVFile> GF;

  std::unique_ptr<sanitychecks::GCOVFile> createGCOVFile();
};

#endif
