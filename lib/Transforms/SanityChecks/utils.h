// This file is part of ASAP.
// Please see LICENSE.txt for copyright and licensing information.

#ifndef SANITYCHECKS_UTILS_H
#define SANITYCHECKS_UTILS_H

#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/IR/DebugLoc.h"

namespace llvm {
class BasicBlock;
class BranchInst;
class CallInst;
class Instruction;
class LLVMContext;
class raw_ostream;
}

// Types used to store sanity check blocks / instructions
typedef llvm::SmallPtrSet<llvm::BasicBlock *, 64> BlockSet;
typedef llvm::SmallPtrSet<llvm::Instruction *, 64> InstructionSet;

struct SanityCheckInstructionsPass;

// Returns true if a given instruction is an instrumentation instruction. This
// includes assertions, sanity checks, thread sanitizer memory access logging,
// etc.
bool isInstrumentation(const llvm::Instruction *I);

// Returns true if the given instruction is an empty inline assembly call.
// These are inserted by instrumentation tools to ensure that instrumentation
// code is not optimized away.
bool isAsmForSideEffect(const llvm::Instruction *I);

// Returns true if a given call aborts the program.
bool isAbortingCall(const llvm::CallInst *CI);

// Returns the debug location of a basic block. This is the location of the
// first instruction in the BB which has debug information.
llvm::DebugLoc getBasicBlockDebugLoc(llvm::BasicBlock *BB);

// Returns the debug location for a piece of instrumentation.
llvm::DebugLoc getInstrumentationDebugLoc(llvm::Instruction *Inst);

void printDebugLoc(const llvm::DebugLoc &DbgLoc, llvm::LLVMContext &Ctx,
                   llvm::raw_ostream &Outs);

// Determines the first and one-past-last instruction of a given instruction
// set, via output parameters `begin` and `end`. Returns false if the set
// does not form a contiguous single-entry-single-exit region.
bool getRegionFromInstructionSet(const InstructionSet &instrs,
    llvm::Instruction **begin, llvm::Instruction **end);

#endif /* SANITYCHECKS_UTILS_H */
