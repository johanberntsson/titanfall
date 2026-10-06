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

# The tile grid: one tile = 2x2 chars (16x16 px), so a room is 20 x 11 tiles
# (X 0-19, Y 0-10). Wall rows are TILES_X bytes apart (WALL_AT: y*20+x, which
# stays below 256 for the whole room).
TILES_X = 40 // 2
TILES_Y = 22 // 2

MAX_ROBOTS_PER_ROOM = 2   # hardware sprites 1 and 2 (sprite 0 = player)
AI_NAMES = ["patrol", "hunter"]      # ai: values; index = AI_* constant in world.asm
LABEL_WIDTH = 12          # status-line item label field width
MSG_INTERIOR = 30         # popup box interior width (matches SBOX_* strings)
TERM_NAME_WIDTH = 22      # robot name in the terminal menu (cols 5-26; the
                          # status word is drawn at cols 28-36)


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


def laser_art_patches(mapdata, l, laser_tiles, floor_tile, what):
    """Screen cells to repaint when laser l (tile rect) is destroyed.

    Scans the room-map window covered by the laser's tiles (2x2 chars per
    tile, plus one char row above/below to catch emitters) for laser_tiles. Each hit becomes the tile on both sides of it if those
    match (a beam crossing a wall keeps the wall continuous), else floor.
    Returns [(map offset, new screen code), ...].
    """
    c0, r0 = 2 * l["x1"], 2 * l["y1"] - 1
    c1, r1 = 2 * l["x2"] + 1, 2 * l["y2"] + 2
    c0, c1 = max(c0, 0), min(c1, 39)
    r0, r1 = max(r0, 0), min(r1, ROOM_MAP_BYTES // 40 - 1)
    patches = []
    for r in range(r0, r1 + 1):
        for c in range(c0, c1 + 1):
            off = r * 40 + c
            if mapdata[off] not in laser_tiles:
                continue
            left = mapdata[off - 1] if c > 0 else floor_tile
            right = mapdata[off + 1] if c < 39 else floor_tile
            new = left if left == right and left not in laser_tiles else floor_tile
            patches.append((off, new))
    if not patches:
        print(f"genworld: warning: {what}: no laser_tiles found in the room art "
              f"under it (map rows {r0}-{r1}, cols {c0}-{c1}) - nothing will be "
              f"erased when it is destroyed", file=sys.stderr)
    if len(patches) > 85:
        die(f"{what}: too many laser chars to erase ({len(patches)} > 85)")
    return patches


def wall_grid(mapdata, maxx, maxy, solid_tiles):
    """Solid tiles of a room, judged by the art.

    Tile (x, y) is the 2x2 block of map chars cols 2x..2x+1, rows
    2y..2y+1; the sprite standing on it has its feet on that block. The
    tile is solid if any of those 4 chars is in solid_tiles. Returns
    grid[y][x] (bool).
    """
    grid = []
    for y in range(maxy + 1):
        row = []
        for x in range(maxx + 1):
            cells = [mapdata[r * 40 + c]
                     for r in (2 * y, 2 * y + 1) for c in (2 * x, 2 * x + 1)]
            row.append(any(ch in solid_tiles for ch in cells))
        grid.append(row)
    return grid


def find_terminals(mapdata, terminal_tiles):
    """Terminals in a room map: each 4-connected group of terminal chars.

    Returns one (col0, row0, col1, row1) map-char rectangle per terminal.
    """
    seen, found = set(), []
    rows = ROOM_MAP_BYTES // 40
    for r in range(rows):
        for c in range(40):
            if (r, c) in seen or mapdata[r * 40 + c] not in terminal_tiles:
                continue
            todo, cells = [(r, c)], []
            seen.add((r, c))
            while todo:
                cr, cc = todo.pop()
                cells.append((cr, cc))
                for nr, nc in ((cr + 1, cc), (cr - 1, cc), (cr, cc + 1), (cr, cc - 1)):
                    if (0 <= nr < rows and 0 <= nc < 40 and (nr, nc) not in seen
                            and mapdata[nr * 40 + nc] in terminal_tiles):
                        seen.add((nr, nc))
                        todo.append((nr, nc))
            found.append((min(c for _, c in cells), min(r for r, _ in cells),
                          max(c for _, c in cells), max(r for r, _ in cells)))
    return found


def patrol_path(x, y, tx, ty):
    """Tiles visited by ACTOR_PATROL_STEP walking (x,y) -> (tx,ty): X first."""
    tiles = []
    while x != tx:
        x += 1 if tx > x else -1
        tiles.append((x, y))
    while y != ty:
        y += 1 if ty > y else -1
        tiles.append((x, y))
    return tiles


# ---- sector map ---------------------------------------------------------
# The map screen (screen rows 2-23 = 22 rows x 40) is generated from the
# doors: each door's wall gives the direction of the room it leads to, so
# the rooms are laid out on a grid from the start room, then drawn as boxes
# with corridors between connected rooms and an opening + "exit" marker for
# every exit door. Emitted as raw screen codes + a colour per cell.
MAP_ROWS, MAP_COLS = 22, 40
SC_HBAR, SC_VBAR = 0x43, 0x5D            # screen codes of the ROM box glyphs
SC_UL, SC_UR, SC_LL, SC_LR = 0x55, 0x49, 0x4A, 0x4B   # rounded corners
DIRS = {"left": (-1, 0), "right": (1, 0), "up": (0, -1), "down": (0, 1)}
MAP_BOX_H = 4                            # top border, label, blank, bottom
MAP_GAP_X, MAP_GAP_Y = 6, 2              # corridor length between boxes
MAP_EXIT_X, MAP_EXIT_Y = 7, 2            # room an exit marker needs outside


def screen_code(ch):
    """Screen code of a PET_SAFE character (as !pet + PET2SCREEN would)."""
    return ord(ch) - 96 if "a" <= ch <= "z" else ord(ch)


def door_dir(door, room, what):
    """Which wall a door rectangle is on (doors sit just outside the room)."""
    if door["x2"] < 0:
        return "left"
    if door["x1"] > room["_maxx"]:
        return "right"
    if door["y2"] < 0:
        return "up"
    if door["y1"] > room["_maxy"]:
        return "down"
    die(f"{what}: door rectangle is not outside a wall of the room")


def build_map(rooms, start, doors):
    """Lay the rooms out and draw the map. doors: (room, dir, dest or None)."""
    pos = {start: (0, 0)}
    queue = [start]
    while queue:
        ri = queue.pop(0)
        for (r, d, dest) in doors:
            if r != ri or dest is None:
                continue
            dx, dy = DIRS[d]
            want = (pos[ri][0] + dx, pos[ri][1] + dy)
            if dest in pos:
                if pos[dest] != want:
                    die(f"map: room {rooms[ri]['name']}'s {d} door leads to "
                        f"{rooms[dest]['name']}, which other doors put elsewhere")
                continue
            if want in pos.values():
                die(f"map: room {rooms[dest]['name']} would overlap another "
                    f"room ({d} of {rooms[ri]['name']})")
            pos[dest] = want
            queue.append(dest)
    for ri, room in enumerate(rooms):
        if ri not in pos:
            die(f"map: room {room['name']} can't be reached through doors "
                f"from the start room")
    minx = min(x for x, _ in pos.values())
    miny = min(y for _, y in pos.values())
    pos = {ri: (x - minx, y - miny) for ri, (x, y) in pos.items()}
    gw = max(x for x, _ in pos.values()) + 1
    gh = max(y for _, y in pos.values()) + 1
    exits = [(r, d) for (r, d, dest) in doors if dest is None]
    for r, d in exits:
        dx, dy = DIRS[d]
        if (pos[r][0] + dx, pos[r][1] + dy) in pos.values():
            die(f"map: room {rooms[r]['name']}'s {d} exit faces another room")

    labels = [r["_label"] for r in rooms]
    lm = MAP_EXIT_X if any(d == "left" and pos[r][0] == 0 for r, d in exits) else 0
    rm = MAP_EXIT_X if any(d == "right" and pos[r][0] == gw - 1 for r, d in exits) else 0
    tm = MAP_EXIT_Y if any(d == "up" and pos[r][1] == 0 for r, d in exits) else 0
    bm = MAP_EXIT_Y if any(d == "down" and pos[r][1] == gh - 1 for r, d in exits) else 0
    min_w = max(len(l) for l in labels) + 4
    box_w = 12
    while box_w > min_w and lm + rm + gw * box_w + (gw - 1) * MAP_GAP_X > MAP_COLS - 2:
        box_w -= 1
    box_w = max(box_w, min_w)
    total_w = lm + rm + gw * box_w + (gw - 1) * MAP_GAP_X
    grid_h = tm + bm + gh * MAP_BOX_H + (gh - 1) * MAP_GAP_Y
    block_h = 2 + grid_h + 2                 # title, blank, grid, blank, prompt
    if total_w > MAP_COLS - 2 or block_h > MAP_ROWS:
        die(f"map: {gw}x{gh} rooms don't fit on the map screen "
            f"({total_w} cols, {block_h} rows)")

    scr = [[0x20] * MAP_COLS for _ in range(MAP_ROWS)]
    col = [[C64_COLORS["dgray"]] * MAP_COLS for _ in range(MAP_ROWS)]

    def put(r, c, code, colour):
        scr[r][c] = code
        col[r][c] = C64_COLORS[colour]

    def text(r, c, t, colour):
        for i, ch in enumerate(t):
            put(r, c + i, screen_code(ch), colour)

    top = (MAP_ROWS - block_h) // 2
    text(top, (MAP_COLS - 14) // 2, "* sector map *", "yellow")
    text(top + block_h - 1, (MAP_COLS - 20) // 2, "press fire to return", "mgray")
    gx0 = (MAP_COLS - total_w) // 2 + lm
    gy0 = top + 2 + tm

    def box_at(ri):
        x, y = pos[ri]
        return gy0 + y * (MAP_BOX_H + MAP_GAP_Y), gx0 + x * (box_w + MAP_GAP_X)

    boxes = []
    for ri in range(len(rooms)):
        r, c = box_at(ri)
        boxes.append((r, c))
        put(r, c, SC_UL, "dgray"); put(r, c + box_w - 1, SC_UR, "dgray")
        put(r + 3, c, SC_LL, "dgray"); put(r + 3, c + box_w - 1, SC_LR, "dgray")
        for i in range(1, box_w - 1):
            put(r, c + i, SC_HBAR, "dgray"); put(r + 3, c + i, SC_HBAR, "dgray")
        for i in (1, 2):
            put(r + i, c, SC_VBAR, "dgray"); put(r + i, c + box_w - 1, SC_VBAR, "dgray")
        text(r + 1, c + (box_w - len(labels[ri])) // 2, labels[ri], "dgray")

    mid = box_w // 2 - 1                     # vertical corridor/exit columns: mid, mid+1
    drawn = set()
    for (a, d, b) in doors:
        if b is None or frozenset((a, b)) in drawn:
            continue
        drawn.add(frozenset((a, b)))
        if d in ("left", "up"):
            a, b = b, a                      # a = left/top room
        (ra, ca), (rb, cb) = boxes[a], boxes[b]
        if d in ("left", "right"):           # walls turn into a corridor
            l, rr = ca + box_w - 1, cb
            put(ra + 1, l, SC_LL, "cyan"); put(ra + 1, rr, SC_LR, "cyan")
            put(ra + 2, l, SC_UL, "cyan"); put(ra + 2, rr, SC_UR, "cyan")
            for c in range(l + 1, rr):
                put(ra + 1, c, SC_HBAR, "cyan"); put(ra + 2, c, SC_HBAR, "cyan")
        else:
            bot, tp = ra + 3, rb
            put(bot, ca + mid, SC_UR, "cyan"); put(bot, ca + mid + 1, SC_UL, "cyan")
            put(tp, ca + mid, SC_LR, "cyan"); put(tp, ca + mid + 1, SC_LL, "cyan")
            for r in range(bot + 1, tp):
                put(r, ca + mid, SC_VBAR, "cyan"); put(r, ca + mid + 1, SC_VBAR, "cyan")
    for (ri, d) in exits:                    # opening in the wall + "exit"
        r, c = boxes[ri]
        if d == "down":
            put(r + 3, c + mid, 0x20, "white"); put(r + 3, c + mid + 1, 0x20, "white")
            put(r + 4, c + mid, SC_VBAR, "white"); put(r + 4, c + mid + 1, SC_VBAR, "white")
            text(r + 5, c + mid - 1, "exit", "white")
        elif d == "up":
            put(r, c + mid, 0x20, "white"); put(r, c + mid + 1, 0x20, "white")
            put(r - 1, c + mid, SC_VBAR, "white"); put(r - 1, c + mid + 1, SC_VBAR, "white")
            text(r - 2, c + mid - 1, "exit", "white")
        else:
            w = c if d == "left" else c + box_w - 1
            s = -1 if d == "left" else 1
            for i in (1, 2):
                put(r + i, w, 0x20, "white")
                put(r + i, w + s, SC_HBAR, "white"); put(r + i, w + 2 * s, SC_HBAR, "white")
            text(r + 1, w - 7 if d == "left" else w + 4, "exit", "white")
    highlight = [(r + 2, c, box_w, MAP_BOX_H) for (r, c) in boxes]   # screen rows
    return scr, col, highlight


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
    if clk_h * 60 + clk_m < 1:
        die("game.start_time must be at least 0:01:00 (the reactor gauge "
            "scales by the starting minutes)")
    penalty = int(game.get("death_penalty_minutes", 30))
    if not 0 < penalty < 60:
        die("game.death_penalty_minutes must be 1-59 (APPLY_DEATH_PENALTY "
            "borrows at most one hour)")

    # ---- actor types ---------------------------------------------------
    types = cfg.get("actor_types") or die("config needs an actor_types section")
    type_index = {name: i for i, name in enumerate(types)}
    if "human" not in types:
        die("actor_types needs a human entry (the player sprite)")
    type_sprite, type_color, type_dir0, type_anim = [], [], [], []
    type_ai = {}                        # type name -> AI name (robots may override)
    for name, t in types.items():
        type_sprite.append(t["sprite"])  # label of first frame; ACME computes /64
        # frame sets: 3 frames per facing, facings down/up/left/right; a
        # 2-direction type only has the left/right groups assembled
        dirs = int(t.get("directions", 4))
        if dirs not in (2, 4):
            die(f"actor type {name}: directions must be 2 (left/right) or 4")
        type_dir0.append(4 - dirs)       # first facing present (DIR_DOWN or DIR_LEFT)
        anim = str(t.get("anim", "walk"))
        if anim not in ("walk", "hover"):
            die(f"actor type {name}: anim must be walk or hover")
        type_anim.append(1 if anim == "hover" else 0)
        color = str(t.get("color", "ltgray")).lower()
        if color not in C64_COLORS:
            die(f"actor type {name}: unknown color {color!r}")
        type_color.append(C64_COLORS[color])
        if name != "human":
            ai = t.get("ai", "patrol")
            if ai not in AI_NAMES:
                die(f"actor type {name}: ai must be one of {', '.join(AI_NAMES)}")
            type_ai[name] = ai

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
        item_msgs.append(text.center(MSG_INTERIOR))   # framed when emitted

    # ---- walk rooms, flattening everything into parallel arrays --------
    act = {k: [] for k in ("type", "room", "sx", "sy", "wx0", "wy0", "wx1", "wy1", "lock", "ai")}
    act_names = []                      # terminal menu name per actor
    actor_ids = {}
    item_pos = {}                       # item index -> (room, x, y)
    door = {k: [] for k in ("room", "x1", "y1", "x2", "y2", "dest", "ax", "ay", "key")}
    map_doors = []                      # (room, wall direction, dest or None)
    laser = {k: [] for k in ("room", "x1", "y1", "x2", "y2")}
    laser_art = []                      # per laser: [(map offset, new char), ...]
    art = cfg.get("art") or die("config needs an art section (floor_tile, laser_tiles)")
    floor_tile = int(art["floor_tile"])
    solid_tiles = {int(t) for t in art.get("solid_tiles") or []}
    laser_tiles = {int(t) for t in art.get("laser_tiles") or []}
    terminal_tiles = {int(t) for t in art.get("terminal_tiles") or []}
    if not laser_tiles:
        die("art.laser_tiles must list the laser beam/emitter screen codes")
    termz = {k: [] for k in ("room", "x1", "y1", "x2", "y2")}

    for ri, room in enumerate(rooms):
        rname = room["name"]
        if "map_view" in room:
            die(f"room {rname}: map_view is obsolete - the sector map is "
                f"generated from the doors (use label: to name the room)")
        room["_label"] = check_pet(str(room.get("label", rname)), f"room {rname} label")
        b = room.get("bounds") or {}       # default: the whole 20x11 room
        room["_maxx"] = int(b.get("max_x", TILES_X - 1))
        room["_maxy"] = int(b.get("max_y", TILES_Y - 1))
        if not (0 <= room["_maxx"] < TILES_X and 0 <= room["_maxy"] < TILES_Y):
            die(f"room {rname}: bounds must lie within X 0-{TILES_X - 1}, "
                f"Y 0-{TILES_Y - 1} (2x2-char tiles)")

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
            aname = check_pet(str(r.get("name", r.get("id", tname))),
                              f"room {rname} robot name")
            if len(aname) > TERM_NAME_WIDTH:
                die(f"room {rname}: robot name {aname!r} longer than "
                    f"{TERM_NAME_WIDTH} chars")
            act_names.append(aname)
            act["lock"].append(1 if r.get("locked") else 0)
            act["type"].append(type_index[tname])
            act["room"].append(ri)
            act["sx"].append(int(start["x"]))
            act["sy"].append(int(start["y"]))
            act["wx0"].append(int(patrol[0]["x"]))
            act["wy0"].append(int(patrol[0]["y"]))
            act["wx1"].append(int(patrol[1]["x"]))
            act["wy1"].append(int(patrol[1]["y"]))
            ai = r.get("ai", type_ai[tname])     # per-robot override of the type's ai
            if ai not in AI_NAMES:
                die(f"room {rname}: robot {aname!r}: ai must be one of {', '.join(AI_NAMES)}")
            # A hunter charges along its own tile row and then walks back to
            # its patrol X-first, so the patrol must be one horizontal line
            # through its start: rush and return then only cover tiles of
            # that row that the line-of-sight test found free of walls.
            if ai == "hunter" and not (int(start["y"]) == act["wy0"][-1] == act["wy1"][-1]):
                die(f"room {rname}: robot {aname!r}: an ai: hunter robot needs a "
                    f"horizontal patrol (both waypoints on its start row)")
            act["ai"].append(AI_NAMES.index(ai))

        for thing in room.get("things") or []:
            iname = thing.get("item")
            if iname not in item_index:
                die(f"room {rname}: unknown item {iname!r}")
            ii = item_index[iname]
            if ii in item_pos:
                die(f"item {iname!r} placed more than once")
            item_pos[ii] = (ri, int(thing["at"]["x"]), int(thing["at"]["y"]))

        for li, l in enumerate(room.get("lasers") or []):
            laser["room"].append(ri)
            for k in ("x1", "y1", "x2", "y2"):
                laser[k].append(int(l[k]))
            mapdata = read_vchar64_map(room.get("vchar64_map")
                                       or die(f"room {rname}: needs vchar64_map"))
            laser_art.append(laser_art_patches(
                mapdata, {k: int(l[k]) for k in ("x1", "y1", "x2", "y2")},
                laser_tiles, floor_tile, f"room {rname} laser {li + 1}"))

        # terminals come from the art: every group of terminal chars is one
        # terminal, usable from its own tiles and the tiles around them
        if "terminals" in room:
            die(f"room {rname}: terminals: is obsolete - terminals are found "
                f"in the room art (art.terminal_tiles)")
        for c0, r0, c1, r1 in find_terminals(read_vchar64_map(room["vchar64_map"]),
                                             terminal_tiles):
            termz["room"].append(ri)
            termz["x1"].append(max(0, c0 // 2 - 1))
            termz["y1"].append(max(0, r0 // 2 - 1))
            termz["x2"].append(min(room["_maxx"], c1 // 2 + 1))
            termz["y2"].append(min(room["_maxy"], r1 // 2 + 1))

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
            map_doors.append((ri, door_dir({k: int(at[k]) for k in ("x1", "y1", "x2", "y2")},
                                           room, f"room {rname} door to {dest}"),
                              None if dest_i == 0xFF else dest_i))

    for iname, ii in item_index.items():
        if ii not in item_pos:
            die(f"item {iname!r} is never placed in a room")

    # ---- walls: solid tiles per room, from the art; validate placements --
    walls = []
    for room in rooms:
        walls.append(wall_grid(read_vchar64_map(room["vchar64_map"]),
                               room["_maxx"], room["_maxy"], solid_tiles))

    def check_open(ri, x, y, what):
        room = rooms[ri]
        if not (0 <= x <= room["_maxx"] and 0 <= y <= room["_maxy"]):
            die(f"{what}: ({x},{y}) is outside room {room['name']}'s bounds")
        if walls[ri][y][x]:
            die(f"{what}: ({x},{y}) is inside a wall in room {room['name']} "
                f"(wall art in map cols {2*x}-{2*x+1}, rows {2*y}-{2*y+1})")

    for ri, room in enumerate(rooms):
        ps = room["player_start"]
        check_open(ri, int(ps["x"]), int(ps["y"]), f"room {room['name']} player_start")
    for ai in range(len(act["type"])):
        ri, what = act["room"][ai], f"robot #{ai} in room {rooms[act['room'][ai]]['name']}"
        sx, sy = act["sx"][ai], act["sy"][ai]
        w0, w1 = (act["wx0"][ai], act["wy0"][ai]), (act["wx1"][ai], act["wy1"][ai])
        check_open(ri, sx, sy, what + " start")
        for (fx, fy), (tx, ty) in (((sx, sy), w1), (w1, w0), (w0, w1)):
            for x, y in patrol_path(fx, fy, tx, ty):
                check_open(ri, x, y, what + f" patrol path {fx},{fy} -> {tx},{ty}")
    for ii, (ri, x, y) in item_pos.items():
        check_open(ri, x, y, f"item {list(item_index)[ii]!r}")
    for di in range(len(door["room"])):
        dest = door["dest"][di]
        if dest == 0xFF:
            continue
        xs = range(door["x1"][di], door["x2"][di] + 1) if door["ax"][di] == 0xFF else [door["ax"][di]]
        ys = range(door["y1"][di], door["y2"][di] + 1) if door["ay"][di] == 0xFF else [door["ay"][di]]
        for x in xs:
            for y in ys:
                check_open(dest, x, y, f"door #{di} from room {rooms[door['room'][di]]['name']} arrival")
    for ti in range(len(termz["room"])):
        ri = termz["room"][ti]
        if all(walls[ri][y][x]
               for y in range(termz["y1"][ti], termz["y2"][ti] + 1)
               for x in range(termz["x1"][ti], termz["x2"][ti] + 1)):
            die(f"terminal zone #{ti} in room {rooms[ri]['name']} is entirely inside walls")
    for ii, (ri, x, y) in item_pos.items():
        for ti in range(len(termz["room"])):
            if (termz["room"][ti] == ri and termz["x1"][ti] <= x <= termz["x2"][ti]
                    and termz["y1"][ti] <= y <= termz["y2"][ti]):
                die(f"item {list(item_index)[ii]!r} at ({x},{y}) is next to a terminal "
                    f"in room {rooms[ri]['name']}: fire there opens the terminal, "
                    f"so it could never be searched for")


    map_scr, map_col, map_hl = build_map(rooms, room_index[start_room], map_doors)

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
    for tname, ti in type_index.items():
        o.append(f"ATYPE_{tname.upper()} = {ti}   ; actor type index")
    for i, ainame in enumerate(AI_NAMES):
        o.append(f"AI_{ainame.upper()} = {i}   ; ACT_AI value")
    o.append("")

    o.append("; ---- actor types (indexed by ACT_TYPE) ----")
    o.append("TYPE_SPRPTR     ; sprite pointer byte (sprite data address / 64)")
    o.append("        !byte " + ",".join(f"{s}/64" for s in type_sprite))
    o.append(tbl("TYPE_COLOR", type_color, "sprite colour"))
    o.append(tbl("TYPE_DIR0", type_dir0, "first facing with frames (0=all 4, 2=left/right only)"))
    o.append(tbl("TYPE_ANIM", type_anim, "0=walk (steps animate) 1=hover (always animating)"))
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

    o.append("; ---- sector map: highlight box per room (colour RAM) ----")
    o.append("MAPHL_LO        ; CRAM address of the room box's top-left corner")
    o.append("        !byte " + ",".join(f"<($D800+{row}*40+{col})" for row, col, _, _ in map_hl))
    o.append("MAPHL_HI")
    o.append("        !byte " + ",".join(f">($D800+{row}*40+{col})" for row, col, _, _ in map_hl))
    o.append(tbl("MAPHL_W", [byte(w, "MAPHL_W") for _, _, w, _ in map_hl]))
    o.append(tbl("MAPHL_H", [byte(h, "MAPHL_H") for _, _, _, h in map_hl]))
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
            ("ACT_WY1", "wy1", ""),
            ("ACT_LOCK", "lock", "1 = terminal refuses to link (locked: true)"),
            ("ACT_AI", "ai", "AI_* routine while computer-controlled")):
        o.append(tbl(name, [byte(v, name) for v in act[key]], comment))
    o.append("ACT_TROW_LO     ; 40-char terminal menu row (name, locked tag)")
    o.append("        !byte " + (",".join(f"<ACT_TROW_{i}" for i in range(len(act_names))) or "0"))
    o.append("ACT_TROW_HI")
    o.append("        !byte " + (",".join(f">ACT_TROW_{i}" for i in range(len(act_names))) or "0"))
    for i, aname in enumerate(act_names):
        row = ("    " + aname.ljust(TERM_NAME_WIDTH + 1)
               + ("locked" if act["lock"][i] else "")).ljust(38)
        o.append(f'ACT_TROW_{i} !pet G_VERT_BAR, "{row}", G_VERT_BAR')
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
            o.append(f'ITEM_MSG_{i} !pet "    ", G_VERT_BAR, "{msg}", G_VERT_BAR, "    "')
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
    o.append("; screen cells ERASE_LASER repaints once a laser is destroyed: entries of")
    o.append("; (map offset lo, hi, new screen code), terminated by a $ff hi byte")
    o.append("LASER_ART_LO")
    o.append("        !byte " + (",".join(f"<LASER_ART_{i}" for i in range(len(laser_art))) or "0"))
    o.append("LASER_ART_HI")
    o.append("        !byte " + (",".join(f">LASER_ART_{i}" for i in range(len(laser_art))) or "0"))
    for i, patches in enumerate(laser_art):
        o.append(f"LASER_ART_{i}")
        for off, ch in patches:
            o.append(f"        !byte ${off & 0xff:02x},${off >> 8:02x},${ch:02x}   ; row {off // 40}, col {off % 40}")
        o.append("        !byte $00,$ff")
    o.append("")

    o.append("; ---- terminal zones (fire inside to open the terminal), found in the art ----")
    for ti in range(len(termz["room"])):
        o.append(f"; terminal {ti}: room {rooms[termz['room'][ti]]['name']}, tiles "
                 f"x {termz['x1'][ti]}-{termz['x2'][ti]}, y {termz['y1'][ti]}-{termz['y2'][ti]}")
    for name, key in (("TERMZ_ROOM", "room"), ("TERMZ_X1", "x1"), ("TERMZ_Y1", "y1"),
                      ("TERMZ_X2", "x2"), ("TERMZ_Y2", "y2")):
        o.append(tbl(name, [byte(v, "termz") for v in termz[key]]))
    o.append("")

    o.append(f"; ---- walls: per room, {TILES_X} bytes per tile row (y*{TILES_X}+x), 1 = solid ----")
    o.append("; (from the 2x2 chars of each tile -- see wall_grid in genworld.py)")
    o.append("ROOM_WALL_LO")
    o.append("        !byte " + ",".join(f"<ROOM_WALLS_{i}" for i in range(len(rooms))))
    o.append("ROOM_WALL_HI")
    o.append("        !byte " + ",".join(f">ROOM_WALLS_{i}" for i in range(len(rooms))))
    for i, grid in enumerate(walls):
        o.append(f"ROOM_WALLS_{i}      ; {rooms[i]['name']}")
        for y, row in enumerate(grid):
            vals = [1 if b else 0 for b in row] + [0] * (TILES_X - len(row))
            pic = "".join("#" if b else "." for b in row)
            o.append(f"        !byte {','.join(str(v) for v in vals)}   ; y={y} {pic}")
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

    o.append("; ---- sector map: screen rows 2-23, generated from the doors ----")
    o.append("; (SETUP_MAP copies MAP_SCR/MAP_COL to screen/colour RAM as they are)")
    picture = {SC_HBAR: "-", SC_VBAR: "|", SC_UL: "+", SC_UR: "+", SC_LL: "+", SC_LR: "+"}
    for r in range(MAP_ROWS):
        line = "".join(picture.get(c, chr(c + 96) if 1 <= c <= 26 else chr(c)) for c in map_scr[r])
        o.append(f";   {line.rstrip()}")
    o.append("MAP_SCR")
    for r in range(MAP_ROWS):
        o.append("        !byte " + ",".join(f"${c:02x}" for c in map_scr[r]))
    o.append("MAP_COL")
    for r in range(MAP_ROWS):
        o.append("        !byte " + ",".join(f"${c:02x}" for c in map_col[r]))
    o.append("")

    o.append("; ---- runtime state (RAM, initialised by SETUP_GAME/RESET_ROUND) ----")
    o.append("ACT_X       !fill NUM_ACTORS    ; current position")
    o.append("ACT_Y       !fill NUM_ACTORS")
    o.append("ACT_TGT     !fill NUM_ACTORS    ; current patrol target waypoint (0/1)")
    o.append("ACT_ALIVE   !fill NUM_ACTORS    ; 0 = destroyed (hidden, no patrol/link)")
    o.append("ACT_DIR     !fill NUM_ACTORS    ; facing (DIR_*)")
    o.append("ACT_ANIM    !fill NUM_ACTORS    ; walk frame 0=rest 1=walk1 2=walk2")
    o.append("ACT_FAST    !fill NUM_ACTORS    ; 1 = rushing (hunter saw the player): double pace")
    o.append("GL_PXL      !fill NUM_ACTORS+1  ; sprite pixel X lo (smooth movement;")
    o.append("GL_PXH      !fill NUM_ACTORS+1  ;  last slot = the human), X hi bit")
    o.append("GL_PY       !fill NUM_ACTORS+1  ; sprite pixel Y")
    o.append("ITEM_STATE  !fill NUM_ITEMS+1   ; 0=hidden 1=carried 2=used (+1 pads the empty case)")
    o.append("LASER_STATE !fill NUM_LASERS+1  ; 0=active 1=destroyed")
    o.append("SPR_SLOT_ACT !fill 2            ; actor shown by hw sprite 1/2, $ff = none")
    o.append("")

    with open(out_path, "w", encoding="ascii") as f:
        f.write("\n".join(o))
    print(f"genworld: wrote {out_path}: {len(rooms)} rooms, {len(act['type'])} actors, "
          f"{len(items)} items, {len(door['room'])} doors, {len(laser['room'])} lasers, "
          f"{len(termz['room'])} terminals")


if __name__ == "__main__":
    main()
