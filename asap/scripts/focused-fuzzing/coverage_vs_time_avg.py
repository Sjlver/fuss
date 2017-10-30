#!/usr/bin/env python3

"""Plots coverage-vs-time graphs, from tsv data.

   This version averages multiple data sets.
"""

import argparse
import re
import sys
import numpy as np
import matplotlib.pyplot as plt

COLORS = {
    'FUSS': '#1f77b4',
    'Baseline': '#ff7f0e',
}

LINESTYLES = {
    'FUSS': 'solid',
    'Baseline': 'dotted',
}

def bootstrap_ci(d, f):
    """A simple bootstrap confidence interval."""
    estimate = f(d, axis=0)
    ii = np.random.randint(0, len(d), size=(1000, len(d)))
    samples = d[ii]
    sample_estimates = f(samples, axis=1)
    percentiles = np.percentile(sample_estimates, [2.5, 97.5], axis=0)
    return percentiles[0], estimate, percentiles[1]

def main():
    parser = argparse.ArgumentParser(description="Plot coverage vs time from LibFuzzer logs")
    parser.add_argument("--data", help="Data file", action="append", required=True)
    parser.add_argument("--legend", help="Description in the legend", action="append", required=True)
    parser.add_argument("--benchmark", help="Name of the benchmark")
    parser.add_argument("--output", help="Output file to save plot to")
    args = parser.parse_args()

    assert len(args.data) == len(args.legend)

    data = []
    for data_file in args.data:
        with open(data_file) as f:
            header = f.readline()
            if re.match(r'^time\s+coverage\s+ft\s+units\s+execs\s*$', header):
                data.append(np.loadtxt(f))
            else:
                print("warning: skipping {}, header check failed.".format(data_file), file=sys.stderr)

    fig = plt.figure()

    for version in sorted(set(args.legend)):
        times = np.array([ d[:, 0] for i, d in enumerate(data) if args.legend[i] == version ])
        coverage = np.array([ d[:, 1] for i, d in enumerate(data) if args.legend[i] == version ])
        xlim = (0, round(float(np.max(times)) / 3600.0) * 3600)

        # Normalize the data for the same x coords
        xs = np.linspace(xlim[0], xlim[1], num=50)
        ys = np.array([
            np.interp(xs, times[i, :], coverage[i, :]) for i in range(len(times)) ])
        lower, means, upper = bootstrap_ci(ys, np.mean)

        plt.fill_between(xs, lower, upper, color=COLORS[version], alpha=0.3)
        plt.plot(xs, means, linewidth=3, color=COLORS[version], linestyle=LINESTYLES[version], label=version)
        plt.plot(xs, lower, linewidth=1, color=COLORS[version], alpha=0.7)
        plt.plot(xs, upper, linewidth=1, color=COLORS[version], alpha=0.7)

    hours = list(range(round(xlim[1] / 3600) + 1))

    legend = plt.legend(loc='lower right', ncol=2, title=args.benchmark)
    title = legend.get_title()
    title.set_weight('bold')
    plt.ylabel('Coverage\n[blocks]')
    plt.xticks([h * 3600 for h in hours], ['{}h'.format(h) for h in hours])
    plt.grid(True)
    plt.xlim(xlim)

    fig.set_size_inches(5.5, 1.6)
    fig.subplots_adjust(left=0.17, right=0.98, bottom=0.15, top=0.95)
    if args.output:
        plt.savefig(args.output)
    else:
        plt.show()


if __name__ == '__main__':
    main()
