#!/usr/bin/env python3
"""The asm build against the C build, module by module (`make compare`).

    python3 tools/compare.py ASM_REPORT

ASM_REPORT is ACME's report file (-r) for src/titanfall.asm: every byte is
counted for the source file that produced it (code, strings, tables and
buffers -- the generated world data, charset, sprites and logo are left out,
they're the same data in both builds). For the C build the compiler's list
files (c/build/*.lst) give the same per module: every section, zero-page and
bss included. game.asm is ported as game.c + move.c + actors.c, titanfall.asm
as main.c + screen.c (+ irq.s, whose bytes the assembler's list doesn't
show; it's ~150).
"""
import collections
import glob
import os
import re
import sys

SHARED = {"world.asm", "charset.asm", "titanfall_title.asm", "petscii.asm"}
GROUPS = {"titanfall.asm": ["main", "screen"], "game.asm": ["game", "move", "actors"]}


def asm_sizes(report):
    cur, recs = None, []
    for line in open(report, errors="replace"):
        m = re.match(r"; \*+ Source: (\S+)", line)
        if m:
            cur = os.path.basename(m.group(1))
            continue
        m = re.match(r"\s*\d+\s+([0-9a-f]{4}) ", line)
        if m:
            recs.append((int(m.group(1), 16), cur))
    recs.sort()
    size = collections.Counter()
    for (a, f), (b, _) in zip(recs, recs[1:]):
        if 0 < b - a < 0x400:       # (a gap: a new segment)
            size[f] += b - a
    return size


def c_sizes(lst):
    c, sec = collections.Counter(), "?"
    for line in open(lst, errors="replace"):
        m = re.match(r"^\s+\\ [0-9a-f]{4}\s+\.section\s+(\w+)", line)
        if m:
            sec = m.group(1)
            continue
        m = re.match(r"^\s+\\ [0-9a-f]{4} ([0-9a-f.]+)\s", line)
        if m:
            c[sec] += len(m.group(1)) // 2
        m = re.match(r"^\s+\\ [0-9a-f]{4}\s+(?:\S+:)?\s*\.space\s+(0x[0-9a-f]+|\d+)", line)
        if m:
            c[sec] += int(m.group(1), 0)
    return c


def lines(path):
    n = 0
    for line in open(path):
        s = line.strip()
        if s and not s.startswith((";", "/*", "*", "//")):
            n += 1
    return n


def main():
    asm = asm_sizes(sys.argv[1])
    mods = sorted((f for f in asm if f not in SHARED and not f.startswith("c64_")),
                  key=lambda f: -asm[f])
    print(f"{'asm module':16s} {'asm B':>6s} {'C B':>6s} {'C code':>7s} {'C/asm':>6s} "
          f"{'asm lines':>9s} {'C lines':>8s}")
    tot = collections.Counter()
    for mod in mods:
        cs = GROUPS.get(mod, [mod[:-4]])
        sizes = [c_sizes(f"c/build/{x}.lst") for x in cs if os.path.exists(f"c/build/{x}.lst")]
        cb = sum(sum(s.values()) for s in sizes)
        cc = sum(s["code"] + s["lowcode"] for s in sizes)
        la = lines(f"src/{mod}")
        lc = sum(lines(f"c/src/{x}.c") for x in cs)
        print(f"{mod:16s} {asm[mod]:6d} {cb:6d} {cc:7d} {cb / asm[mod]:6.2f} {la:9d} {lc:8d}")
        tot.update(a=asm[mod], c=cb, cc=cc, la=la, lc=lc)
    print(f"{'total':16s} {tot['a']:6d} {tot['c']:6d} {tot['cc']:7d} "
          f"{tot['c'] / tot['a']:6.2f} {tot['la']:9d} {tot['lc']:8d}")
    print(f"\n(asm: titanfall.asm includes the sprite block's 256-byte CS_FRAMES; "
          f"C lines leave out titan.h ({lines('c/src/titan.h')}) and irq.s "
          f"({lines('c/src/irq.s')}))")


if __name__ == "__main__":
    main()
