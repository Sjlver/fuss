#!/bin/bash

set -eu

SCRIPT_DIR="$( dirname "$( readlink -f "${BASH_SOURCE[0]}" )" )"

BENCHMARKS="${BENCHMARKS:-boringssl-safe c-ares-safe file harfbuzz-safe http-parser libxml2-safe openssl-1.0.2e pcre re2-safe sqlite-safe woff2-safe}"
REPETITIONS="${REPETITIONS:-3}"

workdir="speed_and_coverage-$(date +%Y%m%d%H%M)"
mkdir "$workdir" && cd "$workdir"

for b in $BENCHMARKS; do
  mkdir "$b"
done

# Run experiments a first time, only one instance per benchmark. The first
# build is unfortunately a bit special (it checks out all the source code and
# builds the initial version) and so we cannot run other builds of the same
# benchmarks in parallel.
parallel --gnu --no-notice -j -2 "$SCRIPT_DIR/speed_and_coverage_experiment_one.sh" {} ::: $BENCHMARKS

# Run more experiments. This time, we can parallelize everything
if [ "$REPETITIONS" -gt 1 ]; then
  parallel --gnu --no-notice -j -2 "$SCRIPT_DIR/speed_and_coverage_experiment_one.sh" {} ::: $BENCHMARKS ::: $( seq $((REPETITIONS - 1)) )
fi

# Gather experimental data and create plots
"$SCRIPT_DIR/speed_and_coverage_plots_all.py" --output-execs plot_execs.png --output-cov plot_cov.png */logs/summary-*.log
