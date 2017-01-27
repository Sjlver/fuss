#!/usr/bin/env python3

"""Parses data from time-to-crash experiments."""

import argparse
import re
import sys
import numpy as np
import matplotlib.pyplot as plt

def get_timestamp(d, description):
    m = re.search(description + r'.* timestamp: (\d+)', d, re.MULTILINE)
    return int(m.group(1)) if m else None

def parse_data(d, crash_re):
    def default(x, xd):
        return x if x is not None else xd

    build_asan_ts = get_timestamp(d, r'fuss: building asan version\.')
    warmup_asan_ts = get_timestamp(d, r'fuss: warming up asan-prof-.* version\.')
    profiling_asan_ts = get_timestamp(d, r'fuss: profiling asan-prof-.* version\.')
    build_fperf_ts = get_timestamp(d, r'fuss: building asan-fperf version\.')
    test_fperf_ts = get_timestamp(d, r'fuss: testing asan-fperf version\.')
    fuss_end_ts = get_timestamp(d, r'fuss: fuss end.*\.')

    build_baseline_ts = get_timestamp(d, r'fuss: building baseline-.* version\.')
    test_baseline_ts = get_timestamp(d, r'fuss: testing baseline-.* version\.')
    baseline_end_ts = get_timestamp(d, r'fuss: baseline end\.')

    crashes = True if re.search(crash_re, d, re.MULTILINE) else False

    profiling_asan_ts = default(profiling_asan_ts, fuss_end_ts)
    build_fperf_ts = default(build_fperf_ts, fuss_end_ts)
    test_fperf_ts = default(test_fperf_ts, fuss_end_ts)

    if fuss_end_ts is not None and baseline_end_ts is None:
        result = {
            'build': warmup_asan_ts - build_asan_ts,
            'fuzz': (profiling_asan_ts - warmup_asan_ts
                + build_fperf_ts - profiling_asan_ts
                + fuss_end_ts - test_fperf_ts),
            'rebuild': test_fperf_ts - build_fperf_ts
        }
    elif fuss_end_ts is None and baseline_end_ts is not None:
        result = {
            'build': test_baseline_ts - build_baseline_ts,
            'fuzz': baseline_end_ts - test_baseline_ts,
            'rebuild': 0
        }
    else:
        return None

    result['crashes'] = crashes
    result['version'] = 'fuss' if fuss_end_ts is not None else 'baseline'
    return result

def main():
    parser = argparse.ArgumentParser(description="Parses data from time-to-crash experiments")
    parser.add_argument("--benchmark", help="Name of the benchmark", required=True)
    parser.add_argument("--crash-re", help="Regular expression to determine whether the benchmark crashed", required=True)
    parser.add_argument("data", nargs="+", help="Log files of the fuzzing run.")
    args = parser.parse_args()

    data = []
    for data_file in args.data:
        with open(data_file) as d:
            data_values = d.read()
        data.append(parse_data(data_values, args.crash_re))

    print("# experiments:", len(data))
    valid_experiments = [d for d in data if d]
    print("# valid_experiments:", len(valid_experiments))

    fuss_experiments = [d for d in valid_experiments if d['version'] == 'fuss']
    print("# fuss_experiments:", len(fuss_experiments))
    print("# fuss_found_crash:", len([d for d in fuss_experiments if d['crashes']]))
    if fuss_experiments:
        print("#                  build\t    fuzz\t rebuild")
        print("# fuss_median:  {build:8.1f}\t{fuzz:8.1f}\t{rebuild:8.1f}".format(
            build=np.median([d['build'] for d in fuss_experiments]),
            fuzz=np.median([d['fuzz'] for d in fuss_experiments]),
            rebuild=np.median([d['rebuild'] for d in fuss_experiments])
        ))

    baseline_experiments = [d for d in valid_experiments if d['version'] == 'baseline']
    print("# baseline_experiments:", len(baseline_experiments))
    print("# baseline_found_crash:", len([d for d in baseline_experiments if d['crashes']]))
    if baseline_experiments:
        print("#                      build\t    fuzz\t rebuild")
        print("# baseline_median:  {build:8.1f}\t{fuzz:8.1f}\t{rebuild:8.1f}".format(
            build=np.median([d['build'] for d in baseline_experiments]),
            fuzz=np.median([d['fuzz'] for d in baseline_experiments]),
            rebuild=np.median([d['rebuild'] for d in baseline_experiments])
        ))

    print()
    print("{:20s}\t{:8s}\t{:7}\t{:>8s}\t{:>8s}\t{:>8s}".format('benchmark', 'version', 'crashes', 'build', 'fuzz', 'rebuild'))
    for d in valid_experiments:
        print("{benchmark:20s}\t{version:8s}\t{crashes:1}\t{build:8.1f}\t{fuzz:8.1f}\t{rebuild:8.1f}".format(benchmark=args.benchmark, **d))

if __name__ == '__main__':
    main()
