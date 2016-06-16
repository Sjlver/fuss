// Various utility functions

// This file is part of ASAP.
// Please see LICENSE.txt for copyright and licensing information.

#include "llvm/Transforms/SanityChecks/utils.h"
#include "llvm/Transforms/SanityChecks/SanityCheckInstructions.h"

#include "llvm/IR/DebugInfo.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/InlineAsm.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/IntrinsicInst.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/raw_ostream.h"
using namespace llvm;

static cl::opt<bool> OptimizeSanityChecks(
    "asap-optimize-sanitychecks",
    cl::desc("Should ASAP affect sanity checks (e.g., from ASan)?"),
    cl::init(true));

static cl::opt<bool> OptimizeAssertions(
    "asap-optimize-assertions",
    cl::desc("Should ASAP affect programmer-written assertions?"),
    cl::init(true));

static cl::opt<bool> OptimizeThreadSanitizer(
    "asap-optimize-tsan",
    cl::desc("Should ASAP affect TSan runtime library functions?"),
    cl::init(true));

namespace {
  // Returns the next instruction after inst that is not a debug info
  // intrinsic.
  Instruction *skipDbgInfoIntrinsics(Instruction *inst) {
    while (inst && isa<DbgInfoIntrinsic>(inst)) { 
      inst = inst->getNextNode();
    }
    return inst;
  }
}  // anonymous namespace

bool isInstrumentation(const Instruction *I) {
  if (auto *CI = dyn_cast<const CallInst>(I)) {
    if (CI->getCalledFunction()) {
      StringRef name = CI->getCalledFunction()->getName();
      if (name.startswith("__ubsan_handle_")) {
        return OptimizeSanityChecks;
      }
      if (name.startswith("__softboundcets_") && name.endswith("_abort")) {
        return OptimizeSanityChecks;
      }
      if (name.startswith("__asan_report_")) {
        return OptimizeSanityChecks;
      }
      if (name == "__assert_fail" || name == "__assert_rtn") {
        return OptimizeAssertions;
      }
      if (name.startswith("__tsan_read") ||
          name.startswith("__tsan_unaligned_read") ||
          name.startswith("__tsan_write") ||
          name.startswith("__tsan_unaligned_write")) {
        return OptimizeThreadSanitizer;
      }
    }
  }
  return false;
}

bool isAsmForSideEffect(const Instruction *I) {
  if (const CallInst *CI = dyn_cast<CallInst>(I)) {
    if (const InlineAsm *IA = dyn_cast<InlineAsm>(CI->getCalledValue())) {
      return (IA->getAsmString().empty() && IA->getConstraintString().empty());
    }
  }

  return false;
}

bool isAbortingCall(const CallInst *CI) {
  if (CI->getCalledFunction()) {
    StringRef name = CI->getCalledFunction()->getName();
    if (name.startswith("__ubsan_") && name.endswith("_abort")) {
      return true;
    }
    if (name.startswith("__softboundcets_") && name.endswith("_abort")) {
      return true;
    }
    if (name.startswith("__asan_report_")) {
      return true;
    }
    if (name == "__assert_fail" || name == "__assert_rtn") {
      return true;
    }
  }
  return false;
}

DebugLoc getBasicBlockDebugLoc(BasicBlock *BB) {
  for (Instruction &Inst : *BB) {
    DebugLoc DL = Inst.getDebugLoc();
    if (DL)
      return DL;
  }
  return DebugLoc();
}

DebugLoc getInstrumentationDebugLoc(Instruction *Inst) {
  DebugLoc DL = Inst->getDebugLoc();
  if (DL)
    return DL;

  // If the instruction itself does not have a debug location,
  // we first scan other instructions in the same basic block.
  BasicBlock *BB = Inst->getParent();
  DL = getBasicBlockDebugLoc(BB);
  if (DL)
    return DL;

  // If that doesn't help, we look at the branch that leads to this
  // instruction, and scan the alternate basic block, if any.
  for (auto U : BB->users()) {
    if (auto *BI = dyn_cast<BranchInst>(U)) {
      for (unsigned i = 0; i < BI->getNumSuccessors(); ++i) {
        BasicBlock *AltBB = BI->getSuccessor(i);
        if (AltBB == BB)
          continue;

        DL = getBasicBlockDebugLoc(AltBB);
        if (DL)
          return DL;
      }
    }
  }

  // Nothing helps...
  return DebugLoc();
}

void printDebugLoc(const DebugLoc &DbgLoc, LLVMContext &Ctx,
                   raw_ostream &Outs) {
  if (!DbgLoc) {
    Outs << "<debug info not available>";
    return;
  }

  DILocation *DL = dyn_cast_or_null<DILocation>(DbgLoc.getAsMDNode());
  if (!DL) {
    Outs << "<debug info not available>";
    return;
  }

  StringRef Filename = DL->getFilename();
  Outs << Filename << ':' << DL->getLine();

  if (DL->getColumn() != 0) {
    Outs << ':' << DL->getColumn();
  }
}

bool getRegionFromInstructionSet(const InstructionSet &instrs,
    Instruction **begin, Instruction **end) {

  // Find a predecessor for each instruction in the set (and for instructions
  // that succeed those in the set).
  DenseMap<Instruction*, Instruction*> predecessors;
  for (auto ins : instrs) {
    // Ensure each instruction from the set is in the map
    if (!predecessors.count(ins)) {
      predecessors[ins] = nullptr;
    }

    // Handle instructions in the middle of basic blocks
    Instruction* successor = skipDbgInfoIntrinsics(ins->getNextNode());
    if (successor) {
      //DEBUG(dbgs() << "Found successor inline: " << *ins << " -> " << *successor << "\n");
      predecessors[successor] = ins;
      continue;
    }

    // No successor? Then it must be a terminator. These are succeeded by the
    // basic blocks they branch to.
    TerminatorInst *tins = cast<TerminatorInst>(ins);
    for (unsigned i = 0, e = tins->getNumSuccessors(); i < e; ++i) {
      BasicBlock *successorBB = tins->getSuccessor(i);
      successor = skipDbgInfoIntrinsics(&*successorBB->begin());
      //DEBUG(dbgs() << "Found successor from terminator: " << *ins << " -> " << *successor << "\n");
      predecessors[successor] = ins;
    }
  }

  // Now look through the predecessors map to find:
  // - an instruction in the set with no predecessor => the entry of the region
  // - an instruction not in the set => the exit of the region
  Instruction *entryIns = nullptr;
  Instruction *exitIns = nullptr;
  for (auto pred : predecessors) {
    if (pred.second == nullptr) {
      //DEBUG(dbgs() << "Found entry: " << *pred.first << "\n");
      if (entryIns == nullptr) {
        entryIns = pred.first;
      } else {
        // Multiple entry nodes... bail out because we don't handle this case.
        entryIns = nullptr;
        break;
      }
    } else if (!instrs.count(pred.first)) {
      //DEBUG(dbgs() << "Found exit: " << *pred.first << "\n");
      if (exitIns == nullptr) {
        exitIns = pred.first;
      } else {
        // Multiple exit nodes... bail out because we don't handle this case.
        exitIns = nullptr;
        break;
      }
    }
  }

  if (entryIns && exitIns) {
    if (begin != nullptr)
      *begin = entryIns;
    if (end != nullptr)
      *end = exitIns;
    return true;
  }

  return false;
}
