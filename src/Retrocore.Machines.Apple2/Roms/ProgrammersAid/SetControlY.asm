;; PROGRAMMER'S AID #1: SETTING UP CTRL-Y ($D5B0-$D5BB)
;;
;; The routine the Ctrl-Y setups share: Relocate's (D4D5G), Tape Verify's (D52EG) and the RAM test's (D5BCG). Apple's
;; listings name it SETCTLY but do not include it. Part of ProgrammersAid.asm.

;; Points the Monitor's Ctrl-Y command at a routine: writes JMP and its address to <Monitor:USRADR>.
;; In: A = the routine's address, low byte; Y = its high byte
;; Uses: A
SETCTLY:
    sta USRADR+1                    ; $D5B0
    sty USRADR+2                    ; $D5B3
    lda #$4C                        ; $D5B6 JMP
    sta USRADR                      ; $D5B8
    rts                             ; $D5BB
