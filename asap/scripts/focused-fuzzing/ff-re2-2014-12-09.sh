# From https://github.com/google/fuzzer-test-suite/tree/master/re2-2014-12-09

# On 20 cores (18 fuzzer jobs), found about 40% of the crashes in one hour
# Note: this one will often stop with out-of-memory too... but I believe that's
# a leak, not a special testcase. Make sure to run it with spare jobs, so that
# it uses all cores until the real crash is found.
export OPTIMAL_N_CORES=56
export CRASH_REGEXP="SUMMARY: AddressSanitizer: heap-buffer-overflow|SUMMARY: AddressSanitizer: bad-free|SUMMARY: AddressSanitizer: heap-use-after-free"

get_git_revision() {
  GIT_REPO="$1"
  GIT_REVISION="$2"
  TO_DIR="$3"
  if ! [ -e $TO_DIR ]; then
    git clone $GIT_REPO $TO_DIR
    (cd $TO_DIR && git checkout $GIT_REVISION)
  fi
}

init_target() {
  get_git_revision https://github.com/google/re2.git 499ef7eff7455ce9c9fae86111d4a77b6ac335de re2
}

build_target_and_fuzzer() {
  local name="$1"
  local extra_cflags="$2"
  local extra_ldflags="$3"

  if ! [ -x "target-${name}-build/fuzzer" ]; then
    rsync -a re2/ "target-${name}-build"
    (
      cd "target-${name}-build"

      make clean
      CC="$CC" CXX="$CXX" CFLAGS="$DEFAULT_CFLAGS $extra_cflags" CXXFLAGS="$DEFAULT_CFLAGS $extra_cflags" LDFLAGS="$DEFAULT_LDFLAGS $extra_ldflags" \
        make -j $N_CORES

      "$CXX" $DEFAULT_CFLAGS $extra_cflags -std=c++11 -I . \
        -c "$SCRIPT_DIR/ff-re2-2014-12-09.cc"
      "$CXX" $DEFAULT_LDFLAGS $extra_ldflags ff-re2-2014-12-09.o obj/libre2.a \
        "$LIBFUZZER_A" -o fuzzer
      cd ..
    )
  fi
}
