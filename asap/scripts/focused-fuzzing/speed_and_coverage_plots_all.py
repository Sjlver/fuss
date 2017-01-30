#!/usr/bin/env python3

"""Plots speed and coverage for multiple benchmarks and versions."""

import argparse
import re
import sys
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt

DATA_FILE_RE = re.compile(r'(?:.*/)?([^/]+)/logs/.*-(\d+)\.log')

BENCHMARK_NAMES_MAP = {
    'ff-boringssl-2016-02-12': 'boringssl',
    'ff-c-ares-safe': 'c-ares',
    'ff-file': 'file',
    'ff-harfbuzz-1.3.2': 'harfbuzz',
    'ff-http-parser': 'http-parser',
    'ff-libxml2': 'libxml2',
    'ff-openssl-1.0.2e': 'openssl',
    'ff-pcre': 'pcre',
    'ff-re2-2014-12-09': 're2',
    'ff-sqlite-2016-11-14': 'sqlite',
    'ff-woff2-safe': 'woff2',
}

CMAP = plt.get_cmap('inferno')
COLORS = {
        'asan': CMAP(0.0),
        'asan-fperf': CMAP(0.2),
        'tpcg': CMAP(0.5),
        'tpcg-fperf': CMAP(0.6),
        'tpcg-fprec': CMAP(0.7),
        'noinstr': CMAP(1.0),
}

VERSIONS = ['asan', 'asan-fperf', 'tpcg', 'tpcg-fperf', 'noinstr']

def load_data(data_files):
    data = []
    for data_file in data_files:
        m = DATA_FILE_RE.match(data_file)
        if not m:
            raise ValueError("Unexpected data file name: " + data_file)
        cur_data = pd.read_table(data_file, sep=r'\s*\t\s*', engine='python')
        cur_data['benchmark'] = BENCHMARK_NAMES_MAP[m.group(1)]
        cur_data['name'] = cur_data['name'].map(lambda n: re.sub('-\d+$', '', n))
        cur_data['run_id'] = int(m.group(2))
        cur_data.set_index(['benchmark', 'name', 'run_id'], inplace=True)
        cur_data['execs'] = normalize_execs(cur_data['execs'])
        cur_data['actual_cov'] = normalize_coverage(cur_data)
        data.append(cur_data)
    data = pd.concat(data)
    return data

def bootstrap_ci(s, f, confidence=0.95):
    """A simple computation of a bootstrap confidence interval.

    Takes a series `s` and a function `f`. Returns a Series containing
    the estimate and its lower/upper bounds.
    """

    s = np.array(s)
    estimate = f(s)
    ii = np.random.randint(0, len(s), size=(10000, len(s)))
    bootstrapped_values = f(s[ii], axis=1)
    lower, upper = np.percentile(bootstrapped_values,
            ((1 - confidence) * 50, 100 - (1 - confidence) * 50))
    return pd.Series({'estimate': estimate, 'lower': lower, 'upper': upper})

def normalize_execs(execs):
    """Normalize executions; scale them to the noinstr version."""
    return execs / float(execs.loc[:, 'noinstr', :])

def normalize_coverage(cov):
    """Compute coverage deltas"""

    return cov['actual_cov'] - cov['init_cov']

def normalize_aggregated_coverage(cov):
    """Normalize coverage; scale them relative to no-fuss version."""

    factors = {}
    for version in cov.index.levels[1]:
        base = re.sub(r'-.*', '', version)
        base = base.replace('noinstr', 'tpcg')
        factors[version] = float(cov.loc[:, base, 'estimate'])
    factors = pd.Series(factors)
    cov = cov.div(factors, level=1)
    return cov

def main():
    parser = argparse.ArgumentParser(description="Plots graphs for speed and coverage.")
    parser.add_argument("--output-execs", help="Output file to save execs plot to")
    parser.add_argument("--output-cov", help="Output file to save cov plot to")
    parser.add_argument("data", nargs="+")
    args = parser.parse_args()

    data = load_data(args.data)

    grouped = data.groupby(level=['benchmark', 'name'])
    benchmarks = data.index.levels[0]
    xs = np.arange(len(benchmarks))
    bar_width = 1.0 / (len(VERSIONS) + 2)

    # Plot median executions
    medians = grouped['execs'].apply(lambda s: bootstrap_ci(s, np.median))

    fig = plt.figure()
    for i, version in enumerate(VERSIONS):
        plt.bar(xs + (i + 1) * bar_width,
                medians.loc[:, version, 'estimate'],
                bar_width,
                color=COLORS[version],
                yerr=(medians.loc[:, version, 'estimate'] - medians.loc[:, version, 'lower'],
                    medians.loc[:, version, 'upper'] - medians.loc[:, version, 'estimate']),
                label=version)

    plt.xlabel("Benchmark")
    plt.xlim(0, len(benchmarks))
    plt.ylabel("Executions (rel. to noinstr)")
    plt.xticks(xs + (len(VERSIONS) / 2 + 1) * bar_width, benchmarks)
    plt.grid(True, axis='y')

    plt.legend(loc='upper center', bbox_to_anchor=(0.5, 1.15), ncol=len(VERSIONS))
    
    fig.set_size_inches(12, 4)
    if args.output_execs:
        plt.savefig(args.output_execs)
    else:
        plt.show()

    # A similar plot for coverage increase instead of executions
    medians = grouped['actual_cov'].apply(lambda s: bootstrap_ci(s, np.median))
    medians = medians.groupby(level='benchmark').transform(normalize_aggregated_coverage)

    fig = plt.figure()
    for i, version in enumerate(VERSIONS):
        plt.bar(xs + (i + 1) * bar_width,
                medians.loc[:, version, 'estimate'],
                bar_width,
                color=COLORS[version],
                yerr=(medians.loc[:, version, 'estimate'] - medians.loc[:, version, 'lower'],
                    medians.loc[:, version, 'upper'] - medians.loc[:, version, 'estimate']),
                label=version)

    plt.xlabel("Benchmark")
    plt.xlim(0, len(benchmarks))
    plt.ylabel("Coverage (BB, rel. to baseline)")
    plt.xticks(xs + (len(VERSIONS) / 2 + 1) * bar_width, benchmarks)
    plt.grid(True, axis='y')
    
    fig.set_size_inches(12, 4)
    if args.output_cov:
        plt.savefig(args.output_cov)
    else:
        plt.show()
    

if __name__ == '__main__':
    main()
