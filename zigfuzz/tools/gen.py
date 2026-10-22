#!/usr/bin/env python3
"""Throwaway generator used to eyeball the converted grammar before building
Grammar-Mutator against it. Same budget idea as grammar_generator: a byte budget
that steers the choice toward the cheapest alternative as it runs out."""
import json
import random
import sys


def min_len(g, memo, k, seen=()):
    if k in memo:
        return memo[k]
    if k in seen:
        return 10 ** 6
    best = 10 ** 6
    for alt in g[k]:
        n = 0
        for t in alt:
            n += min_len(g, memo, t, seen + (k,)) if t in g else len(t)
        best = min(best, n)
    if k not in seen:
        memo[k] = best
    return best


def gen(g, memo, k, budget, out, depth=0):
    alts = g[k]
    if depth > 400:
        alts = sorted(alts, key=lambda a: sum(memo.get(t, len(t)) for t in a))[:1]
    elif budget <= 0:
        cheap = min(sum(memo.get(t, len(t)) for t in a) for a in alts)
        alts = [a for a in alts if sum(memo.get(t, len(t)) for t in a) == cheap]
    alt = random.choice(alts)
    for t in alt:
        if t in g:
            budget = gen(g, memo, t, budget, out, depth + 1)
        else:
            out.append(t)
            budget -= len(t)
    return budget


if __name__ == '__main__':
    g = json.load(open(sys.argv[1]))
    n = int(sys.argv[2]); size = int(sys.argv[3]); outdir = sys.argv[4]
    random.seed(int(sys.argv[5]) if len(sys.argv) > 5 else 0)
    memo = {}
    for k in g:
        min_len(g, memo, k)
    import os
    os.makedirs(outdir, exist_ok=True)
    for i in range(n):
        out = []
        gen(g, memo, '<START>', size, out)
        open('%s/p%05d.zig' % (outdir, i), 'w').write(''.join(out))
    print('wrote %d programs to %s' % (n, outdir))
