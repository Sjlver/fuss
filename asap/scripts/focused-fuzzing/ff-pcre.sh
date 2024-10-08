SRC_DIR="pcre2-10.22"
init_target() {
  if ! [ -d $SRC_DIR ]; then
    wget ftp://ftp.csx.cam.ac.uk/pub/software/programming/pcre/pcre2-10.22.tar.gz
    tar xf pcre2-10.22.tar.gz
  fi
}

# Build pcre2 with the given `name` and flags.
build_target_and_fuzzer() {
  local name="$1"
  local extra_cflags="$2"
  local extra_ldflags="$3"

  if ! [ -x "target-${name}-build/fuzzer" ]; then
    mkdir -p "target-${name}-build"
    (
      cd "target-${name}-build"

      # Configure pcre2 with relatively low resource limits, to ensure fuzzing is
      # fast, and to avoid false positives from AddressSanitizer's low stack
      # overflow limits.
      CC="$CC" CXX="$CXX" CFLAGS="$DEFAULT_CFLAGS" LDFLAGS="$DEFAULT_LDFLAGS" ../$SRC_DIR/configure \
        --disable-shared --with-parens-nest-limit=200 --with-match-limit=1000000 --with-match-limit-recursion=200
      make CFLAGS="$DEFAULT_CFLAGS $extra_cflags" LDFLAGS="$DEFAULT_LDFLAGS $extra_ldflags"  -j $N_CORES V=1 libpcre2-posix.la libpcre2-8.la

      "$CXX" $DEFAULT_CFLAGS $extra_cflags -std=c++11 \
        -I "$WORK_DIR/target-${name}-build/src" -I "$WORK_DIR/$SRC_DIR/src" \
        -c "$SCRIPT_DIR/ff-pcre.cc"
      "$CXX" $DEFAULT_LDFLAGS $extra_ldflags ff-pcre.o \
        "$WORK_DIR/target-${name}-build/.libs/libpcre2-posix.a" \
        "$WORK_DIR/target-${name}-build/.libs/libpcre2-8.a" \
        "$LIBFUZZER_A" -o fuzzer
    )
  fi
}
