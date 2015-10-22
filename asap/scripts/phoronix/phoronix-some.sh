#!/bin/sh

set -e

SCRIPT_DIR="$( dirname $0 )"

benchmarks="$1"
testnames="$2"

parallel --gnu --tag --load '50%' --delay 10 "$SCRIPT_DIR/phoronix-one.sh" {1} {2} ::: $benchmarks ::: $testnames

all_benchmarks="$( cd ~/.phoronix-test-suite/installed-tests && ls -d local/* )"

phoronix-test-suite batch-run $all_benchmarks
