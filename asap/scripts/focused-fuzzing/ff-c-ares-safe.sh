# Like c-ares-CVE-2016-5180, but using a patched version.

. "$SCRIPT_DIR/ff-c-ares-CVE-2016-5180.sh"

init_target() {
  if ! [ -d c-ares ]; then
    get_git_revision https://github.com/c-ares/c-ares.git 7691f773af79bf75a62d1863fd0f13ebf9dc51b1 c-ares
    (cd c-ares && ./buildconf)
  fi
}
