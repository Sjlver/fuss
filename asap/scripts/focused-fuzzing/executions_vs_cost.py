#!/usr/bin/env python3

"""Plots #executions vs cost for instrumentation atoms.
"""

import argparse
import matplotlib.pyplot as plt
import os
import re
import subprocess
import sys

# /path/file.c:560:11:2: asap action:keeping cost:0 type:__sanitizer_cov_trace_pc_guard inlined:/path/file.c:1117:13:0
COSTS_RE = re.compile(r'^(\S+): asap action:(?:keeping|removing) cost:(\d+) type:(\S+)(?: inlined:(\S+))?')

# * 0x520590 14467
EXECUTIONS_RE = re.compile(r'([.*]) (0x[0-9a-f]+) (\d+)')

def parse_costs(data):
    """Parses cost data from the output of AsapPass.

    Returns a list of (location, cost) tuples.
    """

    costs = []
    for line in data.splitlines():
        m = COSTS_RE.match(line)
        if m:
            location = m.group(1)
            cost = int(m.group(2))
            ty = m.group(3)
            inlined = m.group(4).split(',') if m.group(4) else []
            if ty == '__sanitizer_cov_trace_pc_guard':
                costs.append(([location] + inlined, cost))
    return costs


def parse_executions(data, obj):
    """Parses execution data from the output of corpus_coverage.py

    Returns a list of (location, executions, action) tuples.
    """

    executions = []
    for line in data.splitlines():
        m = EXECUTIONS_RE.match(line)
        if m:
            action = m.group(1)
            pc = int(m.group(2), base=16)
            execs = int(m.group(3))
            executions.append((pc, execs, action))
    locations = symbolize([pc for pc, _, _ in executions], obj)
    executions = [(locations[i], executions[i][1], executions[i][2]) for i in range(len(executions))]
    return executions


def symbolize(pcs, obj):
    """Calls llvm-symbolizer to convert an array of pcs into locations."""

    input_data = "\n".join("0x{:x}".format(pc) for pc in pcs)
    output = subprocess.check_output(['llvm-symbolizer', '-functions=none', '-inlining', '-obj=' + obj], input=input_data.encode())
    locations = output.decode().split('\n\n')
    locations = [loc.split() for loc in locations]
    return locations


def merge_costs_and_executions(costs, executions):
    """Merge cost and executions data.

    Returns a list containing those atoms for which we have matching data.
    """

    # When comparing locations, currently we only consider the file basename
    # and line number. These are the only parts that are generally set. Also,
    # comparing directory parts of paths might be problematic if users build
    # multiple versions of the program in different directories.
    def cost_key(loc):
        key = []
        for l in loc:
            path, line, column, discriminator = l.split(':')
            key.append((os.path.basename(path), int(line)))
        return tuple(key)
    def execs_key(loc):
        key = []
        for l in loc:
            path, line, column  = l.split(':')
            key.append((os.path.basename(path), int(line)))
        return tuple(key)

    cost_map = {cost_key(loc): cost for loc, cost in costs}
    execs_map = {execs_key(loc): (execs, action) for loc, execs, action in executions}

    result = []
    for loc, (execs, action) in execs_map.items():
        if loc not in cost_map:
            print("warning: executed atom was not seen by ASAP: {}".format(loc), file=sys.stderr)
            continue
        cost = cost_map[loc]
        result.append((loc, cost, execs, action))
    return result

def main():
    arg_parser = argparse.ArgumentParser()
    arg_parser.add_argument("--fuzzer", help='Fuzzer binary, to symbolize PC values', required=True)
    arg_parser.add_argument("--costs", help='ASAP logfile containing atom costs', required=True)
    arg_parser.add_argument("--executions", help='Output of corpus_coverage.py', required=True)
    arg_parser.add_argument("--output", help="Output file to save plot to")
    args = arg_parser.parse_args(sys.argv[1:])

    with open(args.costs) as costs_file:
        costs_data = costs_file.read()
    costs = parse_costs(costs_data)

    with open(args.executions) as executions_file:
        executions_data = executions_file.read()
    executions = parse_executions(executions_data, args.fuzzer)

    atoms = merge_costs_and_executions(costs, executions)
    atom_costs = [c for _, c, _, _ in atoms]
    atom_execs = [e for _,  _, e, _ in atoms]
    actions_to_color = {'*': 'red', '.': 'blue'}
    atom_colors = [actions_to_color[a] for _, _, _, a in atoms]

    plt.title('Atom costs vs executions')
    plt.scatter(atom_execs, atom_costs, color=atom_colors, alpha=0.5)
    plt.xlabel('Executions')
    plt.ylabel('Cost')
    plt.xscale('log')
    plt.yscale('log')
    plt.xlim((1, 1e10))
    plt.ylim((1, 1e6))
    if args.output:
        plt.savefig(args.output)
    else:
        plt.show()
    
    # Dump the data for debugging:
    for loc, cost, execs, action in sorted(atoms, key=lambda a: a[2]):
        print("{} {:12d} {:12d} {}".format(action, cost, execs, loc), file=sys.stderr)

if __name__ == '__main__':
    main()
