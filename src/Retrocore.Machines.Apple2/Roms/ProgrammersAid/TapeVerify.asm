;; PROGRAMMER'S AID #1: TAPE VERIFY ($D52E-$D5AF)
;;
;; Steve Wozniak's tape verify (1978): it reads a recording back and compares it with memory, without loading it, so a
;; SAVE can be checked while the program is still there. CALL -10955 (<TapeVerify::VFYBSC>) checks an Integer BASIC
;; program against the one in memory; for machine code or data, D52EG sets the Monitor's Ctrl-Y up
;; (<TapeVerify::TVSETUP>), and `begin.end` Ctrl-Y checks that block against the tape. A difference prints ERR, the
;; address, and the byte in memory and then the byte from tape in parentheses; a bad checksum beeps and prints ERR, as
;; LOAD does.
;;
;; Names follow Apple's listing in the Programmer's Aid #1 manual (1978,
;; https://archive.org/details/programmers-aid-1). Part of ProgrammersAid.asm.

.scope TapeVerify

;; The running checksum of the bytes read, as the Monitor's tape READ keeps it.
CHKSUM = $2E

;; Inherit: <Monitor:A1L>
A1 = $3C

;; Inherit: <IntegerBasic:HIMEM>
HIMEM = $4C

;; Inherit: <IntegerBasic:PP>
PP = $CA

;; The program's length (2 bytes), HIMEM - PP, which the tape's header holds.
PRLEN = $CE

;; Where <VFYBSC> keeps X, which BASIC needs back.
XSAVE = $D8

;; Integer BASIC's tape setup for the header: points A1 and A2 at <PRLEN>.
HDRSET = $F11E

;; Integer BASIC's tape setup for the program: points A1 and A2 at PP and HIMEM.
PRGSET = $F12C

;; Inherit: <Monitor:NXTA1>
NXTA1 = $FCBA

;; Inherit: <Monitor:HEADR>
HEADR = $FCC9

;; The Monitor's tape routine that reads a byte.
RDBYTE = $FCEC

;; The Monitor's tape routine that waits for two edges of the signal.
RD2BIT = $FCFA

;; The Monitor's tape routine that reads a bit, into the carry.
RDBIT = $FCFD

;; Inherit: <Monitor:PRA1>
PRA1 = $FD92

;; Inherit: <Monitor:PRBYTE>
PRBYTE = $FDDA

;; Inherit: <Monitor:COUT>
COUT = $FDED

;; The end of the Monitor's tape READ: checks the checksum, and beeps, with ERR if it is wrong.
FINISH = $FF26

;; Inherit: <Monitor:PRERR>
PRERR = $FF2D

;; D52EG: points the Monitor's Ctrl-Y command at <TAPEVFY>.
TVSETUP:
    lda #<TAPEVFY                   ; $D52E
    ldy #>TAPEVFY                   ; $D530
    jmp SETCTLY                     ; $D532

;; CALL -10955: checks the Integer BASIC program in memory against the one on tape, header first.
VFYBSC:
    stx XSAVE                       ; $D535
    sec                             ; $D537
    ldx #$FF                        ; $D538

GETLEN:
    lda HIMEM+1,x                   ; $D53A PRLEN = HIMEM - PP
    sbc PP+1,x                      ; $D53C
    sta PRLEN+1,x                   ; $D53E
    inx                             ; $D540
    beq GETLEN                      ; $D541
    jsr HDRSET                      ; $D543
    jsr TAPEVFY                     ; $D546 the header
    ldx #$01                        ; $D549
    jsr PRGSET                      ; $D54B
    jsr TAPEVFY                     ; $D54E the program
    ldx XSAVE                       ; $D551
    rts                             ; $D553

;; Checks memory from A1 to A2 against the tape: the Monitor's tape READ, comparing instead of storing.
TAPEVFY:
    jsr RD2BIT                      ; $D554
    lda #$16                        ; $D557
    jsr HEADR                       ; $D559 find the header tone
    sta CHKSUM                      ; $D55C
    jsr RD2BIT                      ; $D55E

VRFY2:
    ldy #$24                        ; $D561
    jsr RDBIT                       ; $D563
    bcs VRFY2                       ; $D566
    jsr RDBIT                       ; $D568
    ldy #$3B                        ; $D56B

VRFY3:
    jsr RDBYTE                      ; $D56D
    beq EXTDEL                      ; $D570 always

VFYLOOP:
    eor CHKSUM                      ; $D572
    sta CHKSUM                      ; $D574
    jsr NXTA1                       ; $D576
    ldy #$34                        ; $D579
    bcc VRFY3                       ; $D57B until past A2
    jmp FINISH                      ; $D57D

EXTDEL:
    nop                             ; $D580 as long as READ takes to store a byte
    nop                             ; $D581
    nop                             ; $D582
    cmp (A1,x)                      ; $D583
    beq VFYLOOP                     ; $D585
    pha                             ; $D587 a difference: "ERR", then "addr- mem (tape)"
    jsr PRERR                       ; $D588
    jsr PRA1                        ; $D58B
    lda (A1),y                      ; $D58E
    jsr PRBYTE                      ; $D590
    lda #$A0                        ; $D593 " "
    jsr COUT                        ; $D595
    lda #$A8                        ; $D598 "("
    jsr COUT                        ; $D59A
    pla                             ; $D59D
    jsr PRBYTE                      ; $D59E
    lda #$A9                        ; $D5A1 ")"
    jsr COUT                        ; $D5A3
    lda #$8D                        ; $D5A6 return
    jmp COUT                        ; $D5A8

; A second copy of the last two instructions, which nothing reaches.
    lda #$8D                        ; $D5AB
    jmp COUT                        ; $D5AD

.endscope
