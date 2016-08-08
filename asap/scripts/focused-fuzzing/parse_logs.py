#!/usr/bin/env python3

import sys
import csv
import os
import re

#artifact_prefix='./'; Test unit written to ./crash-56b0800c06f1bdf127da41247d649a518f616ec0
#stat::number_of_executed_units: 49407
#stat::average_exec_per_sec:     355
#stat::new_units_added:          14
#stat::slowest_unit_time_sec:    0
#stat::peak_rss_mb:              511

#==16185== libFuzzer: run interrupted; exiting
#stat::number_of_executed_units: 319186
#stat::average_exec_per_sec:     1866
#stat::new_units_added:          951
#stat::slowest_unit_time_sec:    0
#stat::peak_rss_mb:              616



def main(infile):
    if not os.path.isfile(infile):
        print('File not found [%s]. Aborting...' % infile)
        return
    outfile = 'result-%s.csv' % infile
    try:
        os.remove(outfile)
    except FileNotFoundError:
        pass

    csvin = open(outfile, 'a')
    fieldnames = ['crash', 'executed', 'asap-cost-threshold', 'execs/s']
    writer = csv.DictWriter(csvin, fieldnames=fieldnames)
    writer.writeheader()

    print('[INFO] Dumping output to ' + outfile)
    asap_cost_threshold = 0
    with open(infile, 'r') as f:
        stat = False
        csvline = {}
        for line in f:
            res = re.search(r'asap-cost-threshold:\[[1-9][0-9]*\]', line)
            if res:
                res = re.findall('\d+', line)
                if res:
                    asap_cost_threshold = int(res[-1])

            if not stat:
                res = re.search(r'crash-[0-9a-f]*', line)
                if not res:
                    res = re.search(r'libFuzzer.*interrupted.*exiting', line)
                    if not res:
                        res = re.search(r'Done [0-9]* runs in [0-9]* second', line)
                        if not res:
                            continue
                stat = True
                csvline = {}
                csvline['crash'] = res.group(0)
                csvline['asap-cost-threshold'] = asap_cost_threshold
            else:
                if len(csvline) == len(fieldnames):
                    stat = False
                    writer.writerow(csvline)
                else:
                    res = re.search(r'^stat::number_of_executed_units: [0-9]*', line)
                    if res:
                        csvline['executed'] = int(re.findall('\d+', line)[0])
                        continue
                    res = re.search(r'^stat::average_exec_per_sec: [0-9]*', line)
                    if res:
                        csvline['execs/s'] = int(re.findall('\d+', line)[0])
                        continue



if __name__ == "__main__":
    if len(sys.argv) < 2:
        print('Usage: %s logfile' % sys.argv[0])
        exit()
    main(sys.argv[1])
