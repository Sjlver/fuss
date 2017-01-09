#!/usr/bin/env python3

"""Computes a set of instrumentation atoms required for full corpus coverage.

Given a corpus, this script first records the instrumentation atoms covered by
each testcase. Second, it computes an approximate set coverage solution to find
a set of atoms with low cost that would be enough to achieve full coverage.
"""

import argparse
import os
import re
import subprocess
import sys

# AllTimeCounter: 0x51dcbe in function /path/file.c:638 2
ALLTIMECOUNTER_RE = re.compile(r'^AllTimeCounter: (0x[0-9a-f]+) .* (\d+)$')

def covered_pcs(fuzzer, testcase):
    """Computes the set of PCs covered by a given testcase."""

    output = subprocess.check_output([fuzzer, '-print_final_stats=1', testcase], stderr=subprocess.STDOUT)
    output = output.decode()
    return extract_pcs_and_costs(output)


def extract_pcs_and_costs(log):
    """Extracts PCs and their cost (i.e., counter values) from a fuzzer log."""

    pcs = {}
    for line in log.splitlines():
        m = ALLTIMECOUNTER_RE.match(line)
        if m:
            pc = int(m.group(1), base=16)
            counter = int(m.group(2))
            pcs[pc] = pcs.get(pc, 0) + counter

    return pcs


def cheap_cover(complete, parts):
    """Computes a low-cost set cover of `complete` using `parts`.
    
    `complete` is a dictionary mapping from values to their cost.
    `parts` is a list of submaps of `complete`.
    """

    # This uses a cheap greedy algorithm. First, we order the values by
    # increasing cost. On each value that we haven't covered yet, we choose the
    # part that covers the highest remaining cost.
    cover = set()
    uncovered = set(complete.keys())
    def remaining_cost(p):
        return sum(complete[x] for x in p if x in uncovered)

    while uncovered:
        v = min(uncovered, key=lambda x: complete[x])
        available_parts = [p for p in parts if v in p]
        available_parts.sort(key=remaining_cost)
        assert available_parts, "Value {} not covered by any part?".format(v)
        cover.add(v)
        uncovered.difference_update(available_parts[-1].keys())

    return cover


def main():
    arg_parser = argparse.ArgumentParser()
    arg_parser.add_argument("--fuzzer", required=True)
    arg_parser.add_argument("--corpus", required=True)
    arg_parser.add_argument("--log", required=True)
    args = arg_parser.parse_args(sys.argv[1:])

    with open(args.log) as log_file:
        log = log_file.read()
    all_pcs = extract_pcs_and_costs(log)

    testcase_pcs = []
    for testcase in os.listdir(args.corpus):
        testcase_path = os.path.join(args.corpus, testcase)
        testcase_pcs.append(covered_pcs(args.fuzzer, testcase_path))

    cover = cheap_cover(all_pcs, testcase_pcs)
    for pc in sorted(all_pcs.keys(), key=lambda k: -all_pcs[k]):
        print("{} 0x{:x} {}".format(
            "*" if pc in cover else ".",
            pc,
            all_pcs[pc]))


if __name__ == '__main__':
    main()
