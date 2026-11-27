; retrocore: style=strict
; COMMODORE VIC-20 KERNAL: THE PATCH AREA ($E4A0-$E4FF)
;
; Commodore fixed the kernal late by moving code here, where BASIC's part of the chip leaves room, and jumping to it:
; three of the serial bus's line routines, two patches to the serial bus's LOAD, and in 901486-06 and -07 a fix to
; CLOSE. Commodore's listing places its patches with AROUND and KSP2 (where the serial code goes on after the moved
; routines, and the free space after them), SKIPBY, KSP3, SKIPIT and KSP4, arithmetic on the addresses that this
; source does not need.

; The serial bus: three of its line routines, moved here; the rest is in Kernal.Serial.asm.
.scope Serial continued

;; Releases the serial bus's DATA line, so it goes high unless a device holds it low: VIA 2's CB2 low. It was moved to
;; the patch area at $E4A0 for room.
;; Keeps: X, Y
;; Also: DATAHI (KV20)
.proc ReleaseData
    lda Via2PeripheralControl
    and #<~DATA_OUT
    sta Via2PeripheralControl
    rts
.endproc

;; Pulls the serial bus's DATA line low: VIA 2's CB2 high.
;; Out: zero = clear, always (the byte stored has <DATA_OUT> set), so a caller can follow it with BNE
;; Keeps: X, Y
;; Also: DATALO (KV20)
.proc PullData
    lda Via2PeripheralControl
    ora #DATA_OUT
    sta Via2PeripheralControl
    rts
.endproc

;; Reads the serial bus's lines on VIA 1's port A, again until two reads agree so a line changing mid-read is not
;; taken, and shifts them right once, so CLK lands in carry and DATA in bit 0.
;; Out: carry = set while CLK is released (high), A = port A shifted right once: bit 0 set while DATA is released
;; Keeps: X, Y
;; Also: DEBPIA (KV20)
.proc ReadLines
    lda Via1PortA
    cmp Via1PortA
    bne ReadLines
    lsr a
    rts
.endproc

.endscope

;; The channels and files behind BASIC's OPEN, CLOSE, GET#, INPUT#, PRINT#, CMD, LOAD, SAVE and VERIFY: the RAM
;; vectors' default routines, which send each call to the device the file is on (0 the keyboard, 1 the tape, 2 RS-232,
;; 3 the screen, 4-31 the serial bus), the table of open files, the kernal's messages and its errors.
.scope Channels

;; Patches the serial bus's LOAD: keeps the caller's secondary address in X, before <Load> replaces it with its own,
;; for <LoadAddressPatch>; then SEARCHING through <PrintSearching>.
;; In: SecondaryAddress = the caller's, 0 to load at <LoadAddress>
;; Out: X = the secondary address
;; Also: PATCH2 (KV20)
.proc LoadSearchPatch
    ldx SecondaryAddress
    jmp PrintSearching
.endproc

;; Patches the serial bus's LOAD: with the caller's secondary address 0, the program loads at <LoadAddress> rather
;; than at the address its first two bytes give; then LOADING or VERIFYING through <PrintLoading>.
;; In: X = the caller's secondary address, from <LoadSearchPatch>, EndAddress = the file's own address
;; Out: EndAddress = where the bytes go, carry = clear
;; Keeps: X
;; Also: PATCH3 (KV20)
.proc LoadAddressPatch
    txa
    bne Print
    lda LoadAddress
    sta EndAddress
    lda LoadAddress+1
    sta EndAddressHigh

;; LOADING or VERIFYING.
;; Also: PATCH4 (KV20)
Print:
    jmp PrintLoading
.endproc

;; The ROMs' fix to <Close> (901486-06 and -07 alike), which jumps here once a tape file's end-of-file zero is in
;; the buffer: writes the buffer as the file's last block, and goes back to <Close::LastBlockWritten>.
;;
;; <Close> comes here by JMP with the file's table index on the stack. If STOP gives the write up, the patch drops
;; that index, so <Close> returns at once with A = 0 and carry set, its stack balanced, and leaves the file in the
;; tables. No listing names this patch: at $E4CF Commodore's listing has a STOP-key patch to the clock instead, which
;; the ROMs do not have (see <Clock::Tick::ReadStopRow>).
;; Out: carry = set after STOP, A = 0 after STOP
.proc CloseTapePatch
    jsr Tape::WriteBuffer
    bcc Return

    ; STOP: the table index off the stack.
    pla
    lda #0

;; Goes back to <Close>, carry as <Tape::WriteBuffer> left it.
Return:
    jmp Close::LastBlockWritten
.endproc

    ; The rest of the patch area is blank.
    .res $E500 - *, $FF

.endscope
