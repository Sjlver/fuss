// This file is part of ASAP.
// Please see LICENSE.txt for copyright and licensing information.

#ifndef LLVM_TRANSFORMS_SANITYCHECKS_ASAPPASSBASE_H
#define LLVM_TRANSFORMS_SANITYCHECKS_ASAPPASSBASE_H

#include "llvm/Pass.h"

namespace llvm {
class Instruction;
}

struct SanityCheckCost;
struct SanityCheckInstructions;

// A base class for passes that remove expensive sanity checks. This is mostly
// for code reuse; it contains the functionality to iterate through checks and
// remove expensive ones. Subclasses can parametrize this using, say, different
// was to compute a check's cost.
struct AsapPassBase {
  AsapPassBase() : SCC(0), SCI(0) {}

protected:
  // A pass to compute the cost of a sanity check.
  SanityCheckCost *SCC;

  // A pass to find instructions that belong to sanity checks.
  SanityCheckInstructions *SCI;

  // Removes expensive checks from the given function.
  virtual bool removeExpensiveChecks(llvm::Function &F);

  // Tries to remove a sanity check; returns true if it worked.
  bool optimizeCheckAway(llvm::Instruction *Inst);

  // Writes information about a sanity check to the given stream.
  void logSanityCheck(llvm::Instruction *Inst, llvm::StringRef Action,
                      llvm::raw_ostream &Outs) const;
};

#endif
