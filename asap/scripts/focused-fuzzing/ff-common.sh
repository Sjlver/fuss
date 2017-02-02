#!/bin/bash

set -e
set -o pipefail

SCRIPT_DIR="$( dirname "$( readlink -f "${BASH_SOURCE[0]}" )" )"

if ! clang --version | grep -q asap; then
  echo "Could not find ASAP's clang. Please set \$PATH correctly." >&2
  exit 1
fi
if ! which create_llvm_prof >/dev/null 2>&1; then
  echo "Could not find create_llvm_prof. Please set \$PATH correctly." >&2
  exit 1
fi

# Compiler flags and settings for the various build configurations

CC="$(which clang)"
CXX="$(which clang++)"
LIBFUZZER_CFLAGS="-O3 -g -Wall -std=c++11"
DEFAULT_CFLAGS="-O3 -g -Wall -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION"
DEFAULT_LDFLAGS=""

# We will use the following naming scheme for versions:
# name = base-modifier, where
#
# base: determines type of instrumentation that is being used
#       - asan: with AddressSanitizer + trace_pc_guard
#       - tpcg: with trace_pc_guard only
#       - noinstr: without instrumentation at all
# modifier: determines whether we use FUSS or otherwise change the base.
#       - nofuss: linked against an unmodified libFuzzer.a
#       - prof:   a copy for profiling
#       - fperf:  with fuss, and costs from perf
#       - fprec:  with fuss, and costs from tpcg counters

TPCG_CFLAGS="-fsanitize-coverage=trace-pc-guard"
TPCG_LDFLAGS="-fsanitize-coverage=trace-pc-guard"

ASAN_CFLAGS="-fsanitize=address $TPCG_CFLAGS"
ASAN_LDFLAGS="-fsanitize=address $TPCG_LDFLAGS"

# Parameters for the fuzzers and the build

WORK_DIR="$(pwd)"
N_CORES=${N_CORES:-$(getconf _NPROCESSORS_ONLN)}

if [ "$N_CORES" -ge 3 ]; then
  N_FUZZER_JOBS="$((N_CORES - 2))"
else
  N_FUZZER_JOBS=1
fi

# Set ASAN_OPTIONS to defaults that favor speed over nice output
export ASAN_OPTIONS="malloc_context_size=0"

# The number of seconds for which we run fuzzers during testing and profiling
FUZZER_WARMUP_SECONDS=${FUZZER_WARMUP_SECONDS:-60}
FUZZER_TESTING_SECONDS=${FUZZER_TESTING_SECONDS:-60}
FUZZER_PROFILING_SECONDS=${FUZZER_PROFILING_SECONDS:-60}

# Parameters for FUSS mode
FUSS_TOTAL_SECONDS=${FUSS_TOTAL_SECONDS:-3600}

# The cost level used by FUSS in precise mode
FPREC_COSTLEVEL=0.005

# Which variants should we build and test?
VARIANTS="${VARIANTS}"

# Scripts can override this to use extra fuzzing args and corpora
FUZZER_EXTRA_CORPORA=${FUZZER_EXTRA_CORPORA:-}
FUZZER_EXTRA_ARGS=${FUZZER_EXTRA_ARGS:-}

# The variant of libFuzzer to use. Override e.g., when compiling a baseline
# version that must not use FUSS-specific code.
LIBFUZZER_A="$WORK_DIR/Fuzzer-fuss-build/libFuzzer.a"

# Build LLVM's libFuzzer
init_libfuzzer() {
  mkdir -p logs
  mkdir -p perf-data

  local fuzzer_src="$(llvm-config --src-root)/lib/Fuzzer"
  if ! [ -d "$fuzzer_src" ]; then
    echo "Could not find LibFuzzer sources (searching in \"$fuzzer_src\")" >&2
    exit 1
  fi

  if ! [ -f Fuzzer-build/libFuzzer.a ]; then
    mkdir Fuzzer-build
    cd Fuzzer-build
    for i in "$fuzzer_src"/*.cpp; do
      "$CXX" $LIBFUZZER_CFLAGS -c "$i" -I"$fuzzer_src" &
    done
    wait
    ar ruv libFuzzer.a *.o
    cd ..
  fi
  if ! [ -f Fuzzer-fuss-build/libFuzzer.a ]; then
    mkdir Fuzzer-fuss-build
    cd Fuzzer-fuss-build
    for i in "$fuzzer_src"/*.cpp; do
      "$CXX" $LIBFUZZER_CFLAGS -DFUSS -c "$i" -I"$fuzzer_src" &
    done
    wait
    ar ruv libFuzzer.a *.o
    cd ..
  fi
}

# Obtains an ID for the current testrun. This is a sequentially increasing,
# unique number.
get_run_id() {
  (
    flock --timeout 1 9 || exit 1
    local previous_run_id="$(cat "$WORK_DIR/run_id" 2>/dev/null || echo "0")"

    # Print run-id with leading zero for use in this script, but save it to the
    # file without leading zero. Otherwise it's interpreted as octal number the
    # next time. :-/
    echo "$((previous_run_id + 1))" > "$WORK_DIR/run_id"
    printf "%02d" "$((previous_run_id + 1))"
  ) 9>"$WORK_DIR/.run_id.lock"
}
run_id="$(get_run_id)"

# Test the fuzzer with the given `name`.
test_fuzzer() {
  local name="$1"

  if ! [ -f "logs/fuzzer-${name}-${run_id}.log" ]; then
    echo "test_fuzzer: ${name} run_id: ${run_id} timestamp: $(date +%s)" \
      | tee "logs/fuzzer-${name}-${run_id}.log"

    (
      cd "target-${name}-build"
      mkdir -p "CORPUS-${run_id}"

      # We've seen instances of runaway fuzzers; Limit its CPU time to be sure.
      ulimit -t $((N_FUZZER_JOBS * FUZZER_TESTING_SECONDS + 10))
      "./fuzzer" -max_total_time=$FUZZER_TESTING_SECONDS \
        -print_pcs=1 -print_final_stats=1 -jobs=$N_FUZZER_JOBS -workers=$N_FUZZER_JOBS \
        -artifact_prefix="CORPUS-${run_id}/" \
        $FUZZER_EXTRA_ARGS "CORPUS-${run_id}" $FUZZER_EXTRA_CORPORA 2>&1 \
        | tee -a "../logs/fuzzer-${name}-${run_id}.log"

      cd ..
    )
  fi
}

# Run the fuzzer with the given `name` until it finds a crash, or up to the
# limit given by FUZZER_TESTING_SECONDS.
#
# This is similar to test_fuzzer, except that it tries to work around transient
# crashes (out of memory, for example) by using a higher number of jobs.
#
# Note that this will lead to logs that might be confusing to parse :(
search_crash() {
  local name="$1"

  if ! [ -f "logs/fuzzer-${name}-${run_id}.log" ]; then
    echo "test_fuzzer: ${name} run_id: ${run_id} timestamp: $(date +%s)" \
      | tee "logs/fuzzer-${name}-${run_id}.log"
    (
      cd "target-${name}-build"
      mkdir -p "CORPUS-${run_id}"

      ulimit -t $((N_FUZZER_JOBS * FUZZER_TESTING_SECONDS + 10))
      timeout --kill-after=10 "$FUZZER_TESTING_SECONDS" \
        "./fuzzer" -max_total_time=$FUZZER_TESTING_SECONDS \
        -print_pcs=1 -print_final_stats=1 -jobs=$((10 * N_FUZZER_JOBS)) -workers=$N_FUZZER_JOBS \
        -artifact_prefix="CORPUS-${run_id}/" \
        $FUZZER_EXTRA_ARGS "CORPUS-${run_id}" $FUZZER_EXTRA_CORPORA 2>&1 \
        | tee -a "../logs/fuzzer-${name}-${run_id}.log"

      cd ..
    )
  fi
}

# Run the fuzzer named `name` under perf, and create an llvm_prof file. The
# fuzzer should have been tested before; we continue to use the same corpus.
profile_fuzzer() {
  local name="$1"
  local perf_args="$2"

  if ! [ -f "perf-data/perf-${name}.data" ]; then
    (
      # Only one perf process can run at the same time, because performance
      # counters are a limited resource. Hence, use a global lock.
      flock 9 || exit 1
      echo "profile_fuzzer: ${name} timestamp: $(date +%s)" \
        | tee "logs/perf-${name}.log"
      cd "target-${name}-build"

      # We've seen instances of runaway fuzzers; Limit its CPU time to be sure.
      (
        ulimit -t $((N_FUZZER_JOBS * FUZZER_PROFILING_SECONDS + 10))
        perf record $perf_args -o "../perf-data/perf-${name}.data" \
          "./fuzzer" -max_total_time=$FUZZER_PROFILING_SECONDS \
          -print_pcs=1 -print_final_stats=1 -jobs=$N_FUZZER_JOBS -workers=$N_FUZZER_JOBS \
          -artifact_prefix="CORPUS-${run_id}/" \
          $FUZZER_EXTRA_ARGS "CORPUS-${run_id}" $FUZZER_EXTRA_CORPORA 2>&1 \
          | tee -a "../logs/perf-${name}.log"
      )
      cd ..
    ) 9>"/tmp/asap_global_perf_lock"
  fi

  # Convert perf data to LLVM profiling input.
  if ! [ -f "perf-data/perf-${name}.llvm_prof" ] && echo " $perf_args " | grep -q -- ' -b '; then
    create_llvm_prof --binary="target-${name}-build/fuzzer" \
      --profile="perf-data/perf-${name}.data" \
      --out="perf-data/perf-${name}.llvm_prof"
  fi
}

# See what coverage the fuzzer with the given `name` achieved
compute_coverage() {
  local name="$1"

  # The coverage is computed against the version without any variant. Except
  # for noinstr, where we compute it against tpcg.
  local reference="${name%%-*}"
  if [ "$reference" = "noinstr" ]; then
    reference="tpcg"
  fi

  if ! [ -f "logs/coverage-${name}-${run_id}.log" ]; then
    "./target-${reference}-build/fuzzer" -runs=0 "target-${name}-build/CORPUS-${run_id}" 2>&1 \
      | tee "logs/coverage-${name}-${run_id}.log"
  fi
}

# Estimate a good threshold to use for fuss in precise mode
estimate_fprec_threshold() {
  local prof="$1"

  "$SCRIPT_DIR/alltimecounter_statistics.py" --log "logs/perf-${prof}.log" --costlevel $FPREC_COSTLEVEL
}

# Estimate a good threshold for fuss when using perf
estimate_fperf_threshold() {
  echo $((FUZZER_PROFILING_SECONDS * N_FUZZER_JOBS))
}

# Generate initial, pgo, and thresholded versions
build_all() {
  # Initial builds
  if echo "$VARIANTS" | grep -q "asan"; then
    build_target_and_fuzzer "asan" "$ASAN_CFLAGS" "$ASAN_CFLAGS"
  fi
  if echo "$VARIANTS" | grep -q "tpcg"; then
    build_target_and_fuzzer "tpcg" "$TPCG_CFLAGS" "$TPCG_LDFLAGS"
  fi
  if echo "$VARIANTS" | grep -q "noinstr"; then
    build_target_and_fuzzer "noinstr" "" "$TPCG_LDFLAGS"
  fi

  # Run the fuzzer under perf. Use branch tracing because that's what
  # create_llvm_prof wants.
  for variant in "asan" "tpcg"; do
    if echo "$VARIANTS" | grep -q "$variant"; then
      if ! [ -f "perf-data/perf-${variant}-prof-${run_id}.llvm_prof" ]; then
        rsync -a --delete "target-${variant}-build/" "target-${variant}-prof-${run_id}-build"
        FUZZER_TESTING_SECONDS=$FUZZER_WARMUP_SECONDS test_fuzzer "${variant}-prof-${run_id}"
        profile_fuzzer "${variant}-prof-${run_id}" "-b"

        # Minimize the corpus of this build, and compute it's coverage. We're
        # re-using its corpus later as initial corpus, and so knowing the
        # coverage is useful.
        mv "target-${variant}-prof-${run_id}-build/CORPUS-$run_id" "target-${variant}-prof-${run_id}-build/CORPUS-${run_id}-OLD"
        mkdir "target-${variant}-prof-${run_id}-build/CORPUS-$run_id"
        "./target-${variant}-prof-${run_id}-build/fuzzer" -merge=1 "target-${variant}-prof-${run_id}-build/CORPUS-$run_id" "target-${variant}-prof-${run_id}-build/CORPUS-${run_id}-OLD"
        rm -r "target-${variant}-prof-${run_id}-build/CORPUS-${run_id}-OLD"
        compute_coverage "${variant}-prof-${run_id}"
      fi
    fi
  done

  # Create extra variants.
  for variant in $VARIANTS; do
    local cflags=
    local ldflags=
    local libfuzzer="$LIBFUZZER_A"
    local base=

    case "$variant" in
      asan-*) cflags="$cflags $ASAN_CFLAGS"
              ldflags="$ldflags $ASAN_LDFLAGS"
              base="asan";;
      tpcg-*) cflags="$cflags $TPCG_CFLAGS"
              ldflags="$ldflags $TPCG_LDFLAGS"
              base="tpcg";;
    esac
    case "$variant" in
      *-nofuss*) libfuzzer="$WORK_DIR/Fuzzer-build/libFuzzer.a";;
      *-fperf*) threshold="$(estimate_fperf_threshold)"
                cflags="$cflags -fprofile-sample-use=$WORK_DIR/perf-data/perf-${base}-prof-${run_id}.llvm_prof -fsanitize=asap"
                cflags="$cflags -mllvm -asap-cost-threshold=$threshold -mllvm -asap-verbose";;
      *-fprec*) threshold="$(estimate_fprec_threshold "${base}-prof-${run_id}")"
                cflags="$cflags -fsanitize=asapcoverage"
                cflags="$cflags -mllvm -asap-module-name=$WORK_DIR/target-${base}-prof-${run_id}-build/fuzzer"
                cflags="$cflags -mllvm -asap-coverage-file=$WORK_DIR/logs/perf-${base}-prof-${run_id}.log"
                cflags="$cflags -mllvm -asap-cost-threshold=$threshold -mllvm -asap-verbose";;
    esac

    case "$variant" in
      *-nofuss*|*-fperf*|*-fprec*)
        LIBFUZZER_A="$libfuzzer" build_target_and_fuzzer "${variant}-${run_id}" "$cflags" "$ldflags";;
      asan|tpcg|noinstr)
        [ -d "target-${variant}-${run_id}-build" ] || rsync -a --delete "target-${variant}-build/" "target-${variant}-${run_id}-build";;
    esac
  done
}

# Test all versions that have been built by build_all
test_all() {
  for variant in $VARIANTS; do

    # When testing, start with the corpus from the profiling build.
    # This ensures each version can start with the same non-zero initial corpus.
    local prof="${variant%%-*}"
    if [ "$prof" = "noinstr" ]; then
      prof="tpcg"
    fi
    rsync -a --delete "target-${prof}-prof-${run_id}-build/CORPUS-$run_id/" "target-${variant}-${run_id}-build/CORPUS-$run_id"

    local extra_args=
    case "$variant" in
      noinstr) extra_args="-benchmark=1";;
    esac

    FUZZER_EXTRA_ARGS="$extra_args" test_fuzzer "${variant}-${run_id}"
    compute_coverage "${variant}-${run_id}"
  done
}

# Print out a summary that we can export to spreadsheet
print_summary() {
  local summary_versions="$@"
  if [ -z "$summary_versions"]; then
    summary_versions="$(for variant in $VARIANTS; do echo "${variant}-${run_id}"; done)"
  fi

  echo
  echo "Summary"
  echo "======="
  echo
  (
    printf "%30s\t%8s\t%8s\t%8s\t%8s\t%8s\t%8s\t%8s\t%8s\t%8s\t%12s\n" "name" "cov" "ft" "execs" "execs_per_sec" "units" "init_cov" "init_ft" "actual_cov" "actual_ft" "tpcg"

    for name in $summary_versions; do
      # Get cov, ft from the last output line
      cov="$(grep '#[0-9]*.*DONE' logs/fuzzer-${name}-${run_id}.log | (grep -o 'cov: [0-9]*' || echo "cov: 0") | grep -o '[0-9]*' | sort -n | tail -n1)"
      ft="$(grep '#[0-9]*.*DONE' logs/fuzzer-${name}-${run_id}.log | (grep -o 'ft: [0-9]*' || echo "ft: 0") | grep -o '[0-9]*' | sort -n | tail -n1)"

      # Get information from the final stats
      execs="$(grep 'stat::number_of_executed_units:' logs/fuzzer-${name}-${run_id}.log | grep -o '[0-9]*' | sort -n | tail -n1)"
      execs_per_sec="$(grep 'stat::average_exec_per_sec:' logs/fuzzer-${name}-${run_id}.log | grep -o '[0-9]*' | sort -n | tail -n1)"
      units="$(grep 'stat::new_units_added:' logs/fuzzer-${name}-${run_id}.log | grep -o '[0-9]*' | sort -n | tail -n1)"
      tpcg="$(grep 'stat::total_tpcg_count:' logs/fuzzer-${name}-${run_id}.log | grep -o '[0-9]*' | sort -n | tail -n1)"

      # Get the initial coverage; that's the coverage from the profiling build
      local prof="${name%%-*}"
      if [ "$prof" = "noinstr" ]; then
        prof="tpcg"
      fi
      init_cov="$(grep '#[0-9]*.*DONE' logs/coverage-${prof}-prof-${run_id}-${run_id}.log | grep -o 'cov: [0-9]*' | grep -o '[0-9]*')"
      init_ft="$(grep '#[0-9]*.*DONE' logs/coverage-${prof}-prof-${run_id}-${run_id}.log | grep -o 'ft: [0-9]*' | grep -o '[0-9]*')"

      # Get actual coverage from running the corpus against the base version
      actual_cov="$(grep '#[0-9]*.*DONE' logs/coverage-${name}-${run_id}.log | grep -o 'cov: [0-9]*' | grep -o '[0-9]*')"
      actual_ft="$(grep '#[0-9]*.*DONE' logs/coverage-${name}-${run_id}.log | grep -o 'ft: [0-9]*' | grep -o '[0-9]*')"

      printf "%30s\t%8s\t%8s\t%8s\t%8s\t%8s\t%8s\t%8s\t%8s\t%8s\t%12s\n" "$name" "$cov" "$ft" "$execs" "$execs_per_sec" "$units" "$init_cov" "$init_ft" "$actual_cov" "$actual_ft" "$tpcg"
    done
  ) | tee "logs/summary-${run_id}.log"
}

# usage: print usage information
usage() {
  echo "ff.sh: Focused Fuzzing wrapper script"
  echo "usage: ff.sh command [command args]"
  echo "commands:"
  echo "  clean    - remove generated files"
  echo "  help     - show this help message"
  echo "  speed    - build variants, and measure their speed and coverage"
  echo "  fuss     - initial build, warmup, profiling, recompilation, long fuzzing"
  echo "  baseline - like fuss, except without fussing :)"
}

# clean: Remove generated files
do_clean() {
  rm -rf *-build logs perf-data run_id .run_id.lock
}

# build: build initial, pgo, and thresholded versions
do_speed() {
  init_target
  init_libfuzzer
  build_all
  test_all
  print_summary
}

# fuss: A complete iteration of fuss. This consists of initial testing,
# profiling, and then some fuzzing.
do_fuss() {
  init_target
  init_libfuzzer

  # For this type of experiment, always use the non-fuss build of LibFuzzer
  LIBFUZZER_A="$WORK_DIR/Fuzzer-build/libFuzzer.a"

  (
    local start_time="$(date +%s)"
    local end_time="$((start_time + FUSS_TOTAL_SECONDS))"

    # Build initial fuzzer.
    echo "fuss: building asan version. timestamp: $start_time"
    build_target_and_fuzzer "asan" "$ASAN_CFLAGS" "$ASAN_CFLAGS"

    # Warmup
    echo "fuss: warming up asan-prof-${run_id} version. timestamp: $(date +%s)"
    rsync -a --delete "target-asan-build/" "target-asan-prof-${run_id}-build"
    FUZZER_TESTING_SECONDS=$FUZZER_WARMUP_SECONDS test_fuzzer "asan-prof-${run_id}" || true
    if grep -q -P "$CRASH_REGEXP" "logs/fuzzer-asan-prof-${run_id}-${run_id}.log"; then
      echo "fuss: fuss end (found crash during initial testing). timestamp: $(date +%s)"
      exit 0
    fi
      
    echo "fuss: profiling asan-prof-${run_id} version. timestamp: $(date +%s)"
    profile_fuzzer "asan-prof-${run_id}" "-b" || true
    if grep -q -P "$CRASH_REGEXP" "logs/perf-asan-prof-${run_id}.log"; then
      echo "fuss: fuss end (found crash during profiling). timestamp: $(date +%s)"
      exit 0
    fi

    # Rebuild a high-quality fuzzer.
    echo "fuss: building asan-fperf version. timestamp: $(date +%s)"
    VARIANTS=asan-fperf build_all

    # Copy over the existing corpus (after all, we've earned that one)
    rsync -a --delete "target-asan-prof-${run_id}-build/CORPUS-$run_id/" "target-asan-fperf-${run_id}-build/CORPUS-$run_id"
    
    # And let the fuzzer run for some more time. We ignore crashes in the
    # fuzzer, and simply stop it when this occurs.
    local remaining="$((end_time - $(date +%s)))"
    echo "fuss: testing asan-fperf version. timestamp: $(date +%s) remaining: $remaining"
    FUZZER_TESTING_SECONDS="$remaining" search_crash "asan-fperf-${run_id}" || true
    echo "fuss: fuss end. timestamp: $(date +%s)"
  ) | tee "logs/do_fuss-${run_id}.log"

  # Compute coverage. Carefully choose the right corpus; if a crash is found
  # during initialization or profiling, then the asan-fperf corpus
  # does not exist yet.
  local corpus_for_coverage="target-asan-fperf-${run_id}-build/CORPUS-${run_id}"
  if ! [ -d "$corpus_for_coverage" ]; then
    corpus_for_coverage="target-asan-prof-${run_id}-build/CORPUS-${run_id}"
  fi
  "$SCRIPT_DIR/parse_libfuzzer_coverage_vs_time.py" \
    --fuzzer "target-asan-build/fuzzer" \
    --corpus "$corpus_for_coverage" \
    < "logs/do_fuss-${run_id}.log" > "logs/do_fuss-${run_id}-coverage.tsv"
}

# baseline: A complete iteration of fuss, except that it doesn't use fuss. This
# is the baseline we compare against.
do_baseline() {
  init_target
  init_libfuzzer

  # For this type of experiment, always use the non-fuss build of LibFuzzer
  LIBFUZZER_A="$WORK_DIR/Fuzzer-build/libFuzzer.a"

  (
    local start_time="$(date +%s)"
    local end_time="$((start_time + FUSS_TOTAL_SECONDS))"

    echo "fuss: building baseline-${run_id} version. timestamp: $start_time"
    build_target_and_fuzzer "asan" "$ASAN_CFLAGS" "$ASAN_LDFLAGS"
    rsync -a --delete "target-asan-build/" "target-baseline-${run_id}-build"
    
    # And let the fuzzer run for some time. We ignore crashes in the fuzzer,
    # and simply stop it when this occurs.
    local remaining="$((end_time - $(date +%s)))"
    echo "fuss: testing baseline-${run_id} version. timestamp: $(date +%s) remaining: $remaining"
    FUZZER_TESTING_SECONDS="$remaining" search_crash "baseline-${run_id}" || true
    echo "fuss: baseline end. timestamp: $(date +%s)"
  ) | tee "logs/do_baseline-${run_id}.log"

  # Compute coverage
  "$SCRIPT_DIR/parse_libfuzzer_coverage_vs_time.py" \
    --fuzzer "target-asan-build/fuzzer" \
    --corpus "target-baseline-${run_id}-build/CORPUS-${run_id}" \
    < "logs/do_baseline-${run_id}.log" > "logs/do_baseline-${run_id}-coverage.tsv"
}
