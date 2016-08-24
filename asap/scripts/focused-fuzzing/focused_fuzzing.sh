#!/bin/bash

set -e

SCRIPT_DIR="$( dirname "$( readlink -f "${BASH_SOURCE[0]}" )" )"

if [ "$1" = "clean" ]; then
  rm -rf *-build logs perf-data
  exit 0
fi

# Experiments with fuzzing libxml. On luke1 (DSLab's development machine, 48
# cores), calling `rm -rf *-build; time ./focused_fuzzing.sh` takes about 1.5
# minutes. I think it might make sense to experiment a bit more, and ensure we
# get reliable, reproducible, and fast fuzzing runs.
#
# Interestingly, the configure options have quite a big impact on execution
# speed. On luke1, the fuzzer executes about 20000 runs per second (on a single
# core).

# A couple variants to try:

# "the default"
# 300000 runs in 14 or 15 second(s)
ASAN_CFLAGS="-O2 -fsanitize=address -fsanitize-coverage=edge,indirect-calls,8bit-counters"

# No addresssanitizer checks
# 300000 runs in 13 second(s)
#ASAN_CFLAGS="-O2 -fsanitize=address -fsanitize-coverage=edge,indirect-calls,8bit-counters  -mllvm -asan-instrument-reads=0 -mllvm -asan-instrument-writes=0 -mllvm -asan-globals=0 -mllvm -asan-stack=0"
# 300000 runs in 14 second(s)
#ASAN_CFLAGS="-O2 -fsanitize=address -fsanitize-coverage=edge,indirect-calls,8bit-counters -fsanitize=asap -mllvm -asap-cost-threshold=0"

# This seems fast... what benefits do 8bit-counters give us?
# 300000 runs in 13 second(s)
#ASAN_CFLAGS="-O2 -fsanitize=address -fsanitize-coverage=edge"

ASAN_LDFLAGS="-fsanitize=address -fsanitize-coverage=edge,indirect-calls,8bit-counters"
ASAN_CC="$(which clang)"
ASAN_CXX="$(which clang++)"

WORK_DIR="$(pwd)"
N_CORES=$(getconf _NPROCESSORS_ONLN)


if ! [ -d Fuzzer-src ]; then
  git clone https://chromium.googlesource.com/chromium/llvm-project/llvm/lib/Fuzzer Fuzzer-src
  (cd Fuzzer-src && git checkout -b release_37 95daeb3e343c6b64524acbeaa01b941111145c2e)
fi

if ! [ -d Fuzzer-build ]; then
  mkdir Fuzzer-build
  cd Fuzzer-build
  "$ASAN_CXX" -c -g -O2 -std=c++11 ../Fuzzer-src/*.cpp -I../Fuzzer-src
  ar ruv libFuzzer.a *.o
  cd ..
fi

if ! [ -d libxml2-src ]; then
  git clone git://git.gnome.org/libxml2 libxml2-src
  (cd libxml2-src && git checkout -b old 3a76bfeddeac9c331f761e45db6379c36c8876c3)
  (cd libxml2-src && ./autogen.sh && make distclean)
fi

# Build libxml and the fuzzer, with the given `name` and `extra_cflags`.
build_libxml_and_fuzzer() {
  local name="$1"
  local extra_cflags="$2"

  if ! [ -d "libxml2-$name-build" ]; then
    mkdir "libxml2-$name-build"
    cd "libxml2-$name-build"
    CC="$ASAN_CC" CXX="$ASAN_CXX" CFLAGS="$ASAN_CFLAGS $extra_cflags" LDFLAGS="$ASAN_LDFLAGS" ../libxml2-src/configure \
      --prefix "$WORK_DIR/libxml2-$name-install" \
      --enable-option-checking \
      --disable-shared --disable-ipv6 \
      --without-c14n --without-catalog --without-debug --without-docbook --without-ftp --without-http \
      --without-legacy --without-output --without-pattern --without-push --without-python \
      --without-reader --without-readline --without-regexps --without-sax1 --without-schemas \
      --without-schematron --without-threads --without-valid --without-writer --without-xinclude \
      --without-xpath --without-xptr --without-zlib --without-lzma
    make -j $N_CORES V=1
    make install
    cd ..
  fi

  if ! [ -d "libxmlfuzzer-$name-build" ]; then
    mkdir "libxmlfuzzer-$name-build"
    cd "libxmlfuzzer-$name-build"
    "$ASAN_CXX" -c -g -O2 -std=c++11 -I "$WORK_DIR/libxml2-$name-install/include/libxml2" "$SCRIPT_DIR/libxml_fuzzer.cc"
    "$ASAN_CXX" $ASAN_LDFLAGS libxml_fuzzer.o "$WORK_DIR/libxml2-$name-install/lib/libxml2.a" "$WORK_DIR/Fuzzer-build/libFuzzer.a" -o libxml_fuzzer
    cd ..
  fi
}

# Test the fuzzer with the given `name`.
test_fuzzer() {
  local name="$1"

  if ! [ -f "logs/libxmlfuzzer-${name}.log" ]; then
    mkdir -p logs
    "./libxmlfuzzer-$name-build/libxml_fuzzer" -seed=1 -verbosity=2 -runs=300000 2>&1 \
      | tee "logs/libxmlfuzzer-${name}.log"
  fi
}

# Initial build; simply AddressSanitizer, no PGO, no ASAP.
build_libxml_and_fuzzer "asan" ""

# Test the fuzzer. Should take no more than ~20 seconds for 300000 executions.
test_fuzzer "asan"

# Run the fuzzer under perf. For the moment, we're using the same 300k executions.
if ! [ -f perf-data/perf-asan.data ]; then
  mkdir -p perf-data
  perf record -b -o perf-data/perf-asan.data ./libxmlfuzzer-asan-build/libxml_fuzzer -seed=1 -verbosity=2 -runs=300000 2>&1 | tee logs/libxmlfuzzer-asan-perf.log
fi

# Convert perf data to LLVM profiling input.
if ! [ -f perf-data/perf-asan.llvm_prof ]; then
  create_llvm_prof --binary=./libxmlfuzzer-asan-build/libxml_fuzzer \
    --profile=perf-data/perf-asan.data \
    --out=perf-data/perf-asan.llvm_prof
fi

# Re-build libxml2 using profiling data.
build_libxml_and_fuzzer "asan-2" "-fprofile-sample-use=$WORK_DIR/perf-data/perf-asan.llvm_prof"

# Test the fuzzer. Should be faster now, due to PGO
test_fuzzer "asan-2"

# Re-build the fuzzer using ASAP. It should be faster now, due to ASAP.
build_libxml_and_fuzzer "asap-1000" "-fprofile-sample-use=$WORK_DIR/perf-data/perf-asan.llvm_prof -fsanitize=asap -mllvm -asap-cost-threshold=1000"
test_fuzzer "asap-1000"
build_libxml_and_fuzzer "asap-100" "-fprofile-sample-use=$WORK_DIR/perf-data/perf-asan.llvm_prof -fsanitize=asap -mllvm -asap-cost-threshold=100"
test_fuzzer "asap-100"
build_libxml_and_fuzzer "asap-10" "-fprofile-sample-use=$WORK_DIR/perf-data/perf-asan.llvm_prof -fsanitize=asap -mllvm -asap-cost-threshold=10"
test_fuzzer "asap-10"
build_libxml_and_fuzzer "asap-1" "-fprofile-sample-use=$WORK_DIR/perf-data/perf-asan.llvm_prof -fsanitize=asap -mllvm -asap-cost-threshold=1"
test_fuzzer "asap-1"
