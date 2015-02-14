#!/usr/bin/python

from __future__ import print_function
from __future__ import division

import re

re_f = re.compile(r'^function __')
re_n = re.compile(r'(__[^(]+)')
re_v = re.compile(r'^ var ')
re_s = re.compile(r'(?: var |= 0|[ ,;\n])+')
re_e = re.compile(r'^}')

current_function = ""
current_varcount = 0

bucket_borders = [ 100, 200, 500, 1000, 2000, 5000, 10000 ]
buckets = [ 0 for i in bucket_borders ] + [ 0 ]
results = []
maxresult = 0

with open("yosys.js") as f:
    for line in f:
        if re_f.search(line):
            current_function = re_n.search(line).group(1)
        if re_v.search(line) and current_function != "":
            varlist = re_s.sub(" ", line).split()
            current_varcount += len(varlist)
        if re_e.search(line) and current_function != "":
            maxresult = max(maxresult, current_varcount)
            results.append("%6d %s" % (current_varcount, current_function))
            for i in range(len(bucket_borders)):
                if current_varcount <= bucket_borders[i]:
                    buckets[i] += 1
                    break
            else:
                buckets[-1] += 1
            current_function = ""
            current_varcount = 0

results.sort()
print("<skipping first %d results>" % (len(results)-10))
for line in results[-10:]:
    print(line)
print("")

bb = [0] + bucket_borders + [maxresult]
for i in range(len(buckets)):
    print("%6d - %5d vars: %5d functions" % (bb[i], bb[i+1], buckets[i]))

