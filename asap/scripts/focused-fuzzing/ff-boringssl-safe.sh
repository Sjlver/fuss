# From https://github.com/google/fuzzer-test-suite/tree/master/boringssl-2016-02-12

. "$SCRIPT_DIR/ff-boringssl-2016-02-12.sh"

# Init boringssl source code
init_target() {
  if ! [ -d boringssl-src ]; then
    git clone https://github.com/google/boringssl.git boringssl-src
    (
      cd boringssl-src
      git checkout c0263ab4c85d9b0f4b5d667a857a0ad509ce6a9b
      git am "$SCRIPT_DIR/ff-boringssl-safe.patch"
    )
  fi
}
