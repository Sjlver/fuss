#!/bin/bash

set -e
set -o pipefail

SCRIPT_DIR="$( dirname "$( readlink -f "${BASH_SOURCE[0]}" )" )"
. "$SCRIPT_DIR/ff-common.sh"

if ! [ -d libxml2-src ]; then
  git clone git://git.gnome.org/libxml2 libxml2-src
  (cd libxml2-src && git checkout -b old 3a76bfeddeac9c331f761e45db6379c36c8876c3)
  (cd libxml2-src && ./autogen.sh && make distclean)
fi

# Build libxml with the given `name` and `extra_cflags`.
build_target_and_fuzzer() {
  local name="$1"
  local extra_cflags="$2"

  if ! [ -d "target-${name}-build" ]; then
    mkdir "target-${name}-build"
    cd "target-${name}-build"
    CC="$CC" CXX="$CXX" CFLAGS="$ASAN_CFLAGS $extra_cflags" LDFLAGS="$ASAN_LDFLAGS" ../libxml2-src/configure \
      --enable-option-checking \
      --disable-shared --disable-ipv6 \
      --without-c14n --without-catalog --without-debug --without-docbook --without-ftp --without-http \
      --without-legacy --without-output --without-pattern --without-push --without-python \
      --without-reader --without-readline --without-regexps --without-sax1 --without-schemas \
      --without-schematron --without-threads --without-valid --without-writer --without-xinclude \
      --without-xpath --without-xptr --without-zlib --without-lzma
    make -j $N_CORES V=1 libxml2.la include/libxml/xmlversion.h 2>&1 | tee "../logs/build-${name}.log"

    "$CXX" $ASAN_CFLAGS $extra_cflags -std=c++11 \
      -I "$WORK_DIR/target-${name}-build/include" -I "$WORK_DIR/libxml2-src/include" \
      -c "$SCRIPT_DIR/ff-libxml2.cc"
    "$CXX" $ASAN_LDFLAGS ff-libxml2.o "$WORK_DIR/target-${name}-build/.libs/libxml2.a" \
      "$WORK_DIR/Fuzzer-build/libFuzzer.a" -o fuzzer
    cd ..
  fi
}

init_libfuzzer
build_and_test_all
print_summary
