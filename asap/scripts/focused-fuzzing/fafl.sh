#!/bin/bash

set -e
set -o pipefail

SCRIPT_DIR="$( dirname "$( readlink -f "${BASH_SOURCE[0]}" )" )"
. "$SCRIPT_DIR/fafl-common.sh"

if [ $# -lt 1 ]; then
  usage >&2
  echo >&2
  echo "No command given." >&2
  exit 1
fi

command="$1"
shift

# For commands that have a target, load the extra file
case "$command" in
  "build"|"fuss"|"baseline"|"explore")
    if [ $# -lt 1 ]; then
      usage >&2
      echo >&2
      echo "No target given." >&2
      exit 1
    fi
    target="$1"
    shift

    . "$SCRIPT_DIR/fafl-${target}.sh"
    ;;
esac

# Run the actual command
case "$command" in
  "clean")     do_clean ;;
  "help")      usage; exit 0 ;;
  "build")     do_build "$@" ;;
  "fuss")      do_fuss "$@" ;;
  "baseline")  do_baseline "$@" ;;
  "explore")   do_explore "$@" ;;
  *)
    usage >&2
    echo >&2
    echo "Unknown command \"$command\"" >&2 ;;
esac
