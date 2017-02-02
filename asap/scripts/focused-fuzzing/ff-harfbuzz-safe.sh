. "$SCRIPT_DIR/ff-harfbuzz-1.3.2.sh"

init_target() {
  if ! [ -d harfbuzz-src ]; then
    git clone https://github.com/behdad/harfbuzz.git harfbuzz-src
    (
      cd harfbuzz-src
      git checkout b843c6d8b66c2833cd35407ee494546465e6d775
      ./autogen.sh
      make distclean
    )
  fi
}
