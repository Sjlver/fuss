#!/bin/bash

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )"; pwd )"

# Size, in KB
size=1024
while [ $# -gt 0 ]; do
  case "$1" in
    "--size")
      size="$2"; shift; shift;;
    *)
      echo "Unknown parameter: $1" >&2
      echo "usage: benchmark_pbzip2.sh [--size <size in kb>]" >&2
      exit 1;;
  esac
done

# Create a file containing of random data, the pbzip2 source code, and some
# zeros. Concatenate it to itself until it has the right size.
tempdir=$( mktemp -d pbzip2_temp.XXXXXX )
dd if=/dev/urandom of="$tempdir/input_random.dat" bs=100K count=1 2>/dev/null
cat "$tempdir/input_random.dat" "pbzip2.cpp" > "$tempdir/input.dat"
truncate --size="300K" "$tempdir/input.dat"
while [ "$( stat --format="%s" "$tempdir/input.dat" )" -lt "$(( $size * 1024 ))" ]; do
  mv "$tempdir/input.dat" "$tempdir/half_input.dat"
  cat "$tempdir/half_input.dat" "$tempdir/half_input.dat" > "$tempdir/input.dat"
done
truncate --size="${size}K" "$tempdir/input.dat"
cp "$tempdir/input.dat" "$tempdir/input.orig"

compress_time="$( /usr/bin/time -f "%e" ./pbzip2 "$tempdir/input.dat" 2>&1 )"
decompress_time="$( /usr/bin/time -f "%e" ./pbzip2 --decompress "$tempdir/input.dat.bz2" 2>&1 )"
total_time="$( python -c "print $compress_time + $decompress_time" )"

cmp "$tempdir/input.dat" "$tempdir/input.orig"
rm -r "$tempdir"

echo "$total_time $compress_time $decompress_time"
