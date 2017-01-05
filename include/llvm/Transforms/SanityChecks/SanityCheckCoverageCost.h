// This file is part of ASAP.
// Please see LICENSE.txt for copyright and licensing information.

#ifndef LLVM_TRANSFORMS_SANITYCHECKS_SANITYCHECKCOVERAGECOST_H
#define LLVM_TRANSFORMS_SANITYCHECKS_SANITYCHECKCOVERAGECOST_H

#include "llvm/Transforms/SanityChecks/SanityCheckCost.h"
#include "llvm/Pass.h"

#include "llvm/DebugInfo/DIContext.h"

#include <utility>
#include <vector>

namespace llvm {
class BlockFrequencyInfo;
class Instruction;
class raw_ostream;
class DILocation;
}

// Boilerplate for reading a file and producing intelligent error messages.
// Mostly copied from llvm/ProfileData/...

const std::error_category &sanity_check_cost_category();

enum class sanity_check_cost_error {
  success = 0,
  too_large,
};

inline std::error_code make_error_code(sanity_check_cost_error E) {
  return std::error_code(static_cast<int>(E), sanity_check_cost_category());
}

namespace std {
template <>
struct is_error_code_enum<sanity_check_cost_error> : std::true_type {};
}

// Determines the cost of a check based on data from a sampling profiler.
struct SanityCheckCoverageCost : public llvm::FunctionPass, public SanityCheckCost {
  static char ID;

  SanityCheckCoverageCost() : FunctionPass(ID) {
    initializeSanityCheckCoverageCostPass(*llvm::PassRegistry::getPassRegistry());
  }

  bool doInitialization(llvm::Module &M) override {
    return loadCoverage(M);
  }

  virtual bool runOnFunction(llvm::Function &F) override;

  virtual void getAnalysisUsage(llvm::AnalysisUsage &AU) const override;

  virtual void print(llvm::raw_ostream &O, const llvm::Module *M) const override;

private:
  // The set of locations that have been covered, as a vector of
  // DIInliningInfos.
  std::vector<llvm::DIInliningInfo> CoveredLocations;

  // Loads coverage info from a file containing program counters, and builds a
  // list of symbolized debug locations. Returns true on success.
  bool loadCoverage(const llvm::Module &M);

  // Compares a DIInliningInfo and a DILocation, returning true if they match
  // (i.e., have the same source location and inlining stack).
  bool locationsMatch(const llvm::DILocation &DIL, const llvm::DIInliningInfo &DIII);
};

#endif
