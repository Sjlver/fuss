#!/bin/bash

set -eu

SCRIPT_DIR="$( dirname "$( readlink -f "${BASH_SOURCE[0]}" )" )"

benchmark="$1"

cd "$benchmark"
VARIANTS="tpcg tpcg-fperf noinstr" N_CORES=1 "$SCRIPT_DIR/ff.sh" speed "$benchmark"
