#!/usr/bin/env python3

"""Parses AFL logs, generates coverage-vs-time graphs."""

import argparse
import glob
import os
import re
import shutil
import subprocess
import sys
import tempfile
import numpy as np

TIMESTAMP_RE = re.compile(r' timestamp: (\d+)')
SECONDS_RE = re.compile(r' execs: (\d+) secs: (\d+)')
ANCESTRY_RE = re.compile(r'ANCESTRY: ([0-9a-f]+) -> ([0-9a-f]+) execs: (\d+) secs: (\d+)')
MAP_RE = re.compile(r'^(\d+):(\d+)$')

def parse_logs(f):
    """Parses AFL logs from the given file object `f`.

    Retrieves a list of timestamps together with the unit that was discovered
    at that time, and the number of executions.
    """

    start_timestamp = current_timestamp = current_seconds = None
    current_execs = execs_delta = 0
    result = []

    for line in f:
        m = TIMESTAMP_RE.search(line)
        if m:
            current_timestamp = int(m.group(1))
            current_seconds = 0
            current_execs += execs_delta
            execs_delta = 0
            if start_timestamp is None:
                start_timestamp = current_timestamp
            continue
        m = ANCESTRY_RE.search(line)
        if m:
            execs_delta = int(m.group(3))
            current_seconds = int(m.group(4))
            result.append((current_timestamp - start_timestamp + current_seconds,
                           m.group(2), current_execs + execs_delta))
            continue
        m = SECONDS_RE.search(line)
        if m:
            execs_delta = int(m.group(1))
            current_seconds = int(m.group(2))
            result.append((current_timestamp - start_timestamp + current_seconds,
                           None, current_execs + execs_delta))
            continue

    return result

def coverage_for_units(units):
    """Computes the coverage achieved by the given units."""

    blocks = set()
    for unit in units:
        findings_dir = os.path.dirname(os.path.dirname(unit))
        unit_name = os.path.basename(unit)
        map_file = os.path.join(findings_dir, 'maps', unit_name)

        with open(map_file) as mf:
            for line in mf:
                m = MAP_RE.search(line)
                blocks.add(m.group(1))
    return len(blocks)

def unit_path(unit_id, findings_dir):
    matches = glob.glob(os.path.join(findings_dir, 'queue', "id:{},*".format(unit_id)))
    return matches[0] if matches else None

def main():
    parser = argparse.ArgumentParser(description="Compute coverage vs time from AFL logs")
    parser.add_argument("--findings", help="Path to the findings folder", required=True)
    args = parser.parse_args()

    events = parse_logs(sys.stdin)
    events = [(t, unit_path(u, args.findings) if u else None, e) for t, u, e in events]

    end_time, _, _ = events[-1]
    last_coverage = 0
    last_num_units = 0

    print("{:8s}\t{:8s}\t{:12s}".format("time", "coverage", "execs"))
    for current_time in np.linspace(0, end_time, num=100):
        events_up_to_now = [(t, u, e) for t, u, e in events if t <= current_time]
        if not events_up_to_now:
            print("{:8.0f}\t{:8d}\t{:12d}".format(current_time, 0, 0))
            continue

        # Compute coverage
        units_up_to_now = [u for t, u, e in events_up_to_now if u is not None]
        if len(units_up_to_now) > last_num_units:
            last_coverage = coverage_for_units(units_up_to_now)
            last_num_units = len(units_up_to_now)

        # Compute execs (interpolate between last and next event)
        last_event = events_up_to_now[-1]
        next_event = events[len(events_up_to_now)] if len(events) > len(events_up_to_now) \
                     else last_event
        time_delta = next_event[0] - last_event[0]
        if time_delta != 0:
            time_fraction = float(current_time - last_event[0]) / time_delta
            execs = last_event[2] + (next_event[2] - last_event[2]) * time_fraction
        else:
            execs = next_event[2]
        print("{:8.0f}\t{:8d}\t{:12d}".format(current_time, last_coverage, round(execs)))
        sys.stdout.flush()

    print("{:8.0f}\t{:8d}\t{:12d}".format(events[-1][0], last_coverage, events[-1][2]))

if __name__ == '__main__':
    main()
