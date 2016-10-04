#!/usr/bin/env python3

"""
annotate.py: Annotate source code with checks and their costs.

Usage:
    cd /path/to/build/folder
    /path/to/annotate.py < /path/to/asap_build.log | less
"""

import re
import sys

class Annotator(object):
    FUNCTION_RE = re.compile(r'^AsapPass: ran on (\w+) at ([^:]+):(\d+)',
            re.MULTILINE)
    CHECK_RE = re.compile(r'^([^:\n]+):(\d+):(\d+): (keeping|removing) sanity check with cost i64 (\d+)',
            re.MULTILINE)

    def __init__(self):
        self.checks = []
        self.functions = []

    def parse_function(self, s):
        m = Annotator.FUNCTION_RE.search(s)
        function_name, file_name, line_number = m.groups()
        self.functions.append((function_name, file_name, int(line_number)))

        checks = Annotator.CHECK_RE.findall(s)
        for c in checks:
            file_name, line_number, column_number, action, cost = c
            self.checks.append((function_name, file_name, int(line_number),
                                int(column_number), action, int(cost)))

    def compute_stats(self, checks):
        total_checks = 0
        removed_checks = 0
        total_cost = 0
        removed_cost = 0

        for c in checks:
            total_checks += 1
            removed_checks += 1 if c[4] == 'removing' else 0
            total_cost += c[5]
            removed_cost += c[5] if c[4] == 'removing' else 0

        if total_checks > 0:
            sanity_level = "{:.2f}%".format(
                    100.0 - 100.0 * removed_checks / total_checks)
        else:
            sanity_level = "nan%"

        if total_cost > 0:
            cost_level = "{:.2f}%".format(
                    100.0 - 100.0 * removed_cost / total_cost)
        else:
            cost_level = "nan%"

        return (total_checks, removed_checks, total_cost, removed_cost,
                sanity_level, cost_level)

    def print_stats(self, total_checks, removed_checks, total_cost, removed_cost,
            sanity_level, cost_level):
        print("//!   Static checks: total {}, removed {}, kept {}, sanity level {}".format(
            total_checks, removed_checks, total_checks - removed_checks,
            sanity_level))
        print("//!   Cost: total {}, removed {}, kept {}, cost level {}".format(
            total_cost, removed_cost, total_cost - removed_cost,
            cost_level))

    def annotate_files(self):
        # Sort checks / functions by file name and line number
        self.checks.sort(key=lambda c: (c[1], c[2], c[3]))
        self.functions.sort(key=lambda f: (f[1], f[2], f[0]))

        current_file_name = None
        function_index = 0
        check_index = 0

        print("//! ASAP Summary report")
        self.print_stats(*self.compute_stats(self.checks))
        print()

        while check_index < len(self.checks):
            if current_file_name != self.checks[check_index][1]:
                current_file_name = self.checks[check_index][1]
                with open(current_file_name) as f:
                    print("//! File: {}".format(current_file_name))
                    self.print_stats(*self.compute_stats(
                        c for c in self.checks if c[1] == current_file_name))

                    for line_number, line in enumerate(f):
                        # Fast-forward to the right check/function
                        while self.checks[check_index][1] == current_file_name and \
                                self.checks[check_index][2] < line_number + 1:
                            check_index += 1
                        while self.functions[function_index][1] == current_file_name and \
                                self.functions[function_index][2] < line_number + 1:
                            function_index += 1

                        if function_index < len(self.functions) and \
                                line_number + 1 == self.functions[function_index][2] and \
                                current_file_name == self.functions[function_index][1]:
                            print("//! Function: {}".format(self.functions[function_index][0]))
                            self.print_stats(*self.compute_stats(
                                c for c in self.checks if c[0] == self.functions[function_index][0]))

                        line_checks = []
                        while check_index < len(self.checks) and \
                                line_number + 1 == self.checks[check_index][2] and \
                                current_file_name == self.checks[check_index][1]:
                            line_checks.append(self.checks[check_index])
                            check_index += 1
                        line_checks.sort(key=lambda c: c[5])

                        if len(line_checks) > 1:
                            check_summary = "".join("!" if c[4] == "removing" else "." for c in line_checks)
                            if len(check_summary) > 10:
                                check_summary = check_summary[:9] + "+"
                            check_info = "{:10s} {:>8d}-{:<8d} | ".format(
                                    check_summary,
                                    line_checks[0][5], line_checks[-1][5])
                        elif len(line_checks) == 1:
                            check_info = "{:10s} {:^17d} | ".format(
                                    "!" if line_checks[0][4] == "removing" else ".",
                                    line_checks[0][5])
                        else:
                            check_info = " " * 29 + "| "

                        print(check_info + line.rstrip())


def main():
    log_data = sys.stdin.read()
    annotator = Annotator()
    start = 0
    for m in re.finditer(Annotator.FUNCTION_RE, log_data):
        annotator.parse_function(log_data[start:m.end()])
        start = m.end()

    annotator.annotate_files()

if __name__ == '__main__':
    main()
