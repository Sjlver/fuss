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

    fig, ax = plt.subplots(nrows=1, ncols=1)
    fig.set_size_inches(3, 2)

    kmf = KaplanMeierFitter()
    is_fuss = (data['version'] == 'fuss')
    kmf.fit(data['fuzz'][is_fuss], data['crashes'][is_fuss], label='fuss')
    ax = kmf.plot(ax=ax)
    kmf.fit(data['fuzz'][~is_fuss], data['crashes'][~is_fuss], label='baseline')
    ax = kmf.plot(ax=ax, linestyle='dotted')

    # Set nice ticks
    if np.max(data['fuzz']) <= 3600 + 100:
        plt.xlim(0, 3600)
        plt.xticks([0, 900, 1800, 2700, 3600], ['0', '15min', '30min', '45min', '1h'])
    elif np.max(data['fuzz']) <= 3*3600 + 100:
        plt.xlim(0, 3*3600)
        plt.xticks([0, 3600, 2*3600, 3*3600], ['0', '1h', '2h', '3h'])
    elif np.max(data['fuzz']) <= 4*3600 + 100:
        plt.xlim(0, 4*3600)
        plt.xticks([0, 3600, 2*3600, 3*3600, 4*3600], ['0', '1h', '2h', '3h', '4h'])
    else:
        raise ValueError("Don't know how to create ticks for t=" + str(np.max(data['fuzz'])))

    plt.ylim(0, 1.0)
    plt.xlabel('')
    #plt.xlabel('Time')
    #plt.ylabel('Bug Survival Probability')
    #plt.suptitle(data.at[0, 'benchmark'])
    plt.grid(True)
    fig.tight_layout()

    if args.output:
        plt.savefig(args.output)
    else:
        plt.show()

if __name__ == '__main__':
    main()
