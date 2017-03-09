# From https://github.com/google/fuzzer-test-suite/tree/master/harfbuzz-1.3.2

# On 4 cores (2 fuzzer jobs), found 0/40 crashes in one hour. It starts to find
# them with more cores. Let's also give it a bit more time.
export OPTIMAL_N_CORES=40
export OPTIMAL_FUZZER_TESTING_SECONDS="$((3*60*60))"
export CRASH_REGEXP="Assertion .* failed"

FUZZER_EXTRA_CORPORA="$WORK_DIR/harfbuzz-src/test/shaping/fonts/sha1sum"

init_target() {
  if ! [ -d harfbuzz-src ]; then
    git clone https://github.com/behdad/harfbuzz.git harfbuzz-src
    (
      cd harfbuzz-src
      git checkout f73a87d9a8c76a181794b74b527ea268048f78e3 
      ./autogen.sh
      make distclean
    )
  fi
}

build_target_and_fuzzer() {
  local name="$1"
  local extra_cflags="$2"
  local extra_ldflags="$3"

  if ! [ -x "target-${name}-build/fuzzer" ]; then
    mkdir -p "target-${name}-build"
    (
      cd "target-${name}-build"
      CC="$CC" CXX="$CXX" CFLAGS="$DEFAULT_CFLAGS $extra_cflags" CXXFLAGS="$DEFAULT_CFLAGS $extra_cflags" LDFLAGS="$DEFAULT_LDFLAGS $extra_ldflags" \
        ../harfbuzz-src/configure --enable-static --disable-shared
      make -j $N_CORES -C src fuzzing
      "$CXX" $DEFAULT_CFLAGS $extra_cflags -std=c++11 -I src -I ../harfbuzz-src/src \
        -c ../harfbuzz-src/test/fuzzing/hb-fuzzer.cc
      "$CXX" $DEFAULT_LDFLAGS $extra_ldflags hb-fuzzer.o src/.libs/libharfbuzz-fuzzing.a -lglib-2.0 \
        "$LIBFUZZER_A" -o fuzzer
      cd ..
    )
  fi
}
