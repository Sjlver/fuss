// This file is part of ASAP.
// Please see LICENSE.txt for copyright and licensing information.

#ifndef LLVM_TRANSFORMS_SANITYCHECKS_ASAPPASS_H
#define LLVM_TRANSFORMS_SANITYCHECKS_ASAPPASS_H

#include "llvm/Transforms/SanityChecks/AsapPassBase.h"

// The default instantiation of ASAP. Estimates cost using a sampling profiler.
struct AsapPass : public llvm::FunctionPass, public AsapPassBase {
  static char ID;

  AsapPass() : FunctionPass(ID) {
    initializeAsapPassPass(*llvm::PassRegistry::getPassRegistry());
  }

  virtual bool runOnFunction(llvm::Function &F) override;

  virtual void getAnalysisUsage(llvm::AnalysisUsage &AU) const override;
};

llvm::FunctionPass *createAsapPass();


// An instantiation of ASAP using cost information from GCOV.
struct AsapGcovPass : public llvm::FunctionPass, public AsapPassBase {
  static char ID;

  AsapGcovPass() : FunctionPass(ID) {
    initializeAsapGcovPassPass(*llvm::PassRegistry::getPassRegistry());
  }

  virtual bool runOnFunction(llvm::Function &F) override;

  virtual void getAnalysisUsage(llvm::AnalysisUsage &AU) const override;
};

llvm::FunctionPass *createAsapGcovPass();


// An instantiation of ASAP using cost information from covered PCs.
struct AsapCoveragePass : public llvm::FunctionPass, public AsapPassBase {
  static char ID;

  AsapCoveragePass() : FunctionPass(ID) {
    initializeAsapCoveragePassPass(*llvm::PassRegistry::getPassRegistry());
  }

  virtual bool runOnFunction(llvm::Function &F) override;

  virtual void getAnalysisUsage(llvm::AnalysisUsage &AU) const override;
};

llvm::FunctionPass *createAsapCoveragePass();

#endif
