# From https://github.com/google/fuzzer-test-suite/tree/master/boringssl-2016-02-12

# On 4 cores (2 fuzzer jobs), found 10/40 crashes in one hour
export OPTIMAL_N_CORES=16
export CRASH_REGEXP="SUMMARY: AddressSanitizer: heap-use-after-free|SUMMARY: AddressSanitizer: double-free"

FUZZER_EXTRA_CORPORA="$WORK_DIR/boringssl-src/fuzz/privkey_corpus"
ASAN_OPTIONS="${ASAN_OPTIONS}:detect_leaks=0:quarantine_size_mb=50"

# Init boringssl source code
init_target() {
  if ! [ -d boringssl-src ]; then
    git clone https://github.com/google/boringssl.git boringssl-src
    (
      cd boringssl-src
      git checkout 894a47df2423f0d2b6be57e6d90f2bea88213382
      git am "$SCRIPT_DIR/ff-boringssl-2016-02-12.patch"
    )
  fi
}

# Build boringssl with the given `name` and flags.
build_target_and_fuzzer() {
  local name="$1"
  local extra_cflags="$2"
  local extra_ldflags="$3"

  if ! [ -x "target-${name}-build/fuzzer" ]; then
    mkdir -p "target-${name}-build"
    cd "target-${name}-build"
    # Arrrgh, CMake, why do you add CFLAGS to the linker command line by default?
    cmake -G Ninja -DBUILD_SHARED_LIBS=OFF \
      -DCMAKE_C_COMPILER="$CC" -DCMAKE_C_FLAGS="$DEFAULT_CFLAGS $extra_cflags" \
      -DCMAKE_EXE_LINKER_FLAGS="$DEFAULT_LDFLAGS $extra_ldflags" \
      -DCMAKE_C_LINK_EXECUTABLE="<CMAKE_C_COMPILER> <CMAKE_C_LINK_FLAGS> <LINK_FLAGS> <OBJECTS>  -o <TARGET> <LINK_LIBRARIES>" \
      ../boringssl-src
    ninja -j $N_CORES -v ssl/libssl.a crypto/libcrypto.a 2>&1 | tee "../logs/build-${name}.log"
    "$CXX" $DEFAULT_CFLAGS $extra_cflags -std=c++11 -I include -c ../boringssl-src/fuzz/privkey.cc \
      2>&1 | tee -a "../logs/build-${name}.log"
    "$CXX" $DEFAULT_LDFLAGS $extra_ldflags privkey.o ssl/libssl.a crypto/libcrypto.a \
      "$LIBFUZZER_A" -o fuzzer \
      2>&1 | tee -a "../logs/build-${name}.log"
    cd ..
  fi
}
