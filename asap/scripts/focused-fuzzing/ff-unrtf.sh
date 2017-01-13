init_target() {
  if ! [ -d unrtf-0.21.9 ]; then
    wget https://www.gnu.org/software/unrtf/unrtf-0.21.9.tar.gz
    tar xf unrtf-0.21.9.tar.gz

    cd unrtf-0.21.9
    patch -p1 < "$SCRIPT_DIR/ff-unrtf.patch"
    make distclean

    cd config
    most_recent_automake="$(ls -d1 /usr/share/automake-* | tail -n1)"
    for i in *; do rm "$i"; ln -s "$most_recent_automake/$i"; done
    cd ../..
  fi
}

# Build unrtf with the given `name` and flags.
build_target_and_fuzzer() {
  local name="$1"
  local extra_cflags="$2"
  local extra_ldflags="$3"

  if ! [ -x "target-${name}-build/fuzzer" ]; then
    mkdir -p "target-${name}-build"
    cd "target-${name}-build"
    CC="$CC" CXX="$CXX" CFLAGS="$DEFAULT_CFLAGS $extra_cflags" LDFLAGS="$DEFAULT_LDFLAGS $extra_ldflags" ../unrtf-0.21.9/configure \
      --disable-silent-rules --disable-dependency-tracking
    make -j $N_CORES V=1 2>&1 | tee "../logs/build-${name}.log"

    "$CXX" $DEFAULT_CFLAGS $extra_cflags -std=c++11 \
      -DHAVE_CONFIG_H -I src -I"$WORK_DIR/unrtf-0.21.9/src" \
      -c "$SCRIPT_DIR/ff-unrtf.cc"
    "$CXX" $DEFAULT_LDFLAGS $extra_ldflags ff-unrtf.o $(ls -1 src/*.o | grep -v main.o) \
      "$LIBFUZZER_A" -o fuzzer
    cd ..
  fi
}
