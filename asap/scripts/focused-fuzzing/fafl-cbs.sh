cb_name="$1"
if [ -z "$cb_name" ]; then
  echo "usage: fafl.sh <command> cbs <cb_name>" >&2
  echo "no cb_name given" >&2
  exit 1
fi
shift

init_target() {
  if ! [ -d cb-multios ]; then
    git clone git@github.com:Sjlver/cb-multios.git
  fi
}

# Build unrtf with the given `name` and flags.
build_target() {
  local name="$1"
  local extra_cflags="$2"
  local extra_ldflags="$3"

  if ! [ -d "cb-multios/original-challenges/$cb_name" ]; then
    echo "Could not find CB named \"$cb_name\". Available CBs:" >&2
    ls cb-multios/original-challenges >&2
    exit 1
  fi

  if ! [ -x "target-${name}-build/target" ]; then
    rsync -a cb-multios/ --exclude .git "target-${name}-build"
    cd "target-${name}-build"
    AFL_CC="$AFL_CC" AFL_CXX="$AFL_CXX" CC="$CC" CXX="$CXX" \
      CFLAGS="$DEFAULT_CFLAGS $extra_cflags" LDFLAGS="$extra_ldflags" ./build.sh "$cb_name" \
      2>&1 | tee "../logs/build-${name}.log"

    mkdir CORPUS
    echo "init" > CORPUS/init

    ln -s "processed-challenges/$cb_name/bin/$cb_name" target
    cd ..
  fi
}
