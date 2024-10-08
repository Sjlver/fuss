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
FUZZER_TESTING_SECONDS=${FUZZER_TESTING_SECONDS:-20}
FUZZER_PROFILING_SECONDS=${FUZZER_PROFILING_SECONDS:-20}

FUSS_TESTING_SECONDS=${FUSS_TESTING_SECONDS:-60}
FUSS_PROFILING_SECONDS=${FUSS_PROFILING_SECONDS:-60}
FUSS_THRESHOLD=${FUSS_THRESHOLD:-500}
FUSS_TOTAL_SECONDS=${FUSS_TOTAL_SECONDS:-3600}

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
    patch -p1 < "$SCRIPT_DIR/$AFL_VERSION.patch"
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
  local reference="$2"

  local queue_dir="target-${name}-build/FINDINGS-$run_id/queue"
  local maps_dir="target-${name}-build/FINDINGS-$run_id/maps"
  mkdir -p "$maps_dir"

  if ! [ -f "logs/coverage-${name}-${run_id}.log" ]; then
    local temp_all="$(mktemp)"
    for infile in "$queue_dir/"*; do
      "./$AFL_VERSION/afl-showmap" -t 1000 -q \
        -o "$maps_dir/$(basename "$infile")" \
        -- "target-${reference}-build/target" < "$infile"
      cat "$maps_dir/$(basename "$infile")" >> "$temp_all"
    done
    sort "$temp_all" | uniq > "logs/coverage-${name}-${run_id}.log"
    rm "$temp_all"
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
  compute_coverage "pgo" "pgo"

  # Now that we have a PGO version, we can compute coverages. Make up the
  # coverage computation for the initial version.
  compute_coverage "init" "pgo"

  # Build and test various cost thresholds
  for threshold in $THRESHOLDS; do
    build_target "asap-$threshold" \
      "-fprofile-sample-use=$WORK_DIR/perf-data/perf-init.llvm_prof -fsanitize=asap -mllvm -asap-cost-threshold=$threshold -mllvm -asap-verbose" \
      ""
    test_fuzzer "asap-$threshold"
    compute_coverage "asap-$threshold" "pgo"
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
    printf "%20s\t%8s\t%8s\t%8s\t%8s\t%8s\t%8s\t%8s\n" "name" "cov" "bits" "execs" "execs_per_sec" "units" "actual_cov" "actual_bits"

    for name in $summary_versions; do
      cov="?"
      bits="?"

      # Get units and execs/s from the final stats
      execs="$(grep 'execs_done *:' logs/fuzzer-${name}-${run_id}.log | grep -o '[0-9]*' | sort -n | tail -n1)"
      execs_per_sec="$(grep 'execs_per_sec *:' logs/fuzzer-${name}-${run_id}.log | grep -o '[0-9]*' | sort -n | tail -n1)"
      units="$(grep 'paths_total *:' logs/fuzzer-${name}-${run_id}.log | grep -o '[0-9]*' | sort -n | tail -n1)"

      # Get actual coverage from running the corpus against the PGO version
      actual_cov="$(cat "logs/coverage-${name}-${run_id}.log" | sed 's/:.*//' | sort | uniq | wc)"
      actual_bits="$(cat "logs/coverage-${name}-${run_id}.log" | wc)"

      printf "%20s\t%8s\t%8s\t%8s\t%8s\t%8s\t%8s\t%8s\n" "$name" "$cov" "$bits" "$execs" "$execs_per_sec" "$units" "$actual_cov" "$actual_bits"
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
  echo "  fuss     - initial build, initial fuzzing, profiling, recompilation, long fuzzing"
  echo "  baseline - like fuss, except without fussing :)"
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

# fuss: A complete iteration of fuss. This consists of initial testing,
# profiling, and then some fuzzing.
do_fuss() {
  init_target
  init_afl

  (
    local start_time="$(date +%s)"
    local end_time="$((start_time + FUSS_TOTAL_SECONDS))"

    # Build and test initial fuzzers. Note: unlike for normal benchmarking, we
    # do want to re-build and re-profile these each run. Thus, the fuzzer name
    # contains the run_id.
    echo "fuss: building init-${run_id} version. timestamp: $start_time"
    build_target "fuss-init-${run_id}" "" ""
    echo "fuss: testing init-${run_id} version. timestamp: $(date +%s)"
    FUZZER_TESTING_SECONDS=$FUSS_TESTING_SECONDS test_fuzzer "fuss-init-${run_id}"
    rm -rf "target-fuss-init-${run_id}-build/CORPUS"
    cp -ar "target-fuss-init-${run_id}-build/FINDINGS-${run_id}/queue/" "target-fuss-init-${run_id}-build/CORPUS"
    echo "fuss: profiling init-${run_id} version. timestamp: $(date +%s)"
    FUZZER_PROFILING_SECONDS=$FUSS_PROFILING_SECONDS profile_fuzzer "fuss-init-${run_id}" "-b"

    # Rebuild a high-quality fuzzer.
    echo "fuss: building asap-${FUSS_THRESHOLD}-${run_id} version. timestamp: $(date +%s)"
    build_target "fuss-${FUSS_THRESHOLD}-${run_id}" \
      "-fprofile-sample-use=$WORK_DIR/perf-data/perf-fuss-init-${run_id}.llvm_prof \
      -fsanitize=asap -mllvm -asap-cost-threshold=$FUSS_THRESHOLD" \
      ""

    # Copy over the existing corpus (after all, we've earned that one)
    rm -rf "target-fuss-${FUSS_THRESHOLD}-${run_id}-build/CORPUS"
    cp -ar "target-fuss-init-${run_id}-build/FINDINGS-${run_id}/queue/" "target-fuss-${FUSS_THRESHOLD}-${run_id}-build/CORPUS"
    
    # And let the fuzzer run for some more time.
    local remaining="$((end_time - $(date +%s)))"
    echo "fuss: testing asap-$FUSS_THRESHOLD version. timestamp: $(date +%s) remaining: $remaining"
    FUZZER_TESTING_SECONDS="$remaining" test_fuzzer "fuss-${FUSS_THRESHOLD}-${run_id}"
    echo "fuss: fuss end. timestamp: $(date +%s)"
  ) | tee "logs/do_fuss-${run_id}.log"

  # Compute coverage
  compute_coverage "fuss-${FUSS_THRESHOLD}-${run_id}" "fuss-init-${run_id}"
  "$SCRIPT_DIR/parse_afl_coverage_vs_time.py" \
    --findings "target-fuss-${FUSS_THRESHOLD}-${run_id}-build/FINDINGS-${run_id}" \
    < "logs/do_fuss-${run_id}.log" > "logs/do_fuss-${run_id}-coverage.tsv"
}

# baseline: A complete iteration of fuss, except that it doesn't use fuss. This
# is the baseline we compare against.
do_baseline() {
  init_target
  init_afl

  (
    local start_time="$(date +%s)"
    local end_time="$((start_time + FUSS_TOTAL_SECONDS))"

    echo "fuss: building baseline-${run_id} version. timestamp: $start_time"
    build_target "baseline-${run_id}" "" ""
    
    # And let the fuzzer run for some time.
    local remaining="$((end_time - $(date +%s)))"
    echo "fuss: testing baseline-${run_id} version. timestamp: $(date +%s) remaining: $remaining"
    FUZZER_TESTING_SECONDS="$remaining" test_fuzzer "baseline-${run_id}"
    echo "fuss: baseline end. timestamp: $(date +%s)"
  ) | tee "logs/do_baseline-${run_id}.log"

  # Compute coverage
  compute_coverage "baseline-${run_id}" "baseline-${run_id}"
  "$SCRIPT_DIR/parse_afl_coverage_vs_time.py" \
    --findings "target-baseline-${run_id}-build/FINDINGS-${run_id}" \
    < "logs/do_baseline-${run_id}.log" > "logs/do_baseline-${run_id}-coverage.tsv"
}

# explore: build and test a small set of versions
do_explore() {
  THRESHOLDS="100" do_build
}
