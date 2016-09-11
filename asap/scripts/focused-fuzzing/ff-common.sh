#!/bin/bash

set -e
set -o pipefail

SCRIPT_DIR="$( dirname "$( readlink -f "${BASH_SOURCE[0]}" )" )"

if [ "$1" = "clean" ]; then
  rm -rf *-build logs perf-data
  exit 0
fi

mkdir -p logs
mkdir -p perf-data

if ! clang --version | grep -q asap; then
  echo "Could not find ASAP's clang. Please set \$PATH correctly." >&2
  exit 1
fi
if ! which create_llvm_prof >/dev/null 2>&1; then
  echo "Could not find create_llvm_prof. Please set \$PATH correctly." >&2
  exit 1
fi

LIBFUZZER_CFLAGS="-O3 -g -Wall -std=c++11"
ASAN_CFLAGS="-O3 -g -Wall -fsanitize=address -fsanitize-coverage=edge,indirect-calls,8bit-counters"
ASAN_LDFLAGS="-fsanitize=address -fsanitize-coverage=edge,indirect-calls,8bit-counters"
CC="$(which clang)"
CXX="$(which clang++)"

WORK_DIR="$(pwd)"
N_CORES=${N_CORES:-$(getconf _NPROCESSORS_ONLN)}

# Set ASAN_OPTIONS to defaults that favor speed over nice output
export ASAN_OPTIONS="malloc_context_size=0"

# The number of seconds for which we run fuzzers during testing and profiling
FUZZER_TESTING_SECONDS=20
FUZZER_PROFILING_SECONDS=20

# Which thresholds should we test?
THRESHOLDS="${THRESHOLDS:-5000 2000 1000 750 500 333 200 100 80 50 20 10 5 2 1}"

# Download and build LLVM's libFuzzer
init_libfuzzer() {
  if ! [ -d Fuzzer-src ]; then
    git clone https://chromium.googlesource.com/chromium/llvm-project/llvm/lib/Fuzzer Fuzzer-src
    (cd Fuzzer-src && git checkout -b release_37 95daeb3e343c6b64524acbeaa01b941111145c2e)
  fi

  if ! [ -d Fuzzer-build ]; then
    mkdir Fuzzer-build
    cd Fuzzer-build
    "$CXX" $LIBFUZZER_CFLAGS -c ../Fuzzer-src/*.cpp -I../Fuzzer-src
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

build_and_test_all() {
  # Initial build; simply AddressSanitizer, no PGO, no ASAP.
  build_target_and_fuzzer "asan" ""

  # Test the fuzzer.
  test_fuzzer "asan"

  # Run the fuzzer under perf. Use branch tracing because that's what
  # create_llvm_prof wants.
  profile_fuzzer "asan" "-b"

  # Re-build using profiling data.
  build_target_and_fuzzer "asan-pgo" "-fprofile-sample-use=$WORK_DIR/perf-data/perf-asan.llvm_prof"

  # Test the fuzzer. Should be faster now, due to PGO
  test_fuzzer "asan-pgo"
  compute_coverage "asan-pgo"

  # Build and test various cost thresholds
  for threshold in $THRESHOLDS; do
    build_target_and_fuzzer "asap-$threshold" "-fprofile-sample-use=$WORK_DIR/perf-data/perf-asan.llvm_prof -fsanitize=asap -mllvm -asap-cost-threshold=$threshold -mllvm -asap-verbose"
    test_fuzzer "asap-$threshold"
    compute_coverage "asap-$threshold"
  done
}

# Print out a summary that we can export to spreadsheet
print_summary() {
  echo
  echo "Summary"
  echo "======="
  echo
  (
    echo -e "name\tcov\tbits\texecs\texecs_per_sec\tunits\tactual_cov\tactual_bits"

    for name in asan-pgo $(for i in $THRESHOLDS; do echo asap-$i; done); do
      # Get cov, bits from the last output line
      cov="$(grep '#[0-9]*.*DONE' logs/fuzzer-${name}.log | grep -o 'cov: [0-9]*' | grep -o '[0-9]*')"
      bits="$(grep '#[0-9]*.*DONE' logs/fuzzer-${name}.log | grep -o 'bits: [0-9]*' | grep -o '[0-9]*')"

      # Get units and execs/s from the final stats
      execs="$(grep 'stat::number_of_executed_units:' logs/fuzzer-${name}.log | grep -o '[0-9]*')"
      execs_per_sec="$(grep 'stat::average_exec_per_sec:' logs/fuzzer-${name}.log | grep -o '[0-9]*')"
      units="$(grep 'stat::new_units_added:' logs/fuzzer-${name}.log | grep -o '[0-9]*')"

      # Get actual coverage from running the corpus against the PGO version
      actual_cov="$(grep '#[0-9]*.*DONE' logs/coverage-${name}.log | grep -o 'cov: [0-9]*' | grep -o '[0-9]*')"
      actual_bits="$(grep '#[0-9]*.*DONE' logs/coverage-${name}.log | grep -o 'bits: [0-9]*' | grep -o '[0-9]*')"

      echo -e "$name\t$cov\t$bits\t$execs\t$execs_per_sec\t$units\t$actual_cov\t$actual_bits"
    done
  ) | tee logs/summary.log
}
