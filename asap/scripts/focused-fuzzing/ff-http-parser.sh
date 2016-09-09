#!/bin/bash

set -e

SCRIPT_DIR="$( dirname "$( readlink -f "${BASH_SOURCE[0]}" )" )"
. "$SCRIPT_DIR/ff-common.sh"

HTTP_PARSER_CFLAGS="-DHTTP_PARSER_STRICT=0 -Wextra -Werror -Wno-unused-parameter"

if ! [ -d http-parser-src ]; then
  git clone git@github.com:nodejs/http-parser.git http-parser-src
fi

# Build http-parser with the given `name` and `extra_cflags`.
build_target_and_fuzzer() {
  local name="$1"
  local extra_cflags="$2"

  if ! [ -d "target-${name}-build" ]; then
    mkdir "target-${name}-build"
    cd "target-${name}-build"
    "$CC" $HTTP_PARSER_CFLAGS $ASAN_CFLAGS $extra_cflags -I ../http-parser-src -c ../http-parser-src/http_parser.c -o http_parser.o
    "$CC" $ASAN_CFLAGS $extra_cflags -I ../http-parser-src -c "$SCRIPT_DIR/ff-http-parser.c" -o ff-http-parser.o
    "$CXX" $ASAN_LDFLAGS ff-http-parser.o http_parser.o "$WORK_DIR/Fuzzer-build/libFuzzer.a" -o fuzzer
    cd ..
  fi
}

init_libfuzzer
build_and_test_all
print_summary
