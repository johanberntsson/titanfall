;;; The C build's memory map: the asm build's (CLAUDE.md, "Memory Layout"),
;;; as far as a C64 PRG allows. The Makefile fills in @SPRITES@ (the sprite
;;; block's start, from tools/acme2c.py) and writes c/build/titan.scm.
;;;
;;; One `program` memory, $0801-$BFFF: BASIC is banked out before anything
;;; above $A000 runs (irq.s, __low_level_init). A PRG can't have a second
;;; memory with contents, so the VIC data is pinned inside it: the sprites
;;; right below the charset, the charset at $3800 (the top of VIC bank 0).
;;; The linker puts code and data after the pinned sections, from $4000;
;;; the gap between the startup and the sprites is filled with the code
;;; sections the C files name `lowcode` (#pragma clang section).
;;;
;;; The C build needs more room than that: the big data that's read rarely
;;; -- the packed room maps, the sector map, the logo, the robodex pages --
;;; lives in the RAM under the KERNAL ROM
;;; (`kdata`, $E000-$FFF9), read with the KERNAL banked out for a moment
;;; (kernal_out/kernal_in, titan.h). Its NMI vector at $FFFA (`vectors`)
;;; points at an rti, so RESTORE can't crash it meanwhile. A PRG can't
;;; hold two memories: the linker writes Intel hex, tools/hex2prg.py makes
;;; a PRG of each, and exomizer packs them all.
;;;
;;; The music sits at $C000 (a separate file packed by exomizer), the help
;;; screen's save buffers at $C600-$CDFF; the C stack takes $CE00-$CFFF.
;;; Zero page: $02-$8F -- above it is the KERNAL's (its IRQ runs every
;;; frame) and the music's ($FB/$FC).

(define memories
  '((memory program
            (address (#x801 . #xbfff)) (type any)
            (section (programStart #x801) (startup #x80e)
                     (lowcode #x0880) (sprites @SPRITES@) (charset #x3800)))
    (memory zeroPage (address (#x2 . #x8f)) (type ram) (qualifier zpage))
    (memory stackPage (address (#x100 . #x1ff)) (type ram))
    (memory freeSpace (address (#x02a7 . #x02ff)) (section zpsave))
    (memory kernal
            (address (#xe000 . #xffff))
            (section kdata (vectors #xfffa)))
    (memory upperdata
            (address (#xce00 . #xcfff))
            (section cstack heap))
    (block cstack (size #x200))
    (block heap (size 0))
    ))
