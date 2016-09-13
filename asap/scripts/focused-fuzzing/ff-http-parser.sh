# Init http-parser source code
init_target() {
  if ! [ -d http-parser-src ]; then
    git clone git@github.com:nodejs/http-parser.git http-parser-src
  fi
}

# Build http-parser with the given `name` and `extra_cflags`.
build_target_and_fuzzer() {
  local name="$1"
  local extra_cflags="$2"

  if ! [ -d "target-${name}-build" ]; then
    mkdir "target-${name}-build"
    cd "target-${name}-build"
    "$CC" $HTTP_PARSER_CFLAGS $ASAN_CFLAGS $extra_cflags -I ../http-parser-src -c ../http-parser-src/http_parser.c \
      -o http_parser.o 2>&1 | tee "../logs/build-${name}.log"
    "$CC" $ASAN_CFLAGS $extra_cflags -I ../http-parser-src -c "$SCRIPT_DIR/ff-http-parser.c" \
      -o ff-http-parser.o 2>&1 | tee -a "../logs/build-${name}.log"
    "$CXX" $ASAN_LDFLAGS ff-http-parser.o http_parser.o "$WORK_DIR/Fuzzer-build/libFuzzer.a" \
      -o fuzzer 2>&1 | tee -a "../logs/build-${name}.log"
    cd ..
  fi
}
