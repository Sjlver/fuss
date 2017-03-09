# From https://github.com/google/fuzzer-test-suite/tree/master/sqlite-2016-11-14

# On 4 cores (2 fuzzer jobs), found 8/40 crashes in one hour
export OPTIMAL_N_CORES=16
export CRASH_REGEXP="libFuzzer: out-of-memory|AddressSanitizer: heap-use-after-free|AddressSanitizer: heap-buffer-overflow"

FUZZER_EXTRA_ARGS="-dict=$SCRIPT_DIR/sqlite-2016-11-14/sql.dict"

init_target() {
  if ! [ -d sqlite3-src ]; then
    cp -r "$SCRIPT_DIR/sqlite-2016-11-14/" sqlite3-src
  fi
}

build_target_and_fuzzer() {
  local name="$1"
  local extra_cflags="$2"
  local extra_ldflags="$3"

  if ! [ -x "target-${name}-build/fuzzer" ]; then
    mkdir "target-${name}-build"
    (
      cd "target-${name}-build"

      "$CC" $DEFAULT_CFLAGS $extra_cflags -c "../sqlite3-src/sqlite3.c"
      "$CC" $DEFAULT_CFLAGS $extra_cflags -c "../sqlite3-src/ossfuzz.c"
      "$CXX" $DEFAULT_LDFLAGS $extra_ldflags sqlite3.o ossfuzz.o "$LIBFUZZER_A" -o fuzzer
    )
  fi
}
