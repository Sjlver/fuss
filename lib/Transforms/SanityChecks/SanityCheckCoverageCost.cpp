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
#include "llvm/IR/InstIterator.h"
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
const std::string kTracePcGuardName =
    "__sanitizer_cov_trace_pc_guard";
const std::string kInvalidFileName("<invalid>");
Regex kAllTimeCounterRegex("^AllTimeCounter: (0x[0-9a-f]+) ([0-9]+) ([0-9]+)$");

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
      for (auto &CoveredLocation: CoveredLocations[&F]) {
        auto &DIII = std::get<0>(CoveredLocation);
        dbgs() << "Covered: ";
        for (uint32_t i = 0, e = DIII.getNumberOfFrames(); i < e; ++i) {
          auto IIFrame = DIII.getFrame(i);
          dbgs() << IIFrame.FileName << ":" << IIFrame.Line << ":" << IIFrame.Column << ":" << IIFrame.Discriminator << " ";
        }
        dbgs() << "index: " << std::get<1>(CoveredLocation) << " ";
        dbgs() << "cost: " << std::get<2>(CoveredLocation) << "\n";
      }
  });

  if (!computeTracePCGuardIndexOffset(F)) {
    dbgs() << "Warning: Could not compute trace_pc_guard index offset for function: " << F.getName() << "\n";
    return false;
  }

  for (Instruction *Inst : SCI.getSanityCheckRoots()) {
    assert(Inst->getParent()->getParent() == &F &&
           "SCI must only contain instructions of the current function.");

    // Compute the cost for all `trace_pc_guard` calls from the corresponding
    // CoveredLocation.
    uint64_t Cost = 0;
    if (isTracePCGuardCall(Inst)) {
      CallInst *CI = cast<CallInst>(Inst);
      size_t Index = getTracePCGuardIndex(*CI);
      auto CoveredLocation = std::find_if(CoveredLocations[&F].begin(), CoveredLocations[&F].end(), [this, Index](std::tuple<llvm::DIInliningInfo, size_t, uint64_t> &CL) {
          return std::get<1>(CL) == Index + TracePCGuardIndexOffset;
      });
      if (CoveredLocation != CoveredLocations[&F].end()) {
        Cost = std::get<2>(*CoveredLocation);
      }
    }

    APInt CountInt = APInt(64, Cost);
    MDNode *MD = MDNode::get(
        F.getContext(), {ConstantAsMetadata::get(ConstantInt::get(
                            Type::getInt64Ty(F.getContext()), CountInt))});
    Inst->setMetadata("cost", MD);
    CheckCosts.push_back(std::make_pair(Inst, Cost));
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

  symbolize::LLVMSymbolizer::Options SymbolizerOptions(
      symbolize::FunctionNameKind::LinkageName,
      /* UseSymbolTable */ true,
      /* Demangle */ false,
      /* RelativeAddresses */ false,
      /* DefaultArch */ "");
  symbolize::LLVMSymbolizer Symbolizer(SymbolizerOptions);
  std::unique_ptr<MemoryBuffer> Buffer = std::move(BufOrErr.get());
  line_iterator LineIt(*Buffer, /*SkipBlanks=*/true, '#');
  for (; !LineIt.is_at_eof(); ++LineIt) {
    SmallVector<StringRef, 4> Matches;
    uint64_t Offset = 0;
    size_t Index = 0;
    uint64_t Cost = 0;
    if (kAllTimeCounterRegex.match(*LineIt, &Matches)) {
      if (Matches[1].getAsInteger(0, Offset)) {
        M.getContext().diagnose(DiagnosticInfoSampleProfile(
            PCFile, LineIt.line_number(), "Could not parse PC: " + *LineIt));
        return false;
      }
      if (Matches[2].getAsInteger(0, Index)) {
        M.getContext().diagnose(DiagnosticInfoSampleProfile(
            PCFile, LineIt.line_number(), "Could not parse Index: " + *LineIt));
        return false;
      }
      if (Matches[3].getAsInteger(0, Cost)) {
        M.getContext().diagnose(DiagnosticInfoSampleProfile(
            PCFile, LineIt.line_number(), "Could not parse Cost: " + *LineIt));
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
        Function *F = M.getFunction(Res.getFrame(Res.getNumberOfFrames() - 1).FunctionName);
        if (F) {
          CoveredLocations[F].push_back(std::make_tuple(Res, Index, Cost));
        }
      }
    }
  }

  // Compute the minimum and maximum offset for each function.
  // We go through indices in order. Whenever the function changes, we adjust
  // the bounds of the last and current function.
  std::map<size_t, Function *> FunctionsByOffset;
  for (auto FCL: CoveredLocations) {
    for (auto &CL: FCL.second) {
      FunctionsByOffset[std::get<1>(CL)] = FCL.first;
    }
  }
  Function *LastFunction = nullptr;
  size_t LastOffset = (size_t)(-1);
  for (auto FO: FunctionsByOffset) {
    if (LastFunction != FO.second) {
      if (OffsetRanges.count(FO.second) == 0) {
        OffsetRanges[FO.second].first = LastOffset + 1;
      } else {
        dbgs() << "Warning: non-contiguous function: " << FO.second->getName() << "\n";
      }
      if (LastFunction) {
        OffsetRanges[LastFunction].second = FO.first;
      }
      LastFunction = FO.second;
    }
    LastOffset = FO.first;
  }
  if (LastFunction) {
    OffsetRanges[LastFunction].second = (size_t)(-1);
  }

  return true;
}

bool SanityCheckCoverageCost::computeTracePCGuardIndexOffset(Function &F) {
  // computeTracePCGuardIndexOffset tries to compute the range of
  // CoveredLocations that corresponds to `trace_pc_guard` calls in F. This is
  // tricky, because we can often not uniquely identify which call corresponds
  // to which CoveredLocation.
  //
  // Our plan is to loop through all pairs of `trace_pc_guard` calls and
  // CoveredLocations, and record matching offsets. Then, we return the offset
  // value that was found most often.
  //
  // Note that all of this is rather brittle. In particular, it also expects
  // the set of `trace_pc_guard` calls to be identical to the set that was used
  // to measure coverage. This requires exactly the same compilation steps, and
  // makes it impossible to do things like profile-guided optimization, because
  // PGO affects inlining.
  //
  // There is no real safeguard against mismatches :( Coverage can in principle
  // be arbitrarily low, and so it's hard to define when a match is of
  // sufficient quality.

  TracePCGuardIndexOffset = (size_t)(-1);
  if (!CoveredLocations.count(&F)) {
    dbgs() << "computeTracePCGuardIndexOffset: F:" << F.getName()
           << " Offset: none (no covered locations)\n";
    return false;
  }

  std::map<size_t, size_t> Offsets;
  size_t NumTracePCGuardCalls = 0;
  for (Instruction &I : instructions(&F)) {
    if (!isTracePCGuardCall(&I)) continue;
    CallInst *CI = cast<CallInst>(&I);
    DebugLoc Loc = CI->getDebugLoc();
    if (!Loc) continue;
    DILocation *DIL = Loc.get();
    if (!DIL) continue;
    size_t Index = getTracePCGuardIndex(*CI);
    NumTracePCGuardCalls += 1;

    for (auto CL: CoveredLocations[&F]) {
      DIInliningInfo &DIII = std::get<0>(CL);
      size_t CLIndex = std::get<1>(CL);
      if (/**/ CLIndex > Index
            && CLIndex - Index >= OffsetRanges[&F].first
            && CLIndex - Index < OffsetRanges[&F].second) {
        if (locationsMatch(*DIL, DIII)) {
          DEBUG(dbgs() << "  match: " << F.getName() << " " << Index << " " << CLIndex << "\n");
          Offsets[CLIndex - Index] += 1;
        }
      }
    }
  }

  size_t MostFrequentOffset = 0;
  size_t MaxOffsetCount = 0;
  for (auto O: Offsets) {
    if (O.second > MaxOffsetCount) {
      MaxOffsetCount = O.second;
      MostFrequentOffset = O.first;
    }
  }
  if (MaxOffsetCount) {
    TracePCGuardIndexOffset = MostFrequentOffset;
    dbgs() << "computeTracePCGuardIndexOffset: F:" << F.getName()
           << " Offset:" << MostFrequentOffset
           << " Matches: " << MaxOffsetCount
           << " TPCG calls: " << NumTracePCGuardCalls
           << " Covered locations: " << CoveredLocations[&F].size()
           << " Range: " << OffsetRanges[&F].first << " - " << OffsetRanges[&F].second
           << "\n";
    return true;
  } else {
    dbgs() << "computeTracePCGuardIndexOffset: F:" << F.getName()
           << " Offset: none"
           << " Matches: " << MaxOffsetCount
           << " TPCG calls: " << NumTracePCGuardCalls
           << " Covered locations: " << CoveredLocations[&F].size()
           << " Range: " << OffsetRanges[&F].first << " - " << OffsetRanges[&F].second
           << "\n";
    return false;
  }
}

bool SanityCheckCoverageCost::isTracePCGuardCall(Instruction *I) {
  if (!I) return false;
  if (CallInst *CI = dyn_cast<CallInst>(I)) {
    if (CI->getCalledFunction() && CI->getCalledFunction()->getName() == kTracePcGuardName) {
      return true;
    }
  }
  return false;
}

size_t SanityCheckCoverageCost::getTracePCGuardIndex(CallInst &I) {
  assert(isTracePCGuardCall(&I));

  ConstantExpr *GuardPtr = cast<ConstantExpr>(I.getArgOperand(0));
  if (GuardPtr->getOpcode() == Instruction::IntToPtr) {
    ConstantExpr *GuardAddress = cast<ConstantExpr>(GuardPtr->getOperand(0));
    assert(GuardAddress->getOpcode() == Instruction::Add);
    ConstantInt *Index = cast<ConstantInt>(GuardAddress->getOperand(1));
    // Divide Index by sizeof(int32_t)
    return (size_t)Index->getZExtValue() / 4;
  } else if (GuardPtr->getOpcode() == Instruction::GetElementPtr) {
    return 0;
  } else {
    assert(false && "Can't make sense of trace_pc_guard argument.");
    return 0;
  }
}

bool SanityCheckCoverageCost::locationsMatch(const DILocation &DIL, const DIInliningInfo &DIII) {
  const DILocation *LocFrame = &DIL;
  for (uint32_t i = 0, e = DIII.getNumberOfFrames(); i < e; ++i) {
    if (!LocFrame) {
      // No match if DIII has more frames than DIL.
      return false;
    }
    const DILineInfo &IIFrame = DIII.getFrame(i);

    // Compare the DILocation frame to the DIInliningInfo frame.
    // - We do not compare filenames; some build systems move source files
    //   around, and we'd like to support that.
    // - Instead, function names have to match. We check both LinkageName and
    //   Name and hope that they aren't demangled and that we are lucky :-/
    // - We only take column numbers and discriminators into account if they
    //   are non-zero.
    if (/**/(IIFrame.FunctionName != LocFrame->getScope()->getSubprogram()->getLinkageName()
           && IIFrame.FunctionName != LocFrame->getScope()->getSubprogram()->getName())
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
