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
AFL_CC="$(which clang)"
AFL_CXX="$(which clang++)"

DEFAULT_CFLAGS="-O3 -g -Wall -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION"

# Parameters for the fuzzers and the build

WORK_DIR="$(pwd)"
N_CORES=${N_CORES:-$(getconf _NPROCESSORS_ONLN)}

# The number of seconds for which we run fuzzers during testing and profiling
FUZZER_TESTING_SECONDS=60
FUZZER_PROFILING_SECONDS=60

# Which thresholds and variants should we test?
THRESHOLDS="${THRESHOLDS:-5000 2000 1000 750 500 333 200 100 80 50 20 10 5}"

# Software versions
AFL_VERSION="afl-2.35b"

# Download and build AFL
init_afl() {
  mkdir -p logs
  mkdir -p perf-data

  if ! [ -d "$AFL_VERSION" ]; then
    [ -f "${AFL_VERSION}.tgz" ] || wget "http://lcamtuf.coredump.cx/afl/releases/${AFL_VERSION}.tgz"
    tar xf "${AFL_VERSION}.tgz"
    cd "$AFL_VERSION"
    AFL_TRACE_PC=1 make clean all
    cd "llvm_mode"
    AFL_TRACE_PC=1 make clean all
    cd ../..
  fi

  CC="$WORK_DIR/$AFL_VERSION/afl-clang-fast"
  CXX="$WORK_DIR/$AFL_VERSION/afl-clang-fast++"
  "$CC" --version >/dev/null 2>&1
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
    rm -rf "target-${name}-build/FINDINGS-$run_id"
    mkdir -p "target-${name}-build/FINDINGS-$run_id"
    timeout --preserve-status "${FUZZER_TESTING_SECONDS}s" \
      "./$AFL_VERSION/afl-fuzz" -d \
      -i "target-${name}-build/CORPUS" \
      -o "target-${name}-build/FINDINGS-$run_id" \
      -T "$(basename $(readlink -f "target-${name}-build/target")) $name $run_id" \
      -- "target-${name}-build/target"
    cp "target-${name}-build/FINDINGS-$run_id/fuzzer_stats" "logs/fuzzer-${name}-${run_id}.log"
  fi
}

# Run the fuzzer named `name` under perf, and create an llvm_prof file.
profile_fuzzer() {
  local name="$1"
  local perf_args="$2"

  if ! [ -f "perf-data/perf-${name}.data" ]; then
    (
      # Only one perf process can run at the same time, because performance
      # counters are a limited resource. Hence, use a global lock.
      flock 9 || exit 1
      perf record $perf_args -o "perf-data/perf-${name}.data" \
        timeout --preserve-status "${FUZZER_PROFILING_SECONDS}s" \
        "./$AFL_VERSION/afl-fuzz" -d \
        -i "target-${name}-build/CORPUS" \
        -o "target-${name}-build/FINDINGS-$run_id" \
        -T "$(basename $(readlink -f "target-${name}-build/target")) $name $run_id (perf)" \
        -- "target-${name}-build/target"
    ) 9>"/tmp/asap_global_perf_lock"
  fi

  # Convert perf data to LLVM profiling input.
  if ! [ -f "perf-data/perf-${name}.llvm_prof" ] && echo " $perf_args " | grep -q -- ' -b '; then
    create_llvm_prof --binary="target-${name}-build/target" \
      --profile="perf-data/perf-${name}.data" \
      --out="perf-data/perf-${name}.llvm_prof"
  fi
}

# See what coverage the fuzzer with the given `name` achieved
compute_coverage() {
  local name="$1"

  if ! [ -f "logs/coverage-${name}-${run_id}.log" ]; then
    local temp_map="$(mktemp)"
    local temp_all="$(mktemp)"
    for infile in "target-${name}-build/FINDINGS-$run_id/queue/"*; do
      "./$AFL_VERSION/afl-showmap" -o "$temp_map" -t 1000 -q \
        -- "target-${name}-build/target" < "$infile"
      cat "$temp_map" >> "$temp_all"
    done
    sort "$temp_all" | uniq > "logs/coverage-${name}-${run_id}.log"
    rm "$temp_map" "$temp_all"
  fi
}

# Generate and test initial, pgo, and thresholded versions
build_and_test_all() {
  # Initial build; no options, no PGO, no ASAP.
  build_target "init" "" ""

  # Test the fuzzer.
  test_fuzzer "init"

  # Run the fuzzer under perf. Use branch tracing because that's what
  # create_llvm_prof wants.
  profile_fuzzer "init" "-b"

  # Re-build using profiling data.
  build_target "pgo" \
    "-fprofile-sample-use=$WORK_DIR/perf-data/perf-init.llvm_prof" \
    ""

  # Test the fuzzer. Should be faster now, due to PGO
  test_fuzzer "pgo"
  compute_coverage "pgo"

  # Now that we have a PGO version, we can compute coverages. Make up the
  # coverage computation for the initial version.
  compute_coverage "init"

  # Build and test various cost thresholds
  for threshold in $THRESHOLDS; do
    build_target "asap-$threshold" \
      "-fprofile-sample-use=$WORK_DIR/perf-data/perf-init.llvm_prof -fsanitize=asap -mllvm -asap-cost-threshold=$threshold -mllvm -asap-verbose" \
      ""
    test_fuzzer "asap-$threshold"
    compute_coverage "asap-$threshold"
  done
}

# Print out a summary that we can export to spreadsheet
print_summary() {
  local summary_versions="$@"
  if [ -z "$summary_versions"]; then
    summary_versions="init pgo $(for i in $THRESHOLDS; do echo asap-$i; done)"
  fi

  echo
  echo "Summary"
  echo "======="
  echo
  (
    echo -e "name\tcov\tbits\texecs\texecs_per_sec\tunits\tactual_cov\tactual_bits"

    for name in $summary_versions; do
      cov="?"
      bits="?"

      # Get units and execs/s from the final stats
      execs="$(grep 'execs_done *:' logs/fuzzer-${name}-${run_id}.log | grep -o '[0-9]*' | sort -n | tail -n1)"
      execs_per_sec="$(grep 'execs_per_sec *:' logs/fuzzer-${name}-${run_id}.log | grep -o '[0-9]*' | sort -n | tail -n1)"
      units="$(grep 'paths_total *:' logs/fuzzer-${name}-${run_id}.log | grep -o '[0-9]*' | sort -n | tail -n1)"

      actual_cov="$(wc -l < "logs/coverage-${name}-${run_id}.log")"
      actual_bits="?"

      echo -e "$name\t$cov\t$bits\t$execs\t$execs_per_sec\t$units\t$actual_cov\t$actual_bits"
    done
  ) | tee "logs/summary-${run_id}.log"
}

# usage: print usage information
usage() {
  echo "fafl.sh: Focused Fuzzing wrapper script, for AFL"
  echo "usage: fafl.sh command [command args]"
  echo "commands:"
  echo "  clean   - remove generated files"
  echo "  help    - show this help message"
  echo "  build   - build initial, pgo, and thresholded versions"
  echo "  explore - build and test a small set of versions"
}

# clean: Remove generated files
do_clean() {
  rm -rf *-build logs perf-data run_id .run_id.lock
}

# build: build initial, pgo, and thresholded versions
do_build() {
  init_target
  init_afl
  build_and_test_all
  print_summary
}

# explore: build and test a small set of versions
do_explore() {
  THRESHOLDS="100" do_build
}
