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
DEFAULT_CFLAGS="-O3 -g -Wall -fsanitize=address -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION"
DEFAULT_LDFLAGS="-fsanitize=address"

COVERAGE_COUNTERS_CFLAGS="-fsanitize-coverage=edge,indirect-calls,8bit-counters -mllvm -sanitizer-coverage-prune-blocks=false"
COVERAGE_COUNTERS_LDFLAGS="-fsanitize-coverage=edge,indirect-calls,8bit-counters"

COVERAGE_ICALLS_CFLAGS="-fsanitize-coverage=edge,indirect-calls -mllvm -sanitizer-coverage-prune-blocks=false"
COVERAGE_ICALLS_LDFLAGS="-fsanitize-coverage=edge,indirect-calls"

COVERAGE_EDGE_CFLAGS="-fsanitize-coverage=edge -mllvm -sanitizer-coverage-prune-blocks=false"
COVERAGE_EDGE_LDFLAGS="-fsanitize-coverage=edge"

SANITIZE_NOCHECKS_CFLAGS="-mllvm -asan-instrument-reads=0 -mllvm -asan-instrument-writes=0 -mllvm -asan-globals=0 -mllvm -asan-stack=0"
SANITIZE_NOPOISON_OPTIONS="poison_heap=0"
SANITIZE_NOQUARANTINE_OPTIONS="quarantine_size=0"

# Parameters for the fuzzers and the build

WORK_DIR="$(pwd)"
N_CORES=${N_CORES:-$(getconf _NPROCESSORS_ONLN)}
MAX_LEN=${MAX_LEN:-128}

# Set ASAN_OPTIONS to defaults that favor speed over nice output
export ASAN_OPTIONS="malloc_context_size=0"

# The number of seconds for which we run fuzzers during testing and profiling
FUZZER_TESTING_SECONDS=20
FUZZER_PROFILING_SECONDS=20

# Which thresholds and variants should we test?
THRESHOLDS="${THRESHOLDS:-5000 2000 1000 750 500 333 200 100 80 50 20 10 5 2 1}"
VARIANTS="${VARIANTS:-icalls edge nochecks nopoison noquarantine}"

# Download and build LLVM's libFuzzer
init_libfuzzer() {
  mkdir -p logs
  mkdir -p perf-data

  if ! [ -d Fuzzer-src ]; then
    git clone git@github.com:dslab-epfl/asap-libfuzzer.git Fuzzer-src
    (cd Fuzzer-src && git checkout release_39)
  fi

  if ! [ -d Fuzzer-build ]; then
    mkdir Fuzzer-build
    cd Fuzzer-build
    for i in ../Fuzzer-src/*.cpp; do
      "$CXX" $LIBFUZZER_CFLAGS -c $i -I../Fuzzer-src &
    done
    wait
    ar ruv libFuzzer.a *.o
    cd ..
  fi
}

# Test the fuzzer with the given `name`.
test_fuzzer() {
  local name="$1"

  if ! [ -f "logs/fuzzer-${name}.log" ]; then
    rm -rf "target-${name}-build/CORPUS"
    mkdir -p "target-${name}-build/CORPUS"
    "./target-${name}-build/fuzzer" -seed=1 -max_total_time=$FUZZER_TESTING_SECONDS \
      -print_final_stats=1 "target-${name}-build/CORPUS" 2>&1 \
      | tee "logs/fuzzer-${name}.log"
  fi
}

# Run the fuzzer named `name` under perf, and create an llvm_prof file.
profile_fuzzer() {
  local name="$1"
  local perf_args="$2"

  if ! [ -f "perf-data/perf-${name}.data" ]; then
    perf record $perf_args -o "perf-data/perf-${name}.data" \
      "./target-${name}-build/fuzzer" -seed=1 -max_total_time=$FUZZER_PROFILING_SECONDS \
      -print_final_stats=1 2>&1 \
      | tee "logs/perf-${name}.log"
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

  if ! [ -f "logs/coverage-${name}.log" ]; then
    "./target-asan-pgo-build/fuzzer" -seed=1 -runs=0 "target-${name}-build/CORPUS" 2>&1 \
      | tee "logs/coverage-${name}.log"
  fi
}

# Generate and test initial, pgo, and thresholded versions
build_and_test_all() {
  # Initial build; simply AddressSanitizer, no PGO, no ASAP.
  build_target_and_fuzzer "asan" "$COVERAGE_COUNTERS_CFLAGS" "$COVERAGE_COUNTERS_LDFLAGS"

  # Test the fuzzer.
  test_fuzzer "asan"

  # Run the fuzzer under perf. Use branch tracing because that's what
  # create_llvm_prof wants.
  profile_fuzzer "asan" "-b"

  # Re-build using profiling data.
  build_target_and_fuzzer "asan-pgo" \
    "$COVERAGE_COUNTERS_CFLAGS -fprofile-sample-use=$WORK_DIR/perf-data/perf-asan.llvm_prof" \
    "$COVERAGE_COUNTERS_LDFLAGS"

  # Test the fuzzer. Should be faster now, due to PGO
  test_fuzzer "asan-pgo"
  compute_coverage "asan-pgo"

  # Build and test various cost thresholds
  for threshold in $THRESHOLDS; do
    build_target_and_fuzzer "asap-$threshold" \
      "$COVERAGE_COUNTERS_CFLAGS -fprofile-sample-use=$WORK_DIR/perf-data/perf-asan.llvm_prof -fsanitize=asap -mllvm -asap-cost-threshold=$threshold -mllvm -asap-verbose" \
      "$COVERAGE_COUNTERS_LDFLAGS"
    test_fuzzer "asap-$threshold"
    compute_coverage "asap-$threshold"
  done

  # Create extra variants to measure how much each feature contributes to
  # overhead and coverage.

  if echo "$VARIANTS" | grep -q icalls; then
    build_target_and_fuzzer "asan-icalls" "$COVERAGE_ICALLS_CFLAGS -fprofile-sample-use=$WORK_DIR/perf-data/perf-asan.llvm_prof" "$COVERAGE_ICALLS_LDFLAGS"
    test_fuzzer "asan-icalls"
    compute_coverage "asan-icalls"
  fi

  if echo "$VARIANTS" | grep -q edge; then
    build_target_and_fuzzer "asan-edge" "$COVERAGE_EDGE_CFLAGS -fprofile-sample-use=$WORK_DIR/perf-data/perf-asan.llvm_prof" "$COVERAGE_EDGE_LDFLAGS"
    test_fuzzer "asan-edge"
    compute_coverage "asan-edge"
  fi

  if echo "$VARIANTS" | grep -q nochecks; then
    build_target_and_fuzzer "asan-nochecks" "$COVERAGE_COUNTERS_CFLAGS $SANITIZE_NOCHECKS_CFLAGS -fprofile-sample-use=$WORK_DIR/perf-data/perf-asan.llvm_prof" "$COVERAGE_COUNTERS_LDFLAGS"
    test_fuzzer "asan-nochecks"
    compute_coverage "asan-nochecks"
  fi

  if echo "$VARIANTS" | grep -q nopoison; then
    build_target_and_fuzzer "asan-nopoison" "$COVERAGE_COUNTERS_CFLAGS -fprofile-sample-use=$WORK_DIR/perf-data/perf-asan.llvm_prof" "$COVERAGE_COUNTERS_LDFLAGS"
    ASAN_OPTIONS="$ASAN_OPTIONS:$SANITIZE_NOPOISON_OPTIONS" test_fuzzer "asan-nopoison"
    ASAN_OPTIONS="$ASAN_OPTIONS:$SANITIZE_NOPOISON_OPTIONS" compute_coverage "asan-nopoison"
  fi

  if echo "$VARIANTS" | grep -q noquarantine; then
    build_target_and_fuzzer "asan-noquarantine" "$COVERAGE_COUNTERS_CFLAGS -fprofile-sample-use=$WORK_DIR/perf-data/perf-asan.llvm_prof" "$COVERAGE_COUNTERS_LDFLAGS"
    ASAN_OPTIONS="$ASAN_OPTIONS:$SANITIZE_NOQUARANTINE_OPTIONS" test_fuzzer "asan-noquarantine"
    ASAN_OPTIONS="$ASAN_OPTIONS:$SANITIZE_NOQUARANTINE_OPTIONS" compute_coverage "asan-noquarantine"
  fi
}

# Print out a summary that we can export to spreadsheet
print_summary() {
  local summary_versions="$@"
  if [ -z "$summary_versions"]; then
    summary_versions="asan-pgo $(for i in $THRESHOLDS; do echo asap-$i; done) $(for i in $VARIANTS; do echo asan-$i; done)"
  fi

  echo
  echo "Summary"
  echo "======="
  echo
  (
    echo -e "name\tcov\tbits\texecs\texecs_per_sec\tunits\tactual_cov\tactual_bits"

    for name in $summary_versions; do
      # Get cov, bits from the last output line
      cov="$(grep '#[0-9]*.*DONE' logs/fuzzer-${name}.log | grep -o 'cov: [0-9]*' | grep -o '[0-9]*' | sort -n | tail -n1)"
      bits="$(grep '#[0-9]*.*DONE' logs/fuzzer-${name}.log | (grep -o 'bits: [0-9]*' || echo "bits: 0") | grep -o '[0-9]*' | sort -n | tail -n1)"

      # Get units and execs/s from the final stats
      execs="$(grep 'stat::number_of_executed_units:' logs/fuzzer-${name}.log | grep -o '[0-9]*' | sort -n | tail -n1)"
      execs_per_sec="$(grep 'stat::average_exec_per_sec:' logs/fuzzer-${name}.log | grep -o '[0-9]*' | sort -n | tail -n1)"
      units="$(grep 'stat::new_units_added:' logs/fuzzer-${name}.log | grep -o '[0-9]*' | sort -n | tail -n1)"

      # Get actual coverage from running the corpus against the PGO version
      actual_cov="$(grep '#[0-9]*.*DONE' logs/coverage-${name}.log | grep -o 'cov: [0-9]*' | grep -o '[0-9]*')"
      actual_bits="$(grep '#[0-9]*.*DONE' logs/coverage-${name}.log | grep -o 'bits: [0-9]*' | grep -o '[0-9]*')"

      echo -e "$name\t$cov\t$bits\t$execs\t$execs_per_sec\t$units\t$actual_cov\t$actual_bits"
    done
  ) | tee logs/summary.log
}

# usage: print usage information
usage() {
  echo "ff.sh: Focused Fuzzing wrapper script"
  echo "usage: ff.sh command [command args]"
  echo "commands:"
  echo "  clean   - remove generated files"
  echo "  help    - show this help message"
  echo "  build   - build initial, pgo, and thresholded versions"
  echo "  longrun - build and then run a target for a long time"
}

# clean: Remove generated files
do_clean() {
  rm -rf *-build logs perf-data
}

# build: build initial, pgo, and thresholded versions
do_build() {
  init_target
  init_libfuzzer
  build_and_test_all
  print_summary
}

# longrun: build and then run a target for a long time
do_longrun() {
  GLOBAL_CORPUS="${GLOBAL_CORPUS:-$HOME/asap/fuzzing-corpora/$target}"
  if ! [ -d "$GLOBAL_CORPUS" ]; then
    echo "Please set \$GLOBAL_CORPUS." >&2
    echo "Try:" >&2
    echo "    export GLOBAL_CORPUS=\"$GLOBAL_CORPUS\"" >&2
    echo "    git clone git@github.com:dslab-epfl/fuzzing-corpora.git \"$GLOBAL_CORPUS\"" >&2
    exit 1
  fi

  init_target
  init_libfuzzer
  build_target_and_fuzzer "asan" "$COVERAGE_COUNTERS_CFLAGS" "$COVERAGE_COUNTERS_LDFLAGS"
  profile_fuzzer "asan" "-b"

  local threshold=200
  build_target_and_fuzzer "asap-$threshold" \
    "$COVERAGE_COUNTERS_CFLAGS -fprofile-sample-use=$WORK_DIR/perf-data/perf-asan.llvm_prof \
    -fsanitize=asap -mllvm -asap-cost-threshold=$threshold -mllvm -asap-verbose" \
    "$COVERAGE_COUNTERS_LDFLAGS"

  # Profile this fuzzer for a bit longer than usual.
  # Note: we're not using any delay, because sometimes these fuzzers exit
  # fairly quickly when they find a crash...
  # TODO: it would be cool to profile using the full corpus, and to fix this
  # crash-early issue.
  mkdir -p "target-asap-${threshold}-build/CORPUS"
  FUZZER_PROFILING_SECONDS=60 profile_fuzzer "asap-$threshold" "-b"

  # Rebuild a high-quality fuzzer.
  # Note that because we profiled during 60 seconds instead of the default 20,
  # we set the threshold a bit higher, to 500. This is science we're doing :)
  local longrun_threshold=500
  build_target_and_fuzzer "longrun-$longrun_threshold" \
    "$COVERAGE_COUNTERS_CFLAGS -fprofile-sample-use=$WORK_DIR/perf-data/perf-asap-${threshold}.llvm_prof \
    -fsanitize=asap -mllvm -asap-cost-threshold=$longrun_threshold -mllvm -asap-verbose" \
    "$COVERAGE_COUNTERS_LDFLAGS"
  
  # And let the long-running fuzzer run.
  local workers=
  if [ -n "$N_WORKERS" ]; then
    workers="-workers=$N_WORKERS"
  fi
  cd "target-longrun-${longrun_threshold}-build"
  mkdir -p "CORPUS"
  "./fuzzer" \
    -jobs=1000 $workers -print_final_stats=1 -max_len=$MAX_LEN \
    "CORPUS" "$GLOBAL_CORPUS"
  cd ..
}
