#!/usr/bin/env python3

"""
annotate.py: Annotate source code with checks and their costs.

Usage:
    cd /path/to/build/folder
    /path/to/annotate.py < /path/to/asap_build.log | less
VIM usage:
    vim
    :set foldmethod=marker
    :%!python /path/to/annotate.py < /path/to/asap_build.log
    use zo and zc to fold and unfold
"""

import re
import sys
import os
import argparse

sys.path.insert(0, os.path.abspath('.'))
from ancestry import Ancestry

class Annotator(object):
    FUNCTION_RE = re.compile(r'^AsapPass: ran on (\w+) at ([^:]+):(\d+)',
            re.MULTILINE)
    # /path/file.c:560:11:2: asap action:keeping cost:0 type:__sanitizer_cov_trace_pc_guard inlined:/path/file.c:1117:13:0
    CHECK_RE = re.compile(r'^([^:\n]+):(\d+):(\d+):\d\+ asap action:(keeping|removing) cost:(\d+)(?: type:(\w+))?',
            re.MULTILINE)


    def __init__(self):
        self.checks = []
        self.functions = []

    def parse_function(self, s):
        m = Annotator.FUNCTION_RE.search(s)
        function_name, file_name, line_number = m.groups()
        function = (function_name, file_name, int(line_number))

        # Some projects compile the same source file multiple times, or include
        # the same file in multiple compilation units. We currently don't
        # handle this very well... so simply skip duplicated functions.
        if function in self.functions: return

        self.functions.append(function)

        checks = Annotator.CHECK_RE.findall(s)
        for c in checks:
            file_name, line_number, column_number, action, cost, sanity_function = c
            self.checks.append((function_name, file_name, int(line_number),
                                int(column_number), action, int(cost), sanity_function))


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


    def pc_hash(self, pc):
        (filename, linenumber, _) = pc
        filename = filename.split('/')[-1]
        return filename + ":" + linenumber

    def print_details(self, line_checks):
        if not line_checks:
            return
        print("{{{")
        for c in line_checks:
            check_info = 29 * " " + "{:1s} {:20s} {:30s} with cost {:>8d} was {:10s}".format(
                        "." if c[4] == "keeping" else "!", " ",
                        c[6] or "<no info available>",
                        c[5], "kept" if c[4] == "keeping" else "removed")
            print(check_info)
        print("}}}")


    def print_testcases(self, ancestry_map, current_line_number, current_file_name):
        key = self.pc_hash((current_file_name, str(current_line_number), 0))

        if not key in ancestry_map:
            return
        testcases = ancestry_map[key]

        if not testcases:
            return

        print("{{{")
        for testcase in testcases:
            testcase_info = 29 * " " + "| testcase checksum: {:40s}".format(testcase)
            print(testcase_info)
        print("}}}")

    def annotate_files(self, ancestry):
        # Sort checks / functions by file name and line number
        self.checks.sort(key=lambda c: (c[1], c[2], c[3]))
        self.functions.sort(key=lambda f: (f[1], f[2], f[0]))

        current_file_name = None
        function_index = 0
        check_index = 0

        ancestry_map = {}
        if ancestry.is_valid():
            info = ancestry.get_info()
            for (key, value) in info.items():
                (_, _, _, _, pcs) = value
                for pc in pcs:
                    current_key = self.pc_hash(pc)
                    if not current_key in ancestry_map:
                        ancestry_map[current_key] = []
                    ancestry_map[current_key].append(key)


        print("//! ASAP Summary report")
        self.print_stats(*self.compute_stats(self.checks))
        print()

        while check_index < len(self.checks):
            assert current_file_name != self.checks[check_index][1]
            current_file_name = self.checks[check_index][1]

            print("//! File: {}".format(current_file_name))
            self.print_stats(*self.compute_stats(
                c for c in self.checks if c[1] == current_file_name))

            try:
                with open(current_file_name) as f:
                    for line_number, line in enumerate(f):
                        # Fast-forward to the right check/function
                        while check_index < len(self.checks) and \
                                self.checks[check_index][1] == current_file_name and \
                                self.checks[check_index][2] < line_number + 1:
                            check_index += 1
                        while function_index < len(self.functions) and \
                                self.functions[function_index][1] == current_file_name and \
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
                            check_info = "{:10s} {:>8d}-{:<8d} | {:<5d} ".format(
                                    check_summary,
                                    line_checks[0][5], line_checks[-1][5], line_number + 1)
                        elif len(line_checks) == 1:
                            check_info = "{:10s} {:^17d} | {:<5d} ".format(
                                    "!" if line_checks[0][4] == "removing" else ".",
                                    line_checks[0][5], line_number + 1)
                        else:
                            check_info = " " * 29 + "| {:<5d}".format(line_number + 1) + " "

                        print(check_info + line.rstrip())
                        #after printing the line, print the sanity checks information
                        self.print_details(line_checks)
                        self.print_testcases(ancestry_map, line_number + 1, current_file_name)
            except IOError:
                # Skip over the current file
                while (check_index < len(self.checks) and
                        current_file_name == self.checks[check_index][1]):
                    check_index += 1


def main():
    log_data = sys.stdin.read()
    annotator = Annotator()
    start = 0
    for m in re.finditer(Annotator.FUNCTION_RE, log_data):
        annotator.parse_function(log_data[start:m.end()])
        start = m.end()

    arg_parser = argparse.ArgumentParser()
    arg_parser.add_argument("--ancestry", default="")
    arg_parser.add_argument("--elf", default="")
    args = vars(arg_parser.parse_args(sys.argv[1:]))

    ancestry = Ancestry()
    if args["ancestry"]:
        ancestry_log = open(args["ancestry"]).read()
        ancestry.parse(ancestry_log, args["elf"])
    annotator.annotate_files(ancestry)

if __name__ == '__main__':
    main()
