#!/usr/bin/env python3

"""Parses data from time-to-crash experiments."""

import argparse
import io
import re
import sys
import numpy as np
import matplotlib.pyplot as plt

TIMESTAMP_RE = re.compile(r'^fuss:.* timestamp: (\d+)')
SECONDS_RE = re.compile(r'^#\d.* secs: (\d+)')
JOB_END_RE = re.compile(r'^================== Job (\d+) exited with exit code \d+ ============')
# Note: because stdout and stderr are mixed, JOB_START_RE does not always start
# at the start of a line.
JOB_START_RE = re.compile(r'\./fuzzer .* > fuzz-(\d+).log')

def get_timestamp(d, description):
    m = re.search(description + r'.* timestamp: (\d+)', d, re.MULTILINE)
    return int(m.group(1)) if m else None

def parse_data(d, crash_re):
    def default(x, xd):
        return x if x is not None else xd

    build_asan_ts = get_timestamp(d, r'^fuss: building asan version\.')
    warmup_asan_ts = get_timestamp(d, r'^fuss: warming up asan-prof-.* version\.')
    profiling_asan_ts = get_timestamp(d, r'^fuss: profiling asan-prof-.* version\.')
    build_fperf_ts = get_timestamp(d, r'^fuss: building asan-fperf version\.')
    test_fperf_ts = get_timestamp(d, r'^fuss: testing asan-fperf version\.')
    fuss_end_ts = get_timestamp(d, r'^fuss: fuss end.*\.')

    build_baseline_ts = get_timestamp(d, r'^fuss: building baseline-.* version\.')
    test_baseline_ts = get_timestamp(d, r'^fuss: testing baseline-.* version\.')
    baseline_end_ts = get_timestamp(d, r'^fuss: baseline end\.')

    # Finding the actual time to crash is a bit tricky. We parse the log line
    # by line, keeping track of events:
    # - timestamps
    # - start and progress of jobs
    # - whether a job finds a crash or not
    # Then, we take the time to crash as the first time when a job found the
    # crash.
    
    last_timestamp = None
    last_job = None
    start_after = {}
    start_time = {}
    progress_time = {}

    crash_re = re.compile(crash_re)
    crashes = False
    crash_time = 1e10

    for line in io.StringIO(d):
        m = TIMESTAMP_RE.match(line)
        if m:
            last_timestamp = int(m.group(1))
            continue
        m = SECONDS_RE.match(line)
        if m:
            progress_time[last_job] = start_time[last_job] + int(m.group(1))
            continue
        m = JOB_START_RE.search(line)
        if m:
            job_id = int(m.group(1))
            start_after[job_id] = last_job
            continue
        m = JOB_END_RE.match(line)
        if m:
            last_job = int(m.group(1))
            if start_after[last_job] is not None:
                start_time[last_job] = progress_time[start_after[last_job]]
            else:
                start_time[last_job] = last_timestamp
            progress_time[last_job] = start_time[last_job]
            continue
        m = crash_re.search(line)
        if m:
            crashes = True
            crash_time = min(crash_time, progress_time[last_job])

    if crashes:
        if fuss_end_ts is not None:
            fuss_end_ts = min(fuss_end_ts, crash_time)
        if baseline_end_ts is not None:
            baseline_end_ts = min(baseline_end_ts, crash_time)

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
