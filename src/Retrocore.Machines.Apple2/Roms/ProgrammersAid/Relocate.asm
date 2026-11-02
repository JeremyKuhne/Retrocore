;; PROGRAMMER'S AID #1: RELOCATE ($D4D5-$D52D)
;;
;; Steve Wozniak's relocation of 6502 code (1977): it copies a program to another address and adjusts the absolute
;; addresses in its instructions that point into the program, so the copy runs where it lands. It works through the
;; Monitor's Ctrl-Y command, after D4D5G sets Ctrl-Y up (<Relocate::RELSETUP>):
;;
;; 1. `dest<begin.end` Ctrl-Y defines the blocks: the program's source block and where its copy will run.
;; 2. `dest<begin.end` Ctrl-Y relocates a segment of code; `dest<begin.end` M (the Monitor's Move) copies a segment
;;    of data unchanged.
;; 3. `.end` Ctrl-Y or `.end` M continues with the next segment.
;;
;; An instruction's address is adjusted when it falls in the source block: it moves by the same distance as the
;; block. Names follow Apple's listing in the Programmer's Aid #1 manual (1978,
;; https://archive.org/details/programmers-aid-1). Part of ProgrammersAid.asm.

.scope Relocate

;; SWEET16's R1, low byte: the start of the source block once the blocks are defined.
R1L = $02

;; Where the instruction being relocated is copied (3 bytes), for SWEET16 to adjust its address.
INST = $0B

;; Inherit: <Monitor:LENGTH>
LENGTH = $2F

;; Inherit: <Monitor:YSAV>
YSAV = $34

;; Inherit: <Monitor:A1L>
A1L = $3C

;; Inherit: <Monitor:A4L>
A4L = $42

;; Inherit: <Monitor:IN>
IN = $0200

;; Inherit: <IntegerBasic:SW16>
SW16 = $F689

;; Inherit: <Monitor:INSDS2>
INSDS2 = $F88E

;; Inherit: <Monitor:NXTA4>
NXTA4 = $FCB4

FRMBEG = $01                        ;; SWEET16's R1: the source block's start
FRMEND = $02                        ;; R2: the source block's end
TOBEG = $04                         ;; R4: the destination block's start
ADR = $06                           ;; R6: the address part of the instruction, from INST+1

;; D4D5G: points the Monitor's Ctrl-Y command at <RELOC>.
RELSETUP:
    lda #<RELOC                     ; $D4D5
    ldy #>RELOC                     ; $D4D7
    jmp SETCTLY                     ; $D4D9

;; The Ctrl-Y command: defines the blocks when the command line ends `*`, else relocates the segment from A1 to A2
;; into A4.
RELOC:
    ldy YSAV                        ; $D4DC
    lda IN,y                        ; $D4DE
    cmp #$AA                        ; $D4E1 "*"
    bne RELOC2                      ; $D4E3
    inc YSAV                        ; $D4E5
    ldx #$07                        ; $D4E7

INIT:
    lda A1L,x                       ; $D4E9 copy A1, A2 and A4 to SWEET16's R1 to R4
    sta R1L,x                       ; $D4EB
    dex                             ; $D4ED
    bpl INIT                        ; $D4EE
    rts                             ; $D4F0

RELOC2:
    ldy #$02                        ; $D4F1

GETINS:
    lda (A1L),y                     ; $D4F3 the next instruction, to INST
    sta INST,y                      ; $D4F5
    dey                             ; $D4F8
    bpl GETINS                      ; $D4F9
    jsr INSDS2                      ; $D4FB its length
    ldx LENGTH                      ; $D4FE
    dex                             ; $D500
    bne XLATE                       ; $D501 3 bytes
    lda INST                        ; $D503
    and #$0D                        ; $D505
    beq STINST                      ; $D507 an immediate operand
    and #$08                        ; $D509
    bne STINST                      ; $D50B
    sta INST+2                      ; $D50D a zero-page address: treat it as $00xx

XLATE:
    jsr SW16                        ; $D50F
    LD FRMEND                       ; $D512
    CPR ADR                         ; $D513
    BNC SW16RT                      ; $D514 past the source block
    LD ADR                          ; $D516
    SUB FRMBEG                      ; $D517
    BNC SW16RT                      ; $D518 before it
    ADD TOBEG                       ; $D51A move it with the block
    ST ADR                          ; $D51B

SW16RT:
    RTN                             ; $D51C

STINST:
    ldx #$00                        ; $D51D

STINS2:
    lda INST,x                      ; $D51F copy the instruction to A4
    sta (A4L),y                     ; $D521
    inx                             ; $D523
    jsr NXTA4                       ; $D524
    dec LENGTH                      ; $D527
    bpl STINS2                      ; $D529
    bcc RELOC2                      ; $D52B until past A2
    rts                             ; $D52D

.endscope
