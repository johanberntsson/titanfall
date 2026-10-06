#!/usr/bin/env python3
"""Generate src/charset.asm from the vchar64 charset + tile colour exports.

vchar64's ASM export is labelled ACME-compatible but uses .byte (64tass /
KickAssembler syntax); this re-emits the data as !byte under the labels the
game uses: TILE_COLORS (256 bytes, floats right after the code) and CHARSET
(2048 bytes, pinned at $2800).

Usage: python3 tools/gencharset.py <charset.s> <tile-colors.s> <charset.asm>
"""

import sys


def die(msg):
    sys.exit(f"gencharset: error: {msg}")


def read_bytes(path, expect):
    """All values of the .byte/!byte lines of a vchar64 ASM export."""
    data = []
    try:
        with open(path, encoding="ascii") as f:
            for line in f:
                line = line.strip()
                if not line.startswith((".byte", "!byte")):
                    continue
                for item in line.split(None, 1)[1].split(";")[0].split(","):
                    item = item.strip()
                    data.append(int(item[1:], 16) if item.startswith("$") else int(item, 0))
    except (OSError, ValueError) as e:
        die(f"{path}: {e}")
    if len(data) != expect:
        die(f"{path}: expected {expect} bytes, found {len(data)}")
    return data


def rows(data, indent=""):
    return [f"{indent}!byte " + ",".join(f"${b:02x}" for b in data[i:i + 16]) + f"\t; {i}"
            for i in range(0, len(data), 16)]


def main():
    if len(sys.argv) != 4:
        die("usage: gencharset.py <charset.s> <tile-colors.s> <charset.asm>")
    charset_path, colors_path, out_path = sys.argv[1:]
    charset = read_bytes(charset_path, 2048)
    colors = read_bytes(colors_path, 256)

    o = [
        "; =============================================================================",
        "; GENERATED FILE -- DO NOT EDIT.",
        f"; Built from {charset_path} and {colors_path}",
        "; by tools/gencharset.py (run `make` to regenerate) -- edit the art in vchar64.",
        "; Custom room charset + per-character colour table. A-Z, digits, and the",
        "; box-drawing glyphs used by the intro/gameover/win screens keep their",
        "; default ROM shapes; only unused graphics slots hold room-art tiles.",
        "; =============================================================================",
        "",
        "; ---------------------------------------------------------------------------",
        "; TILE_COLORS -- indexed by screen code, gives the default colour RAM value",
        "; for each room-art tile. Used by DRAW_ROOM/COL_BYTE instead of a switch.",
        "; No fixed address: it follows the code, and must end below CHARSET (see",
        "; the TILE_COLORS gotcha in CLAUDE.md -- ACME only warns on overlap).",
        "; ---------------------------------------------------------------------------",
        "TILE_COLORS",
        *rows(colors),
        "",
        "; ---------------------------------------------------------------------------",
        "; CHARSET -- 2048-byte custom charset at $2800 (2K-aligned, below the sprite",
        "; block at $3000). $D018 = $1A selects screen $0400 / charset $2800.",
        "; ---------------------------------------------------------------------------",
        "        * = $2800",
        "CHARSET",
        *rows(charset),
        "",
    ]
    with open(out_path, "w", encoding="ascii") as f:
        f.write("\n".join(o))
    print(f"gencharset: wrote {out_path}")


if __name__ == "__main__":
    main()
