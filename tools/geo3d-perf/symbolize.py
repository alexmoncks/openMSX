#!/usr/bin/env python3
"""symbolize.py <samples file> <unstripped binary> : per-function and per-class profile."""
import bisect
import collections
import os
import re
import subprocess
import sys

samples_file, binary = sys.argv[1], sys.argv[2]
top = int(sys.argv[3]) if len(sys.argv) > 3 else 25

maps = []      # (start, end, offset, path)
samples = []
with open(samples_file) as f:
    for line in f:
        if line.startswith("M "):
            p = line[2:].split()
            lo, hi = (int(x, 16) for x in p[0].split("-"))
            maps.append((lo, hi, int(p[2], 16), p[5] if len(p) > 5 else "[anon]"))
        elif line.startswith("S "):
            samples.append(int(line[2:], 16))

real = os.path.realpath(binary)
exe = [m for m in maps if os.path.basename(m[3]) == os.path.basename(real)]
base = min(m[0] - m[2] for m in exe)

syms = []
out = subprocess.run(["nm", "-n", "-C", "--defined-only", binary], capture_output=True, text=True).stdout
for line in out.splitlines():
    p = line.split(" ", 2)
    if len(p) == 3 and p[1] in "tTwW":
        syms.append((int(p[0], 16), p[2]))
addrs = [s[0] for s in syms]

def group(name):
    m = re.search(r"openmsx::(?:\(anonymous namespace\)::)?(\w+)", name)
    if m:
        return m.group(1)
    return name.split("(")[0][:40]

funcs = collections.Counter()
groups = collections.Counter()
for a in samples:
    hit = next((m for m in maps if m[0] <= a < m[1]), None)
    if hit is None:
        name = grp = "[unknown]"
    elif hit in exe:
        i = bisect.bisect_right(addrs, a - base) - 1
        name = syms[i][1] if i >= 0 else "[exe?]"
        grp = group(name)
    else:
        name = grp = "lib:" + os.path.basename(hit[3])
    funcs[name] += 1
    groups[grp] += 1

n = len(samples)
print(f"samples: {n}")
print("-- by class / library")
for g, c in groups.most_common(top):
    print(f"{100.0 * c / n:6.2f}%  {g}")
print("-- by function")
for g, c in funcs.most_common(top):
    print(f"{100.0 * c / n:6.2f}%  {g[:150]}")
