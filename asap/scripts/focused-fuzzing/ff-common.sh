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

COVERAGE_COUNTERS_CFLAGS="-fsanitize=address -fsanitize-coverage=trace-pc-guard,indirect-calls"
COVERAGE_COUNTERS_LDFLAGS="-fsanitize=address -fsanitize-coverage=trace-pc-guard,indirect-calls"

COVERAGE_ICALLS_CFLAGS="-fsanitize=address -fsanitize-coverage=edge,indirect-calls"
COVERAGE_ICALLS_LDFLAGS="-fsanitize=address -fsanitize-coverage=edge,indirect-calls"

COVERAGE_EDGE_CFLAGS="-fsanitize=address -fsanitize-coverage=edge"
COVERAGE_EDGE_LDFLAGS="-fsanitize=address -fsanitize-coverage=edge"

COVERAGE_NONE_CFLAGS="-fsanitize=address"
COVERAGE_NONE_LDFLAGS="-fsanitize=address"

COVERAGE_ONLY_CFLAGS="-fsanitize-coverage=trace-pc-guard,indirect-calls"
COVERAGE_ONLY_LDFLAGS="-fsanitize-coverage=trace-pc-guard,indirect-calls"

SANITIZE_NOCHECKS_CFLAGS="-mllvm -asan-instrument-reads=0 -mllvm -asan-instrument-writes=0 -mllvm -asan-globals=0 -mllvm -asan-stack=0"
SANITIZE_NOPOISON_OPTIONS="poison_heap=0"
SANITIZE_NOQUARANTINE_OPTIONS="quarantine_size=0"

# Parameters for the fuzzers and the build

WORK_DIR="$(pwd)"
N_CORES=${N_CORES:-$(getconf _NPROCESSORS_ONLN)}
MAX_LEN=${MAX_LEN:-128}

if [ "$N_CORES" -ge 3 ]; then
  N_FUZZER_JOBS="$((N_CORES - 2))"
else
  N_FUZZER_JOBS=1
fi

# Set ASAN_OPTIONS to defaults that favor speed over nice output
export ASAN_OPTIONS="malloc_context_size=0"

# The number of seconds for which we run fuzzers during testing and profiling
FUZZER_TESTING_SECONDS=${FUZZER_TESTING_SECONDS:-20}
FUZZER_PROFILING_SECONDS=${FUZZER_PROFILING_SECONDS:-20}
FUZZER_BENCHMARKING_SECONDS=${FUZZER_BENCHMARKING_SECONDS:-5}

# Parameters for FUSS mode
FUSS_TESTING_SECONDS=${FUSS_TESTING_SECONDS:-60}
FUSS_PROFILING_SECONDS=${FUSS_PROFILING_SECONDS:-60}
FUSS_THRESHOLD=${FUSS_THRESHOLD:-500}
FUSS_TOTAL_SECONDS=${FUSS_TOTAL_SECONDS:-3600}

# Which thresholds and variants should we test?
THRESHOLDS="${THRESHOLDS:-5000 2000 1000 750 500 333 200 100 80 50 20 10 5 2 1}"
VARIANTS="${VARIANTS:-icalls edge nocoverage noasan nochecks nopoison noquarantine noelastic noinstrumentation asapcoverage}"

# Scripts can override this to use extra fuzzing args and corpora
FUZZER_EXTRA_CORPORA=${FUZZER_EXTRA_CORPORA:-}
FUZZER_EXTRA_ARGS=${FUZZER_EXTRA_ARGS:-}

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
    cd "target-${name}-build"
    mkdir -p "CORPUS-${run_id}"
    "./fuzzer" -max_total_time=$FUZZER_TESTING_SECONDS \
      -print_pcs=1 -print_final_stats=1 -jobs=$N_FUZZER_JOBS -workers=$N_FUZZER_JOBS \
      -artifact_prefix="CORPUS-${run_id}/" \
      $FUZZER_EXTRA_ARGS "CORPUS-${run_id}" $FUZZER_EXTRA_CORPORA 2>&1 \
      | tee -a "../logs/fuzzer-${name}-${run_id}.log"
    cd ..
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
      perf record $perf_args -o "../perf-data/perf-${name}.data" \
        "./fuzzer" -max_total_time=$FUZZER_PROFILING_SECONDS \
        -print_pcs=1 -print_final_stats=1 -jobs=$N_FUZZER_JOBS -workers=$N_FUZZER_JOBS \
        -artifact_prefix="CORPUS-${run_id}/" \
        $FUZZER_EXTRA_ARGS "CORPUS-${run_id}" $FUZZER_EXTRA_CORPORA 2>&1 \
        | tee -a "../logs/perf-${name}.log"
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

  if ! [ -f "logs/coverage-${name}-${run_id}.log" ]; then
    "./target-asan-pgo-build/fuzzer" -runs=0 "target-${name}-build/CORPUS-${run_id}" 2>&1 \
      | tee "logs/coverage-${name}-${run_id}.log"
  fi
}

# Generate initial, pgo, and thresholded versions
build_all() {
  # Initial build; simply AddressSanitizer, no PGO, no ASAP.
  build_target_and_fuzzer "asan" "$COVERAGE_COUNTERS_CFLAGS" "$COVERAGE_COUNTERS_LDFLAGS"

  # Run the fuzzer under perf. Use branch tracing because that's what
  # create_llvm_prof wants.
  if ! [ -f "perf-data/perf-asan.llvm_prof" ]; then
    test_fuzzer "asan"
    profile_fuzzer "asan" "-b"
  fi

  # Re-build using profiling data.
  build_target_and_fuzzer "asan-pgo" \
    "$COVERAGE_COUNTERS_CFLAGS -fprofile-sample-use=$WORK_DIR/perf-data/perf-asan.llvm_prof" \
    "$COVERAGE_COUNTERS_LDFLAGS"

  # Build and test various cost thresholds
  for threshold in $THRESHOLDS; do
    build_target_and_fuzzer "asap-$threshold" \
      "$COVERAGE_COUNTERS_CFLAGS -fprofile-sample-use=$WORK_DIR/perf-data/perf-asan.llvm_prof -fsanitize=asap -mllvm -asap-cost-threshold=$threshold -mllvm -asap-verbose" \
      "$COVERAGE_COUNTERS_LDFLAGS"
  done

  # Create extra variants to measure how much each feature contributes to
  # overhead and coverage.

  if echo "$VARIANTS" | grep -q icalls; then
    build_target_and_fuzzer "asan-icalls" "$COVERAGE_ICALLS_CFLAGS -fprofile-sample-use=$WORK_DIR/perf-data/perf-asan.llvm_prof" "$COVERAGE_ICALLS_LDFLAGS"
  fi

  if echo "$VARIANTS" | grep -q edge; then
    build_target_and_fuzzer "asan-edge" "$COVERAGE_EDGE_CFLAGS -fprofile-sample-use=$WORK_DIR/perf-data/perf-asan.llvm_prof" "$COVERAGE_EDGE_LDFLAGS"
  fi

  if echo "$VARIANTS" | grep -q nocoverage; then
    build_target_and_fuzzer "asan-nocoverage" "$COVERAGE_NONE_CFLAGS -fprofile-sample-use=$WORK_DIR/perf-data/perf-asan.llvm_prof" "$COVERAGE_NONE_LDFLAGS"
  fi

  if echo "$VARIANTS" | grep -q noasan; then
    build_target_and_fuzzer "asan-noasan" "$COVERAGE_ONLY_CFLAGS -fprofile-sample-use=$WORK_DIR/perf-data/perf-asan.llvm_prof" "$COVERAGE_ONLY_LDFLAGS"
  fi

  if echo "$VARIANTS" | grep -q nochecks; then
    build_target_and_fuzzer "asan-nochecks" "$COVERAGE_COUNTERS_CFLAGS $SANITIZE_NOCHECKS_CFLAGS -fprofile-sample-use=$WORK_DIR/perf-data/perf-asan.llvm_prof" "$COVERAGE_COUNTERS_LDFLAGS"
  fi

  if echo "$VARIANTS" | grep -q nopoison; then
    build_target_and_fuzzer "asan-nopoison" "$COVERAGE_COUNTERS_CFLAGS -fprofile-sample-use=$WORK_DIR/perf-data/perf-asan.llvm_prof" "$COVERAGE_COUNTERS_LDFLAGS"
  fi

  if echo "$VARIANTS" | grep -q noquarantine; then
    build_target_and_fuzzer "asan-noquarantine" "$COVERAGE_COUNTERS_CFLAGS -fprofile-sample-use=$WORK_DIR/perf-data/perf-asan.llvm_prof" "$COVERAGE_COUNTERS_LDFLAGS"
  fi

  if echo "$VARIANTS" | grep -q noelastic; then
    build_target_and_fuzzer "asan-noelastic" "$COVERAGE_NONE_CFLAGS $SANITIZE_NOCHECKS_CFLAGS -fprofile-sample-use=$WORK_DIR/perf-data/perf-asan.llvm_prof" "$COVERAGE_NONE_LDFLAGS"
  fi

  if echo "$VARIANTS" | grep -q noinstrumentation; then
    build_target_and_fuzzer "asan-noinstrumentation" "-fprofile-sample-use=$WORK_DIR/perf-data/perf-asan.llvm_prof" "$COVERAGE_ONLY_LDFLAGS"
  fi

  if echo "$VARIANTS" | grep -q asapcoverage; then
    build_target_and_fuzzer "asan-asapcoverage" \
      "$COVERAGE_COUNTERS_CFLAGS -fsanitize=asapcoverage -mllvm -asap-cost-threshold=100000 -mllvm -asap-verbose -mllvm -asap-module-name=$WORK_DIR/target-asan-build/fuzzer -mllvm -asap-coverage-file=$WORK_DIR/logs/perf-asan.log " \
      "$COVERAGE_COUNTERS_LDFLAGS"
  fi
}

# Test all versions that have been built by build_all
test_all() {
  # At the start of testing, set all corpora to those of the initial build.
  # This ensures each version can start with the same non-zero initial corpus.
  for i in target-*-build; do
    if [ "$i" != "target-asan-build" ]; then
      rsync -a --delete "target-asan-build/CORPUS-$run_id/" "$i/CORPUS-$run_id"
    fi
  done

  # Test the initial build.
  test_fuzzer "asan"
  compute_coverage "asan"

  # Test the PGO build.
  test_fuzzer "asan-pgo"
  compute_coverage "asan-pgo"

  # Test various cost thresholds
  for threshold in $THRESHOLDS; do
    test_fuzzer "asap-$threshold"
    compute_coverage "asap-$threshold"
  done

  # Test extra variants to measure how much each feature contributes to
  # overhead and coverage.
  for variant in $VARIANTS; do
    if [ "$variant" = "nopoison" ]; then
      ASAN_OPTIONS="$ASAN_OPTIONS:$SANITIZE_NOPOISON_OPTIONS" test_fuzzer "asan-nopoison"
    elif [ "$variant" = "noquarantine" ]; then
      ASAN_OPTIONS="$ASAN_OPTIONS:$SANITIZE_NOQUARANTINE_OPTIONS" test_fuzzer "asan-noquarantine"
    elif [ "$variant" = "noinstrumentation" ]; then
      FUZZER_EXTRA_ARGS="-benchmark=1" FUZZER_EXTRA_CORPORA="$WORK_DIR/target-asan-build/CORPUS-$run_id" test_fuzzer "asan-noinstrumentation"
    elif [ "$variant" = "noelastic" ]; then
      FUZZER_EXTRA_ARGS="-benchmark=1" FUZZER_EXTRA_CORPORA="$WORK_DIR/target-asan-build/CORPUS-$run_id" test_fuzzer "asan-noelastic"
    else
      test_fuzzer "asan-$variant"
    fi
    compute_coverage "asan-$variant"
  done
}

# Print out a summary that we can export to spreadsheet
print_summary() {
  local summary_versions="$@"
  if [ -z "$summary_versions"]; then
    summary_versions="asan asan-pgo $(for i in $THRESHOLDS; do echo asap-$i; done) $(for i in $VARIANTS; do echo asan-$i; done)"
  fi

  echo
  echo "Summary"
  echo "======="
  echo
  (
    printf "%20s\t%8s\t%8s\t%8s\t%8s\t%8s\t%8s\t%8s\n" "name" "cov" "ft" "execs" "execs_per_sec" "units" "actual_cov" "actual_ft"

    for name in $summary_versions; do
      # Get cov, ft from the last output line
      cov="$(grep '#[0-9]*.*DONE' logs/fuzzer-${name}-${run_id}.log | (grep -o 'cov: [0-9]*' || echo "cov: 0") | grep -o '[0-9]*' | sort -n | tail -n1)"
      ft="$(grep '#[0-9]*.*DONE' logs/fuzzer-${name}-${run_id}.log | (grep -o 'ft: [0-9]*' || echo "ft: 0") | grep -o '[0-9]*' | sort -n | tail -n1)"

      # Get units and execs/s from the final stats
      execs="$(grep 'stat::number_of_executed_units:' logs/fuzzer-${name}-${run_id}.log | grep -o '[0-9]*' | sort -n | tail -n1)"
      execs_per_sec="$(grep 'stat::average_exec_per_sec:' logs/fuzzer-${name}-${run_id}.log | grep -o '[0-9]*' | sort -n | tail -n1)"
      units="$(grep 'stat::new_units_added:' logs/fuzzer-${name}-${run_id}.log | grep -o '[0-9]*' | sort -n | tail -n1)"

      # Get actual coverage from running the corpus against the PGO version
      actual_cov="$(grep '#[0-9]*.*DONE' logs/coverage-${name}-${run_id}.log | grep -o 'cov: [0-9]*' | grep -o '[0-9]*')"
      actual_ft="$(grep '#[0-9]*.*DONE' logs/coverage-${name}-${run_id}.log | grep -o 'ft: [0-9]*' | grep -o '[0-9]*')"

      printf "%20s\t%8s\t%8s\t%8s\t%8s\t%8s\t%8s\t%8s\n" "$name" "$cov" "$ft" "$execs" "$execs_per_sec" "$units" "$actual_cov" "$actual_ft"
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
  echo "  build    - build initial, pgo, and thresholded versions"
  echo "  longrun  - build and then run a target for a long time"
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

  (
    local start_time="$(date +%s)"
    local end_time="$((start_time + FUSS_TOTAL_SECONDS))"

    # Build and test initial fuzzers. Note: unlike for normal benchmarking, we
    # do want to re-build and re-profile these each run. Thus, the fuzzer name
    # contains the run_id.
    echo "fuss: building asan-${run_id} version. timestamp: $start_time"
    build_target_and_fuzzer "fuss-asan-${run_id}" "$COVERAGE_COUNTERS_CFLAGS" "$COVERAGE_COUNTERS_LDFLAGS"
    echo "fuss: testing asan-${run_id} version. timestamp: $(date +%s)"
    FUZZER_TESTING_SECONDS=$FUSS_TESTING_SECONDS test_fuzzer "fuss-asan-${run_id}" || true
    if compgen -G "target-fuss-asan-${run_id}-build/CORPUS-${run_id}/crash-*" > /dev/null; then
      echo "fuss: fuss end (found crash during initial testing). timestamp: $(date +%s)"
      exit 0
    fi
      
    echo "fuss: profiling asan-${run_id} version. timestamp: $(date +%s)"
    FUZZER_PROFILING_SECONDS=$FUSS_PROFILING_SECONDS profile_fuzzer "fuss-asan-${run_id}" "-b" || true
    if compgen -G "target-fuss-asan-${run_id}-build/CORPUS-${run_id}/crash-*" > /dev/null; then
      echo "fuss: fuss end (found crash during profiling). timestamp: $(date +%s)"
      exit 0
    fi

    # Rebuild a high-quality fuzzer.
    echo "fuss: building asap-$FUSS_THRESHOLD-${run_id} version. timestamp: $(date +%s)"
    build_target_and_fuzzer "fuss-$FUSS_THRESHOLD-${run_id}" \
      "$COVERAGE_COUNTERS_CFLAGS -fprofile-sample-use=$WORK_DIR/perf-data/perf-fuss-asan-${run_id}.llvm_prof \
      -fsanitize=asap -mllvm -asap-cost-threshold=$FUSS_THRESHOLD" \
      "$COVERAGE_COUNTERS_LDFLAGS"

    # Copy over the existing corpus (after all, we've earned that one)
    cp -r "target-fuss-asan-${run_id}-build/CORPUS-${run_id}" "target-fuss-${FUSS_THRESHOLD}-${run_id}-build/CORPUS-${run_id}"
    
    # And let the fuzzer run for some more time. We ignore crashes in the
    # fuzzer, and simply stop it when this occurs.
    local remaining="$((end_time - $(date +%s)))"
    echo "fuss: testing asap-$FUSS_THRESHOLD version. timestamp: $(date +%s) remaining: $remaining"
    FUZZER_TESTING_SECONDS="$remaining" test_fuzzer "fuss-$FUSS_THRESHOLD-${run_id}" || true
    echo "fuss: fuss end. timestamp: $(date +%s)"
  ) | tee "logs/do_fuss-${run_id}.log"

  # Compute coverage. Carefully choose the right corpus; if a crash is found
  # during initialization or profiling, then the fuss-$FUSS_THRESHOLD corpus
  # does not exist yet.
  local corpus_for_coverage="target-fuss-${FUSS_THRESHOLD}-${run_id}-build/CORPUS-${run_id}"
  if ! [ -d "$corpus_for_coverage" ]; then
    corpus_for_coverage="target-fuss-asan-${run_id}-build/CORPUS-${run_id}"
  fi
  "$SCRIPT_DIR/parse_libfuzzer_coverage_vs_time.py" \
    --fuzzer "target-fuss-asan-${run_id}-build/fuzzer" \
    --corpus "$corpus_for_coverage" \
    < "logs/do_fuss-${run_id}.log" > "logs/do_fuss-${run_id}-coverage.tsv"
}

# baseline: A complete iteration of fuss, except that it doesn't use fuss. This
# is the baseline we compare against.
do_baseline() {
  init_target
  init_libfuzzer

  (
    local start_time="$(date +%s)"
    local end_time="$((start_time + FUSS_TOTAL_SECONDS))"

    echo "fuss: building baseline-${run_id} version. timestamp: $start_time"
    build_target_and_fuzzer "baseline-${run_id}" "$COVERAGE_COUNTERS_CFLAGS" "$COVERAGE_COUNTERS_LDFLAGS"
    
    # And let the fuzzer run for some time. We ignore crashes in the fuzzer,
    # and simply stop it when this occurs.
    local remaining="$((end_time - $(date +%s)))"
    echo "fuss: testing baseline-${run_id} version. timestamp: $(date +%s) remaining: $remaining"
    FUZZER_TESTING_SECONDS="$remaining" test_fuzzer "baseline-${run_id}" || true
    echo "fuss: baseline end. timestamp: $(date +%s)"
  ) | tee "logs/do_baseline-${run_id}.log"

  # Compute coverage
  "$SCRIPT_DIR/parse_libfuzzer_coverage_vs_time.py" \
    --fuzzer "target-baseline-${run_id}-build/fuzzer" \
    --corpus "target-baseline-${run_id}-build/CORPUS-${run_id}" \
    < "logs/do_baseline-${run_id}.log" > "logs/do_baseline-${run_id}-coverage.tsv"
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
    -jobs=1000 $workers -print_pcs=1 -print_final_stats=1 -max_len=$MAX_LEN \
    "CORPUS" "$GLOBAL_CORPUS"
  cd ..
}

# benchmark: Measure execution speed of various versions
do_benchmark() {
  init_target
  init_libfuzzer
  build_all

  local versions="asan asan-pgo $(for i in $THRESHOLDS; do echo asap-$i; done) $(for i in $VARIANTS; do echo asan-$i; done)"
  local corpus_for_benchmark="$(ls -d target-asan-build/CORPUS-* | head -n1)"
  local extra_asan_options=

  echo
  echo "Benchmark"
  echo "========="
  echo
  (
    for version in $versions; do
      if [ "$version" = "asan-nopoison" ]; then
        extra_asan_options="$SANITIZE_NOPOISON_OPTIONS"
      elif [ "$version" = "asan-noquarantine" ]; then
        extra_asan_options="$SANITIZE_NOQUARANTINE_OPTIONS"
      fi

      printf "%30s\t" "$version"
      ASAN_OPTIONS="$ASAN_OPTIONS:$extra_asan_options" ./target-${version}-build/fuzzer \
        -max_total_time=$FUZZER_BENCHMARKING_SECONDS \
        -print_pcs=1 -print_final_stats=1 -benchmark=1 "$corpus_for_benchmark" 2>&1 | \
        grep stat::number_of_executed_units | grep -o '[0-9]\+'
    done
  ) | tee "logs/benchmark-${run_id}.log"
}

