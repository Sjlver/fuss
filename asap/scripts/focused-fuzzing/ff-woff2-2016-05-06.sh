# From https://github.com/google/fuzzer-test-suite/tree/master/harfbuzz-1.3.2

FUZZER_EXTRA_CORPORA="$WORK_DIR/roboto"

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
  get_git_revision https://github.com/google/woff2.git \
    9476664fd6931ea6ec532c94b816d8fbbe3aed90 woff2
  get_git_revision https://github.com/google/brotli.git \
    3a9032ba8733532a6cd6727970bade7f7c0e2f52 brotli
  get_git_revision https://github.com/FontFaceKit/roboto.git \
    0e41bf923e2599d651084eece345701e55a8bfde roboto
}

build_target_and_fuzzer() {
  local name="$1"
  local extra_cflags="$2"
  local extra_ldflags="$3"

  if ! [ -x "target-${name}-build/fuzzer" ]; then
    mkdir -p "target-${name}-build"
    cd "target-${name}-build"
    rm -f "../logs/build-${name}.log"

    for f in font.cc normalize.cc transform.cc woff2_common.cc woff2_dec.cc woff2_enc.cc \
             glyph.cc table_tags.cc variable_length.cc woff2_out.cc; do
      "$CXX" $DEFAULT_CFLAGS $extra_cflags -std=c++11 -I ../brotli/dec -I ../brotli/enc \
        -c ../woff2/src/$f 2>&1 | tee -a "../logs/build-${name}.log" &
    done

    for f in ../brotli/dec/*.c ../brotli/enc/*.cc; do
      "$CXX" $DEFAULT_CFLAGS $extra_cflags -c $f \
        2>&1 | tee -a "../logs/build-${name}.log" &
    done

    wait

    "$CXX" $DEFAULT_CFLAGS $extra_cflags -std=c++11 -I ../woff2/src \
      -c "$SCRIPT_DIR/ff-woff2-2016-05-06.cc" \
      2>&1 | tee -a "../logs/build-${name}.log"
    "$CXX" $DEFAULT_LDFLAGS $extra_ldflags *.o \
      "$LIBFUZZER_A" -o fuzzer \
      2>&1 | tee -a "../logs/build-${name}.log"
    cd ..
  fi
}
