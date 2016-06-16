// This file is part of ASAP.
// Please see LICENSE.txt for copyright and licensing information.

#include "utils.h"

#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/IR/Dominators.h"
#include "llvm/Pass.h"

#include <map>

namespace llvm {
class AnalysisUsage;
class BasicBlock;
class CallInst;
class DominatorTree;
class Function;
class Instruction;
class Value;
}

// TODO: This talks about sanity checks... renaming all the stuff to
//       "instrumentation" would be more appropriate.

// TODO: Const-correctness. Shouldn't an InstructionSet contain const instrs?

struct SanityCheckInstructions : public llvm::FunctionPass {
  static char ID;

  SanityCheckInstructions() : FunctionPass(ID) {
    initializeSanityCheckInstructionsPass(*llvm::PassRegistry::getPassRegistry());
  }
  virtual ~SanityCheckInstructions() {}

  virtual bool runOnFunction(llvm::Function &F);

  virtual void getAnalysisUsage(llvm::AnalysisUsage &AU) const {
    AU.addRequired<llvm::DominatorTreeWrapperPass>();
    AU.setPreservesAll();
  }

  const InstructionSet &getSanityCheckRoots() const {
    return SCRoots;
  }

  const InstructionSet &
  getInstructionsBySanityCheck(llvm::Instruction *Inst) const {
    return InstructionsBySanityCheck.at(Inst);
  }

private:
  // All instructions that belong to sanity checks
  InstructionSet SCInstructions;

  // All sanity check roots. These are the instructions at the source of a
  // sanity check. For example, a call to __asan_report_read4.
  InstructionSet SCRoots;

  // A map of all instructions on which a given sanity check root
  // instruction depends.
  // Note that instructions can belong to multiple sanity checks.
  std::map<llvm::Instruction *, InstructionSet> InstructionsBySanityCheck;

  // Searches for sanity check instructions in the given function.
  void findInstructions(llvm::Function *F);

  // Determines whether a given value is only used by sanity check
  // instructions, and nowhere else in the program.
  bool onlyUsedInSanityChecks(llvm::Value *V);

  // Determines whether a given instruction dominates only instructions from a
  // given set, and no other instructions.
  bool onlyDominatesInstructionsFrom(llvm::Instruction *I,
                                    const InstructionSet &Instrs,
                                    const llvm::DominatorTree &DT);

  // Determines whether a given block contains only instructions from a
  // given set, and no other instructions.
  bool onlyContainsInstructionsFrom(llvm::BasicBlock *BB,
                                    const InstructionSet &Instrs);
};
