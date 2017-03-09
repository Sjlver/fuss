# Initialize the "file" source code
init_target() {
  if ! [ -d file ]; then
    git clone https://github.com/file/file.git
    (cd file && git checkout 0e93a47b7feaee1d3a0f1b14e40f0ead17d8ccd4)
    (cd file && autoreconf -f -i)
  fi
}

# Build "file" with the given `name` and flags.
build_target_and_fuzzer() {
  local name="$1"
  local extra_cflags="$2"
  local extra_ldflags="$3"

  if ! [ -x "target-${name}-build/fuzzer" ]; then
    mkdir -p "target-${name}-build"
    (
      cd "target-${name}-build"
      CC="$CC" CXX="$CXX" CFLAGS="$DEFAULT_CFLAGS $extra_cflags" LDFLAGS="$DEFAULT_LDFLAGS $extra_ldflags" ../file/configure \
        --disable-silent-rules --disable-dependency-tracking --enable-static --disable-shared --disable-zlib 
      make -j $N_CORES V=1

      "$CXX" $DEFAULT_CFLAGS $extra_cflags -std=c++11 \
        -DASAP_MAGIC_FILE_PATH="\"$WORK_DIR/target-${name}-build/magic/magic\"" \
        -I "$WORK_DIR/target-${name}-build/src" \
        -c "$SCRIPT_DIR/ff-file.cc"
      "$CXX" $DEFAULT_LDFLAGS $extra_ldflags ff-file.o \
        "$WORK_DIR/target-${name}-build/src/.libs/libmagic.a" \
        "$LIBFUZZER_A" -o fuzzer
      cd ..
    )
  fi
}
