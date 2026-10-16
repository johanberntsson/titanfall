#!/usr/bin/env python3
r"""Translate ACME data files into C (the Calypsi build, c/).

The asm build's data -- the generated world (src/world.asm), the generated
charset (src/charset.asm), the sprite sets, the title logo and the PETSCII
constants -- is plain ACME data: constants, and labels followed by !byte /
!pet / !fill. Rather than teach every generator a second output format,
this reads those files and writes one C file and one header, so titan.yaml
and the vchar64 exports stay the only sources and the two builds can't
drift apart.

    python3 tools/acme2c.py --sprites-end 0x3800 --out c/build/data \\
        --sprites src/c64_walker_sprites.asm ... \\
        --pinned CHARSET=charset \\
        src/petscii.asm src/titanfall_title.asm src/charset.asm src/world.asm

What it does with each kind of line:

    NAME = expr          #define NAME value (evaluated; addresses aren't known)
    LABEL  !byte ...     const uint8_t LABEL[] = { ... };  (a label's data runs
                         to the next label)
    !pet "text", n       ASCII text, so the C code needs one way to draw text
                         (scr() in c/src/screen.c): a-z stay lower case ASCII,
                         [ \ ] ^ _ become their screen codes ($1B-$1F),
                         a PETSCII graphic (G_VERT_BAR ...) becomes its screen
                         code, which is always below $60; control bytes (< $20,
                         e.g. the robodex's 0/1/2) pass through
    !fill n[, v]         n bytes of v
    X_LO / X_HI pairs    of <LABEL / >LABEL: one pointer table, X[]
    sprite labels        frame numbers: the sprite files go into one block,
                         SPRITES[], ending at --sprites-end; `label/64` is a
                         sprite pointer, emitted as SPRP_label too

Runtime state -- everything after world.asm's "runtime state" marker, and
the ROOM_WALLS_n grids, which the game writes -- is not const; a runtime
label of one byte becomes a plain variable.
"""

import argparse
import re
import sys

LINE_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)?:?\s*(.*)$")


def die(msg):
    sys.exit(f"acme2c: error: {msg}")


def strip_comment(s):
    """Remove a ; comment, outside of string literals."""
    out, q = [], None
    for ch in s:
        if q:
            out.append(ch)
            if ch == q:
                q = None
        elif ch in "\"'":
            q = ch
            out.append(ch)
        elif ch == ";":
            break
        else:
            out.append(ch)
    return "".join(out).rstrip()


def split_args(s):
    """Split a directive's arguments on commas outside of strings."""
    args, cur, q = [], [], None
    for ch in s:
        if q:
            cur.append(ch)
            if ch == q:
                q = None
        elif ch in "\"'":
            q = ch
            cur.append(ch)
        elif ch == ",":
            args.append("".join(cur).strip())
            cur = []
        else:
            cur.append(ch)
    if "".join(cur).strip():
        args.append("".join(cur).strip())
    return args


def pet2screen(v):
    if v < 0x40:
        return v
    if v < 0x60:
        return v - 0x40
    if v < 0x80:
        return v - 0x20
    if v < 0xA0:
        return v
    if v < 0xC0:
        return v - 0x40
    return v - 0x80


class Conv:
    def __init__(self):
        self.syms = {}         # constants: name -> int
        self.blocks = []       # (label, [items], const, section, comment)
        self.sprite_ptr = {}   # sprite label -> pointer value
        self.order = []        # constant names in order (for the header)

    # ---- expressions ----------------------------------------------------
    def ev(self, expr, what):
        e = expr.strip()
        if e.startswith("<") or e.startswith(">"):
            die(f"{what}: unexpected lo/hi byte operator in {expr!r}")
        if len(e) == 3 and e[0] == "'" and e[2] == "'":
            return ord(e[1])
        py = re.sub(r"\$([0-9A-Fa-f]+)", r"0x\1", e)
        py = re.sub(r"(?<![\w)])%([01]+)", r"0b\1", py)
        py = re.sub(r"\bDIV\b", "//", py)
        py = re.sub(r"(?<!/)/(?!/)", "//", py)

        def ident(m):
            n = m.group(0)
            if n.startswith("0x") or n.startswith("0b"):
                return n
            if n in self.syms:
                return str(self.syms[n])
            if n.endswith("//64") or n in self.sprite_ptr:
                return n
            die(f"{what}: unknown symbol {n!r} in {expr!r}")
        # sprite_label/64 -> pointer
        for lab, ptr in self.sprite_ptr.items():
            py = re.sub(rf"\b{lab}\s*//\s*64\b", str(ptr), py)
        py = re.sub(r"\b[A-Za-z_][A-Za-z0-9_]*\b", ident, py)
        try:
            return int(eval(py, {"__builtins__": {}}))
        except Exception as ex:   # noqa: BLE001
            die(f"{what}: cannot evaluate {expr!r} ({ex})")

    # ---- reading --------------------------------------------------------
    def read(self, path, runtime_marker=None, writable=(), pinned=None,
             sprites=False):
        runtime = False
        cur = None
        with open(path, encoding="utf-8") as f:
            for n, raw in enumerate(f, 1):
                where = f"{path}:{n}"
                if runtime_marker and runtime_marker in raw:
                    runtime = True
                line = strip_comment(raw)
                if not line.strip():
                    continue
                s = line.strip()
                if s.startswith("*") or s.startswith("!if") or \
                        s.startswith("!error") or s == "}" or \
                        s.startswith("!eof") or s.startswith("!cpu"):
                    continue
                m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$", s)
                if m:
                    name, expr = m.groups()
                    self.syms[name] = self.ev(expr, where)
                    self.order.append(name)
                    continue
                label, rest = None, s
                if re.match(r"[A-Za-z_]", line):
                    m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*):?\s*(.*)$", s)
                    label, rest = m.group(1), m.group(2)
                if label:
                    const = not (runtime or any(re.fullmatch(w, label)
                                                for w in writable))
                    sec = next((v for k, v in (pinned or {}).items()
                                if re.fullmatch(k, label)), None)
                    cur = [label, [], const, sec, sprites]
                    self.blocks.append(cur)
                if rest:
                    if cur is None:
                        die(f"{where}: data before any label")
                    self.directive(rest, cur[1], where)

    def directive(self, s, items, where):
        m = re.match(r"^(!\w+)\s*(.*)$", s)
        if not m:
            die(f"{where}: cannot parse {s!r}")
        d, args = m.groups()
        if d == "!byte":
            for a in split_args(args):
                a = a.strip()
                if a[0] in "<>":
                    items.append(("ref", a[0], a[1:].strip()))
                else:
                    items.append(("b", self.ev(a, where) & 0xFF))
        elif d == "!fill":
            a = split_args(args)
            cnt = self.ev(a[0], where)
            v = self.ev(a[1], where) if len(a) > 1 else 0
            items.extend([("b", v & 0xFF)] * cnt)
        elif d == "!pet":
            for a in split_args(args):
                if a.startswith('"'):
                    for ch in a[1:-1]:
                        if ch.isupper() or ch == "@":
                            die(f"{where}: {ch!r} in !pet text {a!r}")
                        v = ord(ch)
                        if 0x5B <= v <= 0x5F:   # [ \ ] ^ _: their screen
                            v -= 0x40           #  codes (0x40-0x5F are glyphs)
                        items.append(("b", v))
                else:
                    v = self.ev(a, where) & 0xFF
                    if v >= 0x20:
                        v = pet2screen(v)
                        if not 0x20 <= v < 0x60:
                            die(f"{where}: PETSCII {a} -> screen code ${v:02x}, "
                                "which scr() can't pass through")
                    items.append(("b", v))
        else:
            die(f"{where}: unsupported directive {d}")

    # ---- writing --------------------------------------------------------
    def write(self, out, sprites_end):
        labels = {b[0] for b in self.blocks}
        consts = {b[0]: b[2] for b in self.blocks}
        # lo/hi pointer pairs
        ptrtabs, skip = {}, set()
        for b in self.blocks:
            name = b[0]
            if not name.endswith("_LO"):
                continue
            hi = name[:-3] + "_HI"
            hb = next((x for x in self.blocks if x[0] == hi), None)
            lo_items, hi_items = b[1], hb[1] if hb else None
            if hb is None or not lo_items or any(i[0] != "ref" for i in lo_items) \
                    or len(lo_items) != len(hi_items):
                continue
            targets = [i[2] for i in lo_items]
            if [i[2] for i in hi_items] != targets:
                die(f"{name}/{hi}: lo and hi tables don't match")
            if all(t in labels for t in targets):
                ptrtabs[name[:-3]] = targets
            elif not any(t in labels for t in targets):
                # fixed addresses (e.g. colour RAM): a table of them
                ptrtabs[name[:-3]] = [f"(uint8_t *)0x{self.ev(t, name):04x}"
                                      for t in targets]
                consts.update({t: False for t in ptrtabs[name[:-3]]})
            else:
                die(f"{name}: a mix of labels and addresses")
            skip |= {name, hi}

        h = [
            "/* GENERATED by tools/acme2c.py from the asm build's data files --",
            " * DO NOT EDIT. See c/README.md. */",
            "#ifndef DATA_H", "#define DATA_H", "#include <stdint.h>", "",
        ]
        for name in self.order:
            h.append(f"#define {name} {self.syms[name]}")
        h.append("")
        c = ["/* GENERATED by tools/acme2c.py -- DO NOT EDIT. */",
             '#include "data.h"', ""]

        # sprites: one block ending at sprites_end
        spr = [b for b in self.blocks if b[4]]
        nframes = sum(len(b[1]) for b in spr) // 64
        if spr:
            base = sprites_end - nframes * 64
            h.append(f"#define SPRITES_START 0x{base:04x}")
            h.append(f"#define SPRITE_FRAMES {nframes}")
            frame = 0
            body = []
            for b in spr:
                if len(b[1]) % 64:
                    die(f"{b[0]}: sprite data not whole frames")
                h.append(f"#define SPRP_{b[0]} {base // 64 + frame}")
                frame += len(b[1]) // 64
                body.extend(i[1] for i in b[1])
            h.append("extern uint8_t SPRITES[SPRITE_FRAMES * 64];")
            c.append('__attribute__((section("sprites")))')
            c.append(f"uint8_t SPRITES[{len(body)}] = {{")
            c += fmt(body)
            c.append("};")
            h.append("")

        for b in self.blocks:
            name, items, const, sec, is_spr = b
            if is_spr or name in skip:
                continue
            if not items:
                # an alias: the next block's data
                nxt = self.blocks[self.blocks.index(b) + 1]
                h.append(f"#define {name} {nxt[0]}")
                continue
            if any(i[0] != "b" for i in items):
                die(f"{name}: lo/hi references outside a pointer table pair")
            vals = [i[1] for i in items]
            q = "const " if const else ""
            attr = f'__attribute__((section("{sec}"))) ' if sec else ""
            if not const and len(vals) == 1:
                h.append(f"extern uint8_t {name};")
                c.append(f"uint8_t {name} = {vals[0]};")
                continue
            h.append(f"extern {q}uint8_t {name}[{len(vals)}];")
            if not const and not any(vals):
                c.append(f"{attr}uint8_t {name}[{len(vals)}];")
            else:
                c.append(f"{attr}{q}uint8_t {name}[{len(vals)}] = {{")
                c += fmt(vals)
                c.append("};")
        h.append("")
        for name, targets in ptrtabs.items():
            q = "const " if all(consts[t] for t in targets) else ""
            h.append(f"extern {q}uint8_t *const {name}[{len(targets)}];")
            c.append(f"{q}uint8_t *const {name}[{len(targets)}] = {{")
            c += ["    " + ", ".join(targets[i:i + 6]) + ","
                  for i in range(0, len(targets), 6)]
            c.append("};")
        h += ["", "#endif"]
        with open(out + ".h", "w", encoding="utf-8") as f:
            f.write("\n".join(h) + "\n")
        with open(out + ".c", "w", encoding="utf-8") as f:
            f.write("\n".join(c) + "\n")


def fmt(vals):
    return ["    " + ",".join(f"0x{v:02x}" for v in vals[i:i + 16]) + ","
            for i in range(0, len(vals), 16)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True, help="output path without .c/.h")
    ap.add_argument("--sprites", nargs="*", default=[])
    ap.add_argument("--sprites-end", type=lambda s: int(s, 0), default=0x3800)
    ap.add_argument("--extra-frames", type=int, default=0,
                    help="zero frames appended to the sprite block (CS_FRAMES)")
    ap.add_argument("--pinned", action="append", default=[],
                    help="REGEX=section: put the labels matching REGEX in "
                         "that section")
    ap.add_argument("--writable", action="append", default=[r"ROOM_WALLS_\d+"],
                    help="regex of labels the game writes (not const)")
    ap.add_argument("--defs", action="append", default=[],
                    help="read for its constants only, not emitted (petscii.asm)")
    ap.add_argument("files", nargs="+")
    a = ap.parse_args()
    cv = Conv()
    pinned = dict(p.split("=", 1) for p in a.pinned)
    # the sprites first: their pointers are needed by the world data
    for p in a.sprites:
        cv.read(p, sprites=True)
    if a.extra_frames:
        cv.blocks.append(["CS_FRAMES", [("b", 0)] * (64 * a.extra_frames),
                          False, None, True])
    nframes = sum(len(b[1]) for b in cv.blocks if b[4]) // 64
    base = a.sprites_end - nframes * 64
    frame = 0
    for b in cv.blocks:
        cv.sprite_ptr[b[0]] = base // 64 + frame
        frame += len(b[1]) // 64
    for p in a.defs:
        n = len(cv.order)
        cv.read(p)
        del cv.order[n:]
    for p in a.files:
        cv.read(p, runtime_marker="---- runtime state", writable=a.writable,
                pinned=pinned)
    cv.write(a.out, a.sprites_end)


if __name__ == "__main__":
    main()
