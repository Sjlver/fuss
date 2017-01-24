# From https://github.com/google/fuzzer-test-suite/tree/master/openssl-1.0.2d

# Fixed version of ff-openssl-1.0.2d; should not crash.

. "$SCRIPT_DIR/ff-openssl-1.0.2d.sh"

init_target() {
  if ! [ -d openssl ]; then
    get_git_revision https://github.com/openssl/openssl.git OpenSSL_1_0_2e openssl
  fi
}
