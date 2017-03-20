. "$SCRIPT_DIR/ff-file.sh"

# This uses a buggy version of file, with a 1-byte overflow in mcopy. This is
# complex to find, we've seen it rarely.
# We've also seen segmentation faults during fuzzing. These happen frequently,
# but are apparently triggered by a combination of testcases... It looks like
# we can't reproduce them when re-playing corpora.
# They also don't affect all fuzzers in a run.
export OPTIMAL_N_CORES=40
export CRASH_REGEXP="AddressSanitizer: heap-buffer-overflow"

# Initialize the "file" source code
init_target() {
  if ! [ -d file ]; then
    git clone https://github.com/file/file.git
    (cd file && \
      git checkout a6d1be7348c5decb6bdf1d35b75aed8e2652117f && \
      git revert --no-edit -X ours 2ff17368a162a4f5c3013737414ede9acd3f85d3)
    (cd file && autoreconf -f -i)
  fi
}
