#!/bin/bash

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )"; pwd )"
source "$SCRIPT_DIR/../python/build_utils.sh"

ASAN_CFLAGS="-fsanitize=address"
ASAN_LDFLAGS="-fsanitize=address"

UBSAN_CFLAGS="-fsanitize=undefined -fno-sanitize=shift -fno-sanitize-recover=all"
UBSAN_LDFLAGS="-fsanitize=undefined"

TSAN_CFLAGS="-fsanitize=thread"
TSAN_LDFLAGS="-fsanitize=thread"


# Fix Mac machines that don't have sha256sum
if ! which sha256sum >/dev/null 2>&1; then
    sha256sum() {
        shasum -a 256 "$@"
    }
fi

fetch_pbzip2() {
    [ -d pbzip2 ] && return 0
    [ -f pbzip2-1.1.12.tar.gz ] || wget 'https://launchpad.net/pbzip2/1.1/1.1.12/+download/pbzip2-1.1.12.tar.gz'
    sha256sum --check "$SCRIPT_DIR/pbzip2-1.1.12.sha256"
    tar -xzf pbzip2-1.1.12.tar.gz
    mv pbzip2-1.1.12 pbzip2
    (
        cd pbzip2
        patch -p1 < "$SCRIPT_DIR/pbzip2_asap.patch"
    )
}

build_pbzip2() {
    local extra_cflags="$1"
    local ldflags="$2"
    make clean
    make -j "$N_JOBS" \
         CXX="$(which asap-clang++)" \
         CXXFLAGS="-O2 -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -DUSE_STACKSIZE_CUSTOMIZATION -pthread -D_POSIX_PTHREAD_SEMANTICS $extra_cflags" \
         LDFLAGS="$ldflags" \
         all
}

test_pbzip2() {
    printf "Running benchmark (10000KB file): "
    "$SCRIPT_DIR/benchmark_pbzip2.sh" --size 10000
}

configure_and_build_pbzip2() {
    rsync -a ../pbzip2/ .
    build_pbzip2 "$@"
}

build_and_test_pbzip2() {
    build_pbzip2 "$@"
    test_pbzip2
}

fetch_pbzip2

build_asap_initial "pbzip2" "baseline" "configure_and_build_pbzip2" "" ""
build_asap_initial "pbzip2" "asan"     "configure_and_build_pbzip2" "$ASAN_CFLAGS" "$ASAN_LDFLAGS"
#build_asap_initial "pbzip2" "ubsan"    "configure_and_build_pbzip2" "$UBSAN_CFLAGS" "$UBSAN_LDFLAGS"
build_asap_initial "pbzip2" "tsan"     "configure_and_build_pbzip2" "$TSAN_CFLAGS" "$TSAN_LDFLAGS"

build_asap_coverage "pbzip2" "asan"  "build_and_test_pbzip2" "$ASAN_CFLAGS" "$ASAN_LDFLAGS"
#build_asap_coverage "pbzip2" "ubsan" "build_and_test_pbzip2" "$UBSAN_CFLAGS" "$UBSAN_LDFLAGS"
build_asap_coverage "pbzip2" "tsan"  "build_and_test_pbzip2" "$TSAN_CFLAGS" "$TSAN_LDFLAGS"

#build_asap_optimized "pbzip2" "asan" "s0000" "-asap-sanity-level=0.000" "build_pbzip2" "$ASAN_CFLAGS" "$ASAN_LDFLAGS"
build_asap_optimized "pbzip2" "asan" "c0010" "-asap-cost-level=0.010"   "build_pbzip2" "$ASAN_CFLAGS" "$ASAN_LDFLAGS"
#build_asap_optimized "pbzip2" "asan" "c0040" "-asap-cost-level=0.040"   "build_pbzip2" "$ASAN_CFLAGS" "$ASAN_LDFLAGS"
#build_asap_optimized "pbzip2" "asan" "c1000" "-asap-cost-level=1.000"   "build_pbzip2" "$ASAN_CFLAGS" "$ASAN_LDFLAGS"

#build_asap_optimized "pbzip2" "ubsan" "s0000" "-asap-sanity-level=0.000" "build_pbzip2" "$UBSAN_CFLAGS" "$UBSAN_LDFLAGS"
#build_asap_optimized "pbzip2" "ubsan" "c0010" "-asap-cost-level=0.010"   "build_pbzip2" "$UBSAN_CFLAGS" "$UBSAN_LDFLAGS"
#build_asap_optimized "pbzip2" "ubsan" "c0040" "-asap-cost-level=0.040"   "build_pbzip2" "$UBSAN_CFLAGS" "$UBSAN_LDFLAGS"
#build_asap_optimized "pbzip2" "ubsan" "c1000" "-asap-cost-level=1.000"   "build_pbzip2" "$UBSAN_CFLAGS" "$UBSAN_LDFLAGS"

#build_asap_optimized "pbzip2" "tsan" "s0000" "-asap-sanity-level=0.000" "build_pbzip2" "$TSAN_CFLAGS" "$TSAN_LDFLAGS"
build_asap_optimized "pbzip2" "tsan" "c0010" "-asap-cost-level=0.010" "build_pbzip2" "$TSAN_CFLAGS" "$TSAN_LDFLAGS"
#build_asap_optimized "pbzip2" "tsan" "c0040" "-asap-cost-level=0.040" "build_pbzip2" "$TSAN_CFLAGS" "$TSAN_LDFLAGS"
#build_asap_optimized "pbzip2" "tsan" "c1000" "-asap-cost-level=1.000" "build_pbzip2" "$TSAN_CFLAGS" "$TSAN_LDFLAGS"
