#!/usr/bin/env python3

"""Computes the number of `trace_pc_guard` calls per execution."""

import argparse
import sys
import csv
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt


VERSIONS = ['asan', 'asan-prof', 'asan-fperf', 'tpcg',
        'tpcg-fperf', 'tpcg-fprec', 'tpcg-prof', 'noinstr']

def bootstrap_ci(s, f, confidence=0.95):
    """A simple computation of a bootstrap confidence interval.

    Takes a series `s` and a function `f`. Returns a Series containing
    the estimate and its lower/upper bounds.
    !!! From speed_and_coverage_plots_all.py
    !!! TODO: refactoring
    """

    s = np.array(s)
    estimate = f(s)
    ii = np.random.randint(0, len(s), size=(10000, len(s)))
    bootstrapped_values = f(s[ii], axis=1)
    lower, upper = np.percentile(bootstrapped_values,
            ((1 - confidence) * 50, 100 - (1 - confidence) * 50))
    return pd.Series({'estimate': estimate, 'lower': lower, 'upper': upper})

def main():
    parser = argparse.ArgumentParser(description="Plot tpcg calls per execution.")
    parser.add_argument("--benchmark", help="Name of the benchmark", required=True)
    parser.add_argument("--data", help="Input file", required=True)
    args = parser.parse_args()

    f = open(args.data)
    reader = csv.DictReader(f, delimiter='\t')

    execs_per_atom = {}
    for v in VERSIONS:
        execs_per_atom[v] = []

    for line in reader:
        if args.benchmark in line['benchmark']:
            execs_per_atom[line['version']].append(
                    float(line['total_tpcg_count']) / float(line['number_of_executed_units']))

    print("%s\t%s\t%s\t%s" % ("version", "estimate", "lower", "upper"))
    for v in VERSIONS:
        m = bootstrap_ci(execs_per_atom[v], np.mean)
        print("%s\t%f\t%f\t%f" % (v, m['estimate'], m['lower'], m['upper']))


if __name__ == '__main__':
    main()
