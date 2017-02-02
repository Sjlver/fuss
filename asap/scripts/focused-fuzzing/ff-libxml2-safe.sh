. "$SCRIPT_DIR/ff-libxml2.sh"

init_target() {
  if ! [ -d libxml2-src ]; then
    git clone git://git.gnome.org/libxml2 libxml2-src
    (
      cd libxml2-src
      git checkout 56a6e1aebed937941d2960cc5012665a5ca0115e
      git am "$SCRIPT_DIR/ff-libxml2.patch"
      autoreconf -fiv
    )
  fi
}
