// This file is part of ASAP.
// Please see LICENSE.txt for copyright and licensing information.

#include "llvm/Transforms/SanityChecks/AsapPassBase.h"
#include "llvm/Transforms/SanityChecks/SanityCheckCost.h"
#include "llvm/Transforms/SanityChecks/SanityCheckInstructions.h"
#include "llvm/Transforms/SanityChecks/utils.h"

#include "llvm/IR/BasicBlock.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/DebugInfo.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/Metadata.h"
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
    AsapVerbose("asap-verbose",
                cl::desc("Print a list of checks with their costs"),
                cl::init(false));

bool AsapPassBase::removeExpensiveChecks(Function &F) {
  // Check whether we got the right amount of parameters
  if (CostThreshold == (unsigned long long)(-1)) {
    report_fatal_error("Please specify -asap-cost-threshold");
  }

  size_t TotalChecks = SCC->getCheckCosts().size();
  if (TotalChecks == 0) {
    if (AsapVerbose) {
      dbgs() << "AsapPass: ran on " << F.getName() << " at ";
      DebugLoc DL = getFunctionDebugLoc(F);
      printDebugLoc(DL, F.getContext(), dbgs());
      dbgs() << "\n";
      dbgs() << "  Static checks: total 0, removed 0, kept 0, sanity level nan%\n";
      dbgs() << "  Cost: total 0, removed 0, kept 0, cost level nan%\n";
    }
    return false;
  }

  uint64_t TotalCost = 0;
  for (const SanityCheckCost::CheckCost &I : SCC->getCheckCosts()) {
    TotalCost += I.second;
  }

  // Start removing checks. They are given in order of decreasing cost, so we
  // simply remove the first few.
  uint64_t RemovedCost = 0;
  size_t NChecksRemoved = 0;
  for (const SanityCheckCost::CheckCost &I : SCC->getCheckCosts()) {
    if (I.second >= CostThreshold) {
      if (optimizeCheckAway(I.first)) {
        RemovedCost += I.second;
        NChecksRemoved += 1;
      }
    } else {
      if (AsapVerbose) {
        logSanityCheck(I.first, "keeping", dbgs());
      }
    }
  }

  if (AsapVerbose) {
    dbgs() << "AsapPass: ran on " << F.getName() << " at ";
    DebugLoc DL = getFunctionDebugLoc(F);
    printDebugLoc(DL, F.getContext(), dbgs());
    dbgs() << "\n";
    dbgs() << "  Static checks: total " << TotalChecks << ", removed "
           << NChecksRemoved << ", kept " << (TotalChecks - NChecksRemoved)
           << ", sanity level "
           << format("%0.2f", 100.0 - 100.0 * NChecksRemoved / TotalChecks) << "%\n";
    if (TotalCost == 0) {
      dbgs() << "  Cost: total 0, removed 0, kept 0, cost level nan%\n";
    } else {
      dbgs() << "  Cost: total " << TotalCost << ", removed " << RemovedCost
             << ", kept " << (TotalCost - RemovedCost) << ", cost level "
             << format("%0.2f", 100.0 - 100.0 * RemovedCost / TotalCost) << "%\n";
    }
  }
  return false;
}

// Tries to remove a sanity check; returns true if it worked.
bool AsapPassBase::optimizeCheckAway(llvm::Instruction *Inst) {
  if (AsapVerbose) {
    logSanityCheck(Inst, "removing", dbgs());
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

    // We also remove atomic qualifiers from loads. Such qualifiers are used
    // by SanitizerCoverage. They should be save to remove, since the load is
    // only used by sanity checks.
    if (auto L = dyn_cast<LoadInst>(I)) {
      L->setAtomic(AtomicOrdering::NotAtomic);
    }
  }
  assert(Inst->use_empty() && "Sanity check is being used?");
  Inst->eraseFromParent();
  return true;
}

void AsapPassBase::logSanityCheck(Instruction *Inst, StringRef Action,
                              raw_ostream &Outs) const {
  DebugLoc DL = getInstrumentationDebugLoc(Inst);
  printDebugLoc(DL, Inst->getContext(), Outs);

  ConstantAsMetadata *CostMD = cast<ConstantAsMetadata>(Inst->getMetadata("cost")->getOperand(0));
  uint64_t Cost = cast<ConstantInt>(CostMD->getValue())->getZExtValue();
  Outs << ": asap action:" << Action << " cost:" << Cost;

  if (auto *CI = dyn_cast<CallInst>(Inst)) {
    Outs << " type:" << CI->getCalledFunction()->getName();
  } else if (isa<StoreInst>(Inst)) {
    // For the moment, the only other recognized instrumentation type is sancov
    // counter increments; blindly assume it's that one.
    Outs << " type:__sancov_gen_cov_counter";
  } else {
    assert(false && "Unrecognized instrumentation type.");
  }

  if (DL) {
    if (MDNode *IA = DL.getInlinedAt()) {
      Outs << " inlined:";
      printDebugLoc(DebugLoc(IA), Inst->getContext(), Outs);
      while ((IA = DebugLoc(IA).getInlinedAt())) {
        Outs << ",";
        printDebugLoc(DebugLoc(IA), Inst->getContext(), Outs);
      }
    }
  }

  Outs << "\n";
}
