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

class Ancestry(object):
    TESTCASE_RE = re.compile(r'^#(\d+)\s+NEW\s+cov: (\d+) (?:bits: (\d+) )?(?:indir: (\d+) )?units: (\d+) exec/s: (\d+) secs: (\d+) L: (\d+) MS: (\d+) (.*)',
            re.MULTILINE)
    ANCESTRY_RE = re.compile(r'^ANCESTRY: ([a-fA-F\d]{40}) -> ([a-fA-F\d]{40})$',
            re.MULTILINE)
    NEW_PC_RE = re.compile(r'NEW_PC: (0x[0-9a-f]+) tc: ([a-fA-F\d]{40})?',
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

    def convert_pcs(self, pcs):
        # transform [pc] into {pc:(file, line_nr, column)}
        result = {}
        input_stream = "\n".join(pcs)
        llvm_symbolizer = subprocess.Popen(['llvm-symbolizer', '-obj=/home/alex/jonas/target-asan-trace-build/fuzzer', '-functions=none'], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        out = llvm_symbolizer.communicate(input=input_stream.encode())[0]

        out = out.decode().rsplit()

        for (pc, info) in zip(pcs, out):
            filename, linenumber, column = info.split(":")
            result[pc] = (filename, linenumber, column)

        return result

    def parse(self, data):
        self.testcases = Ancestry.TESTCASE_RE.findall(data)
        self.ancestry = Ancestry.ANCESTRY_RE.findall(data)
        pcdata = Ancestry.NEW_PC_RE.findall(data)
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

        pcs = [pc for (pc, tc) in pcdata]
        pcs_symbolized = self.convert_pcs(pcs)
        for (pc, testcase)  in pcdata:
            if not testcase:
                testcase = self.root
            self.info[testcase][-1].append(pcs_symbolized[pc])

        #self.print_tree(self.root)



def main():
    log_data = sys.stdin.read()
    ancestry = Ancestry()
    ancestry.parse(log_data)

if __name__ == '__main__':
    main()
