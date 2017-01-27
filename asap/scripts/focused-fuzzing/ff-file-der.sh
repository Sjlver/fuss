. "$SCRIPT_DIR/ff-file.sh"

# This uses a buggy version of file, with a 1-byte overflow when processing
# "der" rules. Crashes fairly quickly.
export OPTIMAL_N_CORES=1
export CRASH_REGEXP="AddressSanitizer: heap-buffer-overflow|AddressSanitizer: SEGV"

# Initialize the "file" source code
init_target() {
  if ! [ -d file ]; then
    git clone https://github.com/file/file.git
    (cd file && git checkout fe5879185744b60613000c83b7f564ff4d88ab5a)
    (cd file && autoreconf -f -i)
  fi
}
