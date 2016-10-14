#!/usr/bin/env python3

"""Plots coverage-vs-time graphs, from tsv data."""

import argparse
import re
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
            assert re.match(r'^time\s+coverage\s+execs\s*$', header)
            data.append(np.loadtxt(f))

    # Compute the median for each time.
    # TO BE CONTINUED...


    plt.title('Coverage and executions vs time')
    for i, series in enumerate(data):
        plt.plot(series[:, 1], series[:, 2], args.format[i], alpha=0.3, linewidth=2)
    plt.xlabel('Coverage [basic blocks]')
    plt.ylabel('Time [seconds]')

    if args.output:
        plt.savefig(args.output)
    else:
        plt.show()


if __name__ == '__main__':
    main()
