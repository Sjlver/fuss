// Various utility functions

// This file is part of ASAP.
// Please see LICENSE.txt for copyright and licensing information.

#include "utils.h"
#include "SanityCheckInstructionsPass.h"

#include "llvm/IR/DebugInfo.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/InlineAsm.h"
#include "llvm/IR/Instructions.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/raw_ostream.h"
using namespace llvm;

static cl::opt<bool>
OptimizeSanityChecks("asap-optimize-sanitychecks",
        cl::desc("Should ASAP affect sanity checks (e.g., from ASan)?"),
        cl::init(true));

static cl::opt<bool>
OptimizeAssertions("asap-optimize-assertions",
        cl::desc("Should ASAP affect programmer-written assertions?"),
        cl::init(true));

static cl::opt<bool>
OptimizeThreadSanitizer("asap-optimize-tsan",
        cl::desc("Should ASAP affect TSan runtime library functions?"),
        cl::init(true));

bool isInstrumentation(const Instruction *I) {
    if (auto *CI = dyn_cast<const CallInst>(I)) {
        if (CI->getCalledFunction()) {
            StringRef name = CI->getCalledFunction()->getName();
            if (name.startswith("__ubsan_") && name.endswith("_abort")) {
                return OptimizeSanityChecks;
            }
            if (name.startswith("__softboundcets_") && name.endswith("_abort")) {
                return OptimizeSanityChecks;
            }
            if (name.startswith("__asan_report_")) {
                return OptimizeSanityChecks;
            }
            if (name == "__assert_fail" || name == "__assert_rtn") {
                return OptimizeAssertions;
            }
            if (name.startswith("__tsan_read") || name.startswith("__tsan_unaligned_read") ||
                name.startswith("__tsan_write") || name.startswith("__tsan_unaligned_write")) {
                return OptimizeThreadSanitizer;
            }
        }
    }
    return false;
}

bool isAsmForSideEffect(const Instruction *I) {
    if (const CallInst *CI = dyn_cast<CallInst>(I)) {
        if (const InlineAsm *IA = dyn_cast<InlineAsm>(CI->getCalledValue())) {
            return (IA->getAsmString().empty() && IA->getConstraintString().empty());
        }
    }

    return false;
}

bool isAbortingCall(const CallInst *CI) {
    if (CI->getCalledFunction()) {
        StringRef name = CI->getCalledFunction()->getName();
        if (name.startswith("__ubsan_") && name.endswith("_abort")) {
            return true;
        }
        if (name.startswith("__softboundcets_") && name.endswith("_abort")) {
            return true;
        }
        if (name.startswith("__asan_report_")) {
            return true;
        }
        if (name == "__assert_fail" || name == "__assert_rtn") {
            return true;
        }
    }
    return false;
}

DebugLoc getBasicBlockDebugLoc(BasicBlock *BB) {
    for (Instruction &Inst : *BB) {
        DebugLoc DL = Inst.getDebugLoc();
        if (DL) return DL;
    }
    return DebugLoc();
}

DebugLoc getInstrumentationDebugLoc(Instruction *Inst) {
    DebugLoc DL = Inst->getDebugLoc();
    if (DL) return DL;

    // If the instruction itself does not have a debug location,
    // we first scan other instructions in the same basic block.
    BasicBlock *BB = Inst->getParent();
    DL = getBasicBlockDebugLoc(BB);
    if (DL) return DL;

    // If that doesn't help, we look at the branch that leads to this
    // instruction, and scan the alternate basic block, if any.
    for (auto U : BB->users()) {
        if (auto *BI = dyn_cast<BranchInst>(U)) {
            for (unsigned i = 0; i < BI->getNumSuccessors(); ++i) {
                BasicBlock *AltBB = BI->getSuccessor(i);
                if (AltBB == BB) continue;

                DL = getBasicBlockDebugLoc(AltBB);
                if (DL) return DL;
            }
        }
    }

    // Nothing helps...
    return DebugLoc();
}

void printDebugLoc(const DebugLoc& DbgLoc,
        LLVMContext &Ctx, raw_ostream &Outs) {
    if (!DbgLoc) {
        Outs << "<debug info not available>";
        return;
    }

    DILocation *DL = dyn_cast_or_null<DILocation>(DbgLoc.getAsMDNode());
    if (!DL) {
        Outs << "<debug info not available>";
        return;
    }

    StringRef Filename = DL->getFilename();
    Outs << Filename << ':' << DL->getLine();

    if (DL->getColumn() != 0) {
        Outs << ':' << DL->getColumn();
    }
}
