// This file is part of ASAP.
// Please see LICENSE.txt for copyright and licensing information.

#include "llvm/Transforms/SanityChecks/AsapPass.h"
#include "llvm/Transforms/SanityChecks/SanityCheckCoverageCost.h"
#include "llvm/Transforms/SanityChecks/SanityCheckGcovCost.h"
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

bool AsapPass::runOnFunction(Function &F) {
  SCC = &getAnalysis<SanityCheckSampledCost>();
  SCI = &getAnalysis<SanityCheckInstructions>();
  
  return removeExpensiveChecks(F);
}

void AsapPass::getAnalysisUsage(AnalysisUsage &AU) const {
  AU.addRequired<SanityCheckSampledCost>();
  AU.addRequired<SanityCheckInstructions>();
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


bool AsapGcovPass::runOnFunction(Function &F) {
  SCC = &getAnalysis<SanityCheckGcovCost>();
  SCI = &getAnalysis<SanityCheckInstructions>();
  
  return removeExpensiveChecks(F);
}

void AsapGcovPass::getAnalysisUsage(AnalysisUsage &AU) const {
  AU.addRequired<SanityCheckGcovCost>();
  AU.addRequired<SanityCheckInstructions>();
}

FunctionPass *createAsapGcovPass() {
  return new AsapGcovPass();
}

char AsapGcovPass::ID = 0;
INITIALIZE_PASS_BEGIN(AsapGcovPass, "asap-gcov",
                      "Removes too costly sanity checks", false, false)
INITIALIZE_PASS_DEPENDENCY(SanityCheckGcovCost)
INITIALIZE_PASS_DEPENDENCY(SanityCheckInstructions)
INITIALIZE_PASS_END(AsapGcovPass, "asap-gcov",
                    "Removes too costly sanity checks", false, false)


bool AsapCoveragePass::runOnFunction(Function &F) {
  SCC = &getAnalysis<SanityCheckCoverageCost>();
  SCI = &getAnalysis<SanityCheckInstructions>();
  
  return removeExpensiveChecks(F);
}

void AsapCoveragePass::getAnalysisUsage(AnalysisUsage &AU) const {
  AU.addRequired<SanityCheckCoverageCost>();
  AU.addRequired<SanityCheckInstructions>();
}

FunctionPass *createAsapCoveragePass() {
  return new AsapCoveragePass();
}

char AsapCoveragePass::ID = 0;
INITIALIZE_PASS_BEGIN(AsapCoveragePass, "asap-coverage",
                      "Removes too costly sanity checks", false, false)
INITIALIZE_PASS_DEPENDENCY(SanityCheckCoverageCost)
INITIALIZE_PASS_DEPENDENCY(SanityCheckInstructions)
INITIALIZE_PASS_END(AsapCoveragePass, "asap-coverage",
                    "Removes too costly sanity checks", false, false)
