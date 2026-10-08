; =============================================================================
; titan_theme_sid.asm — wraps music/titan_theme.prg in a PSID v2 header, so
; the tune plays in SID players (sidplayfp, VICE's vsid, HVSC-style players).
; Built with "make sid" (acme -f plain), output music/titan_theme.sid.
; The header is big-endian and its strings are ASCII (!text, not !pet).
; =============================================================================

        * = 0
        !text "PSID"
        !be16 2                 ; version
        !be16 $7C               ; data offset (header length)
        !be16 0                 ; load address: the data's first 2 bytes
        !be16 $C000             ; init
        !be16 $C003             ; play
        !be16 1                 ; songs
        !be16 1                 ; start song
        !be32 0                 ; speed: all songs on the 50 Hz VBI

SID_STR !text "Countdown (TITAN Fall theme)"
        !fill 32 - (* - SID_STR), 0
SID_AUT !text "Johan Berntsson"
        !fill 32 - (* - SID_AUT), 0
SID_REL !text "2026 TITAN Fall"
        !fill 32 - (* - SID_REL), 0

        !be16 $0014             ; flags: PAL, MOS6581
        !byte 0, 0              ; start page, page length (relocation: none)
        !be16 0                 ; reserved

!if * != $7C {
        !error "PSID header is not $7C bytes"
}
        !binary "music/titan_theme.prg"
