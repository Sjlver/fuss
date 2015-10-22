#!/bin/sh

set -e

SCRIPT_DIR="$( dirname $0 )"
benchmark="$1"
testname="$2"

if [ -z "$benchmark" ] || [ -z "$testname" ]; then
  echo "usage: phoronix-one.sh <benchmark> <testname>" >&2
  exit 1
fi

# Main driver
if [ "$testname" = "all" ]; then
    echo "Installing benchmark $benchmark"
    parallel --gnu --tag --ungroup --load '50%' --delay 10 "$0" "$benchmark" {} ::: \
        baseline \
        asan-c1000 asan-c0010 asan-nochecks asan-s0000 \
        asan-s0990 asan-s0980 asan-s0950 asan-s0900 asan-s0800 asan-s0500 \
        ubsan-c1000 ubsan-c0010 ubsan-s0000 \
        ubsan-s0990 ubsan-s0980 ubsan-s0950 ubsan-s0900 ubsan-s0800 ubsan-s0500
        tsan-c1000 tsan-c0010 tsan-s0000 \
        tsan-s0990 tsan-s0980 tsan-s0950 tsan-s0900 tsan-s0800 tsan-s0500
fi

# Baseline

if [ "$testname" = "baseline" ]; then
    echo "  Install baseline for $benchmark"
    CFLAGS="-O3" CXXFLAGS="-O3" LDFLAGS=" " \
        "$SCRIPT_DIR/phoronix-baseline.sh" $benchmark baseline
fi

# ASan tests

if [ "$testname" = "asan-nochecks" ]; then
    echo "  Install asan-nochecks for $benchmark"
    CFLAGS="-O3 -fsanitize=address -mllvm -asan-instrument-reads=0 -mllvm -asan-instrument-writes=0" \
        CXXFLAGS="-O3 -fsanitize=address -mllvm -asan-instrument-reads=0 -mllvm -asan-instrument-writes=0" \
        LDFLAGS="-fsanitize=address" \
        "$SCRIPT_DIR/phoronix-baseline.sh" $benchmark asan-nochecks
fi

for costlevel in 1.000 0.010; do
    current_testname="asan-c$( echo $costlevel | tr -C -d '0-9' )"
    if [ "$testname" = "$current_testname" ]; then
        echo "  Install $current_testname for $benchmark"
        CFLAGS="-O3 -fsanitize=address" \
            CXXFLAGS="-O3 -fsanitize=address" \
            LDFLAGS="-fsanitize=address" \
            "$SCRIPT_DIR/phoronix-asap.sh" $benchmark "$current_testname" -asap-cost-level=$costlevel
    fi
done

for sanitylevel in 0.990 0.980 0.950 0.900 0.800 0.500 0.000; do
    current_testname="asan-s$( echo $sanitylevel | tr -C -d '0-9' )"
    if [ "$testname" = "$current_testname" ]; then
        echo "  Install $current_testname for $benchmark"
        CFLAGS="-O3 -fsanitize=address" \
            CXXFLAGS="-O3 -fsanitize=address" \
            LDFLAGS="-fsanitize=address" \
            "$SCRIPT_DIR/phoronix-asap.sh" $benchmark "$current_testname" -asap-sanity-level=$sanitylevel
    fi
done

# UBSan tests

for costlevel in 1.000 0.010; do
    current_testname="ubsan-c$( echo $costlevel | tr -C -d '0-9' )"
    if [ "$testname" = "$current_testname" ]; then
        echo "  Install $current_testname for $benchmark"
        CFLAGS="-O3 -fsanitize=undefined" \
            CXXFLAGS="-O3 -fsanitize=undefined" \
            LDFLAGS="-fsanitize=undefined" \
            "$SCRIPT_DIR/phoronix-asap.sh" $benchmark "$current_testname" -asap-cost-level=$costlevel
    fi
done

for sanitylevel in 0.990 0.980 0.950 0.900 0.800 0.500 0.000; do
    current_testname="ubsan-s$( echo $sanitylevel | tr -C -d '0-9' )"
    if [ "$testname" = "$current_testname" ]; then
        echo "  Install $current_testname for $benchmark"
        CFLAGS="-O3 -fsanitize=undefined" \
            CXXFLAGS="-O3 -fsanitize=undefined" \
            LDFLAGS="-fsanitize=undefined" \
            "$SCRIPT_DIR/phoronix-asap.sh" $benchmark "$current_testname" -asap-sanity-level=$sanitylevel
    fi
done

# TSan tests

for costlevel in 1.000 0.010; do
    current_testname="tsan-c$( echo $costlevel | tr -C -d '0-9' )"
    if [ "$testname" = "$current_testname" ]; then
        echo "  Install $current_testname for $benchmark"
        CFLAGS="-O3 -fsanitize=thread" \
            CXXFLAGS="-O3 -fsanitize=thread" \
            LDFLAGS="-fsanitize=thread" \
            "$SCRIPT_DIR/phoronix-asap.sh" $benchmark "$current_testname" -asap-cost-level=$costlevel
    fi
done

for sanitylevel in 0.990 0.980 0.950 0.900 0.800 0.500 0.000; do
    current_testname="tsan-s$( echo $sanitylevel | tr -C -d '0-9' )"
    if [ "$testname" = "$current_testname" ]; then
        echo "  Install $current_testname for $benchmark"
        CFLAGS="-O3 -fsanitize=thread" \
            CXXFLAGS="-O3 -fsanitize=thread" \
            LDFLAGS="-fsanitize=thread" \
            "$SCRIPT_DIR/phoronix-asap.sh" $benchmark "$current_testname" -asap-sanity-level=$sanitylevel
    fi
done

