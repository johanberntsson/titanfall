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
IDLE_NAMES = ["patrol", "roam"]                           # idle: values; index = IDLE_* in world.asm
ATTACK_NAMES = ["none", "rush", "shoot", "forcefield"]     # attack: values; index = ATK_* in world.asm
LABEL_WIDTH = 12          # status-line item label field width
MAX_CODES = 3             # security code types (status line: " code: a 2 b 0 c 0    card: " + label)
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


def door_art_patches(mapdata, d, side, door_tiles, floor_tile):
    """Screen cells to repaint as floor when a keyed door is opened.

    The door's art is drawn in the room's edge tiles next to the door
    rectangle (which lies one tile outside the room): the 2 char rows (or
    columns) at that wall, along the door's span plus one char on each end
    (art that is a char wider than the tile span). Every door_tiles char
    there becomes floor. Returns [(map offset, new screen code), ...].
    """
    rows = ROOM_MAP_BYTES // 40
    if side in ("up", "down"):
        r0, r1 = (0, 1) if side == "up" else (rows - 2, rows - 1)
        c0, c1 = 2 * d["x1"] - 1, 2 * d["x2"] + 2
    else:
        c0, c1 = (0, 1) if side == "left" else (38, 39)
        r0, r1 = 2 * d["y1"] - 1, 2 * d["y2"] + 2
    c0, c1 = max(c0, 0), min(c1, 39)
    r0, r1 = max(r0, 0), min(r1, rows - 1)
    return [(r * 40 + c, floor_tile)
            for r in range(r0, r1 + 1) for c in range(c0, c1 + 1)
            if mapdata[r * 40 + c] in door_tiles]


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
MAP_MIN_GAP_X = 2                        # shortest horizontal corridor when space is tight
                                         # (vertical corridors shrink to 1 row)
GOAL_WIDTH = 32                          # orders line: 40 cols - "orders: "
GOAL_DONE = " - done"                    # appended once the goal is achieved
GOAL_FOUND, GOAL_OPENED, GOAL_VISITED = 1, 2, 3
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
    # Narrow the boxes first (down to the label + a space each side), then
    # shorten the horizontal corridors, until the grid fits.
    min_w = max(len(l) for l in labels) + 2
    box_w, gap_x = 12, MAP_GAP_X
    def width():
        return lm + rm + gw * box_w + (gw - 1) * gap_x
    while box_w > min_w and width() > MAP_COLS - 2:
        box_w -= 1
    box_w = max(box_w, min_w)
    while gap_x > MAP_MIN_GAP_X and width() > MAP_COLS - 2:
        gap_x -= 1
    total_w = width()
    # Vertically: shorten the vertical corridors, then drop the blank rows
    # around the grid, until it fits.
    gap_y, pad = MAP_GAP_Y, 2
    def height():                            # title, blank(s), grid, blank(s), prompt
        return 2 + pad + tm + bm + gh * MAP_BOX_H + (gh - 1) * gap_y
    while gap_y > 1 and height() > MAP_ROWS:
        gap_y -= 1
    while pad > 0 and height() > MAP_ROWS:
        pad -= 1
    block_h = height()
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
    gy0 = top + 1 + (pad + 1) // 2 + tm      # the blank row under the title goes last

    def box_at(ri):
        x, y = pos[ri]
        return gy0 + y * (MAP_BOX_H + gap_y), gx0 + x * (box_w + gap_x)

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
    link_s = int(game.get("robot_link_seconds", 30))
    if not 0 < link_s < 100:
        die("game.robot_link_seconds must be 1-99 (shown as 2 digits in the HUD)")

    # ---- actor types ---------------------------------------------------
    def behaviour(d, default, what):
        """(idle, attack) of a type or robot entry, defaulting to `default`."""
        if "ai" in d:
            die(f"{what}: ai: is gone; say idle: ({' / '.join(IDLE_NAMES)}) and "
                f"attack: ({' / '.join(ATTACK_NAMES)}) instead")
        idle = str(d.get("idle", default[0]))
        attack = str(d.get("attack", default[1]))
        if idle not in IDLE_NAMES:
            die(f"{what}: idle must be one of {', '.join(IDLE_NAMES)}")
        if attack not in ATTACK_NAMES:
            die(f"{what}: attack must be one of {', '.join(ATTACK_NAMES)}")
        return idle, attack

    types = cfg.get("actor_types") or die("config needs an actor_types section")
    type_index = {name: i for i, name in enumerate(types)}
    if "human" not in types:
        die("actor_types needs a human entry (the player sprite)")
    type_sprite, type_color, type_dir0, type_anim = [], [], [], []
    type_ai = {}                        # type name -> (idle, attack) (robots may override)
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
            type_ai[name] = behaviour(t, ("patrol", "none"), f"actor type {name}")

    # ---- security codes ------------------------------------------------
    # name -> how many the player starts with. Linking a robot that needs a
    # code spends one; items with code: add one when found.
    codes = cfg.get("security_codes") or {}
    code_names, code_start = [], []
    for cname, n in codes.items():
        cname = str(cname).lower()
        if len(cname) != 1 or cname not in "abcdefghijklmnopqrstuvwxyz":
            die(f"security_codes: code names must be one letter, not {cname!r}")
        if not 0 <= int(n) <= 9:
            die(f"security_codes: {cname}: start count must be 0-9 (one digit)")
        code_names.append(cname)
        code_start.append(int(n))
    if len(code_names) > MAX_CODES:
        die(f"security_codes: at most {MAX_CODES} code types fit the status line")

    def code_ref(v, what):
        """code: value -> 0 (none) or code index + 1"""
        v = str(v).lower()
        if v == "none":
            return 0
        if v not in code_names:
            die(f"{what}: unknown security code {v!r} (security_codes: "
                f"{', '.join(code_names) or 'none defined'})")
        return code_names.index(v) + 1

    # ---- items ---------------------------------------------------------
    items = cfg.get("items") or {}
    item_index = {name: i for i, name in enumerate(items)}
    item_labels, item_msgs, item_code = [], [], []
    for name, it in items.items():
        # code: <letter> makes the item a security code: finding it adds one
        # to that code's count instead of going into the card slot
        item_code.append(code_ref(it["code"], f"item {name}") if "code" in it else 0)
        if item_code[-1]:
            cname = code_names[item_code[-1] - 1]
            it.setdefault("found_text", f"security code {cname} found!")
            it.setdefault("label", f"code {cname}")   # never shown (no card slot)
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
    act = {k: [] for k in ("type", "room", "sx", "sy", "wx0", "wy0", "wx1", "wy1", "lock", "idle", "attack", "code")}
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
    door_tiles = {int(t) for t in art.get("door_tiles") or []}
    win_tiles = {int(t) for t in art.get("win_tiles") or []}
    missile_tiles = {int(t) for t in art.get("missile_tiles") or []}
    if not missile_tiles:
        die("art.missile_tiles is missing (the missile's chars, launched on game over)")
    targets = []                        # per room: grid[y][x] of win-target tiles
    door_art = []                       # per door: [(map offset, new char), ...]
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
            # per-robot override of the type's idle/attack
            idle, attack = behaviour(r, type_ai[tname],
                                     f"room {rname} robot {r.get('name', tname)!r}")
            # A roaming robot walks randomly over the room (checking walls
            # itself at runtime), so it has no patrol path.
            if idle == "roam" and "patrol" in r:
                die(f"room {rname}: robot {r.get('name', tname)!r}: an idle: roam "
                    f"robot wanders the whole room and takes no patrol:")
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
            if "code" not in r:
                die(f"room {rname}: robot {aname!r} needs a code: (the security "
                    f"code its terminal link costs, or none)")
            act["code"].append(code_ref(r["code"], f"room {rname} robot {aname!r}"))
            act["type"].append(type_index[tname])
            act["room"].append(ri)
            act["sx"].append(int(start["x"]))
            act["sy"].append(int(start["y"]))
            act["wx0"].append(int(patrol[0]["x"]))
            act["wy0"].append(int(patrol[0]["y"]))
            act["wx1"].append(int(patrol[1]["x"]))
            act["wy1"].append(int(patrol[1]["y"]))
            # A rushing / forcefield robot charges along its own tile row and
            # a patrolling one then walks back to its patrol X-first, so the
            # patrol must be one horizontal line through its start: attack and
            # return then only cover tiles of that row that the line-of-sight
            # test found free of walls. (A roaming one checks walls itself.)
            if (idle == "patrol" and attack in ("rush", "forcefield")
                    and not (int(start["y"]) == act["wy0"][-1] == act["wy1"][-1])):
                die(f"room {rname}: robot {aname!r}: a patrolling attack: {attack} "
                    f"robot needs a horizontal patrol (both waypoints on its start row)")
            act["idle"].append(IDLE_NAMES.index(idle))
            act["attack"].append(ATTACK_NAMES.index(attack))

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
            if key is not None and item_code[item_index[key]]:
                die(f"room {rname}: door key {key!r} is a security code - "
                    f"codes are spent on robot links, not doors")
            door["room"].append(ri)
            for k in ("x1", "y1", "x2", "y2"):
                door[k].append(int(at[k]))
            door["dest"].append(dest_i)
            door["ax"].append(0xFF if "x" not in arrive else int(arrive["x"]))
            door["ay"].append(0xFF if "y" not in arrive else int(arrive["y"]))
            door["key"].append(0 if key is None else item_index[key] + 1)
            drect = {k: int(at[k]) for k in ("x1", "y1", "x2", "y2")}
            side = door_dir(drect, room, f"room {rname} door to {dest}")
            map_doors.append((ri, side, None if dest_i == 0xFF else dest_i))
            # a keyed door opens (its art turns to floor) the first time the
            # player walks into it carrying the key
            patches = []
            if key is not None:
                patches = door_art_patches(read_vchar64_map(room["vchar64_map"]),
                                           drect, side, door_tiles, floor_tile)
                if not patches:
                    print(f"genworld: warning: room {rname}: locked door to {dest} "
                          f"has no art.door_tiles drawn at its wall - nothing "
                          f"will visibly open", file=sys.stderr)
            door_art.append(patches)

    for iname, ii in item_index.items():
        if ii not in item_pos:
            die(f"item {iname!r} is never placed in a room")

    # ---- goals: the orders line (row 1) per room ----
    goal_text, goal_kind, goal_arg = [], [], []
    for ri, room in enumerate(rooms):
        rname = room["name"]
        g = room.get("goal") or {}
        if isinstance(g, str):
            g = {"text": g}
        text = check_pet(str(g.get("text", "")), f"room {rname} goal text")
        if len(text) > GOAL_WIDTH - len(GOAL_DONE):
            die(f"room {rname}: goal text longer than "
                f"{GOAL_WIDTH - len(GOAL_DONE)} chars: {text!r}")
        goal_text.append(text)
        done = g.get("done") or {}
        if len(done) > 1:
            die(f"room {rname}: goal done: takes one condition, got {sorted(done)}")
        kind, arg = 0, 0
        if "found" in done:
            if done["found"] not in item_index:
                die(f"room {rname}: goal done: found: unknown item {done['found']!r}")
            kind, arg = GOAL_FOUND, item_index[done["found"]]
        elif "opened" in done:              # this room's keyed door to <room>
            dest = room_index.get(done["opened"])
            hits = [i for i in range(len(door["room"]))
                    if door["room"][i] == ri and door["dest"][i] == dest and door["key"][i]]
            if not hits:
                die(f"room {rname}: goal done: opened: no keyed door from "
                    f"{rname} to {done['opened']!r}")
            kind, arg = GOAL_OPENED, hits[0]
        elif "visited" in done:
            if done["visited"] not in room_index:
                die(f"room {rname}: goal done: visited: unknown room {done['visited']!r}")
            kind, arg = GOAL_VISITED, room_index[done["visited"]]
        elif done:
            die(f"room {rname}: goal done: must be found:, opened: or visited:")
        if kind and not text:
            die(f"room {rname}: goal done: without a goal text")
        goal_kind.append(kind)
        goal_arg.append(arg)

    # ---- walls: solid tiles per room, from the art; validate placements --
    walls = []
    searchable = []                     # per room: tiles that aren't plain floor
    for room in rooms:
        # searchable: any of the tile's 2x2 chars isn't art.floor_tile
        # (furniture, crates, ...) -- only there does holding fire search
        searchable.append(wall_grid(read_vchar64_map(room["vchar64_map"]),
                                    room["_maxx"], room["_maxy"],
                                    set(range(256)) - {floor_tile}))
        # win targets: tiles with any art.win_tiles char (same 2x2 test)
        targets.append(wall_grid(read_vchar64_map(room["vchar64_map"]),
                                 room["_maxx"], room["_maxy"], win_tiles))
        walls.append(wall_grid(read_vchar64_map(room["vchar64_map"]),
                               room["_maxx"], room["_maxy"], solid_tiles))

    # closed doors: a tile with art.door_tiles chars is solid. A keyed
    # door's tiles (from its art patches) also carry the door index + 1 in
    # bits 4-7 of the wall byte: pushing into one opens the door (or shows
    # the locked popup), and opening clears their solid bit at runtime. For
    # the placement checks below they count as open (door arrivals land on
    # them once the door is open). Door art of no keyed door is plain wall.
    door_owner = []                     # per room: {(x, y): door index}
    for ri, room in enumerate(rooms):
        owner = {}
        for di, patches in enumerate(door_art):
            if door["room"][di] != ri:
                continue
            for off, _ in patches:
                x, y = off % 40 // 2, off // 40 // 2
                if y < len(walls[ri]) and x < len(walls[ri][y]) and not walls[ri][y][x]:
                    if di + 1 > 15:
                        die(f"room {room['name']}: keyed door #{di} - only the "
                            f"first 15 doors in titan.yaml can have a key")
                    owner[(x, y)] = di
        door_owner.append(owner)
        dgrid = wall_grid(read_vchar64_map(room["vchar64_map"]),
                          room["_maxx"], room["_maxy"], door_tiles)
        for y, row in enumerate(dgrid):
            for x, d in enumerate(row):
                if d and (x, y) not in owner:
                    walls[ri][y][x] = True

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
        if not searchable[ri][y][x]:
            die(f"item {list(item_index)[ii]!r} at ({x},{y}) in room "
                f"{rooms[ri]['name']} is on plain floor: searching only works on "
                f"tiles with something drawn on them (not all art.floor_tile)")
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
    o.append(f"CFG_LINK_S    = {link_s}")
    o.append(f"CFG_FLOOR     = ${floor_tile:02x}   ; art.floor_tile (cut scene floor)")
    for rid, ai in actor_ids.items():
        o.append(f"ACTOR_{rid.upper()} = {ai}   ; actor index")
    for iname, ii in item_index.items():
        o.append(f"ITEM_{iname.upper()} = {ii}   ; item index")
    for tname, ti in type_index.items():
        o.append(f"ATYPE_{tname.upper()} = {ti}   ; actor type index")
    for i, n in enumerate(IDLE_NAMES):
        o.append(f"IDLE_{n.upper()} = {i}   ; ACT_IDLE value")
    for i, n in enumerate(ATTACK_NAMES):
        o.append(f"ATK_{n.upper()} = {i}   ; ACT_ATTACK value")
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

    o.append("; ---- goals: the orders line (row 1) per room; DRAW_ORDERS ----")
    o.append(f"GOAL_WIDTH = {GOAL_WIDTH}    ; chars per goal string")
    o.append(f"GOAL_FOUND = {GOAL_FOUND}     ; GOAL_KIND: done when ITEM_STATE,arg <> 0")
    o.append(f"GOAL_OPENED = {GOAL_OPENED}    ;  ... DOOR_OPEN,arg <> 0")
    o.append(f"GOAL_VISITED = {GOAL_VISITED}   ;  ... ROOM_SEEN,arg <> 0 (0 = never done)")
    o.append(tbl("GOAL_KIND", goal_kind))
    o.append(tbl("GOAL_ARG", goal_arg))
    o.append(f"GOAL_LO         ; {GOAL_WIDTH}-char goal (after \"orders: \"), and the same + \"{GOAL_DONE}\"")
    o.append("        !byte " + ",".join(f"<GOAL_{i}" for i in range(len(rooms))))
    o.append("GOAL_HI")
    o.append("        !byte " + ",".join(f">GOAL_{i}" for i in range(len(rooms))))
    o.append("GOALD_LO")
    o.append("        !byte " + ",".join(f"<GOALD_{i}" for i in range(len(rooms))))
    o.append("GOALD_HI")
    o.append("        !byte " + ",".join(f">GOALD_{i}" for i in range(len(rooms))))
    for i, t in enumerate(goal_text):
        o.append(f'GOAL_{i}  !pet "{t.ljust(GOAL_WIDTH)}"')
        o.append(f'GOALD_{i} !pet "{(t + GOAL_DONE).ljust(GOAL_WIDTH)}"')
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
            ("ACT_IDLE", "idle", "IDLE_*: what it does when it doesn't see the player"),
            ("ACT_ATTACK", "attack", "ATK_*: what it does when it sees the player"),
            ("ACT_CODE", "code", "security code a link costs: code index + 1, 0 = none")):
        o.append(tbl(name, [byte(v, name) for v in act[key]], comment))
    o.append("ACT_TROW_LO     ; 40-char terminal menu row (name, locked tag)")
    o.append("        !byte " + (",".join(f"<ACT_TROW_{i}" for i in range(len(act_names))) or "0"))
    o.append("ACT_TROW_HI")
    o.append("        !byte " + (",".join(f">ACT_TROW_{i}" for i in range(len(act_names))) or "0"))
    for i, aname in enumerate(act_names):
        status = ("locked" if act["lock"][i] else
                  f"code {code_names[act['code'][i] - 1]}" if act["code"][i] else "")
        row = ("    " + aname.ljust(TERM_NAME_WIDTH + 1) + status).ljust(38)
        o.append(f'ACT_TROW_{i} !pet G_VERT_BAR, "{row}", G_VERT_BAR')
    o.append("ACT_LNAME_LO    ; 40-char popup row: the name, centred (SETUP_LINKED)")
    o.append("        !byte " + (",".join(f"<ACT_LNAME_{i}" for i in range(len(act_names))) or "0"))
    o.append("ACT_LNAME_HI")
    o.append("        !byte " + (",".join(f">ACT_LNAME_{i}" for i in range(len(act_names))) or "0"))
    for i, aname in enumerate(act_names):
        o.append(f'ACT_LNAME_{i} !pet "    ", G_VERT_BAR, "{aname.center(30)}", G_VERT_BAR, "    "')
    o.append("")

    o.append("; ---- security codes and the status line (row 24) ----")
    o.append(f"NUM_CODES     = {len(code_names)}")
    o.append(tbl("CODE_START", code_start, "count at mission start (SETUP_GAME)"))
    if code_names:
        tmpl = " code:" + "".join(f" {c} 0" for c in code_names) + "    card: "
    else:
        tmpl = " card: "
    o.append("STAT_CNT_COL  = 9      ; column of code 0's digit; codes are 4 columns apart")
    o.append(f"STAT_LBL_COL  = {len(tmpl)}     ; column of the card label (LABEL_WIDTH chars)")
    # "not found" sits in the label field: a carried card's label (always
    # LABEL_WIDTH chars, space-padded) is drawn right over it
    o.append(f'STAT_TMPL !pet "{(tmpl + "not found").ljust(40)}"')
    o.append("CODE_MSG_LO     ; terminal message: link refused, no code of this type")
    o.append("        !byte " + (",".join(f"<CODE_MSG_{i}" for i in range(len(code_names))) or "0"))
    o.append("CODE_MSG_HI")
    o.append("        !byte " + (",".join(f">CODE_MSG_{i}" for i in range(len(code_names))) or "0"))
    for i, c in enumerate(code_names):
        o.append(f'CODE_MSG_{i} !pet "{("  access denied. no security code " + c + ".").ljust(40)}"')
    o.append("")

    o.append("; ---- items ----")
    ipr = [item_pos[i] for i in range(len(items))]
    o.append(tbl("ITEM_ROOM", [byte(p[0], "ITEM_ROOM") for p in ipr]))
    o.append(tbl("ITEM_X", [byte(p[1], "ITEM_X") for p in ipr]))
    o.append(tbl("ITEM_Y", [byte(p[2], "ITEM_Y") for p in ipr]))
    o.append(tbl("ITEM_CODE", item_code, "security code it adds when found: index + 1, 0 = a card/key item"))
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

    o.append("; screen cells ERASE_DOOR repaints (door art -> floor) when a keyed door")
    o.append("; opens; same format as LASER_ART_n (empty for doors without a key)")
    o.append("DOOR_ART_LO")
    o.append("        !byte " + (",".join(f"<DOOR_ART_{i}" for i in range(len(door_art))) or "0"))
    o.append("DOOR_ART_HI")
    o.append("        !byte " + (",".join(f">DOOR_ART_{i}" for i in range(len(door_art))) or "0"))
    for i, patches in enumerate(door_art):
        o.append(f"DOOR_ART_{i}")
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

    o.append("; ---- win-target art: per room, the map offsets of every art.win_tiles char")
    o.append("; (lo, hi; a $ff hi byte ends the list) -- PAINT_WIN recolours them: the")
    o.append("; cyan/purple flicker while intact, dark grey when shot")
    o.append("ROOM_WINART_LO")
    o.append("        !byte " + ",".join(f"<ROOM_WINART_{i}" for i in range(len(rooms))))
    o.append("ROOM_WINART_HI")
    o.append("        !byte " + ",".join(f">ROOM_WINART_{i}" for i in range(len(rooms))))
    for i, room in enumerate(rooms):
        mapdata = read_vchar64_map(room["vchar64_map"])
        offs = [o_ for o_ in range(ROOM_MAP_BYTES) if mapdata[o_] in win_tiles]
        if len(offs) > 127:
            die(f"room {room['name']}: too many art.win_tiles chars ({len(offs)} > 127)")
        o.append(f"ROOM_WINART_{i}      ; {room['name']}: {len(offs)} cells")
        for k in range(0, len(offs), 8):
            o.append("        !byte " + ",".join(f"${x & 0xff:02x},${x >> 8:02x}" for x in offs[k:k + 8]))
        o.append("        !byte $00,$ff")
    o.append("")

    # the missile: the bounding box of the art.missile_tiles chars, which must
    # all be in one room; SETUP_GAMEOVER shows that room and launches it
    msl_rooms = []
    for i, room in enumerate(rooms):
        mapdata = read_vchar64_map(room["vchar64_map"])
        cells = [(o_ // 40, o_ % 40) for o_ in range(ROOM_MAP_BYTES) if mapdata[o_] in missile_tiles]
        if cells:
            msl_rooms.append((i, mapdata, cells))
    if len(msl_rooms) != 1:
        die("art.missile_tiles chars must appear in exactly one room "
            f"(found in {len(msl_rooms)})")
    mi, mapdata, cells = msl_rooms[0]
    my0 = min(r for r, c in cells); my1 = max(r for r, c in cells)
    mx0 = min(c for r, c in cells); mx1 = max(c for r, c in cells)
    o.append("; ---- the missile (art.missile_tiles), launched on the game over screen ----")
    o.append(f"MSL_ROOM = {mi}   ; {rooms[mi]['name']}")
    o.append(f"MSL_X    = {mx0}   ; bounding box: map column, row, width, height")
    o.append(f"MSL_Y    = {my0}")
    o.append(f"MSL_W    = {mx1 - mx0 + 1}")
    o.append(f"MSL_H    = {my1 - my0 + 1}")
    o.append("MSL_CHARS       ; the box row by row: the missile's chars, 0 = not missile")
    for r in range(my0, my1 + 1):
        row = [mapdata[r * 40 + c] if mapdata[r * 40 + c] in missile_tiles else 0
               for c in range(mx0, mx1 + 1)]
        o.append("        !byte " + ",".join(f"${v:02x}" for v in row))
    o.append("")

    o.append(f"; ---- walls: per room, {TILES_X} bytes per tile row (y*{TILES_X}+x) ----")
    o.append("; bit 0 = solid (#), bit 1 = win target (*, may be solid too: a bolt fired by a player-driven")
    o.append("; robot entering it wins), bit 2 = searchable (+ when walkable: not all floor_tile),")
    o.append("; bits 4-7 = keyed door index + 1 (=, solid while closed: OPEN_DOOR_WALLS clears bit 0)")
    o.append("; -- from the 2x2 chars of each tile, see wall_grid")
    o.append("ROOM_WALL_LO")
    o.append("        !byte " + ",".join(f"<ROOM_WALLS_{i}" for i in range(len(rooms))))
    o.append("ROOM_WALL_HI")
    o.append("        !byte " + ",".join(f">ROOM_WALLS_{i}" for i in range(len(rooms))))
    for i, grid in enumerate(walls):
        o.append(f"ROOM_WALLS_{i}      ; {rooms[i]['name']}")
        for y, row in enumerate(grid):
            tgt, srch = targets[i][y], searchable[i][y]
            own = [door_owner[i].get((x, y)) for x in range(len(row))]
            vals = [(1 if b else 0) | (2 if t else 0) | (4 if f else 0)
                    | (0 if d is None else 1 | (d + 1) << 4)
                    for b, t, f, d in zip(row, tgt, srch, own)]
            vals += [0] * (TILES_X - len(row))
            pic = "".join("*" if t else "#" if b else "=" if d is not None
                          else "+" if f else "."
                          for b, t, f, d in zip(row, tgt, srch, own))
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
    o.append("ACT_TGT     !fill NUM_ACTORS    ; patrol target waypoint (0/1); idle: roam: steps left*4 + DIR_*")
    o.append("ACT_ALIVE   !fill NUM_ACTORS    ; 0 = destroyed (hidden, no patrol/link)")
    o.append("ACT_DIR     !fill NUM_ACTORS    ; facing (DIR_*)")
    o.append("ACT_ANIM    !fill NUM_ACTORS    ; walk frame 0=rest 1=walk1 2=walk2")
    o.append("ACT_FAST    !fill NUM_ACTORS    ; 1 = rushing (hunter saw the player): double pace")
    o.append("GL_PXL      !fill NUM_ACTORS+1  ; sprite pixel X lo (smooth movement;")
    o.append("GL_PXH      !fill NUM_ACTORS+1  ;  last slot = the human), X hi bit")
    o.append("GL_PY       !fill NUM_ACTORS+1  ; sprite pixel Y")
    o.append("CODE_CNT    !fill NUM_CODES+1   ; security codes carried, per code type (0-9)")
    o.append("CODE_ENT    !fill NUM_CODES+1   ; CODE_CNT on entering the current room (restored on death)")
    o.append("ITEM_STATE  !fill NUM_ITEMS+1   ; 0=hidden 1=carried 2=used (+1 pads the empty case)")
    o.append("DOOR_OPEN   !fill NUM_DOORS+1   ; 1 = keyed door opened (art erased, passable)")
    o.append("ROOM_SEEN   !fill NUM_ROOMS     ; 1 = the player has been in this room (goal visited:)")
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
