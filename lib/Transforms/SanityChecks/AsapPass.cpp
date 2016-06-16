// This file is part of ASAP.
// Please see LICENSE.txt for copyright and licensing information.

#include "llvm/Transforms/SanityChecks/AsapPass.h"
#include "llvm/Transforms/SanityChecks/SanityCheckSampledCost.h"
#include "llvm/Transforms/SanityChecks/SanityCheckInstructions.h"
#include "llvm/Transforms/SanityChecks/utils.h"

#include "llvm/IR/BasicBlock.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/DebugInfo.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/Instructions.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/Debug.h"
#include "llvm/Support/Format.h"
#include "llvm/Support/raw_ostream.h"
#define DEBUG_TYPE "asap"

using namespace llvm;

static cl::opt<unsigned long long>
    CostThreshold("asap-cost-threshold",
                  cl::desc("Remove checks costing this or more"),
                  cl::init((unsigned long long)(-1)));

static cl::opt<bool>
    PrintRemovedChecks("print-removed-checks",
                       cl::desc("Should a list of removed checks be printed?"),
                       cl::init(false));

bool AsapPass::runOnFunction(Function &F) {
  SCC = &getAnalysis<SanityCheckSampledCost>();
  SCI = &getAnalysis<SanityCheckInstructions>();

  // Check whether we got the right amount of parameters
  if (CostThreshold == (unsigned long long)(-1)) {
    report_fatal_error("Please specify -asap-cost-threshold");
  }

  size_t TotalChecks = SCC->getCheckCosts().size();
  if (TotalChecks == 0) {
    if (PrintRemovedChecks) {
      dbgs() << "AsapPass on " << F.getName() << "\n";
      dbgs() << "Removed 0 out of 0 static checks (nan%)\n";
      dbgs() << "Removed 0 out of 0 dynamic checks (nan%)\n";
    }
    return false;
  }

  uint64_t TotalCost = 0;
  for (const SanityCheckSampledCost::CheckCost &I : SCC->getCheckCosts()) {
    TotalCost += I.second;
  }

  // Start removing checks. They are given in order of decreasing cost, so we
  // simply remove the first few.
  uint64_t RemovedCost = 0;
  size_t NChecksRemoved = 0;
  for (const SanityCheckSampledCost::CheckCost &I : SCC->getCheckCosts()) {
    if (I.second < CostThreshold) {
      break;
    }

    if (optimizeCheckAway(I.first)) {
      RemovedCost += I.second;
      NChecksRemoved += 1;
    }
  }

  if (PrintRemovedChecks) {
    dbgs() << "AsapPass on " << F.getName() << "\n";
    dbgs() << "Removed " << NChecksRemoved << " out of " << TotalChecks
           << " static checks ("
           << format("%0.2f", (100.0 * NChecksRemoved / TotalChecks)) << "%)\n";
    if (TotalCost == 0) {
      dbgs() << "Removed " << RemovedCost << " out of " << TotalCost
             << " dynamic checks (nan%)\n";
    } else {
      dbgs() << "Removed " << RemovedCost << " out of " << TotalCost
             << " dynamic checks ("
             << format("%0.2f", (100.0 * RemovedCost / TotalCost)) << "%)\n";
    }
  }
  return false;
}

void AsapPass::getAnalysisUsage(AnalysisUsage &AU) const {
  AU.addRequired<SanityCheckSampledCost>();
  AU.addRequired<SanityCheckInstructions>();
}

// Tries to remove a sanity check; returns true if it worked.
bool AsapPass::optimizeCheckAway(llvm::Instruction *Inst) {
  if (PrintRemovedChecks) {
    DebugLoc DL = getInstrumentationDebugLoc(Inst);
    printDebugLoc(DL, Inst->getContext(), dbgs());
    dbgs() << ": SanityCheck with cost ";
    dbgs() << *Inst->getMetadata("cost")->getOperand(0);

    if (DL) {
      if (MDNode *IA = DL.getInlinedAt()) {
        dbgs() << " (inlined at ";
        printDebugLoc(DebugLoc(IA), Inst->getContext(), dbgs());
        dbgs() << ")";
      }
    }

    if (auto *CI = dyn_cast<CallInst>(Inst)) {
      dbgs() << " " << CI->getCalledFunction()->getName();
    }
    dbgs() << "\n";
  }

  // We'd like to simply remove the check root, and let dead code elimination
  // handle the rest. However, instrumentation tools add things like inline
  // assembly to prevent checks from getting DCE'd, so we need to remove that,
  // too.
  for (auto I : SCI->getInstructionsBySanityCheck(Inst)) {
    if (isAsmForSideEffect(I)) {
      assert(I->use_empty() && "AsmForSideEffect is being used?");
      I->eraseFromParent();
    }
  }
  assert(Inst->use_empty() && "Sanity check is being used?");
  Inst->eraseFromParent();
  return true;
}

FunctionPass *createAsapPass() {
  return new AsapPass();
}

char AsapPass::ID = 0;
INITIALIZE_PASS_BEGIN(AsapPass, "asap",
                      "Removes too costly sanity checks", false, false)
INITIALIZE_PASS_DEPENDENCY(SanityCheckSampledCost)
INITIALIZE_PASS_DEPENDENCY(SanityCheckInstructions)
INITIALIZE_PASS_END(AsapPass, "asap",
                    "Removes too costly sanity checks", false, false)
