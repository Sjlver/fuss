#!/bin/bash

set -e
set -o pipefail

SCRIPT_DIR="$( dirname "$( readlink -f "${BASH_SOURCE[0]}" )" )"
. "$SCRIPT_DIR/ff-common.sh"

if ! [ -d pcre2-10.20 ]; then
  wget ftp://ftp.csx.cam.ac.uk/pub/software/programming/pcre/pcre2-10.20.tar.gz
  tar xf pcre2-10.20.tar.gz
fi

# Build pcre2 with the given `name` and `extra_cflags`.
build_target_and_fuzzer() {
  local name="$1"
  local extra_cflags="$2"

  if ! [ -d "target-${name}-build" ]; then
    mkdir "target-${name}-build"
    cd "target-${name}-build"
    CC="$CC" CXX="$CXX" CFLAGS="$ASAN_CFLAGS $extra_cflags" LDFLAGS="$ASAN_LDFLAGS" ../pcre2-10.20/configure --disable-shared
    make -j $N_CORES V=1 libpcre2-posix.la libpcre2-8.la 2>&1 | tee "../logs/build-${name}.log"

    "$CXX" $ASAN_CFLAGS $extra_cflags -std=c++11 \
      -I "$WORK_DIR/target-${name}-build/src" -I "$WORK_DIR/pcre2-10.20/src" \
      -c "$SCRIPT_DIR/ff-pcre.cc"
    "$CXX" $ASAN_LDFLAGS ff-pcre.o \
      "$WORK_DIR/target-${name}-build/.libs/libpcre2-posix.a" \
      "$WORK_DIR/target-${name}-build/.libs/libpcre2-8.a" \
      "$WORK_DIR/Fuzzer-build/libFuzzer.a" -o fuzzer
    cd ..
  fi
}

init_libfuzzer
build_and_test_all
print_summary
