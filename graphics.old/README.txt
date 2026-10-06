Each room is a separate vchar64 project file, but they all use the same
character set and tile painting scheme.

Each room is 22 x 40 characters. This is since the top two rows are used for
the HUD, and the bottom line is a status line. The game map is the 22 lines
in between.

Adding / changing a room map
----------------------------
1. Edit the room in vchar64 and export the map as an ASM file
   (titan_roomNN-map.s). For room 1, export all (colours, charset, map);
   for other rooms just export the map.
2. Reference the export in titan.yaml (the room's "vchar64_map:" field).
3. Run make. tools/genworld.py reads the export directly and converts the
   .byte lines to ACME !byte in the generated src/world.asm — no manual
   editing of the map export is needed.

Note that walls, doors, lasers, terminals and item spots are NOT read from
the map bytes — they are tile coordinates/rectangles in titan.yaml. Keep the
art and the config in visual sync by hand.

Charset / colours (room 1 exports) are different: they are hand-converted
(.byte -> !byte) into the checked-in src/charset.asm. If the charset or the
TILE_COLORS table changes, regenerate that file with the same substitution —
see "Custom Charset / Screen Art" in CLAUDE.md.
