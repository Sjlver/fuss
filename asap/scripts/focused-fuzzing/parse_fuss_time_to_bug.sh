#!/bin/bash

# Extracts the results from fuss_time_to_bug.sh

set -e
set -o pipefail

logs=$(ls */logs/do_*.log)

for log in $logs; do
  benchmark="$(dirname "$(dirname "$log")")"
  benchmark="${benchmark#ff-}"

  version_run="$(basename "$log" .log)"
  version_run="${version_run#do_}"
  version="${version_run%-[0-9][0-9]}"

  if grep -q "SUMMARY: " "$log"; then
    description="$(grep "SUMMARY: " "$log" | head -n1 || true)"
    description="${description#SUMMARY: }"
  else
    description="na"
  fi

  coverage_file="ff-${benchmark}/logs/do_${version_run}-coverage.tsv"

  if [ -f "$coverage_file" ]; then
    time_to_bug="$(tail -n1 "$coverage_file" | awk '{print $1}')"
  else
    time_to_bug="na"
  fi

  printf "%s\t%s\t%s\t%s\n" "$benchmark" "$description" "$version" "$time_to_bug"
done
