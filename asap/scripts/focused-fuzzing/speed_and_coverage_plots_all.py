#!/usr/bin/env python3

"""Plots speed and coverage for multiple benchmarks and versions."""

import argparse
import re
import sys
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt

DATA_FILE_RE = re.compile(r'(?:.*/)?([^/]+)/logs/.*\.log')

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

def load_data(data_files):
    data = []
    for data_file in data_files:
        m = DATA_FILE_RE.match(data_file)
        if not m:
            raise ValueError("Unexpected data file name: " + data_file)
        cur_data = pd.read_table(data_file, sep=r'\s*\t\s*', engine='python')
        cur_data['benchmark'] = m.group(1)
        data.append(cur_data)
    data = pd.concat(data, ignore_index=True)
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



def main():
    parser = argparse.ArgumentParser(description="Plots graphs for speed and coverage.")
    parser.add_argument("--output", help="Output file to save plot to")
    parser.add_argument("data", nargs="+")
    args = parser.parse_args()

    data = load_data(args.data)
    data['name'] = data['name'].map(lambda n: re.sub('-\d\d$', '', n))
    data['benchmark'] = data['benchmark'].map(BENCHMARK_NAMES_MAP)

    grouped = data.groupby(['benchmark', 'name'])
    medians = grouped['execs'].apply(lambda s: bootstrap_ci(s, np.median))
    medians = medians.groupby(level='benchmark').transform(lambda x: x / x.loc[:, 'noinstr', 'estimate'])

    fig, ax = plt.subplots()
    benchmarks = medians.index.levels[0]
    versions = ['asan', 'asan-fperf', 'tpcg', 'tpcg-fperf', 'noinstr']
    bar_width = 1.0 / (len(versions) + 2)
    xs = np.arange(len(benchmarks))
    
    for i, version in enumerate(versions):
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
    plt.xticks(xs + (len(versions) / 2 + 1) * bar_width, benchmarks)
    
    fig.set_size_inches(15, 5)
    if args.output:
        plt.savefig(args.output)
    else:
        plt.show()
    

if __name__ == '__main__':
    main()
