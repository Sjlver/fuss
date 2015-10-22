#!/bin/sh

set -e

SCRIPT_DIR="$( dirname $0 )"

benchmarks="$@"

parallel --gnu --tag --ungroup --load '50%' --delay 60 "$SCRIPT_DIR/phoronix-one.sh" {} all ::: $benchmarks

all_benchmarks="$( cd ~/.phoronix-test-suite/installed-tests && ls -d local/* )"

phoronix-test-suite batch-run $all_benchmarks
