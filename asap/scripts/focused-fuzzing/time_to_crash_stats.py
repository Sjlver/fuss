#!/usr/bin/env python3

"""Plots data from time-to-crash experiments."""

import argparse
import re
import sys
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from lifelines import KaplanMeierFitter

def kaplan_meier_median(d):
    kmf = KaplanMeierFitter()
    kmf.fit(d['fuzz'], d['crashes'])
    return kmf.median_

def bootstrap_ci(df, f, confidence=0.95):
    """A simple computation of a bootstrap confidence interval.

    Takes a data frame `df` and a function `f`. Returns a Series containing the
    estimate and its lower/upper bounds.
    """

    n_samples = 1000
    estimate = f(df)
    bootstrapped_values = np.zeros(n_samples)
    for i in range(n_samples):
        sample = df.sample(n=len(df), replace=True)
        bootstrapped_values[i] = f(sample)
    lower, upper = np.percentile(bootstrapped_values,
            ((1 - confidence) * 50, 100 - (1 - confidence) * 50))
    return pd.Series({'estimate': estimate, 'lower': lower, 'upper': upper})

def main():
    parser = argparse.ArgumentParser(description="Parses data from time-to-crash experiments")
    parser.add_argument("--n-jobs", type=int, help="Number of fuzzer jobs", required=True)
    parser.add_argument("data", help="Data file with times to crash (from time_to_crash.py)")
    args = parser.parse_args()

    data = pd.read_table(args.data, comment='#', engine='python', sep=r'\s*\t\s*')
    data['fuzz'] *= args.n_jobs
    print("                     benchmark\tfuss_m\tfuss_l\tfuss_u\tbase_m\tbase_l\tbase_u")
    fuss_median = bootstrap_ci(data[data['version'] == 'fuss'], kaplan_meier_median)
    baseline_median = bootstrap_ci(data[data['version'] == 'baseline'], kaplan_meier_median)
    print("{:30}\t{:6.1f}\t{:6.1f}\t{:6.1f}\t{:6.1f}\t{:6.1f}\t{:6.1f}".format(
        data.loc[0, 'benchmark'],
        fuss_median['estimate'],
        fuss_median['lower'],
        fuss_median['upper'],
        baseline_median['estimate'],
        baseline_median['lower'],
        baseline_median['upper']))

if __name__ == '__main__':
    main()
