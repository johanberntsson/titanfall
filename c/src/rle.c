/* The room maps are RLE-packed by genworld.py: a literal char, or RLE_ESC,
 * count, char for a run; RLE_ESC, 0 ends it. (rle.asm) */
#include "titan.h"

/* code below the sprite block (c/titan-c64.scm) */
#pragma clang section text="lowcode"


uint8_t ROOM_BUF[22 * 40];          /* the current room's map, unpacked */

/* CUR_ROOM's map into ROOM_BUF, on every draw_room: everything that puts
 * "the map's chars back" reads it */
void room_unpack(void)
{
    const uint8_t *s = ROOM_MAP[cur_room];
    uint8_t *d = ROOM_BUF;

    kernal_out();                   /* the maps are under the KERNAL */
    for (;;) {
        if (*s != RLE_ESC) {
            *d++ = *s++;
        } else if (s[1]) {
            fill(d, s[2], s[1]);
            d += s[1];
            s += 3;
        } else {
            kernal_in();
            return;
        }
    }
}
