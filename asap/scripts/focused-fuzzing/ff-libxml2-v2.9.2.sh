# From https://github.com/google/fuzzer-test-suite/tree/master/libxml2-v2.9.2

LIBXML_CONFIGURE_ARGS="
      --enable-option-checking
      --disable-shared --disable-ipv6
      --without-c14n --without-catalog --without-debug --without-docbook --without-ftp --without-http
      --without-legacy --without-output --without-pattern --without-push --without-python
      --without-reader --without-readline --without-regexps --without-sax1 --without-schemas
      --without-schematron --without-threads --without-valid --without-writer --without-xinclude
      --without-xpath --without-xptr --with-zlib=no --with-lzma=no"

FUZZER_EXTRA_ARGS="-dict=$WORK_DIR/afl/dictionaries/xml.dict"

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
  if ! [ -d libxml2 ]; then
    get_git_revision git://git.gnome.org/libxml2  v2.9.2 libxml2
    (cd libxml2 && autoreconf -fiv)
  fi
  get_git_revision https://github.com/mcarpenter/afl be3e88d639da5350603f6c0fee06970128504342 afl
}

build_target_and_fuzzer() {
  local name="$1"
  local extra_cflags="$2"
  local extra_ldflags="$3"

  if ! [ -x "target-${name}-build/fuzzer" ]; then
    mkdir -p "target-${name}-build"
    cd "target-${name}-build"

    CC="$CC" CXX="$CXX" CFLAGS="$DEFAULT_CFLAGS $extra_cflags" LDFLAGS="$DEFAULT_LDFLAGS $extra_ldflags" ../libxml2/configure $LIBXML_CONFIGURE_ARGS 2>&1 | tee "../logs/build-${name}.log"
    make -j $N_CORES V=1 libxml2.la include/libxml/xmlversion.h 2>&1 | tee -a "../logs/build-${name}.log"

    "$CXX" $DEFAULT_CFLAGS $extra_cflags -std=c++11 \
      -I "$WORK_DIR/target-${name}-build/include" -I "$WORK_DIR/libxml2/include" \
      -c "$SCRIPT_DIR/ff-libxml2.cc" \
      2>&1 | tee -a "../logs/build-${name}.log"
    "$CXX" $DEFAULT_LDFLAGS $extra_ldflags ff-libxml2.o "$WORK_DIR/target-${name}-build/.libs/libxml2.a" \
      "$WORK_DIR/Fuzzer-build/libFuzzer.a" -o fuzzer \
      2>&1 | tee -a "../logs/build-${name}.log"
    cd ..
  fi
}
