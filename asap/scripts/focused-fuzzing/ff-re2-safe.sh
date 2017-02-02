. "$SCRIPT_DIR/ff-re2-2014-12-09.sh"

init_target() {
  get_git_revision https://github.com/google/re2.git 09fc9ce11a634150a22d2a477ff7ba8866398a7a re2
}
