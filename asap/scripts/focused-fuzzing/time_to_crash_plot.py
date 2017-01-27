#!/usr/bin/env python3

"""Plots data from time-to-crash experiments."""

import argparse
import re
import sys
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from lifelines import KaplanMeierFitter

def main():
    parser = argparse.ArgumentParser(description="Parses data from time-to-crash experiments")
    parser.add_argument("--output", help="File to save the plot to")
    parser.add_argument("data", help="Data file with times to crash (from time_to_crash.py)")
    args = parser.parse_args()

    data = pd.read_table(args.data, comment='#', engine='python', sep=r'\s*\t\s*')

    kmf = KaplanMeierFitter()
    is_fuss = (data['version'] == 'fuss')
    kmf.fit(data['fuzz'][is_fuss], data['crashes'][is_fuss], label='fuss')
    ax = kmf.plot()
    kmf.fit(data['fuzz'][~is_fuss], data['crashes'][~is_fuss], label='baseline')
    ax = kmf.plot(ax=ax)

    plt.xlim(0, 3600)
    plt.xticks([0, 900, 1800, 2700, 3600], ['0', '15min', '30min', '45min', '1h'])
    plt.ylim(0, 1.0)
    plt.xlabel('Time')
    plt.ylabel('Bug Survival Probability')
    plt.suptitle(data.at[0, 'benchmark'])
    plt.grid(True)

    if args.output:
        plt.savefig(args.output)
    else:
        plt.show()

if __name__ == '__main__':
    main()
