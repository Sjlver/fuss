#!/bin/bash

# A script for running all experiments that measure the time to find a bug.

set -ex

if [ -z "$FUSS_START_ID" ]; then
  echo "Please set FUSS_START_ID. It's the first run_id. This allows you to" >&2
  echo "use multiple machines in parallel without run_id conflicts" >&2
  exit 1
fi

if [ -z "$FUSS_NUM_REPETITIONS" ]; then
  echo "Please set FUSS_NUM_REPETITIONS." >&2
  exit 1
fi

if ! [ -d ff-template ]; then
  echo "Please create the ff-template folder." >&2
  exit 1
fi

export FUSS_TOTAL_SECONDS="${FUSS_TOTAL_SECONDS:-86400}"

BENCHMARKS="${BENCHMARKS:-c-ares-CVE-2016-5180 file openssl-1.0.1f openssl-1.0.2d woff2-2016-05-06 libxml2 libxml2-v2.9.2 pcre2-10.00 re2-2014-12-09 boringssl-2016-02-12 harfbuzz-1.3.2}"

for benchmark in $BENCHMARKS; do
  (
    rsync -a ff-template/ ff-$benchmark
    cd ff-$benchmark
    if [ ! -e run_id ]; then
      echo "$FUSS_START_ID" > run_id
    fi
    for rep in $(seq "$FUSS_NUM_REPETITIONS"); do
      for version in baseline fuss; do
        bash -x ~/asap/asap/asap/scripts/focused-fuzzing/ff.sh $version $benchmark
        sleep 5
      done
    done
  ) || true
  sleep 5
done
