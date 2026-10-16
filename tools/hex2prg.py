#!/usr/bin/env python3
"""Split Calypsi's Intel hex output into C64 PRG files, one per contiguous
run of bytes (the C build has two: $0801.. and the data under the KERNAL
at $E000..). Each is written as <stem>-<addr>.prg, lowest address first,
and their names are printed for the Makefile to hand to exomizer.

    python3 tools/hex2prg.py c/build/game-c.hex c/build/game-c
"""
import sys


def main():
    src, stem = sys.argv[1], sys.argv[2]
    mem, base = {}, 0
    with open(src, encoding="ascii") as f:
        for line in f:
            line = line.strip()
            if not line.startswith(":"):
                continue
            b = bytes.fromhex(line[1:])
            n, addr, kind, data = b[0], b[1] << 8 | b[2], b[3], b[4:4 + b[0]]
            if kind == 0:
                for i, v in enumerate(data):
                    mem[base + addr + i] = v
            elif kind == 4:
                base = (data[0] << 8 | data[1]) << 16
            elif kind == 2:
                base = (data[0] << 8 | data[1]) << 4
    runs, start, prev = [], None, None
    for a in sorted(mem):
        if start is None or a != prev + 1:
            if start is not None:
                runs.append((start, prev))
            start = a
        prev = a
    if start is not None:
        runs.append((start, prev))
    names = []
    for lo, hi in runs:
        if hi > 0xFFFF:
            sys.exit(f"hex2prg: data above 64K at ${lo:x}")
        name = f"{stem}-{lo:04x}.prg"
        with open(name, "wb") as f:
            f.write(bytes([lo & 0xFF, lo >> 8]))
            f.write(bytes(mem[a] for a in range(lo, hi + 1)))
        names.append(name)
    print(" ".join(names))


if __name__ == "__main__":
    main()
