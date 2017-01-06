// This file is part of ASAP.
// Please see LICENSE.txt for copyright and licensing information.

#include "llvm/Transforms/SanityChecks/SanityCheckCoverageCost.h"
#include "llvm/Transforms/SanityChecks/SanityCheckInstructions.h"
#include "llvm/Transforms/SanityChecks/utils.h"

#include "llvm/Analysis/BlockFrequencyInfo.h"
#include "llvm/Analysis/TargetTransformInfo.h"
#include "llvm/DebugInfo/Symbolize/Symbolize.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/DebugInfoMetadata.h"
#include "llvm/IR/DiagnosticInfo.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/Metadata.h"
#include "llvm/IR/Module.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/Debug.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/Format.h"
#include "llvm/Support/LineIterator.h"
#include "llvm/Support/Regex.h"

#include <algorithm>
#include <map>
#include <memory>
#include <string>
#include <system_error>
#define DEBUG_TYPE "sanity-check-cost"

using namespace llvm;

namespace {
const std::string kInvalidFileName("<invalid>");
Regex kPCLineRegex("^[ \t]*(NEW_PC: )?(0x[0-9a-f]+)");

// FIXME: This class is only here to support the transition to llvm::Error. It
// will be removed once this transition is complete. Clients should prefer to
// deal with the Error value directly, rather than converting to error_code.
class SanityCheckCostErrorCategoryType : public std::error_category {
  const char *name() const noexcept override { return "sanity-check-cost"; }
  std::string message(int IE) const override {
    sanity_check_cost_error E = static_cast<sanity_check_cost_error>(IE);
    switch (E) {
    case sanity_check_cost_error::success:
      return "Success";
    case sanity_check_cost_error::too_large:
      return "Too much coverage data";
    }
    llvm_unreachable("A value of sampleprof_error has no message.");
  }
};

bool largerCost(const SanityCheckCost::CheckCost &a,
                const SanityCheckCost::CheckCost &b) {
  return a.second > b.second;
}

// Prepare a memory buffer for the contents of Filename.
//
// Returns an error code indicating the status of the buffer.
static ErrorOr<std::unique_ptr<MemoryBuffer>>
setupMemoryBuffer(const Twine &Filename) {
  auto BufferOrErr = MemoryBuffer::getFile(Filename);
  if (std::error_code EC = BufferOrErr.getError())
    return EC;
  auto Buffer = std::move(BufferOrErr.get());

  // Sanity check the file.
  if (Buffer->getBufferSize() > std::numeric_limits<uint32_t>::max())
    return sanity_check_cost_error::too_large;

  return std::move(Buffer);
}
} // anonymous namespace

static ManagedStatic<SanityCheckCostErrorCategoryType> ErrorCategory;

const std::error_category &sanity_check_cost_category() {
  return *ErrorCategory;
}

static cl::opt<std::string> ModuleName("asap-module-name", cl::init(""),
    cl::desc("Path to object file where we can resolve program counters"));

static cl::opt<std::string> PCFile("asap-coverage-file", cl::init(""),
    cl::desc("Path to file containing covered program counters"));

bool SanityCheckCoverageCost::runOnFunction(Function &F) {
  DEBUG(dbgs() << "SanityCheckCoverageCost on " << F.getName() << "\n");
  CheckCosts.clear();

  SanityCheckInstructions &SCI = getAnalysis<SanityCheckInstructions>();

  DEBUG({
      for (auto &DIII: CoveredLocations) {
        dbgs() << "Covered: ";
        for (uint32_t i = 0, e = DIII.getNumberOfFrames(); i < e; ++i) {
          auto IIFrame = DIII.getFrame(i);
          dbgs() << IIFrame.FileName << ":" << IIFrame.Line << ":" << IIFrame.Column << ":" << IIFrame.Discriminator << " ";
        }
        dbgs() << "\n";
      }
  });

  for (Instruction *Inst : SCI.getSanityCheckRoots()) {
    assert(Inst->getParent()->getParent() == &F &&
           "SCI must only contain instructions of the current function.");

    // The cost of a check is one if it has the same debug location as a PC in
    // `PCFile`, otherwise zero.
    double Cost = 0;
    DEBUG(dbgs() << "Check instruction " << *Inst << "\n");
    if (DebugLoc Loc = Inst->getDebugLoc()) {
      if (DILocation *DIL = Loc.get()) {
        DEBUG({
            dbgs() << "Looking for " << DIL->getFilename() << ":" << DIL->getLine() << ":" << DIL->getColumn() << ":" << DIL->getDiscriminator();
            for (auto DIP = DIL->getInlinedAt(); DIP; DIP = DIP->getInlinedAt()) {
              dbgs() << " " << DIP->getFilename() << ":" << DIP->getLine() << ":" << DIP->getColumn() << ":" << DIP->getDiscriminator();
            }
            dbgs() << " ...\n";
        });

        if (std::any_of(CoveredLocations.begin(), CoveredLocations.end(), [this, DIL](const DIInliningInfo &DIII) {
              return locationsMatch(*DIL, DIII);
              })) {
          Cost = 1;
          DEBUG(dbgs() << "found");
        }
        DEBUG(dbgs() << "\n");
      }
    }

    APInt CountInt = APInt(64, (uint64_t)Cost);
    MDNode *MD = MDNode::get(
        F.getContext(), {ConstantAsMetadata::get(ConstantInt::get(
                            Type::getInt64Ty(F.getContext()), CountInt))});
    Inst->setMetadata("cost", MD);
    CheckCosts.push_back(std::make_pair(Inst, (uint64_t)Cost));
  }

  std::sort(CheckCosts.begin(), CheckCosts.end(), largerCost);

  return false;
}

void SanityCheckCoverageCost::getAnalysisUsage(AnalysisUsage &AU) const {
  AU.addRequired<SanityCheckInstructions>();
  AU.setPreservesAll();
}

void SanityCheckCoverageCost::print(raw_ostream &O, const Module *M) const {
  O << "                Cost Location\n";
  for (const CheckCost &I : CheckCosts) {
    O << format("%20llu ", I.second);
    DebugLoc DL = getInstrumentationDebugLoc(I.first);
    printDebugLoc(DL, M->getContext(), O);
    O << '\n';
  }
}

bool SanityCheckCoverageCost::loadCoverage(const Module &M) {
  assert(!CoveredLocations.size() &&
         "SanityCheckCoverageCost initialized twice?");

  auto BufOrErr = setupMemoryBuffer(PCFile);
  if (std::error_code EC = BufOrErr.getError()) {
    M.getContext().diagnose(DiagnosticInfoSampleProfile(
        PCFile, "Could not open PCFile: " + EC.message()));
    return false;
  }

  symbolize::LLVMSymbolizer Symbolizer;

  std::unique_ptr<MemoryBuffer> Buffer = std::move(BufOrErr.get());
  line_iterator LineIt(*Buffer, /*SkipBlanks=*/true, '#');
  for (; !LineIt.is_at_eof(); ++LineIt) {
    SmallVector<StringRef, 3> Matches;
    if (kPCLineRegex.match(*LineIt, &Matches)) {
      uint64_t Offset;
      if (Matches[2].getAsInteger(0, Offset)) {
        M.getContext().diagnose(DiagnosticInfoSampleProfile(
            PCFile, LineIt.line_number(), "Could not parse PC: " + *LineIt));
        return false;
      }

      auto ResOrErr = Symbolizer.symbolizeInlinedCode(ModuleName, Offset);
      if (!ResOrErr) {
        M.getContext().diagnose(DiagnosticInfoSampleProfile(
            PCFile, LineIt.line_number(), "Could not symbolize PC: " + *LineIt));
        return false;
      }

      auto Res = ResOrErr.get();
      if (Res.getNumberOfFrames() && Res.getFrame(0).FileName != kInvalidFileName) {
        DEBUG(dbgs() << "Covered! " << Matches[2] << " " << Res.getFrame(0).FileName << ":" << Res.getFrame(0).Line << "\n");
        CoveredLocations.push_back(Res);
      }
    }
  }

  return true;
}

bool SanityCheckCoverageCost::locationsMatch(const DILocation &DIL, const DIInliningInfo &DIII) {
  const DILocation *LocFrame = &DIL;
  for (uint32_t i = 0, e = DIII.getNumberOfFrames(); i < e; ++i) {
    if (!LocFrame) {
      // No match if DIII has more frames than DIL.
      return false;
    }
    const DILineInfo &IIFrame = DIII.getFrame(i);

    // Compare the DILocation frame to the DIInliningInfo frame. Note that the
    // debug info in the binary does not preserve column numbers and
    // discriminators for inlined instructions. Thus we only take these values
    // into account if they are non-zero.
    if (/**/!sys::fs::equivalent(IIFrame.FileName, LocFrame->getFilename())
         || IIFrame.Line != LocFrame->getLine()
         || (IIFrame.Column != 0 && LocFrame->getColumn() != 0
           && IIFrame.Column != LocFrame->getColumn())
         || (IIFrame.Discriminator != 0 && LocFrame->getDiscriminator() != 0
           && IIFrame.Discriminator != LocFrame->getDiscriminator())) {
      return false;
    }
    LocFrame = LocFrame->getInlinedAt();
  }
  if (LocFrame) {
    // No match if DIL has more frames than DIII.
    return false;
  }
  return true;
}

char SanityCheckCoverageCost::ID = 0;
INITIALIZE_PASS_BEGIN(SanityCheckCoverageCost, "sanity-check-coverage-cost",
                      "Finds costs of sanity checks", false, false)
INITIALIZE_PASS_DEPENDENCY(BlockFrequencyInfoWrapperPass)
INITIALIZE_PASS_DEPENDENCY(TargetTransformInfoWrapperPass)
INITIALIZE_PASS_DEPENDENCY(SanityCheckInstructions)
INITIALIZE_PASS_END(SanityCheckCoverageCost, "sanity-check-coverage-cost",
                    "Finds costs of sanity checks", false, false)
