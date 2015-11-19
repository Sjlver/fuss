// This file is part of ASAP.
// Please see LICENSE.txt for copyright and licensing information.

#include "SanityCheckInstructionsPass.h"

#include <algorithm>

#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/Pass.h"
#include "llvm/IR/Dominators.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/Metadata.h"
#include "llvm/IR/CFG.h"
#include "llvm/Support/Debug.h"
#include "llvm/IR/Module.h"
#define DEBUG_TYPE "sanity-check-instructions"

using namespace llvm;

bool SanityCheckInstructionsPass::runOnModule(Module &M) {
  for (Function &F : M) {
    DEBUG(dbgs() << "SanityCheckInstructionsPass on " << F.getName() << "\n");
    SanityCheckInstructions[&F] = InstructionSet();
    SanityCheckRoots[&F] = InstructionSet();
    findInstructions(&F);

    MDNode *MD = MDNode::get(M.getContext(), {});
    for (Instruction *Inst : SanityCheckInstructions[&F]) {
      Inst->setMetadata("sanitycheck", MD);
    }
  }

  return false;
}

void SanityCheckInstructionsPass::findInstructions(Function *F) {
  if (F->empty()) {
    return;
  }

  // A list of instructions that are used by sanity checks. They become sanity
  // check instructions if it turns out they're not used by anything else.
  SmallPtrSet<Instruction *, 128> Worklist;

  // A list of basic blocks that contain sanity check instructions. They
  // become sanity check blocks if it turns out they don't contain anything
  // else.
  SmallPtrSet<BasicBlock *, 64> BlockWorklist;

  // A map from instructions to the checks that use them.
  std::map<Instruction *, SmallPtrSet<Instruction *, 4>> ChecksByInstruction;

  // A dominator tree that we need to determine whether terminators are sanity
  // check instructions.
  DominatorTree DT;
  DT.recalculate(*F);

  // Initialize the work list.
  for (BasicBlock &BB : *F) {
    Instruction *InstrumentationInBB = nullptr;
    for (Instruction &I : BB) {
      if (isInstrumentation(&I)) {
        Worklist.insert(&I);
        ChecksByInstruction[&I].insert(&I);
        SanityCheckRoots[F].insert(&I);
        InstrumentationInBB = &I;
      }

      // If instrumentation is followed by asm instructions for side
      // effects or unreachable instructions, add them. Such instructions
      // were added by the instrumentation tool. This is a bit of a
      // hack...
      if (InstrumentationInBB &&
          (isAsmForSideEffect(&I) || isa<UnreachableInst>(&I))) {
        Worklist.insert(&I);
        ChecksByInstruction[&I].insert(InstrumentationInBB);
      }
    }
  }

  while (!Worklist.empty() || !BlockWorklist.empty()) {
    // Alternate between emptying the worklist...
    while (!Worklist.empty()) {
      Instruction *Inst = *Worklist.begin();
      Worklist.erase(Inst);

      if (onlyUsedInSanityChecks(Inst)) {
        if (SanityCheckInstructions[F].insert(Inst).second) {
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

      if (onlyDominatesInstructionsFrom(
              BB->begin(), SanityCheckInstructions.at(BB->getParent()), DT)) {
        for (User *U : BB->users()) {
          if (Instruction *Inst = dyn_cast<Instruction>(U)) {
            Worklist.insert(Inst);
            // Attribute Inst to the same check as the first instruction in BB.
            auto CBI = ChecksByInstruction.find(BB->begin());
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

bool SanityCheckInstructionsPass::onlyUsedInSanityChecks(Value *V) {
  for (User *U : V->users()) {
    Instruction *Inst = dyn_cast<Instruction>(U);
    if (!Inst)
      return false;

    Function *F = Inst->getParent()->getParent();
    if (!(SanityCheckInstructions[F].count(Inst))) {
      return false;
    }
  }
  return true;
}

bool SanityCheckInstructionsPass::onlyDominatesInstructionsFrom(
    Instruction *I, const InstructionSet &Instrs, const DominatorTree &DT) {
  SmallVector<BasicBlock *, 8> dominatedBBs;
  DT.getDescendants(I->getParent(), dominatedBBs);
  return std::all_of(dominatedBBs.begin(), dominatedBBs.end(),
                     [this, &Instrs](BasicBlock *BB) {
                       return onlyContainsInstructionsFrom(BB, Instrs);
                     });
}

bool SanityCheckInstructionsPass::onlyContainsInstructionsFrom(
    BasicBlock *BB, const InstructionSet &Instrs) {
  return std::all_of(BB->begin(), BB->end(), [&Instrs](Instruction &I) {
    // TODO: ignore debug intrinsics, etc.?
    return Instrs.count(&I) > 0;
  });
}

char SanityCheckInstructionsPass::ID = 0;

static RegisterPass<SanityCheckInstructionsPass>
    X("sanity-check-instructions",
      "Finds instructions belonging to sanity checks", false, false);
