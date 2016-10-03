init_target() {
  if ! [ -d unrtf-0.21.9 ]; then
    [ -f unrtf-0.21.9.tar.gz ] || wget https://www.gnu.org/software/unrtf/unrtf-0.21.9.tar.gz
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
build_target() {
  local name="$1"
  local extra_cflags="$2"
  local extra_ldflags="$3"

  if ! [ -d "target-${name}-build" ]; then
    mkdir "target-${name}-build"
    cd "target-${name}-build"
    AFL_CC="$AFL_CC" AFL_CXX="$AFL_CXX" CC="$CC" CXX="$CXX" \
      CFLAGS="$DEFAULT_CFLAGS $extra_cflags" LDFLAGS="$extra_ldflags" ../unrtf-0.21.9/configure \
      --disable-silent-rules --disable-dependency-tracking
    make -j $N_CORES V=1 pkgdatadir="$WORK_DIR/unrtf-0.21.9/outputs" 2>&1 | tee "../logs/build-${name}.log"

    ln -s src/unrtf target

    mkdir CORPUS
    cp ../unrtf-0.21.9/tests/accents.rtf CORPUS/

    cd ..
  fi
}
