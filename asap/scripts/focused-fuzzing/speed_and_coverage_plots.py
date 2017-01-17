#!/usr/bin/env python3

"""Plots graphs for speed and coverage obtained by various fuzzer versions."""

import argparse
import re
import sys
import numpy as np
import matplotlib.pyplot as plt


def main():
    parser = argparse.ArgumentParser(description="Plots graphs for speed and coverage.")
    parser.add_argument("--output", help="Output file to save plot to")
    parser.add_argument("--benchmark", help="Name of the benchmark", required=True)
    parser.add_argument("data", nargs="+")
    args = parser.parse_args()

    data = []
    for data_file in args.data:
        data.append(np.genfromtxt(data_file, dtype=None, names=True))
    data = np.stack(data)

    names = data[0, :]['name']
    names = [ re.sub(r'-\d\d$', '', n.decode()) for n in names ]
    names = [ n.replace('asan-', '') for n in names ]
    names = [ n.replace('noinstrumentation', 'noinstr') for n in names ]
    names = [ re.sub(r'asap-\d\d$', 'asap-profile', n) for n in names ]
    names = [ n.replace('asapcoverage', 'asap-precise') for n in names ]
    execs_per_sec = data['execs_per_sec'].astype(float)
    cov = data['actual_cov']

    fig, axes = plt.subplots(nrows=2, ncols=1)
    fig.suptitle('Execution speed and coverage: {}'.format(args.benchmark))
    axes[0].boxplot(execs_per_sec, labels=names, showmeans=True)
    axes[0].set_ylabel('Execution speed [execs/sec]')

    axes[1].boxplot(cov, labels=names, showmeans=True)
    axes[1].set_ylabel('Coverage [Basic blocks]')

    if args.output:
        plt.savefig(args.output)
    else:
        plt.show()


if __name__ == '__main__':
    main()
