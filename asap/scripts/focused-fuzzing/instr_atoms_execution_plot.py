#!/usr/bin/env python3

"""Creates a cumulative distribution plot for instrumentation atom executions."""

import argparse
import re
import os
import sys
import fnmatch
import numpy as np
import matplotlib.pyplot as plt

ALL_TIME_COUNTER_RE = re.compile(r'^AllTimeCounter: (0x[0-9a-fA-F]+) (\d+) (\d+)',re.MULTILINE)
patterns = ["fuzzer-asan-fperf*.log", "fuzzer-asan-prof*.log", "fuzzer-tpcg-prof*.log", "fuzzer-tpcg-fperf*.log"]

def gini(list_of_values):
    n = len(list_of_values)
    sorted_list = sorted(list_of_values)

    #Compute cumulative sum
    cs = [0]
    for i in range(n):
        cs.append(sum(sorted_list[0:(i + 1)]))

    norm = [float(i)/sum(cs) for i in cs]
    return norm

def find_file_by_pattern(d, pattern):
    for f in os.listdir(d):
        if fnmatch.fnmatch(f, pattern):
            return f


def main():
    parser = argparse.ArgumentParser(description="Plots graphs for instrumentation atoms distribution.")
    parser.add_argument("--output", help="Output file to save plot to")
    parser.add_argument("--benchmark", help="Name of the benchmark", required=True)
    parser.add_argument("--data", help="Input file", required=True)
    args = parser.parse_args()

    norms = []
    for p in patterns:
        fname = find_file_by_pattern(args.data, p)
        f = open(os.path.join(args.data, fname))
        data = f.read()
        all_time_counters = ALL_TIME_COUNTER_RE.findall(data)

        ginis = [float(x[-1]) for x in all_time_counters]

        vs = np.array(ginis)
        vs.sort()
        cs = vs.cumsum()
        norm = cs / cs.max()
        norms.append(norm)

    fig = plt.figure()
    axe = fig.add_subplot(111)
    for n, p in zip(norms, patterns):
        plt.plot(n, label=p)
    axe.legend(loc=2)
    plt.title(args.benchmark)
    if args.output:
        plt.savefig(args.output)
    else:
        plt.show()


if __name__ == '__main__':
    main()
