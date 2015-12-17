// This file is part of ASAP.
// Please see LICENSE.txt for copyright and licensing information.

#include "utils.h"
#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/Pass.h"

#include <map>

namespace llvm {
class AnalysisUsage;
class BasicBlock;
class CallInst;
class Function;
class Instruction;
class Value;
}

// TODO: This talks about sanity checks... renaming all the stuff to
//       "instrumentation" would be more appropriate.

// TODO: Const-correctness. Shouldn't an InstructionSet contain const instrs?

struct SanityCheckInstructionsPass : public llvm::ModulePass {
  static char ID;

  SanityCheckInstructionsPass() : ModulePass(ID) {}
  virtual ~SanityCheckInstructionsPass() {}

  virtual bool runOnModule(llvm::Module &M);

  virtual void getAnalysisUsage(llvm::AnalysisUsage &AU) const {
    AU.setPreservesAll();
  }

  const InstructionSet &getSanityCheckRoots(llvm::Function *F) const {
    return SanityCheckRoots.at(F);
  }

  const BlockSet &getSanityCheckBlocks(llvm::Function *F) const {
    return SanityCheckBlocks.at(F);
  }

  const InstructionSet &
  getInstructionsBySanityCheck(llvm::Instruction *Inst) const {
    return InstructionsBySanityCheck.at(Inst);
  }

private:
  // All blocks that contain only sanity check instructions
  std::map<llvm::Function *, BlockSet> SanityCheckBlocks;

  // All instructions that belong to sanity checks
  std::map<llvm::Function *, InstructionSet> SanityCheckInstructions;

  // All sanity check roots. These are the instructions at the source of a
  // sanity check. For example, a call to __asan_report_read4.
  std::map<llvm::Function *, InstructionSet> SanityCheckRoots;

  // A map of all instructions on which a given sanity check root
  // instruction depends.
  // Note that instructions can belong to multiple sanity checks.
  std::map<llvm::Instruction *, InstructionSet> InstructionsBySanityCheck;

  // Searches for sanity check instructions in the given function.
  void findInstructions(llvm::Function *F);

  // Determines whether a given value is only used by sanity check
  // instructions, and nowhere else in the program.
  bool onlyUsedInSanityChecks(llvm::Value *V);

  // Determines whether a given block contains only instructions from a
  // given set, and no other instructions.
  bool onlyContainsInstructionsFrom(llvm::BasicBlock *BB,
                                    const InstructionSet &Instrs);
};
