# From https://github.com/google/fuzzer-test-suite/tree/master/woff2-2016-05-06

# Safe version of ff-woff2-2016-05-06

. "$SCRIPT_DIR/ff-woff2-2016-05-06.sh"

init_target() {
  get_git_revision https://github.com/google/woff2.git \
    afbecce5ff16faf92ce637eab991810f5b66f803 woff2
  get_git_revision https://github.com/google/brotli.git \
    3a9032ba8733532a6cd6727970bade7f7c0e2f52 brotli
  get_git_revision https://github.com/FontFaceKit/roboto.git \
    0e41bf923e2599d651084eece345701e55a8bfde roboto
}
