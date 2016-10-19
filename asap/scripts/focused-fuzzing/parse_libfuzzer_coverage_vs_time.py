#!/usr/bin/env python3

"""Parses LibFuzzer logs, generates coverage-vs-time graphs."""

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
import numpy as np

TIMESTAMP_RE = re.compile(r' timestamp: (\d+)$')
SECONDS_RE = re.compile(r'^#(\d+)\s.* secs: (\d+)(:? |$)')
ANCESTRY_RE = re.compile(r'^ANCESTRY: ([0-9a-f]+) -> ([0-9a-f]+)$')
COVERAGE_BITS_RE = re.compile(br'^#\d+.*\sDONE\s.* cov: (\d+)(:? |$)', re.MULTILINE)
JOB_EXITED_RE = re.compile(r'===+ Job (\d+) exited with exit code \d+ ===+')

def parse_logs(f):
    """Parses LibFuzzer logs from the given file object `f`.

    Retrieves a list of timestamps together with the unit that was discovered
    at that time, and the number of executions.
    """

    start_timestamp = current_timestamp = current_seconds = None
    current_execs = execs_delta = 0
    current_job = 0
    result = []

    for line in f:
        m = JOB_EXITED_RE.search(line)
        if m:
            current_job = int(m.group(1))
            continue
        m = TIMESTAMP_RE.search(line)
        if m:
            current_timestamp = int(m.group(1))
            current_seconds = 0
            current_execs += execs_delta
            execs_delta = 0
            if start_timestamp is None:
                start_timestamp = current_timestamp
            continue
        m = SECONDS_RE.search(line)
        if m:
            execs_delta = int(m.group(1))
            current_seconds = int(m.group(2))
            result.append((current_timestamp - start_timestamp + current_seconds,
                           None, current_execs + execs_delta, current_job))
            continue
        m = ANCESTRY_RE.search(line)
        if m:
            result.append((current_timestamp - start_timestamp + current_seconds,
                           m.group(2), current_execs + execs_delta, current_job))

    return result

def coverage_for_units(units, fuzzer):
    """Computes the coverage achieved by the given units."""

    # Copy units to a temporary corpus folder
    with tempfile.TemporaryDirectory() as tmp:
        for u in units:
            try:
                shutil.copy(u, tmp)
            except OSError:
                # Some files might not exist, particularly if crashes were
                # found. This is not a problem.
                pass

        output = subprocess.check_output([fuzzer, "-runs=0", tmp], stderr=subprocess.STDOUT)
        m = COVERAGE_BITS_RE.search(output)
        return int(m.group(1))

def main():
    parser = argparse.ArgumentParser(description="Compute coverage vs time from LibFuzzer logs")
    parser.add_argument("--fuzzer", help="Path to the reference fuzzer", required=True)
    parser.add_argument("--corpus", help="Path to the corpus", required=True)
    args = parser.parse_args()

    events = parse_logs(sys.stdin)
    events.sort(key=lambda e: e[0])
    events = [(t, os.path.join(args.corpus, u) if u else None, e, j) for t, u, e, j in events]

    all_jobs = set(j for _, _, _, j in events)

    end_time, _, _, _ = events[-1]
    last_coverage = 0
    last_num_units = 0

    print("{:8s}\t{:8s}\t{:12s}".format("time", "coverage", "execs"))
    for current_time in np.linspace(0, end_time, num=100):
        events_up_to_now = [(t, u, e, j) for t, u, e, j in events if t <= current_time]
        if not events_up_to_now:
            print("{:8.0f}\t{:8d}\t{:12d}".format(current_time, 0, 0))
            continue

        # Compute coverage
        units_up_to_now = [u for t, u, e, j in events_up_to_now if u is not None]
        if len(units_up_to_now) > last_num_units:
            last_coverage = coverage_for_units(units_up_to_now, args.fuzzer)
            last_num_units = len(units_up_to_now)

        # Compute execs (interpolate between last and next event)
        total_execs = 0
        for job in all_jobs:
            last_event = next(((t, e) for t, _, e, j in reversed(events_up_to_now) if j == job), None)
            if not last_event:
                continue
            next_event = next(((t, e) for t, _, e, j in events[len(events_up_to_now):] if j == job), None)
            if not next_event:
                next_event = last_event

            time_delta = next_event[0] - last_event[0]
            if time_delta != 0:
                time_fraction = float(current_time - last_event[0]) / time_delta
                execs = last_event[1] + (next_event[1] - last_event[1]) * time_fraction
            else:
                execs = next_event[1]
            total_execs += execs
        print("{:8.0f}\t{:8d}\t{:12d}".format(current_time, last_coverage, round(total_execs)))
        sys.stdout.flush()

if __name__ == '__main__':
    main()
