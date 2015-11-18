// This file is part of ASAP.
// Please see LICENSE.txt for copyright and licensing information.

#include "WrapInSuperbranchPass.h"
#include "utils.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/MDBuilder.h"
#include "llvm/IR/Module.h"
#include "llvm/Support/Debug.h"

#define DEBUG_TYPE "asap"

using namespace llvm;

// FIXME: fix LLVM var names. Is it still "M" with capital M? If yes, I need to
// adjust my other vars.

bool WrapInSuperbranchPass::runOnModule(Module &M) {
  SCI = &getAnalysis<SanityCheckInstructionsPass>();

  // Add a global variable called `__superbranch_enabled` to the module. It is
  // used as a branch condition in superbranches.
  Type *ty = Type::getInt1Ty(M.getContext());
  GlobalVariable *superbranchEnabled = new GlobalVariable(M,
      ty, false, GlobalValue::InternalLinkage,
      Constant::getNullValue(ty), "__superbranch_enabled");

  for (auto &func : M) {
    for (auto sc : SCI->getSanityCheckRoots(&func)) {
      auto &instrs = SCI->getInstructionsBySanityCheck(sc);
      Instruction *begin = nullptr;
      Instruction *end = nullptr;
      getRegionFromInstructionSet(instrs, &begin, &end);

      DEBUG(
        dbgs() << "Sanitycheck: " << *sc << "\n";
        if (begin) {
          dbgs() << "  Begin: " << *begin << "\n";
        }
        if (end) {
          dbgs() << "  End: " << *end << "\n";
        }
      );

      if (!begin || !end) {
        continue;
      }

      // Create new basic blocks for the code before, in, and after the
      // instrumentation.
      BasicBlock *preBB = begin->getParent();
      BasicBlock *instrumentationBB = preBB->splitBasicBlock(begin, "sb_instrumentation");
      BasicBlock *postBB = end->getParent()->splitBasicBlock(end, "sb_post");

      // Modify the terminator before the instrumentation, so that it skips the
      // instrumentation.
      preBB->getTerminator()->eraseFromParent();
      IRBuilder<> builder(preBB);
      MDBuilder mdBuilder(M.getContext());
      Value *cond = builder.CreateLoad(superbranchEnabled);
      builder.CreateCondBr(cond, instrumentationBB, postBB,
          mdBuilder.createBranchWeights(1, 100000));
    }
  }

  return false;
}

void WrapInSuperbranchPass::getAnalysisUsage(AnalysisUsage &AU) const {
  AU.addRequired<SanityCheckInstructionsPass>();
}

bool WrapInSuperbranchPass::getRegionFromInstructionSet(
    const SanityCheckInstructionsPass::InstructionSet &instrs,
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
    Instruction* successor = ins->getNextNode();
    if (successor && successor != ins->getParent()->end()) {
      //DEBUG(dbgs() << "Found successor inline: " << *ins << " -> " << *successor << "\n");
      predecessors[successor] = ins;
      continue;
    }

    // No successor? Then it must be a terminator. These are succeeded by the
    // basic blocks they branch to.
    TerminatorInst *tins = cast<TerminatorInst>(ins);
    for (unsigned i = 0, e = tins->getNumSuccessors(); i < e; ++i) {
      BasicBlock *successorBB = tins->getSuccessor(i);
      successor = successorBB->begin();
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
    *begin = entryIns;
    *end = exitIns;
    return true;
  }

  return false;
}

char WrapInSuperbranchPass::ID = 0;
static RegisterPass<WrapInSuperbranchPass>
    X("wrap-in-superbranch", "Wraps instrumentation in superbranches", false,
      false);
