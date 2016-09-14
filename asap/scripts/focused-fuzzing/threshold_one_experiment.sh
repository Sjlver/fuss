#!/bin/bash

set -e
set -o pipefail

SCRIPT_DIR="$( dirname "$( readlink -f "${BASH_SOURCE[0]}" )" )"
. "$SCRIPT_DIR/ff-common.sh"

usage() {
  echo "usage: threshold_one_experiment.sh experiment {target}"
}

do_experiment() {
  init_target
  init_libfuzzer
  THRESHOLDS=1 build_and_test_all
  
  # Set up initial state
  rsync -a --delete target-asan-pgo-build/ target-exp-pgo-start-build
  rsync -a --delete target-asap-1-build/ target-exp-1nc-start-build
  rsync -a --delete target-asap-1-build/ target-exp-1wc-start-build
  rsync -a target-asan-pgo-build/CORPUS/ target-exp-1wc-start-build/CORPUS
  cp logs/fuzzer-asan-pgo.log logs/fuzzer-exp-pgo-start.log
  cp logs/fuzzer-asap-1.log logs/fuzzer-exp-1nc-start.log
  cp logs/fuzzer-asap-1.log logs/fuzzer-exp-1wc-start.log

  # Copy initial state, so that we can run experiments on the copy
  for i in exp-pgo exp-1nc exp-1wc; do
    rsync -a --delete target-${i}-start-build/ target-${i}-end-build
  done

  # Run experiments on the copy
  for i in exp-pgo exp-1nc exp-1wc; do
    cd target-${i}-end-build
    "./fuzzer" -max_total_time=60 \
      -jobs=20 -workers=20 -max_len=64 \
      -print_final_stats=1 -prune_corpus=0 "CORPUS" 2>&1 \
      | tee "../logs/fuzzer-${i}-end.log"
    cd ..
  done

  for i in exp-pgo exp-1nc exp-1wc; do
    compute_coverage ${i}-start
    compute_coverage ${i}-end
  done

  print_summary asan-pgo asap-1 exp-pgo-start exp-pgo-end exp-1wc-start exp-1wc-end exp-1nc-start exp-1nc-end
}

if [ $# -lt 1 ]; then
  usage >&2
  echo >&2
  echo "No command given." >&2
  exit 1
fi

command="$1"
shift

# For commands that have a target, load the extra file
case "$command" in
  "experiment")
    if [ $# -lt 1 ]; then
      usage >&2
      echo >&2
      echo "No target given." >&2
      exit 1
    fi
    target="$1"
    shift

    . "$SCRIPT_DIR/ff-${target}.sh"
    ;;
esac

# Run the actual command
case "$command" in
  "experiment")   do_experiment ;;
  *)
    usage >&2
    echo >&2
    echo "Unknown command \"$command\"" >&2 ;;
esac
