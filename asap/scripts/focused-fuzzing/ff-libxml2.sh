# Finds 12/40 crashes on two cores in one hour.
export OPTIMAL_N_CORES=16
export CRASH_REGEXP="AddressSanitizer: heap-buffer-overflow"

LIBXML_CONFIGURE_ARGS="
      --enable-option-checking
      --disable-shared --disable-ipv6
      --without-c14n --without-catalog --without-debug --without-docbook --without-ftp --without-http
      --without-legacy --without-output --without-pattern --without-push --without-python
      --without-reader --without-readline --without-regexps --without-sax1 --without-schemas
      --without-schematron --without-threads --without-valid --without-writer --without-xinclude
      --without-xpath --without-xptr --with-zlib=no --with-lzma=no"

init_target() {
  if ! [ -d libxml2-src ]; then
    git clone git://git.gnome.org/libxml2 libxml2-src
    (
      cd libxml2-src
      git checkout -b old 3a76bfeddeac9c331f761e45db6379c36c8876c3
      git am "$SCRIPT_DIR/ff-libxml2.patch"
      autoreconf -fiv
    )
  fi
}

# Build libxml with the given `name` and flags.
build_target_and_fuzzer() {
  local name="$1"
  local extra_cflags="$2"
  local extra_ldflags="$3"

  if ! [ -x "target-${name}-build/fuzzer" ]; then
    mkdir -p "target-${name}-build"
    cd "target-${name}-build"
    CC="$CC" CXX="$CXX" CFLAGS="$DEFAULT_CFLAGS $extra_cflags" LDFLAGS="$DEFAULT_LDFLAGS $extra_ldflags" ../libxml2-src/configure $LIBXML_CONFIGURE_ARGS
    make -j $N_CORES V=1 libxml2.la include/libxml/xmlversion.h 2>&1 | tee "../logs/build-${name}.log"

    "$CXX" $DEFAULT_CFLAGS $extra_cflags -std=c++11 \
      -I "$WORK_DIR/target-${name}-build/include" -I "$WORK_DIR/libxml2-src/include" \
      -c "$SCRIPT_DIR/ff-libxml2.cc"
    "$CXX" $DEFAULT_LDFLAGS $extra_ldflags ff-libxml2.o "$WORK_DIR/target-${name}-build/.libs/libxml2.a" \
      "$LIBFUZZER_A" -o fuzzer
    cd ..
  fi
}
