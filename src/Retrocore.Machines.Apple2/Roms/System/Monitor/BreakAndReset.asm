.if MONITOR = MONITOR_II
    .byte $FF, $FF, $FF             ; $FA40 unused

;; Runs one instruction of the program at PCL/PCH for the S and T commands, then shows the registers.
;;
;; Apple II Monitor only. It disassembles the instruction (<INSTDSP>) and runs it with the program's
;; registers from <A5H>, <XREG>, <YREG> and <STATUS>. Most instructions are copied to <XQT> and run
;; there, followed by NOPs and a jump to <NBRNCH>, which saves the registers again and moves PCL/PCH past
;; the instruction. A relative branch is copied with a displacement of 4, so that when it is taken it
;; lands on the jump to <BRANCH> instead, which applies the real displacement. JSR, RTS, JMP, JMP
;; indirect and RTI would leave the copy, so they are simulated (<XJSR>, <XRTS>, <XJMP>, <XJMPAT>,
;; <XRTI>), and BRK stops in <XBRK>. Every other way ends at <RTNJMP>, which shows the registers.
;;
;; The command line called it through <TOSUB>; its return address is moved to <RTNL>/<RTNH> while the
;; instruction runs, so the instruction sees the program's stack.
;; In: PCL/PCH = the instruction to run
;; Out: PCL/PCH = the next instruction to run
;; See: <STEPZ>, <TRACE>, <INITBL>
STEP:
    jsr INSTDSP                     ; $FA43 sets LENGTH
    pla                             ; $FA46
    sta RTNL                        ; $FA47
    pla                             ; $FA49
    sta RTNH                        ; $FA4A
    ldx #$08                        ; $FA4C

XQINIT:
    lda INITBL-1,x                  ; $FA4E fills XQT+1 to XQT+8 with NOPs and the two jumps
    sta XQT,x                       ; $FA51
    dex                             ; $FA53
    bne XQINIT                      ; $FA54
    lda (PCL,x)                     ; $FA56 the opcode
    beq XBRK                        ; $FA58
    ldy LENGTH                      ; $FA5A
    cmp #$20                        ; $FA5C JSR
    beq XJSR                        ; $FA5E
    cmp #$60                        ; $FA60 RTS (equal, so carry is set)
    beq XRTS                        ; $FA62
    cmp #$4C                        ; $FA64 JMP
    beq XJMP                        ; $FA66
    cmp #$6C                        ; $FA68 JMP indirect (carry set)
    beq XJMPAT                      ; $FA6A
    cmp #$40                        ; $FA6C RTI
    beq XRTI                        ; $FA6E
    and #$1F                        ; $FA70
    eor #$14                        ; $FA72 only a branch, %xxx10000, gives 4
    cmp #$04                        ; $FA74
    beq XQ2                         ; $FA76 a branch's displacement becomes 4

XQ1:
    lda (PCL),y                     ; $FA78

XQ2:
    sta XQT,y                       ; $FA7A
    dey                             ; $FA7D
    bpl XQ1                         ; $FA7E
    jsr RESTORE                     ; $FA80
    jmp XQT                         ; $FA83 returns through NBRNCH or BRANCH
.endif

;; IRQ and BRK entry (the 6502's $FFFE vector points here on the original IIe).
;; Saves A in A5H.
;; Original IIe: looks at the pushed status; BRK goes to BREAK, other interrupts to the user's handler
;; through IRQLOC ($03FE).
;; Enhanced IIe: the vector points to the firmware at $C3FA instead; this entry passes A to it.
;;
;; The Apple II's two Monitors work as the original IIe's; the Apple II Monitor's is at $FA86.
IRQ:
    sta A5H                         ; $FA40 1978 $FA86
.if ENHANCED
    lda A5H                         ; $FA42
    jmp IRQHANDLER                  ; $FA44
.else
    pla                             ; $FA42
    pha                             ; $FA43
    asl a                           ; $FA44
    asl a                           ; $FA45
    asl a                           ; $FA46
.endif

IRQ_1:
.if ENHANCED
    sta SETSLOTCXROM                ; $FA47
    sta A5H                         ; $FA4A
.else
    bmi BREAK                       ; $FA47
    jmp (IRQLOC)                    ; $FA49
.endif

;; Handles BRK: saves A, X, Y, P and S (SAVE), sets PCL/PCH from the return address on the stack,
;; then jumps through BRKV ($03F0), normally OLDBRK.
;;
;; The Apple II Monitor has no BRKV: it continues in <XBRK>, which does what OLDBRK does.
BREAK:
    plp                             ; $FA4C 1978 $FA92
    jsr SAV1                        ; $FA4D
    pla                             ; $FA50
    sta PCL                         ; $FA51
    pla                             ; $FA53
    sta PCH                         ; $FA54
.if MONITOR = MONITOR_II

;; Apple II Monitor: shows the instruction at PC and the registers, and enters the Monitor.
;;
;; <BREAK> continues here after a BRK, and <STEP> comes here when the instruction to run is a BRK.
;; Later Monitors call this code OLDBRK and reach it through the vector BRKV.
XBRK:
.else
    jmp (BRKV)                      ; $FA56

;; The default BRK handler: disassembles the instruction at PC, shows the registers, and enters the
;; Monitor.
OLDBRK:
.endif
    jsr INSDS1                      ; $FA59 1978 $FA9C
    jsr RGDSP1                      ; $FA5C
    jmp MON                         ; $FA5F
.if MONITOR = MONITOR_II

;; Apple II Monitor: simulates RTI for <STEP>: pulls the status, then the return address (<XRTS>).
;;
;; The carry is cleared so the address is used as it is, where RTS adds one.
XRTI:
    clc                             ; $FAA5
    pla                             ; $FAA6
    sta STATUS                      ; $FAA7

;; Apple II Monitor: simulates RTS for <STEP>: pulls the return address into PCL/PCH and adds one.
;;
;; <STEP> enters with the carry set from its compare, which adds the one; <XRTI> enters with it clear.
;; Entry: PCINC2 = with A the new PCH, PCINC3 = adds LENGTH and the carry to PCL/PCH
XRTS:
    pla                             ; $FAA9
    sta PCL                         ; $FAAA
    pla                             ; $FAAC

PCINC2:
    sta PCH                         ; $FAAD

PCINC3:
    lda LENGTH                      ; $FAAF
    jsr PCADJ3                      ; $FAB1 adds LENGTH and the carry to PCL/PCH
    sty PCH                         ; $FAB4
    clc                             ; $FAB6
    bcc NEWPCL                      ; $FAB7

;; Apple II Monitor: simulates JSR for <STEP>: pushes the address of the JSR's last byte, as JSR does,
;; then jumps to its target (<XJMP>).
XJSR:
    clc                             ; $FAB9
    jsr PCADJ2                      ; $FABA PC + LENGTH, the JSR's last byte
    tax                             ; $FABD
    tya                             ; $FABE
    pha                             ; $FABF
    txa                             ; $FAC0
    pha                             ; $FAC1
    ldy #$02                        ; $FAC2

;; Apple II Monitor: simulates JMP for <STEP>: loads PCL/PCH from the instruction's operand.
;;
;; JMP indirect enters at XJMPAT with the carry set: the first pass loads the pointer into PCL/PCH,
;; and the second, from <NEWPCL>, loads the address it points to.
;; Entry: XJMPAT = keeps the carry, NEWPCL = with A the new PCL
XJMP:
    clc                             ; $FAC4

XJMPAT:
    lda (PCL),y                     ; $FAC5 the high byte (Y = 2, then 1)
    tax                             ; $FAC7
    dey                             ; $FAC8
    lda (PCL),y                     ; $FAC9
    stx PCH                         ; $FACB

NEWPCL:
    sta PCL                         ; $FACD
    bcs XJMP                        ; $FACF

;; Apple II Monitor: ends <STEP>: pushes back the command line's return address, then shows the
;; registers (<REGDSP>) and returns to the command line.
RTNJMP:
    lda RTNH                        ; $FAD1
    pha                             ; $FAD3
    lda RTNL                        ; $FAD4
    pha                             ; $FAD6
.else

;; The reset handler (RESETVEC).
;; Restores normal video, text mode, a full window and the screen and keyboard hooks, turns
;; annunciators 0 and 1 off, lets the internal firmware reset its state, releases any $C800 ROM and
;; clears the keyboard strobe, then beeps.
;; When PWREDUP shows the reset vector (SOFTEV) was set by a program, jumps through SOFTEV; the first
;; time SOFTEV holds BASIC's cold start ($E000) it is changed to $E003 so later resets warm-start
;; AppleSoft. Otherwise this is a power-up (PWRUP).
;;
;; The Autostart Monitor reads CLRAN2 and CLRAN3 in place of the firmware call, as the IIe has no
;; internal firmware to reset. The Apple II Monitor has no RESET: its reset vector points at OLDRST.
RESET:
    cld                             ; $FA62
    jsr SETNORM                     ; $FA63
    jsr INIT                        ; $FA66
    jsr SETVID                      ; $FA69
    jsr SETKBD                      ; $FA6C

INITAN:
    lda CLRAN0                      ; $FA6F
    lda CLRAN1                      ; $FA72
.if MONITOR = MONITOR_AUTOSTART
    lda CLRAN2                      ; $FA75
    lda CLRAN3                      ; $FA78
.else
.if ENHANCED
    ldy #$09                        ; $FA75 firmware function: 5 on the original IIe, 9 on the Enhanced IIe
.else
    ldy #$05                        ; $FA75 firmware function: 5 on the original IIe, 9 on the Enhanced IIe
.endif
    jsr GOTOCX                      ; $FA77
    nop                             ; $FA7A
.endif
    lda CLRROM                      ; $FA7B
    bit KBDSTRB                     ; $FA7E

NEWMON:
    cld                             ; $FA81
    jsr BELL                        ; $FA82
    lda SOFTEV+1                    ; $FA85
    eor #$A5                        ; $FA88
    cmp PWREDUP                     ; $FA8A PWREDUP must equal SOFTEV's high byte EOR $A5
    bne PWRUP                       ; $FA8D
    lda SOFTEV                      ; $FA8F
    bne NOFIX                       ; $FA92
    lda #$E0                        ; $FA94
    cmp SOFTEV+1                    ; $FA96
    bne NOFIX                       ; $FA99

FIXSEV:
    ldy #$03                        ; $FA9B
    sty SOFTEV                      ; $FA9D
    jmp BASIC                       ; $FAA0

;; Warm reset: continues at the program's reset vector, SOFTEV ($03F2).
NOFIX:
    jmp (SOFTEV)                    ; $FAA3

;; Power-up: shows the title, sets BRKV, SOFTEV and PWREDUP to their defaults, then looks for a
;; bootable disk controller from slot 7 down to slot 1 by its signature bytes, and starts the first
;; one found at $Cn00. With none, starts AppleSoft (BASIC).
PWRUP:
    jsr APPLEII                     ; $FAA6

SETPG3:
    ldx #$05                        ; $FAA9

SETPLP:
    lda PWRCON-1,x                  ; $FAAB
    sta BRKV-1,x                    ; $FAAE
    dex                             ; $FAB1
    bne SETPLP                      ; $FAB2
    lda #$C8                        ; $FAB4
    stx LOC0                        ; $FAB6
    sta LOC1                        ; $FAB8

SLOOP:
.if ENHANCED
    ldy #$05                        ; $FABA
.else
    ldy #$07                        ; $FABA
.endif
    dec LOC1                        ; $FABC
    lda LOC1                        ; $FABE
    cmp #$C0                        ; $FAC0
    beq FIXSEV                      ; $FAC2
    sta MSLOT                       ; $FAC4

NXTBYT:
    lda (LOC0),y                    ; $FAC7
    cmp DISKID-1,y                  ; $FAC9
    bne SLOOP                       ; $FACC
    dey                             ; $FACE
    dey                             ; $FACF
    bpl NXTBYT                      ; $FAD0
    jmp (LOC0)                      ; $FAD2
.if ENHANCED
    .byte $00, $00                  ; $FAD5
.else
    .byte $EA, $EA                  ; $FAD5
.endif
.endif
