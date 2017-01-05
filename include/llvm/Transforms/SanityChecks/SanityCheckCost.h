// This file is part of ASAP.
// Please see LICENSE.txt for copyright and licensing information.

#ifndef LLVM_TRANSFORMS_SANITYCHECKS_SANITYCHECKCOST_H
#define LLVM_TRANSFORMS_SANITYCHECKS_SANITYCHECKCOST_H

#include <cstdint>
#include <utility>
#include <vector>

namespace llvm {
class Instruction;
}

// A base class for passes that compute sanity check costs.
struct SanityCheckCost {
  // A pair that stores a sanity check and its cost.
  typedef std::pair<llvm::Instruction *, uint64_t> CheckCost;

  const std::vector<CheckCost> &getCheckCosts() const { return CheckCosts; };

protected:
  // Checks in the current function, with their cost.
  std::vector<CheckCost> CheckCosts;
};

#endif
