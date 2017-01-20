#!/usr/bin/env python3

"""Computes statistics from AllTimeCounter values.
"""

import argparse
import re
import sys

# AllTimeCounter: 0x51dcbe 123 2
ALLTIMECOUNTER_RE = re.compile(r'^AllTimeCounter: (0x[0-9a-f]+) .* (\d+)$')

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


def get_threshold_for_costlevel(vs, c):
    """Computes a threshold that would preserve a fraction `c` of the total
       cost.
    """

    vs = sorted(vs)
    total_cost = sum(vs)
    target_cost = c * total_cost
    preserved_cost = 0
    for v in vs:
        preserved_cost += v
        if preserved_cost >= target_cost:
            return v + 1

    assert False, "No threshold found for c={}".format(c)


def main():
    arg_parser = argparse.ArgumentParser()
    arg_parser.add_argument("--log", required=True)
    arg_parser.add_argument("--costlevel", type=float, required=True)
    args = arg_parser.parse_args(sys.argv[1:])

    with open(args.log) as log_file:
        log = log_file.read()
    all_pcs = extract_pcs_and_costs(log)

    print(get_threshold_for_costlevel(all_pcs.values(), args.costlevel))


if __name__ == '__main__':
    main()
