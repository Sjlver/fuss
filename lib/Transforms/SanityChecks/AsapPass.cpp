// This file is part of ASAP.
// Please see LICENSE.txt for copyright and licensing information.

#include "AsapPass.h"
#include "SanityCheckCostPass.h"
#include "SanityCheckInstructionsPass.h"
#include "utils.h"

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

static cl::opt<double>
SanityLevel("sanity-level", cl::desc("Fraction of static checks to be preserved"), cl::init(-1.0));

static cl::opt<double>
CostLevel("cost-level", cl::desc("Fraction of dynamic checks to be preserved"), cl::init(-1.0));

static cl::opt<unsigned long long>
CostThreshold("asap-cost-threshold",
        cl::desc("Remove checks costing this or more"),
        cl::init((unsigned long long)(-1)));

static cl::opt<bool>
PrintRemovedChecks("print-removed-checks",
        cl::desc("Should a list of removed checks be printed?"),
        cl::init(false));


bool AsapPass::runOnModule(Module &M) {
    SCC = &getAnalysis<SanityCheckCostPass>();
    SCI = &getAnalysis<SanityCheckInstructionsPass>();

    // Check whether we got the right amount of parameters
    int nParams = 0;
    if (SanityLevel >= 0.0) nParams += 1;
    if (CostLevel >= 0.0) nParams += 1;
    if (CostThreshold != (unsigned long long)(-1)) nParams += 1;
    if (nParams != 1) {
        report_fatal_error("Please specify exactly one of -cost-level, "
                           "-sanity-level or -asap-cost-threshold");
    }

    size_t TotalChecks = SCC->getCheckCosts().size();
    if (TotalChecks == 0) {
        dbgs() << "Removed 0 out of 0 static checks (nan%)\n";
        dbgs() << "Removed 0 out of 0 dynamic checks (nan%)\n";
        return false;
    }

    uint64_t TotalCost = 0;
    for (const SanityCheckCostPass::CheckCost &I : SCC->getCheckCosts()) {
        TotalCost += I.second;
    }

    // Start removing checks. They are given in order of decreasing cost, so we
    // simply remove the first few.
    uint64_t RemovedCost = 0;
    size_t NChecksRemoved = 0;
    for (const SanityCheckCostPass::CheckCost &I : SCC->getCheckCosts()) {
        
        if (SanityLevel >= 0.0) {
            if ((NChecksRemoved + 1) > TotalChecks * (1.0 - SanityLevel)) {
                break;
            }
        } else if (CostLevel >= 0.0) {
            // Make sure we get the boundary conditions right... it's important
            // that at cost level 0.0, we don't remove checks that cost zero.
            if (RemovedCost >= TotalCost * (1.0 - CostLevel) ||
                    (RemovedCost + I.second) > TotalCost * (1.0 - CostLevel)) {
                break;
            }
        } else if (CostThreshold != (unsigned long long)(-1)) {
            if (I.second < CostThreshold) {
                break;
            }
        }
        
        if (optimizeCheckAway(I.first)) {
            RemovedCost += I.second;
            NChecksRemoved += 1;
        }
    }
    
    dbgs() << "Removed " << NChecksRemoved << " out of " << TotalChecks
           << " static checks (" << format("%0.2f", (100.0 * NChecksRemoved / TotalChecks)) << "%)\n";
    dbgs() << "Removed " << RemovedCost << " out of " << TotalCost
           << " dynamic checks (" << format("%0.2f", (100.0 * RemovedCost / TotalCost)) << "%)\n";
    return false;
}

void AsapPass::getAnalysisUsage(AnalysisUsage& AU) const {
    AU.addRequired<SanityCheckCostPass>();
    AU.addRequired<SanityCheckInstructionsPass>();
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

    // We'd like to simply remove the check root, and let dead code elimination handle
    // the rest. However, instrumentation tools add things like inline assembly
    // to prevent checks from getting DCE'd, so we need to remove that, too.
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

char AsapPass::ID = 0;
static RegisterPass<AsapPass> X("asap",
        "Removes too costly sanity checks", false, false);
