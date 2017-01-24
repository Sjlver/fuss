#!/usr/bin/env python3

"""Plots coverage-vs-time graphs, from tsv data."""

import argparse
import re
import sys
import numpy as np
import matplotlib.pyplot as plt


def main():
    parser = argparse.ArgumentParser(description="Compute coverage vs time from LibFuzzer logs")
    parser.add_argument("--data", help="Data file", action="append", required=True)
    parser.add_argument("--format", help="Format to use for plotting", action="append", required=True)
    parser.add_argument("--legend", help="Description in the legend", action="append", required=True)
    parser.add_argument("--output", help="Output file to save plot to")
    args = parser.parse_args()

    assert len(args.data) == len(args.format) == len(args.legend)

    data = []
    for data_file in args.data:
        with open(data_file) as f:
            header = f.readline()
            assert re.match(r'^time\s+coverage\s+ft\s+units\s+execs\s*$', header)
            data.append(np.loadtxt(f))

    plt.title('Coverage and executions vs time')
    plt.subplot(2, 1, 1)
    for i, series in enumerate(data):
        plt.plot(series[:, 0], series[:, 1], args.format[i], alpha=0.3, linewidth=2)
    plt.ylabel('Coverage [basic blocks]')

    plt.subplot(2, 1, 2)
    legends = set()
    for i, series in enumerate(data):
        legend = args.legend[i] if args.legend[i] not in legends else None
        legends.add(legend)
        plt.plot(series[:, 0], series[:, 4], args.format[i], label=legend, alpha=0.3, linewidth=2)
    plt.xlabel('Time [seconds]')
    plt.ylabel('Executions')
    plt.legend(loc='upper left')

    if args.output:
        plt.savefig(args.output)
    else:
        plt.show()


if __name__ == '__main__':
    main()
