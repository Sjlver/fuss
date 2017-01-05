// This file is part of ASAP.
// Please see LICENSE.txt for copyright and licensing information.

#include "llvm/InitializePasses.h"
#include "llvm/PassRegistry.h"

using namespace llvm;

void llvm::initializeSanityChecks(PassRegistry &Registry) {
  initializeAsapPassPass(Registry);
  initializeAsapCoveragePassPass(Registry);
  initializeAsapGcovPassPass(Registry);
  initializeExitInsteadOfAbortPass(Registry);
  initializeOverheadEstimationPass(Registry);
  initializeSanityCheckGcovCostPass(Registry);
  initializeSanityCheckCoverageCostPass(Registry);
  initializeSanityCheckInstructionsPass(Registry);
  initializeSanityCheckSampledCostPass(Registry);
}
