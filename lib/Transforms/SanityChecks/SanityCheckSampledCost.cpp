// This file is part of ASAP.
// Please see LICENSE.txt for copyright and licensing information.

#include "llvm/Transforms/SanityChecks/SanityCheckSampledCost.h"
#include "llvm/Transforms/SanityChecks/SanityCheckInstructions.h"
#include "llvm/Transforms/SanityChecks/CostModel.h"
#include "llvm/Transforms/SanityChecks/utils.h"

#include "llvm/Analysis/BlockFrequencyInfo.h"
#include "llvm/Analysis/TargetTransformInfo.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/Metadata.h"
#include "llvm/IR/Module.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/Debug.h"
#include "llvm/Support/Format.h"

#include <algorithm>
#include <memory>
#include <system_error>
#define DEBUG_TYPE "sanity-check-cost"

using namespace llvm;

namespace {
bool largerCost(const SanityCheckSampledCost::CheckCost &a,
                const SanityCheckSampledCost::CheckCost &b) {
  return a.second > b.second;
}
} // anonymous namespace

bool SanityCheckSampledCost::runOnFunction(Function &F) {
  DEBUG(dbgs() << "SanityCheckSampledCost on " << F.getName() << "\n");
  CheckCosts.clear();

  TargetTransformInfoWrapperPass &TTIWP =
      getAnalysis<TargetTransformInfoWrapperPass>();

  const TargetTransformInfo &TTI = TTIWP.getTTI(F);
  SanityCheckInstructions &SCI = getAnalysis<SanityCheckInstructions>();
  BlockFrequencyInfo &BFI = getAnalysis<BlockFrequencyInfo>();

  for (Instruction *Inst : SCI.getSanityCheckRoots()) {
    assert(Inst->getParent()->getParent() == &F &&
           "SCI must only contain instructions of the current function.");

#ifndef NDEBUG
    int nInstructions = 0;
    int nFreeInstructions = 0;
    uint64_t maxCount = 0;
#endif

    // The cost of a check is the sum of the cost of all instructions
    // that this check uses.
    // TODO: If an instruction is used by multiple checks, we need an
    // intelligent way to handle the nonlinearity.
    double Cost = 0;
    for (Instruction *CI : SCI.getInstructionsBySanityCheck(Inst)) {
      unsigned CurrentCost = sanitychecks::getInstructionCost(CI, &TTI);

      // Assume a default cost of 1 for unknown instructions
      if (CurrentCost == (unsigned)(-1)) {
        CurrentCost = 1;
      }

      DEBUG(if (CurrentCost == 0) { nFreeInstructions += 1; });

      assert(CurrentCost <= 100 && "Outlier cost value?");

      Cost += CurrentCost * getExecutionCount(CI, BFI);
      DEBUG(nInstructions += 1);
      DEBUG(
          if (getExecutionCount(CI, BFI) > maxCount) { maxCount = getExecutionCount(CI, BFI); });
    }

    APInt CountInt = APInt(64, (uint64_t)Cost);
    MDNode *MD = MDNode::get(
        F.getContext(), {ConstantAsMetadata::get(ConstantInt::get(
                            Type::getInt64Ty(F.getContext()), CountInt))});
    Inst->setMetadata("cost", MD);
    CheckCosts.push_back(std::make_pair(Inst, (uint64_t)Cost));

    DEBUG(dbgs() << "Sanity check: " << *Inst << "\n";
          DebugLoc DL = getInstrumentationDebugLoc(Inst);
          printDebugLoc(DL, F.getContext(), dbgs());
          dbgs() << "\nnInstructions: " << nInstructions << "\n";
          dbgs() << "nFreeInstructions: " << nFreeInstructions << "\n";
          dbgs() << "maxCount: " << maxCount << "\n";
          dbgs() << "Cost: " << Cost << "\n";);
  }

  std::sort(CheckCosts.begin(), CheckCosts.end(), largerCost);

  return false;
}

void SanityCheckSampledCost::getAnalysisUsage(AnalysisUsage &AU) const {
  AU.addRequired<BlockFrequencyInfo>();
  AU.addRequired<TargetTransformInfoWrapperPass>();
  AU.addRequired<SanityCheckInstructions>();
  AU.setPreservesAll();
}

void SanityCheckSampledCost::print(raw_ostream &O, const Module *M) const {
  O << "                Cost Location\n";
  for (const CheckCost &I : CheckCosts) {
    O << format("%20llu ", I.second);
    DebugLoc DL = getInstrumentationDebugLoc(I.first);
    printDebugLoc(DL, M->getContext(), O);
    O << '\n';
  }
}

double SanityCheckSampledCost::getExecutionCount(const Instruction *I, const BlockFrequencyInfo &BFI) const {
  const BasicBlock *BB = I->getParent();
  BlockFrequency Freq = BFI.getBlockFreq(BB);
  uint64_t EntryFreq = BFI.getEntryFreq();

  // Entry counts for functions are the number of samples in the entry block.
  // I'm not sure how precise this is and whether we should mess with it or
  // not. Lots of functions have zeros, though, so let's assume they execute at
  // least once.
  Optional<uint64_t> EntryCount = BB->getParent()->getEntryCount();
  uint64_t AdjustedCount = EntryCount.hasValue() && EntryCount.getValue() > 0
    ? EntryCount.getValue() : 1;

  double scale = (double)Freq.getFrequency() / EntryFreq;
  return AdjustedCount * scale;
}

char SanityCheckSampledCost::ID = 0;
INITIALIZE_PASS_BEGIN(SanityCheckSampledCost, "sanity-check-sampled-cost",
                      "Finds costs of sanity checks", false, false)
INITIALIZE_PASS_DEPENDENCY(TargetTransformInfoWrapperPass)
INITIALIZE_PASS_DEPENDENCY(SanityCheckInstructions)
INITIALIZE_PASS_END(SanityCheckSampledCost, "sanity-check-sampled-cost",
                    "Finds costs of sanity checks", false, false)
