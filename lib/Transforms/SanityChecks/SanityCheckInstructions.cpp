// This file is part of ASAP.
// Please see LICENSE.txt for copyright and licensing information.

#include "llvm/Transforms/SanityChecks/SanityCheckInstructions.h"

#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/ADT/Statistic.h"
#include "llvm/Pass.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/Metadata.h"
#include "llvm/IR/CFG.h"
#include "llvm/Support/Debug.h"
#include "llvm/IR/Module.h"

#include <algorithm>

#define DEBUG_TYPE "sanity-check-instructions"

using namespace llvm;

STATISTIC(NumSanityChecksDetected, "Number of sanity checks detected");

bool SanityCheckInstructions::runOnFunction(Function &F) {
  DEBUG(dbgs() << "SanityCheckInstructions on " << F.getName() << "\n");
  SCInstructions.clear();
  SCRoots.clear();
  InstructionsBySanityCheck.clear();
  findInstructions(&F);

  MDNode *MD = MDNode::get(F.getContext(), {});
  for (Instruction *Inst : SCInstructions) {
    Inst->setMetadata("sanitycheck", MD);
  }

  return !SCInstructions.empty();
}

void SanityCheckInstructions::findInstructions(Function *F) {
  if (F->empty()) {
    return;
  }

  // A list of instructions that are used by sanity checks. They become sanity
  // check instructions if it turns out they're not used by anything else.
  SmallPtrSet<Instruction *, 32> Worklist;

  // A list of basic blocks that contain sanity check instructions. They
  // become sanity check blocks if it turns out they don't contain anything
  // else.
  SmallPtrSet<BasicBlock *, 32> BlockWorklist;

  // A map from instructions to the checks that use them.
  std::map<Instruction *, SmallPtrSet<Instruction *, 4>> ChecksByInstruction;

  // A dominator tree that we need to determine whether terminators are sanity
  // check instructions.
  DominatorTree &DT = getAnalysis<DominatorTreeWrapperPass>().getDomTree();

  // Initialize the work list.
  for (BasicBlock &BB : *F) {
    Instruction *InstrumentationInBB = nullptr;
    for (Instruction &I : BB) {
      if (isInstrumentation(&I)) {
        Worklist.insert(&I);
        ChecksByInstruction[&I].insert(&I);
        SCRoots.insert(&I);
        NumSanityChecksDetected += 1;
        InstrumentationInBB = &I;
      }

      // If instrumentation is followed by asm instructions for side
      // effects, unreachable instructions or an unconditional branch, add
      // them. Such instructions were added by the instrumentation tool. This
      // is a bit of a hack...
      if (InstrumentationInBB) {
        BranchInst *BI = dyn_cast<BranchInst>(&I);
        if (isAsmForSideEffect(&I) || isa<UnreachableInst>(&I) ||
            (BI && BI->isUnconditional())) {
          Worklist.insert(&I);
          ChecksByInstruction[&I].insert(InstrumentationInBB);
        }
      }
    }
  }

  while (!Worklist.empty() || !BlockWorklist.empty()) {
    // Alternate between emptying the worklist...
    while (!Worklist.empty()) {
      Instruction *Inst = *Worklist.begin();
      Worklist.erase(Inst);

      if (onlyUsedInSanityChecks(Inst)) {
        if (SCInstructions.insert(Inst).second) {
          for (Use &U : Inst->operands()) {
            if (Instruction *Op = dyn_cast<Instruction>(U.get())) {
              Worklist.insert(Op);

              // Copy ChecksByInstruction from Inst to Op
              auto CBI = ChecksByInstruction.find(Inst);
              if (CBI != ChecksByInstruction.end()) {
                ChecksByInstruction[Op].insert(CBI->second.begin(),
                                               CBI->second.end());
              }
            }
          }

          BlockWorklist.insert(Inst->getParent());

          // Fill InstructionsBySanityCheck from the inverse
          // ChecksByInstruction
          auto CBI = ChecksByInstruction.find(Inst);
          if (CBI != ChecksByInstruction.end()) {
            for (Instruction *CI : CBI->second) {
              InstructionsBySanityCheck[CI].insert(Inst);
            }
          }
        }
      }
    }

    // ... and checking whether this causes basic blocks to dominate only
    // sanity check instructions. This would imply that branches to these
    // blocks could be eliminated, and would cause the corresponding
    // terminators to be added to the worklist.
    while (!BlockWorklist.empty()) {
      BasicBlock *BB = *BlockWorklist.begin();
      BlockWorklist.erase(BB);

      if (onlyDominatesInstructionsFrom(&*BB->begin(), SCInstructions, DT)) {
        for (User *U : BB->users()) {
          if (Instruction *Inst = dyn_cast<Instruction>(U)) {
            Worklist.insert(Inst);
            // Attribute Inst to the same check as the first instruction in BB.
            auto CBI = ChecksByInstruction.find(&*BB->begin());
            if (CBI != ChecksByInstruction.end()) {
              ChecksByInstruction[Inst].insert(CBI->second.begin(),
                                               CBI->second.end());
            }
          }
        }
      }
    }
  }
}

bool SanityCheckInstructions::onlyUsedInSanityChecks(Value *V) {
  for (User *U : V->users()) {
    Instruction *Inst = dyn_cast<Instruction>(U);
    if (!Inst)
      return false;

    if (!(SCInstructions.count(Inst))) {
      return false;
    }
  }
  return true;
}

bool SanityCheckInstructions::onlyDominatesInstructionsFrom(
    Instruction *I, const InstructionSet &Instrs, const DominatorTree &DT) {
  SmallVector<BasicBlock *, 8> dominatedBBs;
  DT.getDescendants(I->getParent(), dominatedBBs);
  return std::all_of(dominatedBBs.begin(), dominatedBBs.end(),
                     [this, &Instrs](BasicBlock *BB) {
                       return onlyContainsInstructionsFrom(BB, Instrs);
                     });
}

bool SanityCheckInstructions::onlyContainsInstructionsFrom(
    BasicBlock *BB, const InstructionSet &Instrs) {
  return std::all_of(BB->begin(), BB->end(), [&Instrs](Instruction &I) {
    // TODO: ignore debug intrinsics, etc.?
    return Instrs.count(&I) > 0;
  });
}

char SanityCheckInstructions::ID = 0;
INITIALIZE_PASS_BEGIN(SanityCheckInstructions, "sanity-check-instructions",
                      "Finds instructions belonging to sanity checks", false, false)
INITIALIZE_PASS_DEPENDENCY(DominatorTreeWrapperPass)
INITIALIZE_PASS_END(SanityCheckInstructions, "sanity-check-instructions",
                      "Finds instructions belonging to sanity checks", false, false)
