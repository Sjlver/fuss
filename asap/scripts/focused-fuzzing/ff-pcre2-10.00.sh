# From https://github.com/google/fuzzer-test-suite/tree/master/pcre2-10.00

init_target() {
  if ! [ -d pcre2 ]; then
    svn checkout -r 183 svn://vcs.exim.org/pcre2/code/trunk pcre2
    (cd pcre2 && ./autogen.sh)
  fi
}

build_target_and_fuzzer() {
  local name="$1"
  local extra_cflags="$2"
  local extra_ldflags="$3"

  if ! [ -x "target-${name}-build/fuzzer" ]; then
    mkdir -p "target-${name}-build"
    cd "target-${name}-build"

    CC="$CC" CXX="$CXX" CFLAGS="$DEFAULT_CFLAGS $extra_cflags" LDFLAGS="$DEFAULT_LDFLAGS $extra_ldflags" \
      ../pcre2/configure --enable-never-backslash-C --with-match-limit=1000 --with-match-limit-recursion=1000 \
      2>&1 | tee "../logs/build-${name}.log"
    make -j $N_CORES 2>&1 | tee -a "../logs/build-${name}.log"

    "$CXX" $DEFAULT_CFLAGS $extra_cflags -std=c++11 \
      -I src -I ../pcre2/src -c "$SCRIPT_DIR/ff-pcre2-10.00.cc" \
      2>&1 | tee -a "../logs/build-${name}.log"
    "$CXX" $DEFAULT_LDFLAGS $extra_ldflags ff-pcre2-10.00.o .libs/libpcre2-posix.a .libs/libpcre2-8.a \
      "$LIBFUZZER_A" -o fuzzer \
      2>&1 | tee -a "../logs/build-${name}.log"
    cd ..
  fi
}
