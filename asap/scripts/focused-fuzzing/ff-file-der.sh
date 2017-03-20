. "$SCRIPT_DIR/ff-file.sh"

# This uses a buggy version of file, with a 1-byte overflow when processing
# "der" rules. Crashes fairly quickly.
export OPTIMAL_N_CORES=1
export CRASH_REGEXP="AddressSanitizer: heap-buffer-overflow|AddressSanitizer: SEGV"

# Initialize the "file" source code
init_target() {
  if ! [ -d file ]; then
    git clone https://github.com/file/file.git
    (cd file && git checkout 1d7ecf11937305da6b7503916778ad1071e1bb6e)
    (cd file && autoreconf -f -i)
  fi
}
