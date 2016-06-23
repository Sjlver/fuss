#!/bin/bash

set -e

SCRIPT_DIR="$( dirname "$( readlink -f "${BASH_SOURCE[0]}" )" )"

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
asan_cflags="-O2 -fsanitize=address -fsanitize-coverage=edge,indirect-calls,8bit-counters"

# No addresssanitizer checks
# 300000 runs in 13 second(s)
#asan_cflags="-O2 -fsanitize=address -fsanitize-coverage=edge,indirect-calls,8bit-counters  -mllvm -asan-instrument-reads=0 -mllvm -asan-instrument-writes=0 -mllvm -asan-globals=0 -mllvm -asan-stack=0"
# 300000 runs in 14 second(s)
#asan_cflags="-O2 -fsanitize=address -fsanitize-coverage=edge,indirect-calls,8bit-counters -fsanitize=asap -mllvm -asap-cost-threshold=0"

# This seems fast... what benefits do 8bit-counters give us?
# 300000 runs in 13 second(s)
#asan_cflags="-O2 -fsanitize=address -fsanitize-coverage=edge"

asan_ldflags="-fsanitize=address -fsanitize-coverage=edge,indirect-calls,8bit-counters"
asan_cc="$(which clang)"
asan_cxx="$(which clang++)"

WORK_DIR="$(pwd)"
N_CORES=$(getconf _NPROCESSORS_ONLN)                                                                                                                                                                                                          
if ! [ -d libxml2-src ]; then
  git clone git://git.gnome.org/libxml2 libxml2-src
  (cd libxml2-src && git checkout -b old 3a76bfeddeac9c331f761e45db6379c36c8876c3)
  (cd libxml2-src && ./autogen.sh && make distclean)
fi

if ! [ -d libxml2-asan-build ]; then
  mkdir libxml2-asan-build
  cd libxml2-asan-build
  CC="$asan_cc" CXX="$asan_cxx" CFLAGS="$asan_cflags" LDFLAGS="$asan_ldflags" ../libxml2-src/configure \
    --prefix "$WORK_DIR/libxml2-asan-install" \
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

if ! [ -d Fuzzer-src ]; then
  git clone https://chromium.googlesource.com/chromium/llvm-project/llvm/lib/Fuzzer Fuzzer-src
  (cd Fuzzer-src && git checkout -b release_37 badcec68b8d90f0e6f1296a04c023cf484b98488)
fi

if ! [ -d Fuzzer-build ]; then
  mkdir Fuzzer-build
  cd Fuzzer-build
  "$asan_cxx" -c -g -O2 -std=c++11 ../Fuzzer-src/*.cpp -I../Fuzzer-src
  ar ruv libFuzzer.a *.o
  cd ..
fi

if ! [ -d libxmlfuzzer-asan-build ]; then
  mkdir libxmlfuzzer-asan-build
  cd libxmlfuzzer-asan-build
  "$asan_cxx" -c -g -O2 -std=c++11 -I "$WORK_DIR/libxml2-asan-install/include/libxml2" "$SCRIPT_DIR/libxml_fuzzer.cc"
  "$asan_cxx" $asan_ldflags libxml_fuzzer.o "$WORK_DIR/libxml2-asan-install/lib/libxml2.a" "$WORK_DIR/Fuzzer-build/libFuzzer.a" -o libxml_fuzzer
  cd ..
fi

# Test the fuzzer. Should take no more than ~20 seconds for 300000 executions.
./libxmlfuzzer-asan-build/libxml_fuzzer -seed=1 -verbosity=2 -runs=300000
