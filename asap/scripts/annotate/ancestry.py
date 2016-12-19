#!/usr/bin/env python3

"""
ancestry.py: Print ancestry of test cases

Usage:
    cd /path/to/build/folder
    /path/to/ancestry.py < /path/to/fuzzer_output.log | less
Usage VIM:
    vim
    :set foldmethod=marker
    :%!python /path/to/ancestry.py < /path/to/fuzzer_output.log
    use zo and zc to fold and unfold
"""

import re
import sys
import subprocess
import argparse

class Ancestry(object):
    # 12 NEW    cov: 3 ft: 3 corp: 2/2b exec/s: 0 rss: 24Mb secs: 0 L: 1 MS: 1 ChangeBit-
    TESTCASE_RE = re.compile(r'^#(\d+)\s+NEW\s+cov: (\d+) (?:ft: (\d+) )?(?:indir: (\d+) )?corp: (\d+)/\d+b exec/s: (\d+) rss: \S+ secs: (\d+) L: (\d+) MS: (\d+) (.*)',
            re.MULTILINE)
    ANCESTRY_RE = re.compile(r'^ANCESTRY: ([a-fA-F\d]{40}) -> ([a-fA-F\d]{40})$',
            re.MULTILINE)
    # NEW_PC: 0x41f58d in http_parser_execute /home/jowagner/asap/experiments/ff-http-parser/target-asap-10-build/../http-parser-src/http_parser.c:656:5
    NEW_PC_RE = re.compile(r'NEW_PC: (0x[0-9a-f]+) in (\S+) ([^:]+):(\d+):(\d+)',
            re.MULTILINE)

    def __init__(self):
        self.ancestry = None
        self.testcases = None
        self.tree = {}
        self.kids = {}
        self.info = {}
        self.lvl = {}
        self.root = None

    def is_valid(self):
        return len(self.info) > 0

    def get_info(self):
        return self.info

    def build_tree(self):
        for parent, child in self.ancestry:
            self.tree[child] = parent
            if parent not in self.kids:
                self.kids[parent] = []
            self.kids[parent].append(child)
            if parent not in self.lvl:
                self.lvl[parent] = 5
            self.lvl[child] = self.lvl[parent] + 2

    def print_tree(self, shasum):
        if not self.tree:
            print("The input stream does not look like fuzzing log")
            return
        parent = self.tree[shasum]
        (index, cov, execs, action, pcs) = self.info[shasum]
        if not parent:
            line = "ROOT | {:40s}\n".format(shasum)
        else:
            line_ancestry = " " * self.lvl[parent] + \
                    "-" * (self.lvl[shasum] - self.lvl[parent])
            line = line_ancestry + "| {:<8d} {:40s} cov: {:>8d} exec/s: {:>8d} {:20s}\n".format(
                    int(index), shasum, int(cov), int(execs), action)
        line += "{{{\n"
        for (filename, linenumber, column) in pcs:
            line += " " * 29 + "| {:40s} : {:<8d}\n".format(filename, int(linenumber))
        line += "}}}\n"

        print(line)
        print("{{{")
        if shasum in self.kids:
            for kid in self.kids[shasum]:
                self.print_tree(kid)
        print("}}}")

    def parse(self, data, elf_path=''):
        self.testcases = []
        self.ancestry = []
        pcdata = []
        for line in data.split('\n'):
            m = Ancestry.TESTCASE_RE.search(line)
            if m:
                self.testcases.append(m.groups())
            m = Ancestry.ANCESTRY_RE.search(line)
            if m:
                if m.group(1) != '0000000000000000000000000000000000000000':
                    self.ancestry.append(m.groups())
                last_testcase = m.group(2)
            m = Ancestry.NEW_PC_RE.search(line)
            if m:
                pcdata.append((m.group(1), last_testcase, m.group(3), m.group(4), m.group(5)))

        assert len(self.testcases) == len(self.ancestry)

        self.build_tree()
        for i in range(len(self.testcases)):
            tc = self.testcases[i]
            parent, child = self.ancestry[i]
            if len(tc) < 10:
                index, cov, bits, units, execs, secs, l, ms, action = tc
            else:
                #-fsanitize-coverage=indirect-calls
                index, cov, bits, indir, units, execs, secs, l, ms, action = tc

            if parent not in self.tree:
                self.tree[parent] = None
                self.root = parent
                self.info[self.root] = (0, 0, 0, "", [])

            self.info[child] = (index, cov, execs, tc[-1], [])

        for (pc, testcase, filename, line_number, column_number)  in pcdata:
            self.info[testcase][-1].append((filename, line_number, column_number))

        #self.print_tree(self.root)



def main():
    log_data = sys.stdin.read()
    ancestry = Ancestry()

    arg_parser = argparse.ArgumentParser()
    arg_parser.add_argument("--elf", default="")
    args = vars(arg_parser.parse_args(sys.argv[1:]))

    ancestry.parse(log_data, args["elf"])
    ancestry.print_tree(ancestry.root)

if __name__ == '__main__':
    main()
