#!/bin/bash

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )"; pwd )"
source "$SCRIPT_DIR/../python/build_utils.sh"

ASAN_CFLAGS="-fsanitize=address"
ASAN_LDFLAGS="-fsanitize=address"

UBSAN_CFLAGS="-fsanitize=undefined -fno-sanitize=shift -fno-sanitize-recover=all"
UBSAN_LDFLAGS="-fsanitize=undefined"

fetch_openssh() {
    if [ -d openssh ]; then
        cd openssh && update_repository && cd -
    else
        git clone git://anongit.mindrot.org/openssh.git
    fi
}

build_openssh() {
    make clean
    make all -j "$N_JOBS" all
}

configure_and_build_openssh() {
    local extra_cflags="$1"
    local ldflags="$2"
    rsync -a ../openssh/ .
    autoreconf
    ./configure \
        --without-privsep-user --without-privsep-path \
        CC="$(which asap-clang)" \
        CFLAGS="-Wall -Winline -O3 -g -D_FILE_OFFSET_BITS=64 $extra_cflags" \
        LDFLAGS="$ldflags"

    build_openssh "$@"
}

test_openssh() {
    build_openssh
    env TEST_SHELL=/bin/bash TEST_SSH_LOGFILE=/tmp/sshd.log \
        TEST_COMBASE=`pwd` TEST_SSH_TRACE=yes make tests \
        LTESTS=""
}

fetch_openssh

build_asap_initial "openssh" "baseline" "configure_and_build_openssh" "" ""
build_asap_initial "openssh" "asan"     "configure_and_build_openssh" "$ASAN_CFLAGS" "$ASAN_LDFLAGS"
build_asap_initial "openssh" "ubsan"    "configure_and_build_openssh" "$UBSAN_CFLAGS" "$UBSAN_LDFLAGS"

for tool in "asan" "ubsan"; do
    build_asap_coverage  "openssh" "$tool" "test_openssh"
    build_asap_optimized "openssh" "$tool" "s0000" "-asap-sanity-level=0.000" "build_openssh"
    build_asap_optimized "openssh" "$tool" "c0010" "-asap-cost-level=0.010"   "build_openssh"
    build_asap_optimized "openssh" "$tool" "c0040" "-asap-cost-level=0.040"   "build_openssh"
    build_asap_optimized "openssh" "$tool" "c1000" "-asap-cost-level=1.000"   "build_openssh"
done
