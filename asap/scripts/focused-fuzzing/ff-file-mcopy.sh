. "$SCRIPT_DIR/ff-file.sh"

# This uses a buggy version of file, with a 1-byte overflow in mcopy. This is complex to find, we've seen it rarely.
export OPTIMAL_N_CORES=40
export CRASH_REGEXP="AddressSanitizer: heap-buffer-overflow"

# Initialize the "file" source code
init_target() {
  if ! [ -d file ]; then
    git clone https://github.com/file/file.git
    (cd file && \
      git checkout 0e93a47b7feaee1d3a0f1b14e40f0ead17d8ccd4 && \
      git revert --no-edit -X ours 2e3e8a716151a87c2301a49e0e37b0b126a26994)
    (cd file && autoreconf -f -i)
  fi
}
