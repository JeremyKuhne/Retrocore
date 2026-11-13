;; THE HOST'S FIRMWARE: THE SLOT PAGE, AND THE CODE AT $CA00-$CFFF
;;
;; The code the Apple II runs, which the card's 65C02 copies out of the EPROM at start-up: the slot page ($8100,
;; seen at $Cn00), the call and boot code ($8200-$83FF, which the card keeps at its $0200-$03FF and the host runs
;; at $CA00-$CBFF with bank 0 latched), and the transfers ($8400-$87FF, at $CC00-$CFFF). It is 6502 code that also
;; runs on the 65C02 and, on a IIgs, takes 65816 paths that move a block through any bank with the machine at full
;; speed. The 65816 instructions are written with the macros below, which give their bytes.
;;
;; THE SLOT PAGE
;;
;; $Cn01 = $20, $Cn03 = $00, $Cn05 = $03 and $Cn07 = $00 mark a SmartPort. $CnFB = $C0 (extended calls), $CnFC-$CnFD
;; = 0 (ask STATUS for the size), $CnFE = $BF (removable, interruptible, four volumes, format, write, read and
;; status) and $CnFF = $1C: ProDOS calls $Cn1C and SmartPort $Cn1F. The page holds three waits, each a branch to
;; itself, whose offsets the card rewrites once it is ready: the boot's at $Cn0B (to $Cn23, as a call with overflow
;; set), the diagnostics' at $Cn17, and the calls' at $Cn21. Until then a boot or a call waits; a card that fails its
;; self-test writes JMP $FF59 over $Cn00, $Cn0D and $Cn23 instead, so each goes to the Monitor.
;;
;; A CALL
;;
;; A call saves page zero $40-$51 in the card's RAM, copies its parameters into page zero, checks the count, and
;; hands the command to the card through the card's own page zero, seen at $C800-$C80C and $C856 with bank 0
;; latched. A block moves through one of the window's banks, 512 bytes at $C800 or $CA00. On the way out the call
;; puts page zero back and returns A = the error, carry set when it is not 0, and X and Y = the bytes moved.
;;
;;   $C800  the card's state: bit 7 set while it waits for a command; the host writes the command there
;;   $C801  the data: $FF from the host as it sends; bit 7 set while the card works, 0 for no data, else the bank
;;          (bits 1-4) and half (bit 0) the data is in; the host ORs in $F0 when it has taken or left it
;;   $C802  the command, $C803 the unit, $C804-$C80A the call's page zero $45-$4B
;;   $C80B  a count, both ways, low byte first
;;   $C856  the error
;;
;; The card's commands: the SmartPort command less its extended bit ($00-$0B), $0C to read the boot block, $3D to
;; start the diagnostics, and $7E or $7F to say the host is not or is a IIgs.

.cpu Mos6502

.include "../System/IIeEquates.asm"
.include "../System/MonitorEntries.asm"

; The host's names that the SDK's equates lack.
LOC1 = $01                          ;; the high byte of the Monitor's slot pointer, $Cn while it boots slot n
SHADOW = $C035                      ;; the IIgs's shadowing register
CYAREG = $C036                      ;; the IIgs's speed register: bit 7 for full speed
STATEREG = $C068                    ;; the IIgs's state register, which a IIe does not have
CLRROM = $CFFF                      ;; releases the $C800 expansion ROM of every card
BASIC = $E000                       ;; AppleSoft's cold start
SLOOP = $FABA                       ;; the Monitor's boot scan, which goes on to the next slot
SETTXT = $FB39                      ;; the Monitor's text mode
ZIDBYTE = $FBC0                     ;; $E0 on the enhanced IIe, the IIc and the IIgs
IDROUTINE = $FE1F                   ;; an RTS on the IIe; on the IIgs it returns carry clear

; The call's page zero, which the call saves and restores.
SPBUFFER = $40                      ;; the buffer, three bytes; first the caller's return address
SPCOMMAND = $43                     ;; the command: bit 6 extended, bit 7 a ProDOS call
SPUNIT = $44                        ;; the SmartPort unit
SPPARAMS = $46                      ;; the call's other parameters, $46-$4B
SPLIST = $4C                        ;; the parameter list; later the data in the window
SPCOUNT = $4E                       ;; the bytes moved; first the parameter list's bank
SPRESULT = $50                      ;; the parameter count, then the error
SPSLOT16 = $51                      ;; the slot times 16
SPTRIES = A1L                       ;; the boot's waits

SAVEDZP = $40                       ;; the first page-zero byte saved
SAVEDZPEND = $52                    ;; past the last

; The card's page zero, at $C800 with bank 0 latched.
MBSTATE = $C800                     ;; bit 7 set while the card waits; the command goes here
MBDATA = $C801                      ;; where the data is, or 0 for none; bit 7 set while the card works
MBCOMMAND = $C802                   ;; the call's $43-$4B
MBUNIT = $C803                      ;; the unit
MBFLOW = $C804                      ;; the call's $45, which the IIgs's writes use to pace the card
MBCOUNT = $C80B                     ;; a count, low and high
MBERROR = $C856                     ;; the error

; The card's RAM at $0A00, at $CA00 with bank 2 latched.
CALLBUSY = $CA00                    ;; bit 7 set while a call runs, on a host that is not a IIgs
SAVEDZPAREA = $CA02                 ;; page zero $40-$51 while a call runs

; The window banks.
BANKMAILBOX = 0                     ;; the card's page zero, and this code at $CA00
BANKSAVE = 2                        ;; the busy flag and saved page zero

; The card's commands.
CMDBOOT = $0C                       ;; reads the boot block into the window
CMDDIAGNOSTICS = $3D                ;; loads the diagnostics' code at $CC00
CMDNOTIIGS = $7E                    ;; the host is not a IIgs
CMDIIGS = $7F                       ;; the host is a IIgs

; SmartPort's errors that the host names.
BADCMD = $01
BADPCNT = $04
NODRIVE = $28
NOWRITE = $2B
IOERROR = $27
OFFLINE = $2F
NEVERREADY = $30                    ;; the card did not answer: not a SmartPort error, only the boot's

DIAGENTRY = $CC00                   ;; the diagnostics' code, once the card has put it in place of this

;; The 65816's XCE, which swaps carry with the emulation flag.
.macro Xce816
    .byte $FB
.endmacro

;; The 65816's REP: clears the status bits set in the mask.
.macro Rep816 mask
    .byte $C2, mask
.endmacro

;; The 65816's SEP: sets the status bits set in the mask.
.macro Sep816 mask
    .byte $E2, mask
.endmacro

;; The 65816's (and 65C02's) PHX.
.macro Phx816
    .byte $DA
.endmacro

;; The 65816's (and 65C02's) PLX.
.macro Plx816
    .byte $FA
.endmacro

;; The 65816's LDA [dp],Y, through a three-byte pointer.
.macro LdaLongY pointer
    .byte $B7, pointer
.endmacro

;; The 65816's STA [dp],Y, through a three-byte pointer.
.macro StaLongY pointer
    .byte $97, pointer
.endmacro

.logicalorg $C500
;; Boots the card's first drive. The four loads are the SmartPort identification at $Cn01-$Cn07. Overflow, set by
;; the addition, makes the call that follows a boot; until the card is ready the branch waits on itself.
SLOTROM:
    ldx #$20
    ldx #$00
    ldy #$03
    lda #$00
    sec
    adc #$7F
BOOTWAIT:
    bvs BOOTWAIT                    ; the card makes it BVS CALL
.assert * == $C50D

;; Starts the card's diagnostics, as Cn0DG does from the Monitor.
DIAG:
    php
    sei
    bit CLRROM
    jsr ASKDIAG
;; Waits for the diagnostics' code, then runs it. The boot comes here with A = 0 for Control-D.
;; In:    A = 0, the caller's status on the stack
DIAGWAIT:
    plp
    tax
DIAGWAIT_Loop:
    beq DIAGWAIT_Loop               ; the card makes it fall through once the code is there
    jmp DIAGENTRY

.assert * == $C51C
;; The ProDOS block-device entry.
;; In:    $42 = the command (0 status, 1 read, 2 write, 3 format), $43 = the unit, $44/$45 = the buffer,
;;          $46/$47 = the block
;; Out:   A = 0 or the error, carry = set on an error; X/Y = the block count after status
PRODOS:
    clc
    bcc CALLWAIT                    ; always

.assert * == $C51F
;; The SmartPort entry: JSR $Cn1F, then the command and the parameter list's address (four bytes for an extended
;; command), which the call steps over.
;; Out:   A = 0 or the error, carry = set on an error, X/Y = the bytes moved
SMARTPORT:
    sec
CALLWAIT:
    clv
CALLWAIT_Loop:
    bvc CALLWAIT_Loop               ; the card makes it fall through

;; The common entry: finds the slot, saves page zero and runs a boot, a ProDOS call or a SmartPort call.
;; In:    carry = set for SmartPort, overflow = set to boot
CALL:
    php
    sei
    lda CLRROM
    jsr RETURN                      ; leaves its return address's high byte, $Cn, just below the stack
    tsx
    lda $0100,x
    sta MSLOT
    tay
    ldx SLOT16TABLE-$C1,y
    lda LCRAM2+BANKSAVE,x
    jsr ENTER
    ldx #SAVEDZPEND-SAVEDZP
CALL_Save:
    lda SAVEDZP-1,x
    sta SAVEDZPAREA-1,x
    dex
    bne CALL_Save
    plp
    ldx SLOT16TABLE-$C1,y
    lda LCRAM2+BANKMAILBOX,x
    bvc CALL_Call
    jsr BOOT
    beq DIAGWAIT                    ; Control-D: the diagnostics
CALL_Call:
    bit HOSTTYPE
    bpl CALL_Known
    jsr IDENTIFY
    ldy MSLOT
CALL_Known:
    bcc CALL_ProDOS

    ; SmartPort: the command and the list follow the JSR.
    pla
    sta SPBUFFER
    pla
    sta SPBUFFER+1
    ldy #1
    lda (SPBUFFER),y
    sta SPRESULT
    iny
    lda (SPBUFFER),y
    sta SPLIST
    iny
    lda (SPBUFFER),y
    sta SPLIST+1
    iny
    lda (SPBUFFER),y                ; an extended list's bank
    dey
    bit SPRESULT
    bvc CALL_Bank0
    ldy #5
    bit HOSTTYPE
    bvs CALL_Bank                   ; only the IIgs reaches other banks
CALL_Bank0:
    lda #0
CALL_Bank:
    sta SPCOUNT
    tya
    clc
    adc SPBUFFER
    tax
    lda #0
    adc SPBUFFER+1
    pha
    txa
    pha                             ; returns past the command and list
    jsr GETLIST
    lda SPCOMMAND
    and #$BF
    cmp #$0C
    bcc CALL_Dispatch
CALL_BadCommand:
    lda #BADCMD
    bne CALL_Return                 ; always
    lda #$11                        ; no code reaches this
    bne CALL_Return

CALL_ProDOS:
    lda $42
    cmp #4
    bcs CALL_BadCommand
    jsr PRODOSLIST
    lda SPCOMMAND
    clc
    adc #$8C                        ; $80-$83 become $0C-$0F
CALL_Dispatch:
    jsr DISPATCH
    lda SPRESULT
CALL_Return:
    pha
    lda SPCOUNT
    pha
    lda SPCOUNT+1
    pha
    ldy MSLOT
    ldx SLOT16TABLE-$C1,y
    lda LCRAM2+BANKSAVE,x
    ldx #0
CALL_Restore:
    ldy SAVEDZPAREA,x
    sty SAVEDZP,x
    inx
    cpx #SAVEDZPEND-SAVEDZP
    bcc CALL_Restore
    lda #0
    sta CALLBUSY
    pla
    tay
    pla
    tax
    pla
    cmp #1
    ora #0
    rts

;; Copies the 16 bytes at $C100-$C10F to $CBEE-$CBFD, for the diagnostics, which look there for the factory
;; fixture's ROM in slot 1.
COPYC100:
    ldy #$0F
COPYC100_Loop:
    lda $C100,y
    bit CLRROM
    sta $CBEE,y
    dey
    bpl COPYC100_Loop
    rts

    .byte 0, 0
.assert * == $C5F8
    .byte 0, 0, 0
    .byte $C0                       ; $CnFB: extended SmartPort calls
    .word 0                         ; $CnFC: ask STATUS for the block count
    .byte $BF                       ; $CnFE: removable, interruptible, four volumes, format, write, read, status
    .byte <PRODOS                   ; $CnFF: the ProDOS entry
.assert * == $C600

.logicalorg $CA00
;; Tells the card whether the host is a IIgs: one whose $C068 holds what is written to it, whose Monitor is the IIe's
;; family's ($FBB3 = $06, $FBC0 = $E0), and whose IDROUTINE returns carry clear.
;; Keeps: Y, interrupt
IDENTIFY:
    php
    sei
    lda STATEREG
    pha
    ldx #10
IDENTIFY_Toggle:
    eor #$0E
    sta STATEREG
    cmp STATEREG
    bne IDENTIFY_Not
    dex
    bne IDENTIFY_Toggle
    pla
    sta STATEREG
    lda VERSION
    cmp #$06
    bne IDENTIFY_NotIIgs
    lda ZIDBYTE
    cmp #$E0
    bne IDENTIFY_NotIIgs
    sec
    jsr IDROUTINE
    bcs IDENTIFY_NotIIgs
    lda #CMDIIGS
    bne IDENTIFY_Tell               ; always
IDENTIFY_Not:
    pla
IDENTIFY_NotIIgs:
    lda #CMDNOTIIGS
IDENTIFY_Tell:
    bit MBSTATE
    bpl IDENTIFY_Tell
    sta MBSTATE
IDENTIFY_Done:
    bit MBSTATE
    bpl IDENTIFY_Done
    plp
    rts

;; Copies the parameter list into page zero: a standard list's eight bytes after the count, or an extended list's
;; eleven, then moves the buffer to $40-$42, the command to $43 and the unit to $44.
;; In:    SPLIST = the list, SPCOUNT = its bank on a IIgs, SPRESULT = the command
;; Out:   SPRESULT = the list's count
GETLIST:
    bit SPRESULT
    bvs GETLIST_Extended
    ldy #8
GETLIST_Standard:
    tax
    lda (SPLIST),y
    dey
    bmi GETLIST_Standard_Done
    cpy #3
    bcc GETLIST_Standard_Low
    sta SPCOMMAND,y                 ; the parameters after the buffer go to $46-$4A
    bcs GETLIST_Standard            ; always
GETLIST_Standard_Low:
    sta SPBUFFER+1,y                ; the unit and buffer go to $41-$43
    bcc GETLIST_Standard            ; always
GETLIST_Standard_Done:
    iny
    sty SPUNIT                      ; the buffer's bank: 0
    sty SPPARAMS+5
    beq GETLIST_Move                ; always
GETLIST_Extended:
    ldy #11
GETLIST_Extended_Next:
    tax
    bit HOSTTYPE
    bvs GETLIST_Extended_Long
    lda (SPLIST),y
    bvc GETLIST_Extended_Got        ; always
GETLIST_Extended_Long:
    LdaLongY SPLIST
GETLIST_Extended_Got:
    dey
    bmi GETLIST_Move
    sta SPBUFFER+1,y
    bpl GETLIST_Extended_Next       ; always
GETLIST_Move:
    ldy SPRESULT
    sta SPRESULT
    lda $42
    sta SPBUFFER
    lda $43
    sta SPBUFFER+1
    lda SPUNIT
    sta SPBUFFER+2
    stx SPUNIT
    sty SPCOMMAND
    rts

;; Each command's handler, less one, low and high bytes, then the parameter count it needs ($FF for none): SmartPort's
;; $00-$0B, then ProDOS's status, read, write and format.
HANDLERLOW:
    .byte <(SPSTATUS-1), <(READBLOCK-1), <(WRITEBLOCK-1), <(SIMPLE-1), <(CONTROL-1), <(SPINIT-1), <(SIMPLE-1)
    .byte <(SIMPLE-1), <(SPSTATUS-1), <(WRITE-1), <(COMMAND0A-1), <(SPSTATUS-1)
    .byte <(PRODOSSTATUS-1), <(READBLOCK-1), <(WRITEBLOCK-1), <(SIMPLE-1)
HANDLERHIGH:
    .byte >(SPSTATUS-1), >(READBLOCK-1), >(WRITEBLOCK-1), >(SIMPLE-1), >(CONTROL-1), >(SPINIT-1), >(SIMPLE-1)
    .byte >(SIMPLE-1), >(SPSTATUS-1), >(WRITE-1), >(COMMAND0A-1), >(SPSTATUS-1)
    .byte >(PRODOSSTATUS-1), >(READBLOCK-1), >(WRITEBLOCK-1), >(SIMPLE-1)
PARAMCOUNTS:
    .byte 3, 3, 3, 1, 3, 1, 1, 1, 4, 4, 3, 3   ; STATUS to $0B
    .byte $FF, $FF, $FF, $FF                    ; ProDOS's calls have no count

;; Boots: waits for the card, or starts the diagnostics after three Control-Ds, then has the card read the boot block
;; into $0800 and runs it with X = the slot times 16, as ProDOS expects. A block that does not start with $01 and a
;; nonzero byte is not a boot block.
;; In:    X = the slot times 16, bank 0 latched
;; Out:   zero = set for the diagnostics, with the caller's status and return address back on the stack; otherwise
;;          it does not return
BOOT:
    stx SPSLOT16
    jsr IDENTIFY
    lda #0
    sta SPCOUNT
    sta SPCOUNT+1
    ldx #3                          ; three Control-Ds
    stx SPTRIES
    ldy VERSION
    cpy #$06
    beq BOOT_Strobe
    lda KBD                         ; a II or II Plus: no key held to look for
    ora #$80
    bmi BOOT_Key                    ; always
BOOT_Strobe:
    bit KBDSTRB
    bpl BOOT_Ready                  ; no key down
    bmi BOOT_Look                   ; always
BOOT_Next:
    sta KBDSTRB
BOOT_Look:
    lda KBD
    bmi BOOT_Key
    cpy #$06
    bne BOOT_Count
    bit KBDSTRB
    bpl BOOT_Ready
BOOT_Count:
    inc SPCOUNT
    bne BOOT_Look
    inc SPCOUNT+1
    bne BOOT_Look
    dec SPTRIES
    bne BOOT_Look
    beq BOOT_Ready                  ; always
BOOT_Key:
    cmp #$84                        ; Control-D
    bne BOOT_Ready
    dex
    bne BOOT_Next
    ; The diagnostics: put the caller's status back above its return address and ask the card.
    php
    sei
    pla
    tay
    pla
    sta SPCOUNT
    pla
    sta SPCOUNT+1
    tya
    pha
    lda SPCOUNT+1
    pha
    lda SPCOUNT
    pha
    jmp ASKDIAG
BOOT_Ready:
    ldx #3
BOOT_Wait:
    lda MBSTATE
    bmi BOOT_Read
    inc SPCOUNT
    bne BOOT_Wait
    inc SPCOUNT+1
    bne BOOT_Wait
    dex
    bne BOOT_Wait
    lda #NEVERREADY
    sta SPRESULT
    bne BOOT_Fail                   ; always
BOOT_Read:
    lda #$FF
    sta MBDATA
    lda #0
    sta MBUNIT
    lda #$81                        ; a ProDOS read, so errors are ProDOS's
    sta SPCOMMAND
    lda #CMDBOOT
    sta MBSTATE
    lda #>$0800
    sta SPBUFFER+1
    lda #<$0800
    sta SPBUFFER
    sta SPBUFFER+2
    jsr RECEIVEBLOCK
    ldx SPSLOT16
    cmp #1
    bcs BOOT_Fail
    lda #1                          ; ProDOS's page zero, as for a read of block 0
    sta $42
    stx $43
    lda #>$0800
    sta $45
    lda #<$0800
    sta $44
    sta $46
    sta $47
    lda $0800
    cmp #$01
    bne BOOT_Fail
    lda $0801
    beq BOOT_Fail
    lda #0
    bit HOSTTYPE
    bvc BOOT_Run
    sta SHADOW
BOOT_Run:
    jmp $0801
BOOT_Fail:
    stx SPSLOT16
    jmp NOBOOT

;; Turns a ProDOS call's error into one of ProDOS's: 0, $2B, $28 and $2F stand, $11 is $28 and the rest are $27.
;; SmartPort's errors stand.
;; In:    A = the error
;; Out:   A = the error to return
MAPERROR:
    bit SPCOMMAND
    bpl MAPERROR_Done
    cmp #0
    beq MAPERROR_Done
    cmp #NOWRITE
    beq MAPERROR_Done
    cmp #NODRIVE
    beq MAPERROR_Done
    cmp #OFFLINE
    beq MAPERROR_Done
    cmp #$11
    bne MAPERROR_IO
    lda #NODRIVE
    rts
MAPERROR_IO:
    lda #IOERROR
MAPERROR_Done:
    rts

;; Sets ProDOS status's error from the status byte: none for a disk that is in and writable, $2B for one that is
;; write-protected, $2F for none.
;; In:    Y = the status byte's bits 4 (online) and 2 (write-protected), bank 0 latched
PRODOSERROR:
    cpy #$10
    beq PRODOSERROR_Done
    lda #NOWRITE
    cpy #$14
    beq PRODOSERROR_Set
    lda #OFFLINE
PRODOSERROR_Set:
    sta MBERROR
PRODOSERROR_Done:
    rts

    .res 26

;; Gives a call the wrong parameter count's error.
BADCOUNT:
    lda #BADPCNT
    sta SPRESULT
    rts

;; Checks a command's parameter count and goes to its handler, with bank 0 latched once the card is waiting.
;; In:    A = the command: $00-$0B, or $0C-$0F for ProDOS's
DISPATCH:
    ldy MSLOT
    ldx SLOT16TABLE-$C1,y
    stx SPSLOT16
    tax
    lda PARAMCOUNTS,x
    bmi DISPATCH_Go
    cmp SPRESULT
    bne BADCOUNT
DISPATCH_Go:
    lda HANDLERHIGH,x
    pha
    lda HANDLERLOW,x
    pha
    lda #0
    sta SPRESULT
    sta SPCOUNT+1
    sta SPCOUNT
    ldx SPSLOT16
    jsr UNITHOOK
.assert * == $CC00
    lda LCRAM2+BANKMAILBOX,x
;; Waits for the card to wait for a command.
WAITCARD:
    lda MBSTATE
    bpl WAITCARD
;; An RTS: the call jumps to it to find its slot.
RETURN:
    rts

;; Bit 7 set until the host is identified; bit 6 set on a IIgs, whose transfers take the 65816 paths. The card keeps
;; it.
HOSTTYPE:
    .byte $80

;; FORMAT, OPEN, CLOSE and ProDOS's format: the card does all of it.
SIMPLE:
    jsr SEND
    clc
    jmp FINISH

;; ProDOS's status: the card's status 0, then the block count in X and Y, with $2B for a write-protected disk and $2F
;; for none.
PRODOSSTATUS:
    lda #0
    sta SPPARAMS                    ; status code 0
    jsr SEND
PRODOSSTATUS_Wait:
    lda MBDATA
    bmi PRODOSSTATUS_Wait
    beq PRODOSSTATUS_Done
    jsr WINDOW
    ldy #2
    lda (SPLIST),y
    sta SPCOUNT+1
    dey
    lda (SPLIST),y
    sta SPCOUNT
    dey
    lda (SPLIST),y
    and #$14
    tay
    ldx SPSLOT16
    lda LCRAM2+BANKMAILBOX,x
    jsr PRODOSERROR
PRODOSSTATUS_Done:
    jmp FINISHED

;; STATUS, READ and command $0B: the card sends what it read and its length.
;; In:    SPPARAMS = the status code or byte count
SPSTATUS:
    lda SPPARAMS
    sta MBCOUNT
    lda SPPARAMS+1
    sta MBCOUNT+1
    jsr SEND
SPSTATUS_Wait:
    lda MBDATA
    bmi SPSTATUS_Wait
    beq SPSTATUS_Done
    ldx MBCOUNT
    stx SPCOUNT
    ldx MBCOUNT+1
    stx SPCOUNT+1
    jsr WINDOW
    ldx SPCOUNT+1
    beq SPSTATUS_Bytes
    sec
    jsr TOBUFFER                    ; the whole pages
SPSTATUS_Bytes:
    ldx SPCOUNT
    beq SPSTATUS_Done
    clc
    jsr TOBUFFER                    ; the rest
SPSTATUS_Done:
    jmp FINISHED

;; Copies from the window to the buffer.
;; In:    carry = set to copy X pages, clear to copy X bytes; SPLIST = the window, SPBUFFER = the buffer
;; Out:   SPLIST, SPBUFFER = past what was copied
TOBUFFER:
    ldy #0
TOBUFFER_Loop:
    lda (SPLIST),y
    bit HOSTTYPE
    bvc TOBUFFER_Short
    StaLongY SPBUFFER
    bvs TOBUFFER_Stored             ; always
TOBUFFER_Short:
    sta (SPBUFFER),y
TOBUFFER_Stored:
    iny
    bcc TOBUFFER_Count
    bne TOBUFFER_Loop
    inc SPLIST+1
    inc SPBUFFER+1
    bne TOBUFFER_Count
    inc SPBUFFER+2
TOBUFFER_Count:
    dex
    bne TOBUFFER_Loop
    rts

;; WRITE: the card takes the bytes from the buffer.
;; In:    SPPARAMS = the byte count
WRITE:
    lda SPPARAMS
    sta MBCOUNT
    pha
    lda SPPARAMS+1
    sta MBCOUNT+1
    pha
    jmp TOCARD

;; CONTROL: the control list starts with its length, which the card takes, then the list.
CONTROL:
    ldy #0
    bit HOSTTYPE
CONTROL_Length:
    bvc CONTROL_Short
    LdaLongY SPBUFFER
    bvs CONTROL_Got                 ; always
CONTROL_Short:
    lda (SPBUFFER),y
CONTROL_Got:
    sta MBCOUNT,y
    pha
    iny
    cpy #1
    beq CONTROL_Length
    lda SPBUFFER
    clc
    adc #2
    sta SPBUFFER
    bcc TOCARD
    inc SPBUFFER+1
    bne TOCARD
    inc SPBUFFER+2
;; Sends the command, then the bytes counted on the stack, high byte on top.
TOCARD:
    jsr SEND
TOCARD_Wait:
    lda MBDATA
    bmi TOCARD_Wait
    beq TOCARD_Failed
    jsr WINDOW
    pla
    tax
    beq TOCARD_Bytes
    sec
    jsr FROMBUFFER
TOCARD_Bytes:
    pla
    tax
    beq TOCARD_Done
    clc
    jsr FROMBUFFER
TOCARD_Done:
    clc
    jmp FINISH
TOCARD_Failed:
    pla
    pla
    jmp FINISHED

;; Copies from the buffer to the window.
;; In:    carry = set to copy X pages, clear to copy X bytes; SPBUFFER = the buffer, SPLIST = the window
;; Out:   SPLIST, SPBUFFER = past what was copied
FROMBUFFER:
    ldy #0
FROMBUFFER_Loop:
    bit HOSTTYPE
    bvc FROMBUFFER_Short
    LdaLongY SPBUFFER
    bvs FROMBUFFER_Got              ; always
FROMBUFFER_Short:
    lda (SPBUFFER),y
FROMBUFFER_Got:
    sta (SPLIST),y
    iny
    bcc FROMBUFFER_Count
    bne FROMBUFFER_Loop
    inc SPLIST+1
    inc SPBUFFER+1
    bne FROMBUFFER_Count
    inc SPBUFFER+2
FROMBUFFER_Count:
    dex
    bne FROMBUFFER_Loop
    rts

;; Command $0A: sends up to four bytes from the buffer in $46-$49, as many as $46 says.
;; In:    SPPARAMS = the count
COMMAND0A:
    lda #0
    ldx SPPARAMS
    sta SPPARAMS
    sta SPPARAMS+1
    sta SPPARAMS+2
    sta SPPARAMS+3
    beq SPINIT
    cpx #5
    bcc COMMAND0A_Copy
    ldx #4
COMMAND0A_Copy:
    ldy #0
COMMAND0A_Next:
    bit HOSTTYPE
    bvc COMMAND0A_Short
    LdaLongY SPBUFFER
    bvs COMMAND0A_Got               ; always
COMMAND0A_Short:
    lda (SPBUFFER),y
COMMAND0A_Got:
    sta a:SPPARAMS,y
    iny
    dex
    bne COMMAND0A_Next
;; INIT: the card does all of it.
SPINIT:
    jsr SEND
    clc
    jmp FINISH

;; Latches the bank the card's data is in and points SPLIST at it.
;; In:    A = MBDATA: bits 1-4 the bank, bit 0 the half
;; Out:   X = the slot times 16 plus the bank, SPLIST = $C800 or $CA00
WINDOW:
    and #$1F
    lsr a
    php
    clc
    adc SPSLOT16
    tax
    lda LCRAM2,x
    lda #0
    sta SPLIST
    plp
    rol a
    asl a
    adc #$C8
    sta SPLIST+1
    rts

;; READBLOCK and ProDOS's read: 512 bytes from the card.
READBLOCK:
    jsr SEND
;; Takes a block from the card into the buffer.
;; Out:   A = the card's error when there is no block
RECEIVEBLOCK:
    lda MBDATA
    bmi RECEIVEBLOCK
    bne RECEIVEBLOCK_Data
    lda MBERROR
    jmp RECEIVEBLOCK_Done
RECEIVEBLOCK_Data:
    jsr WINDOW
    ldx #2
    ldy #0
    bit HOSTTYPE
    bvs RECEIVEBLOCK_Long
RECEIVEBLOCK_Copy:
    lda (SPLIST),y
    sta (SPBUFFER),y
    iny
    bne RECEIVEBLOCK_Copy
    inc SPLIST+1
    inc SPBUFFER+1
    dex
    bne RECEIVEBLOCK_Copy
RECEIVEBLOCK_Done:
    sec
    jmp BLOCKDONE
RECEIVEBLOCK_Long:
    ; The IIgs: native mode at full speed, 16 bits at a time through a long pointer.
    clc
    Xce816
    php
    lda CYAREG
    pha
    ora #$80
    sta CYAREG
    lda #%00000010                  ; bit 1 of the window's page: $CA
    bit SPLIST+1
    Rep816 $20
    bne RECEIVEBLOCK_UpperHalf
RECEIVEBLOCK_C800:
    lda $C800,y
    StaLongY SPBUFFER
    iny
    iny
    lda $C800,y
    StaLongY SPBUFFER
    iny
    iny
    bne RECEIVEBLOCK_C800
    inc SPBUFFER+1
RECEIVEBLOCK_C900:
    lda $C900,y
    StaLongY SPBUFFER
    iny
    iny
    lda $C900,y
    StaLongY SPBUFFER
    iny
    iny
    bne RECEIVEBLOCK_C900
    beq RECEIVEBLOCK_Back           ; always
RECEIVEBLOCK_UpperHalf:
    lda $CA00,y
    StaLongY SPBUFFER
    iny
    iny
    lda $CA00,y
    StaLongY SPBUFFER
    iny
    iny
    bne RECEIVEBLOCK_UpperHalf
    inc SPBUFFER+1
RECEIVEBLOCK_CB00:
    lda $CB00,y
    StaLongY SPBUFFER
    iny
    iny
    lda $CB00,y
    StaLongY SPBUFFER
    iny
    iny
    bne RECEIVEBLOCK_CB00
RECEIVEBLOCK_Back:
    Sep816 $30
    pla
    sta CYAREG
    plp
    Xce816
    sec
    jmp BLOCKDONE

;; WRITEBLOCK and ProDOS's write: 512 bytes to the card. With MBFLOW's bit 7 set the copy runs with interrupts off.
WRITEBLOCK:
    jsr SEND
WRITEBLOCK_Wait:
    ldx MBDATA
    bmi WRITEBLOCK_Wait
    bne WRITEBLOCK_Data
    jmp FINISHED
WRITEBLOCK_Data:
    lda MBFLOW
    php
    bpl WRITEBLOCK_Window
    sei
    lda #$C0
    sta MBFLOW
WRITEBLOCK_Window:
    txa
    jsr WINDOW
    ldy #0
    bit HOSTTYPE
    bvs WRITEBLOCK_Long
    plp
    ldx #2
WRITEBLOCK_Copy:
    lda (SPBUFFER),y
    sta (SPLIST),y
    iny
    bne WRITEBLOCK_Copy
    inc SPBUFFER+1
    inc SPLIST+1
    dex
    bne WRITEBLOCK_Copy
    jmp BLOCKSENT
WRITEBLOCK_Long:
    ; The IIgs: each page in turn, telling the card through MBFLOW as each is ready.
    clc
    Xce816
    php
    lda CYAREG
    pha
    ora #$80
    sta CYAREG
    Phx816
    lda #%00000010                  ; bit 1 of the window's page: $CA
    bit SPLIST+1
    Rep816 $20
    bne WRITEBLOCK_UpperHalf
WRITEBLOCK_C800:
    LdaLongY SPBUFFER
    sta $C800,y
    iny
    iny
    LdaLongY SPBUFFER
    sta $C800,y
    iny
    iny
    bne WRITEBLOCK_C800
    inc SPBUFFER+1
    Sep816 $20
    ldx SPSLOT16
    lda LCRAM2+BANKMAILBOX,x
    inc MBFLOW
    Plx816
    lda LCRAM2,x
    Rep816 $20
WRITEBLOCK_C900:
    LdaLongY SPBUFFER
    sta $C900,y
    iny
    iny
    LdaLongY SPBUFFER
    sta $C900,y
    iny
    iny
    bne WRITEBLOCK_C900
    beq WRITEBLOCK_Back             ; always
WRITEBLOCK_UpperHalf:
    LdaLongY SPBUFFER
    sta $CA00,y
    iny
    iny
    LdaLongY SPBUFFER
    sta $CA00,y
    iny
    iny
    bne WRITEBLOCK_UpperHalf
    inc SPBUFFER+1
    Sep816 $20
    ldx SPSLOT16
    lda LCRAM2+BANKMAILBOX,x
    inc MBFLOW
    Plx816
    lda LCRAM2,x
    Rep816 $20
WRITEBLOCK_CB00:
    LdaLongY SPBUFFER
    sta $CB00,y
    iny
    iny
    LdaLongY SPBUFFER
    sta $CB00,y
    iny
    iny
    bne WRITEBLOCK_CB00
WRITEBLOCK_Back:
    Sep816 $30
    pla
    sta CYAREG
    plp
    Xce816
    ldx SPSLOT16
    lda LCRAM2+BANKMAILBOX,x
    lda #$D0
    sta MBFLOW
    plp
;; A block has gone to the card: wait for the card to finish.
BLOCKSENT:
    clc
;; A block has moved: counts 512 bytes and finishes.
;; In:    carry = set to finish without waiting for the card
BLOCKDONE:
    lda #>512
    sta SPCOUNT+1
    bne FINISH                      ; always
;; Finishes a call without waiting for the card.
FINISHED:
    sec
;; Tells the card the data is taken, waits for it unless carry is set, and takes its error.
;; In:    carry = set not to wait
;; Out:   SPRESULT = the error, mapped for ProDOS
FINISH:
    ldx SPSLOT16
    lda LCRAM2+BANKMAILBOX,x
    lda MBDATA
    ora #$F0
    sta MBDATA
    bcs FINISH_Error
FINISH_Wait:
    lda MBSTATE
    bpl FINISH_Wait
FINISH_Error:
    lda MBERROR
    jsr MAPERROR
    sta SPRESULT
    ldx #0
    stx MBERROR
    rts

;; Sends the command in page zero: waits for the card, gives it $43-$4B and then the command.
;; Keeps: X
SEND:
    lda MBSTATE
    bpl SEND
    lda #$FF
    sta MBDATA
    txa
    pha
    ldx #8
SEND_Copy:
    lda SPCOMMAND,x
    sta MBCOMMAND,x
    dex
    bpl SEND_Copy
    pla
    tax
    lda MBCOMMAND
    and #$1F
    sta MBSTATE
    rts

;; Each slot's number times 16, for slots 1 to 7, indexed by $Cn less $C1.
SLOT16TABLE:
    .byte $10, $20, $30, $40, $50, $60, $70

;; Turns a ProDOS call into SmartPort's: the command with bit 7 set, the buffer in $40-$42, a three-byte block, and
;; the unit. A unit in this slot is SmartPort unit 1 or 2 by its drive bit; one ProDOS mapped to slot 2 is unit 3 or
;; 4, and one mapped to any other slot 5 or 6. Unit 0 for slot 0.
;; In:    A = the ProDOS command, $43 = the ProDOS unit, Y = $Cn
PRODOSLIST:
    ora #$80
    ldx $43
    sta SPCOMMAND
    lda $44
    sta SPBUFFER
    lda $45
    sta SPBUFFER+1
    lda #0
    sta SPBUFFER+2
    sta SPPARAMS+2
    sta SPPARAMS+3
    txa
    and #$70
    beq PRODOSLIST_Unit
    lsr a
    lsr a
    lsr a
    lsr a
    ora #$C0
    sta SPUNIT
    lda #0
    cpy SPUNIT
    beq PRODOSLIST_Drive
    lda #$C0
    eor SPUNIT
    cmp #2
    beq PRODOSLIST_Drive
    lda #4
PRODOSLIST_Drive:
    cpx #$80
    adc #1
PRODOSLIST_Unit:
    sta SPUNIT
    rts

;; Asks the card for its diagnostics, finding the slot from the caller's return address.
;; Out:   A = 0, MSLOT = $Cn
ASKDIAG:
    tsx
    lda $0102,x
    sta MSLOT
    tay
    ldx SLOT16TABLE-$C1,y
    lda LCRAM2+BANKMAILBOX,x
ASKDIAG_Wait:
    bit MBSTATE
    bpl ASKDIAG_Wait
    lda #CMDDIAGNOSTICS
    sta MBSTATE
    lda #0
    rts

;; The boot failed: goes on to the next slot when the Monitor's scan brought it here, else says why and starts BASIC.
;; In:    SPRESULT = NEVERREADY when the card did not answer
NOBOOT:
    bit LCROM
    lda LOC0
    bne NOBOOT_Say
    lda LOC1
    cmp MSLOT
    bne NOBOOT_Say
    jmp SLOOP
NOBOOT_Say:
    jsr SETVID
    jsr SETKBD
    jsr SETTXT
    jsr HOME
    ldy #0
    lda SPRESULT
    cmp #NEVERREADY
    bne NOBOOT_Print
    ldy #NEVERREADYTEXT-NOBOOTTEXT
NOBOOT_Print:
    ldx #0
NOBOOT_Next:
    lda NOBOOTTEXT,y
    beq NOBOOT_Done
    sta $0488,x                     ; the text screen's line 9, column 8
    iny
    inx
    bne NOBOOT_Next                 ; always
NOBOOT_Done:
    jmp BASIC

NOBOOTTEXT:
    .hiascii "UNABLE TO BOOT"
    .byte 0
NEVERREADYTEXT:
    .hiascii "CONTROLLER NEVER READY"
    .byte 0

;; Runs the unit's hook in the card's RAM at $CB80, $CBA0, $CBC0 or $CBE0 with bank 2 latched, for units 1 to 4. The
;; card puts an RTS in each.
;; In:    X = the slot times 16
;; Keeps: X, Y
UNITHOOK:
    lda SPUNIT
    beq UNITHOOK_Done
    cmp #5
    bcs UNITHOOK_Done
    tya
    pha
    txa
    pha
    lda LCRAM2+BANKSAVE,x
    jsr UNITHOOK_Go
    pla
    tax
    lda LCRAM2+BANKMAILBOX,x
    pla
    tay
UNITHOOK_Done:
    rts
UNITHOOK_Go:
    lda #>$CB80
    pha
    ldx SPUNIT
    lda UNITHOOKS-1,x
    pha
    rts
UNITHOOKS:
    .byte <($CB80-1), <($CBA0-1), <($CBC0-1), <($CBE0-1)

;; Marks a call as running, or refuses a second one while the first runs. A boot, or a call before the host is
;; identified, clears the mark instead.
;; In:    overflow = set for a boot, bank 2 latched
;; Out:   A = 1 and carry = set, returned from the call itself, for a second call
ENTER:
    bvs ENTER_Clear
    bit HOSTTYPE
    bpl ENTER_Mark
ENTER_Clear:
    lda #0
    sta CALLBUSY
    rts
ENTER_Mark:
    bit CALLBUSY
    bmi ENTER_Busy
    lda #$80
    sta CALLBUSY
    rts
ENTER_Busy:
    pla
    pla
    lda #1
    plp
    sec
    rts

    .res 7
.assert * == $CFFF
    .byte 0
.logicalorg
