HTTP_PARSER_CFLAGS="-DHTTP_PARSER_STRICT=0 -Wextra -Werror -Wno-unused-parameter"

# Init http-parser source code
init_target() {
  if ! [ -d http-parser-src ]; then
    git clone git@github.com:nodejs/http-parser.git http-parser-src
  fi
}

# Build http-parser with the given `name` and flags.
build_target_and_fuzzer() {
  local name="$1"
  local extra_cflags="$2"
  local extra_ldflags="$3"

  if ! [ -x "target-${name}-build/fuzzer" ]; then
    mkdir -p "target-${name}-build"
    (
      cd "target-${name}-build"
      "$CC" $HTTP_PARSER_CFLAGS $DEFAULT_CFLAGS $extra_cflags -I ../http-parser-src -c ../http-parser-src/http_parser.c \
        -o http_parser.o
      "$CC" $DEFAULT_CFLAGS $extra_cflags -I ../http-parser-src -c "$SCRIPT_DIR/ff-http-parser.c" \
        -o ff-http-parser.o
      "$CXX" $DEFAULT_LDFLAGS $extra_ldflags ff-http-parser.o http_parser.o "$LIBFUZZER_A" \
        -o fuzzer
    )
  fi
}
