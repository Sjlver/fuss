// This file is part of ASAP.
// Please see LICENSE.txt for copyright and licensing information.

#include "llvm/Pass.h"

#include "SanityCheckInstructionsPass.h"

namespace llvm {
  class Instruction;
}

struct WrapInSuperbranchPass : public llvm::ModulePass {
  static char ID;

  WrapInSuperbranchPass() : ModulePass(ID), SCI(nullptr) {}

  virtual bool runOnModule(llvm::Module &M);

  virtual void getAnalysisUsage(llvm::AnalysisUsage &AU) const;

private:
  SanityCheckInstructionsPass *SCI;

  /// Determines the first and one-past-last instruction of a given instruction
  /// set, via output parameters `begin` and `end`. Returns false if the set
  /// does not form a contiguous single-entry-single-exit region.
  bool getRegionFromInstructionSet(
      const SanityCheckInstructionsPass::InstructionSet &instrs,
      llvm::Instruction **begin, llvm::Instruction **end);
};
