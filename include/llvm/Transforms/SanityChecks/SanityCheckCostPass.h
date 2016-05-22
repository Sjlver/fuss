// This file is part of ASAP.
// Please see LICENSE.txt for copyright and licensing information.

#include "GCOV.h"

#include "llvm/Pass.h"

#include <utility>
#include <vector>

namespace llvm {
class Instruction;
class raw_ostream;
}

struct SanityCheckCostPass : public llvm::FunctionPass {
  static char ID;

  SanityCheckCostPass() : FunctionPass(ID) {}

  virtual bool doInitialization(llvm::Module &M);

  virtual bool runOnFunction(llvm::Function &F);

  virtual void getAnalysisUsage(llvm::AnalysisUsage &AU) const;

  virtual void print(llvm::raw_ostream &O, const llvm::Module *M) const;

  // A pair that stores a sanity check and its cost.
  typedef std::pair<llvm::Instruction *, uint64_t> CheckCost;

  const std::vector<CheckCost> &getCheckCosts() const { return CheckCosts; };

private:
  // The GCOVFile for the module being compiled. This is shared accross calls
  // to runOnFunction. Since it's read-only, I hope this is OK.
  std::unique_ptr<sanitychecks::GCOVFile> GF;

  // Checks in the current function, with their cost.
  std::vector<CheckCost> CheckCosts;

  std::unique_ptr<sanitychecks::GCOVFile> createGCOVFile();
};
