;;; The C port's assembly: only what C can't do. (titanfall.asm, game.asm)
;;;
;;; __low_level_init  banks BASIC out before the C startup runs anything:
;;;                   code and data run past $A000.
;;; raster_irq        the 50 Hz tick: sets tick_flag, then plays a sound
;;;                   effect or the music, then the KERNAL's IRQ tail -- but
;;;                   not in the game state: the game reads the keyboard
;;;                   matrix itself, and the KERNAL's scan costs ~1300 cycles
;;;                   a frame while a key is held (the asm build pays them;
;;;                   the C build needs them). The menus (GETIN) keep it.
;;; sound_tick        the effects, from the IRQ: it may only use A (the
;;;                   KERNAL saves A/X/Y) and the snd_* variables -- C code
;;;                   called from an interrupt would have to save Calypsi's
;;;                   pseudo-registers too.
;;; getin, music_init wrappers for the KERNAL's GETIN and the tune's init.

              .extern tick_flag, snd_tmr, snd_kind, music_off, lfsr_st
              .extern irq_frames, game_state

MUSIC_INIT:   .equlab 0xc000
MUSIC_PLAY:   .equlab 0xc003
KERNAL_IRQ:   .equlab 0xea31
KERNAL_RTI:   .equlab 0xea81            ; the KERNAL IRQ's exit: pla/tay/pla/tax/pla/rti
GETIN:        .equlab 0xffe4
ZAP_LEN:      .equ    40
BOOM_LEN:     .equ    100

              .section code,text
              .public __low_level_init, irq_install, getin, music_init

;;; The C startup calls this first (commodore-startup.s). BASIC ROM out:
;;; $A000-$BFFF becomes RAM; the KERNAL and I/O stay in.
__low_level_init:
              sei
              lda     #0x36
              sta     0x01
              rts

;;; The raster IRQ at line 50 and the NMI (RESTORE does nothing: the
;;; KERNAL's handler would warm-start the banked-out BASIC). Interrupts are
;;; still off from __low_level_init; init() in main.c turns them on.
irq_install:  lda     #.byte0 raster_irq
              sta     0x0314
              lda     #.byte1 raster_irq
              sta     0x0315
              lda     #.byte0 nmi_rti
              sta     0x0318
              lda     #.byte1 nmi_rti
              sta     0x0319
              rts

raster_irq:   lda     #1
              sta     0xd019
              sta     tick_flag
              inc     irq_frames            ; (frames counted, for profiling)
              lda     snd_tmr
              beq     music$
              jsr     sound_tick            ; an effect owns the SID
              jmp     done$
music$:       lda     music_off
              bne     done$
              jsr     MUSIC_PLAY
done$:        lda     zp:game_state
              cmp     #1                    ; the game: no KERNAL keyboard scan
              bne     kernal$
              jmp     KERNAL_RTI
kernal$:      jmp     KERNAL_IRQ

nmi_rti:      rti

getin:        jmp     GETIN

music_init:   lda     #0
              jmp     MUSIC_INIT

;;; The laser zap (snd_kind 0) and the explosion (1); see game.asm.
sound_tick:   lda     snd_tmr
              beq     out$
              dec     snd_tmr
              bne     kind$
              lda     #0x20                 ; the end: gate off
              sta     0xd404
              lda     #0x0f
              sta     0xd418
out$:         rts
kind$:        lda     snd_kind
              bne     boom$
              lda     snd_tmr               ; the zap: fade the last 15 frames
              cmp     #16
              bcs     wave$
              sta     0xd418
wave$:        lda     snd_tmr
              and     #7
              cmp     #3
              beq     gap$
              lda     snd_tmr
              lsr     a
              bcc     buzz$
              lda     lfsr_st               ; odd frame: noise crackle
              eor     snd_tmr
              and     #0x0f
              ora     #0x20
              sta     0xd401
              lda     #0x81
              sta     0xd404
              rts
buzz$:        lda     lfsr_st               ; even frame: the buzz
              eor     snd_tmr
              sta     0xd400
              and     #1
              ora     #4
              sta     0xd401
              lda     #0x41
              sta     0xd404
              rts
gap$:         lda     #0x40                 ; gate off for a frame: the stutter
              sta     0xd404
              rts
boom$:        lda     snd_tmr               ; the explosion
              cmp     #BOOM_LEN/2+1
              bne     b2$
              lda     #0x80                 ; gate off for a frame ...
              sta     0xd404
              rts
b2$:          cmp     #BOOM_LEN/2
              bne     b3$
              lda     #0x81                 ; ... second blast
              sta     0xd404
b3$:          lda     snd_tmr               ; pitch falls: a rumble
              lsr     a
              lsr     a
              clc
              adc     #2
              sta     0xd401
              rts

;;; The vectors in the RAM under the KERNAL: read while kernal_out() has
;;; the ROM banked out (interrupts off, but RESTORE is an NMI).
              .section vectors,rodata,root
              .word   nmi_rti, nmi_rti, nmi_rti
