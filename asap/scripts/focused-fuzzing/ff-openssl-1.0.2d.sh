# From https://github.com/google/fuzzer-test-suite/tree/master/openssl-1.0.1f

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
  if ! [ -d openssl ]; then
    get_git_revision https://github.com/openssl/openssl.git OpenSSL_1_0_2d openssl
  fi
}

build_target_and_fuzzer() {
  local name="$1"
  local extra_cflags="$2"
  local extra_ldflags="$3"

  if ! [ -x "target-${name}-build/fuzzer" ]; then
    rsync -a openssl/ "target-${name}-build"
    cd "target-${name}-build"

    CC="$CC" CXX="$CXX" ./Configure $DEFAULT_CFLAGS $extra_cflags linux-x86_64 2>&1  | tee "../logs/build-${name}.log"
    # Weird... make seems to fail the first time?
    (make -j $N_CORES || make -j $N_CORES) 2>&1 | tee -a "../logs/build-${name}.log"

    "$CXX" $DEFAULT_CFLAGS $extra_cflags -std=c++11 \
      -I include -DCERT_PATH="\"$SCRIPT_DIR/\"" \
      -c "$SCRIPT_DIR/ff-openssl-1.0.2d.cc" \
      2>&1 | tee -a "../logs/build-${name}.log"
    "$CXX" $DEFAULT_LDFLAGS $extra_ldflags ff-openssl-1.0.2d.o libssl.a libcrypto.a \
      "$WORK_DIR/Fuzzer-build/libFuzzer.a" -lgcrypt -o fuzzer \
      2>&1 | tee -a "../logs/build-${name}.log"
    cd ..
  fi
}
