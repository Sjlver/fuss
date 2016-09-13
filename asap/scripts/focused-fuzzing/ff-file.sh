# Initialize the "file" source code
init_target() {
  if ! [ -d file ]; then
    git clone https://github.com/file/file.git
    (cd file && autoreconf -f -i)
  fi
}

# Build "file" with the given `name` and `extra_cflags`.
build_target_and_fuzzer() {
  local name="$1"
  local extra_cflags="$2"

  if ! [ -d "target-${name}-build" ]; then
    mkdir "target-${name}-build"
    cd "target-${name}-build"
    CC="$CC" CXX="$CXX" CFLAGS="$ASAN_CFLAGS $extra_cflags" LDFLAGS="$ASAN_LDFLAGS" ../file/configure \
      --disable-silent-rules --disable-dependency-tracking --enable-static --disable-shared --disable-zlib 
    make -j $N_CORES V=1 2>&1 | tee "../logs/build-${name}.log"

    "$CXX" $ASAN_CFLAGS $extra_cflags -std=c++11 \
      -DASAP_MAGIC_FILE_PATH="\"$WORK_DIR/target-${name}-build/magic/magic\"" \
      -I "$WORK_DIR/target-${name}-build/src" \
      -c "$SCRIPT_DIR/ff-file.cc"
    "$CXX" $ASAN_LDFLAGS ff-file.o \
      "$WORK_DIR/target-${name}-build/src/.libs/libmagic.a" \
      "$WORK_DIR/Fuzzer-build/libFuzzer.a" -o fuzzer
    cd ..
  fi
}
