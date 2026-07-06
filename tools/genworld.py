#!/usr/bin/env python3
"""Generate src/world.asm from titan.yaml.

Emits ACME data tables (no code) describing the game world: rooms, actors
(robots), items, doors, lasers and terminal zones, plus the room map data
converted from the vchar64 ASM exports (.byte -> !byte). The game code in
src/game.asm etc. is fully table-driven and only knows about the labels and
NUM_* constants emitted here.

Usage: python3 tools/genworld.py titan.yaml src/world.asm
"""

import sys

import yaml

C64_COLORS = {
    "black": 0, "white": 1, "red": 2, "cyan": 3, "purple": 4, "green": 5,
    "blue": 6, "yellow": 7, "orange": 8, "brown": 9, "ltred": 10,
    "dgray": 11, "mgray": 12, "ltgreen": 13, "ltblue": 14, "ltgray": 15,
}

# Characters we allow inside !pet "" strings (lowercase PETSCII text).
PET_SAFE = set("abcdefghijklmnopqrstuvwxyz0123456789 !?.,:;'()+-=*/<>[]#%&@")

ROOM_MAP_BYTES = 22 * 40  # rows x cols of one room's screen-code data

MAX_ROBOTS_PER_ROOM = 2   # hardware sprites 1 and 2 (sprite 0 = player)
LABEL_WIDTH = 12          # status-line item label field width
MSG_INTERIOR = 30         # popup box interior width (matches SBOX_* strings)


def die(msg):
    sys.exit(f"genworld: error: {msg}")


def check_pet(s, what):
    bad = set(s) - PET_SAFE
    if bad:
        die(f"{what}: characters not supported in !pet strings: {sorted(bad)}")
    return s


def byte(v, what):
    if not -128 <= v <= 255:
        die(f"{what}: value {v} does not fit in a byte")
    return v & 0xFF


def tbl(name, values, comment=""):
    out = [f"{name}"]
    if comment:
        out[0] += f"        ; {comment}"
    if values:
        out.append("        !byte " + ",".join(f"${v:02x}" for v in values))
    return "\n".join(out)


def read_vchar64_map(path):
    """Parse a vchar64 ASM export (.byte lines) into a list of byte values."""
    data = []
    try:
        with open(path, encoding="ascii") as f:
            for line in f:
                line = line.strip()
                if line.startswith((".byte", "!byte")):
                    row = line.split(None, 1)[1].split(";")[0]
                    for item in row.split(","):
                        item = item.strip()
                        data.append(int(item[1:], 16) if item.startswith("$")
                                    else int(item, 0))
    except OSError as e:
        die(f"cannot read vchar64 map: {e}")
    if len(data) != ROOM_MAP_BYTES:
        die(f"{path}: expected {ROOM_MAP_BYTES} bytes, found {len(data)}")
    return data


def main():
    if len(sys.argv) != 3:
        die("usage: genworld.py <titan.yaml> <world.asm>")
    cfg_path, out_path = sys.argv[1], sys.argv[2]

    with open(cfg_path, encoding="utf-8") as f:
        cfg = yaml.safe_load(f)

    rooms = cfg.get("rooms") or []
    if not rooms:
        die("config must define at least one room")
    room_index = {}
    for i, room in enumerate(rooms):
        name = room.get("name") or die("every room needs a name")
        if name in room_index:
            die(f"duplicate room name: {name}")
        room_index[name] = i

    # ---- game globals -------------------------------------------------
    game = cfg.get("game") or {}
    start_room = game.get("start_room", rooms[0]["name"])
    if start_room not in room_index:
        die(f"game.start_room: unknown room {start_room!r}")
    try:
        clk_h, clk_m, clk_s = (int(p) for p in str(game["start_time"]).split(":"))
    except (KeyError, ValueError):
        die("game.start_time must look like \"05:47:33\"")
    if not (0 <= clk_m < 60 and 0 <= clk_s < 60):
        die("game.start_time: minutes/seconds must be 0-59")
    penalty = int(game.get("death_penalty_minutes", 30))
    if not 0 < penalty < 60:
        die("game.death_penalty_minutes must be 1-59 (APPLY_DEATH_PENALTY "
            "borrows at most one hour)")

    # ---- actor types ---------------------------------------------------
    types = cfg.get("actor_types") or die("config needs an actor_types section")
    type_index = {name: i for i, name in enumerate(types)}
    type_sprite, type_color = [], []
    for name, t in types.items():
        type_sprite.append(t["sprite"])  # label; ACME computes /64 pointer
        color = str(t.get("color", "ltgray")).lower()
        if color not in C64_COLORS:
            die(f"actor type {name}: unknown color {color!r}")
        type_color.append(C64_COLORS[color])
        ai = t.get("ai")
        if name != "human" and ai != "patrol":
            die(f"actor type {name}: only ai: patrol is implemented")

    # ---- items ---------------------------------------------------------
    items = cfg.get("items") or {}
    item_index = {name: i for i, name in enumerate(items)}
    item_labels, item_msgs = [], []
    for name, it in items.items():
        label = check_pet(str(it.get("label", name)), f"item {name} label")
        if len(label) > LABEL_WIDTH:
            die(f"item {name}: label longer than {LABEL_WIDTH} chars")
        item_labels.append(label.ljust(LABEL_WIDTH))
        text = check_pet(str(it.get("found_text", f"{name} found!")),
                         f"item {name} found_text")
        if len(text) > MSG_INTERIOR:
            die(f"item {name}: found_text longer than {MSG_INTERIOR} chars")
        item_msgs.append(f"    |{text.center(MSG_INTERIOR)}|    ")

    # ---- walk rooms, flattening everything into parallel arrays --------
    act = {k: [] for k in ("type", "room", "sx", "sy", "wx0", "wy0", "wx1", "wy1")}
    actor_ids = {}
    item_pos = {}                       # item index -> (room, x, y)
    door = {k: [] for k in ("room", "x1", "y1", "x2", "y2", "dest", "ax", "ay", "key")}
    laser = {k: [] for k in ("room", "x1", "y1", "x2", "y2")}
    termz = {k: [] for k in ("room", "x1", "y1", "x2", "y2")}

    for ri, room in enumerate(rooms):
        rname = room["name"]
        b = room.get("bounds") or die(f"room {rname}: needs bounds")
        room.setdefault("_maxx", int(b["max_x"]))
        room.setdefault("_maxy", int(b["max_y"]))

        robots = room.get("robots") or []
        if len(robots) > MAX_ROBOTS_PER_ROOM:
            die(f"room {rname}: more than {MAX_ROBOTS_PER_ROOM} robots "
                f"(only hardware sprites 1-2 are available per room)")
        for r in robots:
            tname = r.get("type")
            if tname not in type_index or tname == "human":
                die(f"room {rname}: robot has bad type {tname!r}")
            if rid := r.get("id"):
                if rid in actor_ids:
                    die(f"duplicate robot id {rid!r}")
                actor_ids[rid] = len(act["type"])
            start = r["start"]
            patrol = r.get("patrol") or [start, start]
            if len(patrol) != 2:
                die(f"room {rname}: patrol must be exactly 2 waypoints")
            act["type"].append(type_index[tname])
            act["room"].append(ri)
            act["sx"].append(int(start["x"]))
            act["sy"].append(int(start["y"]))
            act["wx0"].append(int(patrol[0]["x"]))
            act["wy0"].append(int(patrol[0]["y"]))
            act["wx1"].append(int(patrol[1]["x"]))
            act["wy1"].append(int(patrol[1]["y"]))

        for thing in room.get("things") or []:
            iname = thing.get("item")
            if iname not in item_index:
                die(f"room {rname}: unknown item {iname!r}")
            ii = item_index[iname]
            if ii in item_pos:
                die(f"item {iname!r} placed more than once")
            item_pos[ii] = (ri, int(thing["at"]["x"]), int(thing["at"]["y"]))

        for l in room.get("lasers") or []:
            laser["room"].append(ri)
            for k in ("x1", "y1", "x2", "y2"):
                laser[k].append(int(l[k]))

        for t in room.get("terminals") or []:
            termz["room"].append(ri)
            for k in ("x1", "y1", "x2", "y2"):
                termz[k].append(int(t[k]))

        for d in room.get("doors") or []:
            at = d["at"]
            dest = d.get("leads_to") or die(f"room {rname}: door needs leads_to")
            if dest == "exit":
                dest_i = 0xFF
            elif dest in room_index:
                dest_i = room_index[dest]
            else:
                die(f"room {rname}: door leads_to unknown room {dest!r}")
            arrive = d.get("arrive") or {}
            key = d.get("key")
            if key is not None and key not in item_index:
                die(f"room {rname}: door key references unknown item {key!r}")
            door["room"].append(ri)
            for k in ("x1", "y1", "x2", "y2"):
                door[k].append(int(at[k]))
            door["dest"].append(dest_i)
            door["ax"].append(0xFF if "x" not in arrive else int(arrive["x"]))
            door["ay"].append(0xFF if "y" not in arrive else int(arrive["y"]))
            door["key"].append(0 if key is None else item_index[key] + 1)

    for iname, ii in item_index.items():
        if ii not in item_pos:
            die(f"item {iname!r} is never placed in a room")

    # ---- emit ----------------------------------------------------------
    o = []
    o.append("; =============================================================================")
    o.append("; GENERATED FILE -- DO NOT EDIT.")
    o.append(f"; Built from {cfg_path} by tools/genworld.py (run `make` to regenerate).")
    o.append("; Data tables only, no code. See titan.yaml for the world definition.")
    o.append("; =============================================================================")
    o.append("")
    o.append(f"NUM_ROOMS     = {len(rooms)}")
    o.append(f"NUM_ACTORS    = {len(act['type'])}")
    o.append(f"NUM_ITEMS     = {len(items)}")
    o.append(f"NUM_DOORS     = {len(door['room'])}")
    o.append(f"NUM_LASERS    = {len(laser['room'])}")
    o.append(f"NUM_TERMZONES = {len(termz['room'])}")
    o.append(f"START_ROOM    = {room_index[start_room]}")
    o.append(f"CFG_CLK_H     = {clk_h}")
    o.append(f"CFG_CLK_M     = {clk_m}")
    o.append(f"CFG_CLK_S     = {clk_s}")
    o.append(f"CFG_PENALTY_M = {penalty}")
    for rid, ai in actor_ids.items():
        o.append(f"ACTOR_{rid.upper()} = {ai}   ; actor index")
    for iname, ii in item_index.items():
        o.append(f"ITEM_{iname.upper()} = {ii}   ; item index")
    o.append("")

    o.append("; ---- actor types (indexed by ACT_TYPE) ----")
    o.append("TYPE_SPRPTR     ; sprite pointer byte (sprite data address / 64)")
    o.append("        !byte " + ",".join(f"{s}/64" for s in type_sprite))
    o.append(tbl("TYPE_COLOR", type_color, "sprite colour"))
    o.append("")

    o.append("; ---- rooms ----")
    o.append("ROOM_MAP_LO     ; pointer to 22x40 screen-code map data")
    o.append("        !byte " + ",".join(f"<ROOM_MAP_{i}" for i in range(len(rooms))))
    o.append("ROOM_MAP_HI")
    o.append("        !byte " + ",".join(f">ROOM_MAP_{i}" for i in range(len(rooms))))
    for name, key, comment in (
            ("ROOM_MAXX", "_maxx", "walkable tile range 0..max"),
            ("ROOM_MAXY", "_maxy", ""),
    ):
        o.append(tbl(name, [byte(r[key], name) for r in rooms], comment))
    o.append(tbl("ROOM_PSX", [byte(int(r["player_start"]["x"]), "ROOM_PSX") for r in rooms],
                 "player start position"))
    o.append(tbl("ROOM_PSY", [byte(int(r["player_start"]["y"]), "ROOM_PSY") for r in rooms]))
    o.append("")

    o.append("; ---- sector map view: highlight box per room (colour RAM) ----")
    hl_addr = []
    for r in rooms:
        mv = r.get("map_view") or die(f"room {r['name']}: needs map_view")
        hl_addr.append((int(mv["row"]), int(mv["col"]), int(mv["width"]), int(mv["height"])))
    o.append("MAPHL_LO        ; CRAM address of the box's top-left corner")
    o.append("        !byte " + ",".join(f"<($D800+{row}*40+{col})" for row, col, _, _ in hl_addr))
    o.append("MAPHL_HI")
    o.append("        !byte " + ",".join(f">($D800+{row}*40+{col})" for row, col, _, _ in hl_addr))
    o.append(tbl("MAPHL_W", [byte(w, "MAPHL_W") for _, _, w, _ in hl_addr]))
    o.append(tbl("MAPHL_H", [byte(h, "MAPHL_H") for _, _, _, h in hl_addr]))
    o.append("")

    o.append("; ---- actors (robots; the player is not in this table) ----")
    for name, key, comment in (
            ("ACT_TYPE", "type", "index into TYPE_* tables"),
            ("ACT_ROOM", "room", ""),
            ("ACT_SX", "sx", "start position (RESET_ROUND copies to ACT_X/Y)"),
            ("ACT_SY", "sy", ""),
            ("ACT_WX0", "wx0", "patrol waypoint 0"),
            ("ACT_WY0", "wy0", ""),
            ("ACT_WX1", "wx1", "patrol waypoint 1"),
            ("ACT_WY1", "wy1", "")):
        o.append(tbl(name, [byte(v, name) for v in act[key]], comment))
    o.append("")

    o.append("; ---- items ----")
    ipr = [item_pos[i] for i in range(len(items))]
    o.append(tbl("ITEM_ROOM", [byte(p[0], "ITEM_ROOM") for p in ipr]))
    o.append(tbl("ITEM_X", [byte(p[1], "ITEM_X") for p in ipr]))
    o.append(tbl("ITEM_Y", [byte(p[2], "ITEM_Y") for p in ipr]))
    if items:
        o.append("ITEM_LABEL_LO   ; 12-char status-line label")
        o.append("        !byte " + ",".join(f"<ITEM_LBL_{i}" for i in range(len(items))))
        o.append("ITEM_LABEL_HI")
        o.append("        !byte " + ",".join(f">ITEM_LBL_{i}" for i in range(len(items))))
        o.append("ITEM_MSG_LO     ; 40-char popup message row")
        o.append("        !byte " + ",".join(f"<ITEM_MSG_{i}" for i in range(len(items))))
        o.append("ITEM_MSG_HI")
        o.append("        !byte " + ",".join(f">ITEM_MSG_{i}" for i in range(len(items))))
        for i, (label, msg) in enumerate(zip(item_labels, item_msgs)):
            o.append(f'ITEM_LBL_{i} !pet "{label}"')
            o.append(f'ITEM_MSG_{i} !pet "{msg}"')
    else:
        o.append("ITEM_LABEL_LO")
        o.append("ITEM_LABEL_HI")
        o.append("ITEM_MSG_LO")
        o.append("ITEM_MSG_HI")
    o.append("")

    o.append("; ---- doors (rects just outside the walkable range) ----")
    for name, key, comment in (
            ("DOOR_ROOM", "room", ""),
            ("DOOR_X1", "x1", "trigger rectangle"),
            ("DOOR_Y1", "y1", ""),
            ("DOOR_X2", "x2", ""),
            ("DOOR_Y2", "y2", ""),
            ("DOOR_DEST", "dest", "destination room, $ff = mission exit (win)"),
            ("DOOR_AX", "ax", "arrival position, $ff = keep current"),
            ("DOOR_AY", "ay", ""),
            ("DOOR_KEY", "key", "required item index + 1, 0 = none")):
        o.append(tbl(name, [byte(v, name) for v in door[key]], comment))
    o.append("")

    o.append("; ---- lasers ----")
    for name, key in (("LASER_ROOM", "room"), ("LASER_X1", "x1"), ("LASER_Y1", "y1"),
                      ("LASER_X2", "x2"), ("LASER_Y2", "y2")):
        o.append(tbl(name, [byte(v, name) for v in laser[key]]))
    o.append("")

    o.append("; ---- terminal zones (press space inside to open the terminal) ----")
    for name, key in (("TERMZ_ROOM", "room"), ("TERMZ_X1", "x1"), ("TERMZ_Y1", "y1"),
                      ("TERMZ_X2", "x2"), ("TERMZ_Y2", "y2")):
        o.append(tbl(name, [byte(v, "termz") for v in termz[key]]))
    o.append("")

    o.append("; ---- room map data: 22 rows x 40 chars of raw screen codes ----")
    o.append("; (from the vchar64 exports -- blitted directly, no PET2SCREEN)")
    for i, room in enumerate(rooms):
        path = room.get("vchar64_map") or die(f"room {room['name']}: needs vchar64_map")
        data = read_vchar64_map(path)
        o.append(f"ROOM_MAP_{i}      ; {room['name']} -- {path}")
        for off in range(0, len(data), 16):
            row = ",".join(f"${b:02x}" for b in data[off:off + 16])
            o.append(f"!byte {row}\t; {off}")
    o.append("")

    o.append("; ---- runtime state (RAM, initialised by SETUP_GAME/RESET_ROUND) ----")
    o.append("ACT_X       !fill NUM_ACTORS    ; current position")
    o.append("ACT_Y       !fill NUM_ACTORS")
    o.append("ACT_TGT     !fill NUM_ACTORS    ; current patrol target waypoint (0/1)")
    o.append("ACT_ALIVE   !fill NUM_ACTORS    ; 0 = destroyed (hidden, no patrol/link)")
    o.append("ITEM_STATE  !fill NUM_ITEMS+1   ; 0=hidden 1=carried 2=used (+1 pads the empty case)")
    o.append("LASER_STATE !fill NUM_LASERS+1  ; 0=active 1=destroyed")
    o.append("SPR_SLOT_ACT !fill 2            ; actor shown by hw sprite 1/2, $ff = none")
    o.append("")

    with open(out_path, "w", encoding="ascii") as f:
        f.write("\n".join(o))
    print(f"genworld: wrote {out_path}: {len(rooms)} rooms, {len(act['type'])} actors, "
          f"{len(items)} items, {len(door['room'])} doors, {len(laser['room'])} lasers")


if __name__ == "__main__":
    main()
