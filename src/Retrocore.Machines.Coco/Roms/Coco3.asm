;; TRS-80 COLOR COMPUTER 3: START-UP AND SUPER EXTENDED COLOR BASIC ($C000-$FFFF)
;;
;; The upper half of the CoCo 3's 32K ROM. Its lower half is Extended Color BASIC 1.1 and Color BASIC 1.2 with the
;; CoCo 3's patches, which ExtendedBasic.asm and ColorBasic.asm build when COCO3 is set; this source is the rest.
;;
;; RESET goes to <INTRESET>, in the patched Extended BASIC, which maps the whole ROM in and comes to <COCO3RESET>.
;; That sets the GIME up and copies <STARTUP> into RAM at $4000, out of the way, to run there. <STARTUP> copies
;; Extended and Color BASIC, a Disk BASIC ROM when one is in the cartridge port, and $E000-$FDFF from ROM into the
;; RAM under them, patches the copies (<PATCHTAB>, <DSKPATCH>), and switches the ROM out: from then on BASIC runs
;; in RAM, so the patches hold. Holding ALT and CTRL at RESET shows the authors' picture (<AUTHSHOW>) instead.
;;
;; Super Extended Color BASIC, from $E000, adds the GIME's graphics and 40 and 80-column text to Extended BASIC:
;; HSCREEN, HCLS, HCOLOR, HSET, HRESET, HPOINT, HLINE, HCIRCLE, HPAINT, HDRAW, HGET, HPUT, HPRINT and HBUFF;
;; WIDTH, LOCATE, ATTR, HSTAT and PALETTE; LPEEK and LPOKE for the 512K of RAM the MMU reaches; ON ERR and ON BRK,
;; with ERNO, ERLIN and BUTTON. Its words join BASIC through the patched crunch and command loops (<CRUNCH20>,
;; <XCOMMAND20>). The hi-res screens live in blocks the MMU maps in only while a command draws: graphics at
;; $2000-$9FFF in task 1, through <SELTASK1>, and text at $2000-$3FFF, through <SELTEXT>.
;;
;; Labels follow the names Spectral Associates' Super Extended Basic Unravelled uses where they have them, such
;; as <PATCHTAB>, <HSCREEN> and <SELTASK1>, and the GIME's registers' names. The comments are our own.
;;
;; Maintained by hand. CocoRomSourceTests check that it assembles byte-identically to the ROM, with the patched
;; Color and Extended BASIC below it.

.cpu M6809

.include "ColorBasicEquates.asm"
.include "ColorBasicEntries.asm"
.include "ExtendedBasicEquates.asm"
.include "ExtendedBasicEntries.asm"
.include "Coco3Equates.asm"

;; Starts a patch in <PATCHTAB>: where it goes and how many bytes it has, then its code, assembled for where it
;; runs. <ENDPATCH> ends it.
.macro PATCH target, length
    .dbyt target
    .byte length
    .logicalorg target
.endmacro

;; Ends a patch that <PATCH> began: back to <STARTUP>'s addresses in RAM.
.macro ENDPATCH
    .logicalorg
    .logicalorg STARTUP + * - BEGMOVE
.endmacro

.org $C000

; ----------------------------------------------------------------------------------------------------------------
; Start-up: runs from ROM, then from RAM at $4000
; ----------------------------------------------------------------------------------------------------------------

;; Starts the CoCo 3 after RESET, from the ROM that <INTRESET> mapped in: blanks the screen by setting every
;; palette register to one color, maps the MMU's blocks from <MMUIMAGE>, and copies <STARTUP> to RAM at $4000 to
;; run there, since copying BASIC to RAM switches this ROM out.
COCO3RESET:
    ORCC #$50
    LDS #$5EFF                      ; the stack in block $34, which task 0 maps at $4000
    LDA #$12                        ; every color the same: nothing shows while the screen is set up
    LDB #16
    LDX #PALETREG
COCO3RESET_PALETTE:
    STA ,X+
    DECB
    BNE COCO3RESET_PALETTE
    LDX #MMUREG
    LEAY >MMUIMAGE-STARTUP+BEGMOVE,PCR ; the images, in ROM
    LDB #16
COCO3RESET_MMU:
    LDA ,Y+
    STA ,X+
    DECB
    BNE COCO3RESET_MMU
    LDA #COCO+MMUEN+MC3+MC2+MC1     ; CoCo compatible, the MMU on, constant page, standard SCS, 32K ROM
    STA INIT0
    LEAX >BEGMOVE,PCR
    LDY #STARTUP
COCO3RESET_COPY:
    LDD ,X++                        ; four bytes at a time
    LDU ,X++
    STD ,Y++
    STU ,Y++
    CMPX #ENDMOVE                   ; past the end of what runs in RAM?
    BCS COCO3RESET_COPY
    JMP STARTUP
BEGMOVE:
    .logicalorg $4000

;; Sets the hardware up, copies BASIC from ROM into the RAM under it and patches it, then starts Color BASIC at its
;; reset, <RESVEC>, which warm or cold starts it. Runs in RAM at $4000, where <COCO3RESET> copied it.
;;
;; The video registers come from <VIDIMAGE>, the PIAs and the SAM are set as Color BASIC sets them, and F1 held down
;; picks the alternate color set. ALT and CTRL held down show the authors' picture (<AUTHSHOW>) instead.
;;
;; BASIC is copied again unless the constant page's interrupt jumps are set up (<INT_FLAG>) and BASIC's warm start
;; is good, as <WARMCK> checks it, in the RAM BASIC used or in block $30, where a program may have moved the direct
;; page. The copy goes through <ROMTORAM>, Extended and Color BASIC first, then a Disk BASIC ROM if the cartridge
;; has one, then $E000-$FDFF; then <PATCHTAB>'s patches go in, <DSKPATCH> patches Disk BASIC, <AUTHNAMES> decodes
;; the authors' names, and <INTIMAGE> sets up the interrupt jumps.
STARTUP:
    LEAS -1,S                       ; a byte on the stack for the F1 key
    NOP                             ; nothing: room the code never used
    NOP
    NOP
    NOP
    NOP
    LDA #$FF                        ; the GIME's timer: $FFFF, counting
    STA V_TIMER
    STA V_TIMER+1
    LEAX >VIDIMAGE,PCR
    LDY #VIDEOREG
STARTUP_VIDEO:
    LDA ,X+
    STA ,Y+
    CMPY #MMUREG                    ; to $FF9F
    BNE STARTUP_VIDEO
    LDX #PIA1
    LDD #$FF34                      ; the PIAs as <INITHW> sets them
    CLR 1,X
    CLR 3,X
    DECA
    STA ,X
    LDA #$F8
    STA 2,X
    STB 1,X
    STB 3,X
    CLR 2,X                         ; the VDG's text mode
    LDA #$02
    STA ,X                          ; serial output marking
    LDA #$FF
    LDX #PIA0
    CLR 1,X
    CLR 3,X
    CLR ,X
    STA 2,X
    STB 1,X
    STB 3,X
    LDB #12                         ; the SAM's first twelve bits: the VDG's mode and the display's offset
    LDU #SAMREG
STARTUP_SAM:
    STA ,U++
    DECB
    BNE STARTUP_SAM
    STA SAMREG+9                    ; the text screen at $0400
    TFR B,DP                        ; B = 0: the direct page at $0000
    CLR 2,X
    STA -3,U                        ; the SAM's page bit, which the CoCo 3 ignores
    LDX #PIA0
    LDB #$DF                        ; column 2 strobed: F1 in row 6
    STB 2,X
    LDA ,X
    COMA
    ANDA #$40                       ; F1 down?
    STA ,S
    LDY #2                          ; two keys: CTRL, in the next column, then ALT
STARTUP_KEYS:
    ASRB                            ; the next column
    STB 2,X
    LDA ,X
    COMA
    ANDA #$40
    BEQ STARTUP_CHECK
    LEAY -1,Y                       ; the next key
    BNE STARTUP_KEYS
    LBRA AUTHSHOW                   ; both down: show the picture
STARTUP_CHECK:
    LDA #COCO+MMUEN+MC3+MC1         ; no standard SCS: a disk controller cannot answer while BASIC is copied
    STA INIT0
    LDA INT_FLAG                    ; the interrupt jumps set up?
    CMPA #$55
    BNE STARTUP_COPY
    LDA RSTFLG                      ; BASIC's warm start set up?
    CMPA #$55
    BNE STARTUP_BLOCK0
    LDX RSTVEC
    LDA ,X
    CMPA #$12                       ; does it begin with NOP?
    LBEQ STARTUP_WARM               ; then BASIC is intact: nothing to copy
STARTUP_BLOCK0:
    CLR MMUREG                      ; block $30 at $0000: a program may have moved BASIC's RAM there
    LDA RSTFLG
    CMPA #$55
    BNE STARTUP_BLOCK7
    LDX RSTVEC
    LDA ,X
    CMPA #$12                       ; its warm start good?
    LBEQ STARTUP_WARM
STARTUP_BLOCK7:
    LDA #BLOCK7_0                   ; BASIC's own block back at $0000
    STA MMUREG
STARTUP_COPY:
    LDX #ROMPAK                     ; Extended and Color BASIC, $8000-$BFFF
    LDY #EXBAS
    LBSR ROMTORAM
    LEAY >PATCHTAB,PCR
    LDA ,Y+
STARTUP_PATCH:
    PSHS A
    LDX ,Y++                        ; where it goes
    LDB ,Y+                         ; its length
STARTUP_PATCHBYTE:
    LDA ,Y+
    STA ,X+
    DECB
    BNE STARTUP_PATCHBYTE
    PULS A
    DECA
    BNE STARTUP_PATCH
    CLR SAMREG+30                   ; the ROM in again
    LDA #COCO+MMUEN+MC3             ; 16K of internal ROM and 16K from the cartridge
    STA INIT0
    LDD ROMPAK                      ; a Disk BASIC ROM begins with DK
    CMPA #'D'
    BNE STARTUP_SUPER
    CMPB #'K'
    BNE STARTUP_SUPER
    LDX #SUPERVAR
    LDY #ROMPAK
    BSR ROMTORAM
    LBSR DSKPATCH
STARTUP_SUPER:
    CLR SAMREG+30
    LDA #COCO+MMUEN+MC3+MC1         ; 32K of internal ROM again
    STA INIT0
    LDX #H_CRSLOC                   ; Super Extended BASIC, $E000-$FDFF
    LDY #SUPERVAR
    BSR ROMTORAM
    LBSR AUTHNAMES
    LEAY >INTIMAGE,PCR
    LDX #INT_FLAG                   ; the jumps go to $FEED, with their valid flag
    LDB #19                         ; the flag and six jumps
    LBSR MOVEXY
    CLR SAMREG+31                   ; the ROM out: BASIC runs in RAM from now on
    TST ,S                          ; F1 held down?
    BEQ STARTUP_CLEAR
    LDX #IM_TEXT                    ; the alternate color set in the video images Super Extended BASIC keeps
    LDB #$03                        ; three text modes
    LEAX 1,X                        ; past the first image's INIT0
STARTUP_ALTTEXT:
    LDA ,X
    ORA #$20                        ; the alternate color set
    STA ,X
    LEAX 9,X                        ; the next image
    DECB
    BNE STARTUP_ALTTEXT
    LDB #$02                        ; two graphics modes
    LDX #IM_GRAPH
STARTUP_ALTGRAPH:
    LDA ,X
    ORA #$20
    STA ,X
    LEAX 9,X
    DECB
    BNE STARTUP_ALTGRAPH
STARTUP_CLEAR:
    LDX #VIDRAM                     ; a fresh copy: clear the text screen
    LDA #$60
STARTUP_CLEARLOOP:
    STA ,X+
    CMPX #VIDRAM+512
    BCS STARTUP_CLEARLOOP
STARTUP_WARM:
    LDA #COCO+MMUEN+MC3+MC2+MC1     ; the standard SCS again: the disk controller can answer
    STA INIT0
    TST ,S                          ; F1 held down?
    BEQ STARTUP_PALETTE
    LDA #$20                        ; the alternate color set
    STA VIDEOREG
STARTUP_PALETTE:
    LDX #PALETREG
    LEAY >PALIMAGE,PCR
    LDB #16
    BSR MOVEXY
    LEAS 1,S                        ; drop the F1 flag
    JMP RESVEC                      ; Color BASIC's reset, which warm or cold starts BASIC

;; Copies ROM into the RAM under it, eight bytes at a time: each is read with the ROM switched in and written with
;; it switched out, through D, X, U and S, so the stack pointer is kept aside meanwhile.
;;
;; In:   Y = the first address, X = the end, plus one
ROMTORAM:
    STX COPYEND                     ; the end
    STS COPYSTK                     ; the stack, which the copy borrows
ROMTORAM_LOOP:
    CLR SAMREG+30                   ; the ROM in
    LDD ,Y
    LDX 2,Y
    LDU 4,Y
    LDS 6,Y
    CLR SAMREG+31                   ; the RAM in
    STD ,Y                          ; the same bytes into the RAM
    STX 2,Y
    STU 4,Y
    STS 6,Y
    LEAY 8,Y                        ; the next eight
    CMPY COPYEND
    BCS ROMTORAM_LOOP
    LDS COPYSTK
    RTS

;; Copies bytes from Y to X.
;;
;; In:   B = the count, X = where to, Y = where from
;; Out:  X = past the bytes written, Y = past the bytes read
MOVEXY:
    LDA ,Y+
    STA ,X+
    DECB
    BNE MOVEXY
    RTS

;; Decodes the authors' names from <AUTHCODED> into <AUTHORMS>, where the copy of Super Extended BASIC in RAM shows
;; them with the picture.
AUTHNAMES:
    LDX #AUTHORMS
    LEAY >AUTHCODED,PCR
    LDB #21
AUTHNAMES_LOOP:
    LDA ,Y+
    COMA                            ; each byte is stored complemented
    STA ,X+
    DECB
    BNE AUTHNAMES_LOOP
    RTS

;; Shows the authors' picture: copies <AUTHPIC> to RAM at $0E00 and shows it as the VDG's 256x192 two-color graphics,
;; white on black, then waits forever. RESET then copies BASIC afresh, since the interrupt jumps' flag and
;; <RSTFLG> are cleared.
AUTHSHOW:
    CLRA
    STA INT_FLAG                    ; the interrupt jumps not set up
    STA RSTFLG                      ; no warm start
    STA SAMREG+30                   ; the ROM in, to read the picture
    LDB #$09                        ; the colors the picture shows in
    STB PALETREG+10
    LDB #63                         ; white
    STB PALETREG+11
    LDX #AUTHPIC
    LDY #$0E00                      ; the picture's place in RAM
AUTHSHOW_COPY:
    LDD ,X++
    LDU ,X++
    STD ,Y++
    STU ,Y++
    CMPX #AUTHPIC_END
    BCS AUTHSHOW_COPY
    LDA #$F9                        ; PMODE 4's graphics, the second color set
    STA PIA1+2
    CLRA                            ; the SAM: V0 clear, V1 and V2 set for 256x192 graphics
    LDX #SAMREG
    STA ,X
    STA 3,X
    STA 5,X
    STA 7,X
    STA 9,X                         ; F0 to F2 set: the display at 7 x 512, $0E00
    STA 11,X
AUTHSHOW_WAIT:
    BRA AUTHSHOW_WAIT               ; until RESET

;; What <STARTUP> puts in the video registers, $FF98-$FF9F: the CoCo compatible text mode, its display based at
;; block $38, BASIC's first, so the SAM's offset places the screen as on a CoCo 2, and the vertical scroll that
;; mode needs.
VIDIMAGE:
    .byte $00, $00, $00, $00, $0F, $E0
    .byte $00, $00

;; What <STARTUP> puts in the palette registers, $FFB0-$FFBF: the composite colors the VDG showed, as the GIME
;; makes them.
PALIMAGE:
    .byte 18, 36, 11, 7, 63, 31
    .byte 9, 38, 0, 18, 0, 63
    .byte 0, 18, 0, 38

;; What <COCO3RESET> puts in the MMU's registers: task 0, BASIC's 64K with block $34 at $4000 for start-up, then
;; task 1, the hi-res graphics screen, blocks $30-$33, at $2000-$9FFF, with block $35 at $C000 for its stack.
MMUIMAGE:
    .byte BLOCK7_0, BLOCK7_1, BLOCK6_4, BLOCK7_3, BLOCK7_4, BLOCK7_5, BLOCK7_6, BLOCK7_7
    .byte BLOCK7_0, BLOCK6_0, BLOCK6_1, BLOCK6_2, BLOCK6_3, BLOCK7_5, BLOCK6_5, BLOCK7_7

;; The patches <STARTUP> makes to the copies of Extended and Color BASIC in RAM, after a count: each is where it
;; goes, its length, and its code, which mostly jumps to Super Extended BASIC's code for what the CoCo 3 does
;; differently.
PATCHTAB:
    .byte 27                        ; the patches

    PATCH XBWMST, 1                 ; Extended BASIC's warm start back: start-up has made sure BASIC is in RAM
    NOP
    ENDPATCH

    PATCH CRUNCH_FUNCTIONS, 3       ; crunching: Super Extended BASIC's words
    JMP CRUNCH20
    ENDPATCH

    PATCH DETOK_TABLE, 3            ; listing: Super Extended BASIC's tokens as words
    JMP DETOK20
    ENDPATCH

    PATCH XCOMMAND_DISK, 4          ; Extended BASIC's commands: Super Extended BASIC's, before Disk BASIC's
    JMP XCOMMAND20
    NOP
    ENDPATCH

    PATCH XFUNCTION_DISK, 4         ; Extended BASIC's functions: Super Extended BASIC's, before Disk BASIC's
    JMP XFUNCTION20
    NOP
    ENDPATCH

    ; Patches 6 to 11 read &H and &O numbers up to 24 bits, for LPEEK and LPOKE: the digits shift through
    ; <HEXSHIFT>, and the number fills three bytes of FPA0.
    PATCH HEXOCT_SHIFT, 18
    JMP HEXSHIFT
HEXPATCH_CLEAR:
    CLR FPA0+1
    CLR FPA0+2
    CLR FPA0+3
    BRA HEXPATCH_POINT
HEXPATCH_TOP:
    CLR FPA0
    BRA GIVINT_TYPE
HEXPATCH_OCTAL:
    JMP HEXOCTAL
    ENDPATCH

    PATCH HEXOCT, 7
    BRA HEXPATCH_CLEAR
    NOP
HEXPATCH_RTS:
    RTS
HEXPATCH_POINT:
    LDX #FPA0+1                     ; the value, three bytes
    ENDPATCH

    PATCH HEXOCT_OCTAL_CHECK, 2
    BRA HEXPATCH_OCTAL
    ENDPATCH

    PATCH HEXOCT_HEX_END, 2
    BCS HEXPATCH_TOP
    ENDPATCH

    PATCH XVEC19_AMPERSAND, 2
    BNE HEXPATCH_RTS
    ENDPATCH

    PATCH NODIRECT_RUNNING, 2       ; its RTS is gone under patch 6
    BNE HEXPATCH_RTS
    ENDPATCH

    PATCH XBINIT_SIGNON, 3          ; Extended BASIC's sign-on: Super Extended BASIC's, with Microware's copyright
    JMP XSIGNON20
    ENDPATCH

    PATCH XSIGNON_LAST, 1           ; one blank line fewer after it
    .byte 0
    ENDPATCH

    PATCH GRINIT_END, 3             ; the end of GRINIT: the hi-res graphics' state too
    JMP GRINIT20
    ENDPATCH

    PATCH ISCNTC_KEY, 4             ; BREAK in a program: ON BRK
    JMP BREAK20
    NOP
    ENDPATCH

    PATCH LINEIN_BREAK, 4           ; BREAK while typing a line: ON BRK
    JMP LINEBRK20
    NOP
    ENDPATCH

    PATCH INPLIN_BREAK+1, 2         ; BREAK during INPUT: ON BRK
    .dbyt INPUTBRK20
    ENDPATCH

    PATCH ON, 3                     ; ON ERR and ON BRK
    JMP ON20
    ENDPATCH

    PATCH RSTSTK_OLDPTR, 4          ; resetting the stack: ON ERR and ON BRK off
    JMP RSTSTK20
    NOP
    ENDPATCH

    PATCH ERROR, 3                  ; errors: ON ERR
    JMP ERROR20
    ENDPATCH

    PATCH OKPRMT, 3                 ; the OK prompt: the hi-res text screen, when WIDTH chose one
    JMP OKPRMT20
    ENDPATCH

    PATCH SCRCHR, 3                 ; the screen's output: the hi-res text screen
    JMP PUTCHR3
    ENDPATCH

    PATCH CLS, 3                    ; CLS: the hi-res text screen
    JMP CLS3
    ENDPATCH

    PATCH WAITKY, 8                 ; waiting for a key: the hi-res text screen's cursor
    JMP WAITKY3
    NOP
    NOP
    NOP
    NOP
    NOP
    ENDPATCH

    PATCH PRINT_AT_CURSOR, 3        ; PRINT @: the hi-res text screen
    JMP PRINTAT20
    ENDPATCH

    PATCH NEWLIN, 3                 ; a new line: the hi-res text screen
    JMP NEWLIN20
    ENDPATCH

    PATCH LINEIN_CLEAR, 3           ; typing a line: the hi-res text screen
    JMP LINEIN20
    ENDPATCH

;; The authors' names, complemented, which <AUTHNAMES> decodes into <AUTHORMS>.
AUTHCODED:
    .byte $AB, $D1, $B7, $9E, $8D, $8D
    .byte $96, $8C, $DF, $D9, $DF, $AB
    .byte $D1, $BA, $9E, $8D, $93, $9A
    .byte $8C, $F2, $FF

;; Patches the copy of Disk BASIC in RAM: its sign-on goes to <DISK20MS> or <DISK21MS>, which show Disk BASIC 2.0 or
;; 2.1 with Microware's copyright, and 1.1's quick keyboard check before each statement goes, as Color BASIC's
;; <KEYCHK> went.
DSKPATCH:
    LDA DCNVEC                      ; DSKCON's high byte tells the versions apart
    CMPA #$D6                       ; 1.0's DSKCON is at $D6xx
    BNE DSKPATCH_11
    LDX #DSKSIGNON10
    LEAY >DSK10PATCH,PCR
    LDB ,Y+
    BRA DSKPATCH_COPY
DSKPATCH_11:
    LDX #DVEC20_KEYS11
    LDA #$12                        ; NOP
    LDB #11                         ; the eleven bytes of the check
DSKPATCH_NOP:
    STA ,X+
    DECB
    BNE DSKPATCH_NOP
    LDX #DSKSIGNON11
    LEAY >DSK11PATCH,PCR
    LDB ,Y+
DSKPATCH_COPY:
    LDA ,Y+
    STA ,X+
    DECB
    BNE DSKPATCH_COPY
    RTS

;; Disk BASIC 1.1's sign-on patch for <DSKPATCH>: its length, then a jump to <DISK21SIGNON>.
DSK11PATCH:
    .byte 3
    JMP DISK21SIGNON
;; Disk BASIC 1.0's sign-on patch for <DSKPATCH>: its length, then a jump to <DISK20SIGNON>.
DSK10PATCH:
    .byte 3
    JMP DISK20SIGNON

;; The constant page's interrupt jumps, which <STARTUP> copies to $FEED: the flag that says they are set up, then a
;; jump for each vector to its jump in page 1, where BASIC can change it.
;; See: <INT_FLAG>
INTIMAGE:
    .logicalorg INT_FLAG
    .byte $55
    LBRA SW3VEC
    LBRA SW2VEC
    LBRA FRQVEC
    LBRA IRQVEC
    LBRA SWIVEC
    LBRA NMIVEC
    .logicalorg
    .logicalorg STARTUP + * - BEGMOVE
    .logicalorg
ENDMOVE:

; ----------------------------------------------------------------------------------------------------------------
; The authors' picture, and room nothing uses
; ----------------------------------------------------------------------------------------------------------------

;; Room past what start-up copies to RAM, which nothing uses.
STARTUP_SPARE:
    .byte $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $00, $55, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $00, $18, $00, $0E, $00

;; The authors' picture, which <AUTHSHOW> shows: 256x192 pixels, a bit each, 32 bytes to a row.
AUTHPIC:
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $7F, $FF
    .byte $FF, $F7, $FF, $FB, $EE, $EF, $FB, $FF, $BB, $FF, $FF, $FF, $FB, $FF, $FF, $BB
    .byte $BB, $BB, $BF, $BB, $BB, $FF, $BF, $FF, $FE, $EF, $FF, $FF, $FF, $EF, $7F, $FF
    .byte $FF, $F7, $BB, $FF, $BB, $BB, $BF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $BB, $BF, $BB, $FF, $BB, $7F, $FF
    .byte $FF, $F6, $EE, $EE, $EE, $EE, $EE, $EF, $FF, $FE, $FF, $FE, $EE, $EE, $FE, $EE
    .byte $EE, $EE, $EF, $EE, $EE, $EE, $EE, $EE, $FE, $EE, $EE, $EE, $EE, $EE, $7F, $FF
    .byte $FF, $F3, $BB, $FF, $BB, $BB, $BB, $BB, $BF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FB, $BB, $BB, $BB, $BB, $BB, $7F, $FF
    .byte $FF, $F6, $AA, $AE, $AA, $AE, $AA, $EA, $BB, $BB, $FB, $FF, $BB, $FF, $BF, $BF
    .byte $FF, $FB, $BF, $BB, $BB, $BB, $BB, $BB, $BA, $EA, $AA, $EE, $AE, $EE, $7F, $FF
    .byte $FF, $F3, $BB, $BF, $BB, $BB, $BB, $BB, $BF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FB, $BB, $BB, $BB, $BB, $BB, $7F, $FF
    .byte $FF, $F6, $EE, $EE, $EE, $EE, $EE, $EE, $EE, $EE, $EF, $FE, $EF, $FF, $FF, $FF
    .byte $FF, $FE, $EF, $EE, $EE, $EE, $EE, $EE, $EE, $EE, $EE, $EE, $EE, $EF, $7F, $FF
    .byte $FF, $F7, $BB, $BB, $BB, $BB, $BB, $BB, $BF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $BB, $BB, $BB, $BB, $BB, $7F, $FF
    .byte $FF, $F6, $AA, $EE, $AA, $AA, $AA, $EA, $AB, $BB, $BB, $FF, $BB, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FB, $BF, $FF, $FF, $BB, $BB, $EA, $AE, $AA, $AA, $AF, $7F, $FF
    .byte $FF, $F7, $BB, $BB, $BF, $FF, $FB, $BB, $BF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FB, $BB, $BB, $BB, $BB, $7F, $FF
    .byte $FF, $F6, $EE, $EE, $EE, $EF, $EF, $EE, $EE, $EF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $EE, $EE, $FF, $EF, $EE, $EE, $EF, $7F, $FF
    .byte $FF, $F7, $BB, $BB, $BF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $BB, $BB, $BB, $7F, $FF
    .byte $FF, $F7, $EA, $AA, $BB, $BB, $BB, $BB, $BB, $FB, $BB, $BF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FB, $FF, $FB, $FB, $BB, $BB, $BA, $AA, $AA, $EF, $7F, $FF
    .byte $FF, $F7, $BB, $BB, $BF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FB, $BB, $BB, $BB, $7F, $FF
    .byte $FF, $F6, $EE, $EE, $EE, $FE, $EE, $EE, $EE, $EE, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FE, $EE, $EF, $FE, $EE, $EE, $EE, $EF, $7F, $FF
    .byte $FF, $F7, $BB, $BB, $FB, $BF, $FF, $FF, $FF, $FF, $FF, $FF, $FE, $00, $00, $00
    .byte $00, $00, $00, $00, $0F, $FF, $FF, $FF, $FF, $FF, $FB, $BB, $BB, $BB, $7F, $FF
    .byte $FF, $F6, $EA, $AB, $AA, $AB, $BB, $BB, $BF, $BF, $FF, $FF, $FF, $80, $00, $7F
    .byte $FF, $FF, $C0, $00, $3F, $FF, $FF, $BB, $BB, $BF, $AA, $AA, $AA, $EF, $7F, $FF
    .byte $FF, $F3, $BB, $BB, $BB, $BF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $BB, $BB, $BB, $BF, $7F, $FF
    .byte $FF, $F6, $EE, $EE, $EE, $EF, $EE, $FF, $FF, $FF, $EE, $FF, $FF, $80, $00, $3F
    .byte $FF, $FF, $80, $00, $3F, $FF, $FF, $EE, $FE, $EE, $EE, $EE, $EE, $EF, $7F, $FF
    .byte $FF, $F3, $BB, $BB, $BB, $BF, $FF, $FF, $FF, $FF, $FF, $FF, $F0, $00, $00, $00
    .byte $00, $00, $00, $00, $07, $FF, $FF, $FF, $FF, $FF, $BB, $BB, $BB, $BF, $7F, $FF
    .byte $FF, $F6, $EE, $AB, $AE, $EB, $BB, $BF, $FB, $FF, $FF, $FF, $FF, $80, $00, $1F
    .byte $FF, $FF, $00, $00, $3F, $FF, $FF, $FF, $BB, $BB, $AA, $AA, $BE, $AB, $7F, $FF
    .byte $FF, $F3, $BB, $BF, $BB, $BF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FB, $FB, $BB, $BB, $BF, $7F, $FF
    .byte $FF, $F6, $EE, $EE, $EE, $EE, $EE, $EF, $FE, $EF, $FF, $FF, $FF, $80, $00, $0F
    .byte $FF, $FE, $00, $00, $3F, $FF, $FF, $EF, $EF, $EE, $EE, $EE, $EE, $EF, $7F, $FF
    .byte $FF, $F3, $BB, $BF, $FB, $BF, $FF, $FF, $FF, $FF, $FF, $FF, $F0, $00, $00, $00
    .byte $00, $00, $00, $00, $03, $FF, $FF, $FF, $FF, $FB, $BF, $FF, $BB, $BF, $7F, $FF
    .byte $FF, $F6, $EA, $AB, $BA, $AB, $BB, $FB, $FF, $BF, $FF, $FF, $FF, $80, $00, $07
    .byte $FF, $FC, $00, $00, $3F, $FF, $FF, $FF, $FB, $AA, $FF, $FE, $EA, $AB, $7F, $FF
    .byte $FF, $F3, $BB, $BF, $FB, $BF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $BB, $BF, $FF, $BB, $BF, $7F, $FF
    .byte $FF, $F6, $EE, $EE, $FF, $FE, $EE, $EE, $FF, $FF, $FF, $FF, $FF, $80, $00, $03
    .byte $FF, $F8, $00, $00, $3F, $FF, $FF, $FE, $EE, $EE, $FF, $FE, $EE, $EF, $7F, $FF
    .byte $FF, $F7, $BB, $BF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $F0, $00, $00, $00
    .byte $00, $00, $00, $00, $03, $FF, $FF, $FF, $FF, $BB, $BF, $FF, $BB, $FF, $7F, $FF
    .byte $FF, $F7, $AA, $FB, $BB, $BB, $BF, $FF, $FF, $FF, $FF, $FF, $FF, $80, $00, $01
    .byte $FF, $F0, $00, $00, $3F, $FF, $FF, $BB, $BB, $AE, $BB, $BE, $AF, $BB, $7F, $FF
    .byte $FF, $F7, $BB, $BF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $BB, $FF, $FF, $BB, $FF, $7F, $FF
    .byte $FF, $F6, $EE, $EE, $FF, $FF, $FF, $FF, $FE, $FF, $FF, $FF, $FF, $80, $08, $00
    .byte $FF, $E0, $02, $00, $3F, $FF, $FF, $FE, $EF, $EE, $FF, $EE, $EF, $EF, $7F, $FF
    .byte $FF, $F7, $BB, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $F0, $00, $00, $00
    .byte $00, $00, $00, $00, $03, $FF, $FF, $FF, $FF, $FB, $FF, $FF, $BB, $FF, $7F, $FF
    .byte $FF, $F7, $AA, $BB, $BB, $FB, $BB, $FF, $BF, $FF, $FF, $FF, $FF, $80, $0C, $00
    .byte $7F, $C0, $06, $00, $3F, $FF, $FF, $FF, $BB, $FF, $FF, $BF, $EB, $BB, $7F, $FF
    .byte $FF, $F7, $BB, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $7F, $FF
    .byte $FF, $F6, $EE, $EF, $FF, $EF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $80, $0E, $00
    .byte $3F, $80, $0E, $00, $3F, $FF, $FF, $FE, $FF, $FF, $FE, $EE, $EE, $FF, $7F, $FF
    .byte $FF, $F7, $BB, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $F0, $00, $00, $00
    .byte $00, $00, $00, $00, $03, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $7F, $FF
    .byte $FF, $F3, $EA, $BB, $BF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $80, $0F, $00
    .byte $1F, $00, $1E, $00, $3F, $FF, $FF, $FF, $BF, $FF, $FF, $FF, $FF, $BF, $7F, $FF
    .byte $FF, $F7, $BB, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $7F, $FF
    .byte $FF, $F7, $EE, $EE, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $80, $0F, $80
    .byte $0E, $00, $3E, $00, $3F, $FF, $FF, $EE, $FF, $FF, $FF, $FE, $EF, $EF, $7F, $FF
    .byte $FF, $F7, $BB, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $F0, $00, $00, $00
    .byte $00, $00, $00, $00, $03, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $BF, $7F, $FF
    .byte $FF, $F6, $EA, $BB, $BB, $BF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $80, $0F, $C0
    .byte $00, $00, $7E, $00, $3F, $FF, $FF, $BF, $FF, $FF, $FF, $FF, $BA, $EF, $7F, $FF
    .byte $FF, $F7, $BB, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $00, $1F, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $BB, $7F, $FF
    .byte $FF, $F6, $EE, $EE, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $80, $0F, $E0
    .byte $00, $00, $FE, $00, $3F, $FF, $FF, $FF, $FF, $FF, $FF, $FE, $FE, $EF, $7F, $FF
    .byte $FF, $F7, $BB, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $F0, $00, $00, $00
    .byte $00, $00, $00, $00, $03, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $BB, $7F, $FF
    .byte $FF, $F6, $EB, $BF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $80, $0F, $C0
    .byte $00, $00, $3E, $00, $3F, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FE, $EB, $7F, $FF
    .byte $FF, $F7, $BB, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00
    .byte $00, $00, $1F, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $BA, $7F, $FF
    .byte $FF, $F6, $EE, $EF, $FF, $FF, $FF, $C0, $1F, $FF, $FF, $FF, $FF, $80, $0C, $00
    .byte $00, $00, $1E, $00, $3F, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $EE, $EB, $7F, $FF
    .byte $FF, $F7, $BB, $FF, $FF, $FF, $FC, $00, $0F, $FF, $FF, $FF, $F0, $00, $00, $00
    .byte $00, $00, $00, $00, $03, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FE, $AA, $7F, $FF
    .byte $FF, $F6, $AB, $BB, $FF, $FF, $00, $00, $03, $FF, $FF, $FF, $FF, $80, $0C, $00
    .byte $00, $00, $06, $00, $3F, $FF, $FF, $FF, $FF, $FF, $79, $9F, $FB, $AB, $7F, $FF
    .byte $FF, $F7, $BB, $FF, $FF, $F8, $00, $00, $01, $FF, $FF, $FF, $FF, $FF, $F0, $00
    .byte $00, $38, $03, $FF, $FF, $FF, $FF, $FF, $FF, $F0, $00, $03, $FE, $EE, $7F, $FF
    .byte $FF, $F6, $EF, $FF, $FF, $E0, $00, $00, $00, $4F, $FF, $FF, $FF, $80, $00, $00
    .byte $01, $7C, $00, $00, $3F, $FF, $FF, $FF, $FF, $80, $00, $00, $FA, $BB, $7F, $FF
    .byte $FF, $F7, $FF, $FF, $FF, $C0, $00, $00, $00, $01, $FF, $FF, $F0, $00, $00, $00
    .byte $03, $FE, $00, $00, $03, $FF, $FF, $FF, $FF, $00, $00, $00, $7E, $EE, $7F, $FF
    .byte $FF, $F3, $BB, $FF, $FF, $00, $00, $00, $00, $00, $FF, $FF, $FF, $80, $00, $00
    .byte $0F, $FF, $00, $00, $3F, $FF, $FF, $FF, $FC, $00, $00, $00, $3B, $BB, $7F, $FF
    .byte $FF, $F7, $FF, $FF, $FE, $00, $00, $00, $00, $00, $7F, $FF, $FF, $FF, $00, $00
    .byte $2F, $FF, $00, $7F, $FF, $FF, $FF, $FF, $F0, $00, $00, $00, $0E, $EE, $7F, $FF
    .byte $FF, $F6, $FF, $FF, $FC, $00, $00, $00, $00, $00, $3F, $FF, $FF, $80, $00, $01
    .byte $FF, $FF, $80, $00, $3F, $FF, $FF, $FF, $E0, $00, $00, $00, $07, $BB, $7F, $FF
    .byte $FF, $F7, $FF, $FF, $F8, $00, $00, $00, $00, $00, $3F, $FF, $F0, $00, $00, $03
    .byte $FF, $FF, $40, $00, $03, $FF, $FF, $FF, $C0, $00, $00, $00, $03, $EE, $7F, $FF
    .byte $FF, $F3, $BB, $FF, $F0, $00, $00, $00, $01, $00, $1F, $FF, $FF, $80, $01, $07
    .byte $FF, $FF, $A0, $00, $3F, $FF, $FF, $FF, $80, $00, $00, $00, $01, $BB, $7F, $FF
    .byte $FF, $F7, $FF, $FF, $E0, $00, $00, $00, $01, $80, $1F, $FF, $FF, $FE, $0E, $2F
    .byte $FF, $FF, $C0, $1F, $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00, $EE, $7F, $FF
    .byte $FF, $F6, $FF, $FF, $E0, $00, $00, $00, $65, $E0, $0F, $FF, $FF, $80, $0C, $1F
    .byte $FF, $FF, $E0, $00, $3F, $FF, $FF, $FF, $00, $00, $00, $00, $00, $3B, $7F, $FF
    .byte $FF, $F7, $FF, $FF, $C0, $00, $00, $0B, $FF, $F0, $0F, $FF, $FC, $00, $18, $0F
    .byte $F8, $00, $60, $00, $07, $FF, $FF, $FE, $00, $00, $00, $00, $00, $0E, $7F, $FF
    .byte $FF, $F3, $BB, $FF, $C0, $00, $01, $FF, $FF, $F8, $0F, $FF, $FF, $80, $00, $01
    .byte $F8, $00, $20, $00, $3F, $FF, $FF, $FE, $00, $00, $00, $00, $00, $1B, $7F, $FF
    .byte $FF, $F7, $FF, $FF, $80, $00, $03, $FF, $FF, $FC, $0F, $FF, $FF, $FC, $03, $03
    .byte $FF, $7F, $F0, $03, $FF, $FF, $FF, $FC, $00, $00, $00, $00, $00, $0E, $7F, $FF
    .byte $FF, $F7, $FE, $FF, $80, $01, $5D, $FF, $FF, $FC, $0F, $FF, $FF, $C0, $07, $F1
    .byte $FC, $07, $FC, $00, $3F, $FF, $FF, $FC, $00, $00, $00, $00, $00, $03, $7F, $FF
    .byte $FF, $F7, $BF, $FF, $00, $02, $EF, $FF, $FF, $FC, $0F, $FF, $FF, $00, $0E, $00
    .byte $7C, $00, $F4, $00, $0C, $7F, $FF, $F8, $00, $00, $00, $00, $00, $0E, $7F, $FF
    .byte $FF, $F2, $AB, $FF, $00, $05, $FF, $FF, $FF, $FE, $0F, $FF, $FF, $F8, $1C, $00
    .byte $FC, $01, $F8, $01, $FB, $BF, $FF, $F8, $00, $00, $0F, $E1, $80, $0B, $7F, $FF
    .byte $FF, $F7, $BF, $FF, $00, $03, $FF, $FF, $FF, $FE, $0F, $FF, $FF, $F8, $1F, $C0
    .byte $FE, $3F, $FC, $01, $F6, $DF, $FF, $F8, $00, $3F, $FF, $FF, $80, $0E, $7F, $FF
    .byte $FF, $F6, $EE, $EE, $00, $07, $FF, $FF, $FF, $FE, $0F, $FE, $FF, $FC, $1F, $F1
    .byte $FF, $9F, $F8, $37, $F5, $DF, $FF, $F8, $00, $FF, $FF, $FF, $80, $0B, $7F, $FF
    .byte $FF, $F7, $BF, $FF, $00, $07, $FF, $FF, $FF, $FF, $07, $FF, $FF, $F8, $0F, $EF
    .byte $7F, $FF, $FC, $03, $F6, $DF, $FF, $F8, $7F, $FF, $FF, $FF, $80, $06, $7F, $FF
    .byte $FF, $F6, $FF, $BF, $00, $03, $FF, $FF, $FF, $FF, $07, $FB, $BB, $FD, $DF, $FF
    .byte $EF, $FF, $F9, $7F, $FB, $BF, $FF, $FC, $7F, $FF, $FF, $FF, $C0, $0B, $7F, $FF
    .byte $FF, $F7, $BF, $FE, $00, $03, $FF, $FF, $FF, $F8, $07, $FF, $FF, $FF, $9F, $FF
    .byte $FF, $FF, $FF, $BF, $FC, $7F, $FF, $FC, $75, $0F, $FF, $CF, $C0, $0E, $7F, $FF
    .byte $FF, $F6, $FF, $FE, $00, $07, $F5, $47, $FF, $E0, $07, $FF, $EF, $FF, $CF, $FD
    .byte $FF, $FF, $FF, $3F, $FF, $FF, $FF, $FC, $00, $00, $E0, $07, $C0, $0F, $7F, $FF
    .byte $FF, $F7, $BF, $FF, $00, $0F, $F8, $07, $FF, $DC, $07, $FF, $FF, $FF, $CF, $FB
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FC, $00, $00, $00, $03, $E0, $0D, $7F, $FF
    .byte $FF, $F6, $FF, $FE, $00, $1F, $D1, $1F, $FF, $EF, $07, $FF, $FF, $FF, $FF, $FF
    .byte $F1, $FF, $FF, $FF, $FF, $FF, $FF, $FE, $00, $00, $00, $7B, $F0, $0B, $7F, $FF
    .byte $FF, $F3, $BF, $FE, $00, $1F, $FF, $EF, $FE, $81, $07, $FF, $FF, $FF, $7F, $F8
    .byte $40, $FF, $FF, $FF, $FF, $FF, $FF, $FE, $60, $01, $FC, $1D, $F0, $0D, $7F, $FF
    .byte $FF, $F6, $EE, $FF, $00, $1F, $FF, $01, $FE, $01, $87, $FE, $EE, $FF, $FF, $F0
    .byte $00, $1F, $FF, $FF, $FF, $FF, $FF, $FE, $E0, $03, $F0, $67, $F0, $17, $7F, $FF
    .byte $FF, $F3, $BF, $FE, $00, $1F, $F8, $01, $FC, $03, $87, $FF, $FF, $FF, $FF, $C0
    .byte $00, $0F, $FC, $3F, $FF, $FF, $FF, $FF, $C0, $03, $F0, $33, $F0, $5F, $7F, $FF
    .byte $FF, $F6, $AF, $FE, $00, $1F, $FF, $F0, $FE, $0F, $87, $FF, $BF, $FF, $FF, $80
    .byte $FF, $07, $F8, $3F, $FF, $FF, $FF, $FF, $FF, $03, $FA, $FF, $F1, $BB, $7F, $FF
    .byte $FF, $F3, $BF, $BF, $00, $1F, $FF, $FE, $FE, $9B, $87, $FF, $FF, $FF, $FF, $BD
    .byte $80, $F3, $F8, $3F, $FF, $FF, $FF, $FF, $FF, $17, $FF, $FF, $F4, $EE, $7F, $FF
    .byte $FF, $F6, $EE, $FF, $00, $1F, $FF, $FF, $FF, $03, $87, $EF, $EE, $EF, $FF, $00
    .byte $00, $07, $F8, $3F, $FF, $FF, $FF, $FF, $FF, $77, $FF, $FF, $FE, $BB, $7F, $FF
    .byte $FF, $F3, $BF, $BF, $00, $0F, $FF, $EF, $F8, $83, $87, $FF, $FF, $FF, $FF, $BE
    .byte $BF, $FF, $F8, $7F, $FF, $FF, $FF, $FF, $FD, $B3, $FF, $FF, $FD, $EE, $7F, $FF
    .byte $FF, $F6, $EE, $EF, $00, $0F, $FF, $F8, $7F, $F7, $8F, $FF, $FB, $BF, $FF, $FF
    .byte $FF, $F7, $FC, $FF, $BF, $FF, $FF, $FF, $FF, $07, $FF, $FF, $FF, $BB, $7F, $FF
    .byte $FF, $F3, $BB, $BB, $00, $0F, $FF, $F3, $7F, $0F, $8F, $FF, $FF, $FF, $FF, $FF
    .byte $BF, $E3, $FC, $FF, $FF, $FF, $FF, $FF, $FF, $07, $FF, $FF, $FF, $EE, $7F, $FF
    .byte $FF, $F6, $EE, $EF, $00, $0F, $FE, $F7, $FF, $CF, $8E, $FF, $FF, $EF, $FF, $FF
    .byte $17, $F7, $FD, $EF, $EF, $FE, $FF, $FF, $FF, $9F, $FF, $FF, $FF, $BB, $7F, $FF
    .byte $FF, $F3, $BB, $BB, $00, $07, $FF, $FE, $FF, $C1, $9F, $FF, $FF, $FF, $FF, $FE
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $07, $F7, $FF, $FE, $EE, $7F, $FF
    .byte $FF, $F6, $EE, $EE, $00, $03, $FF, $C4, $1C, $03, $9B, $FB, $AF, $BF, $FF, $FF
    .byte $FF, $FF, $FE, $FB, $FB, $BB, $FF, $BF, $FE, $02, $AB, $FF, $F8, $FB, $7F, $FF
    .byte $FF, $F3, $BF, $BA, $04, $03, $FA, $00, $00, $01, $9F, $FF, $BB, $FF, $FB, $FF
    .byte $FF, $FF, $FB, $BF, $FF, $FB, $FE, $EF, $FC, $00, $05, $FF, $F9, $EE, $7F, $FF
    .byte $FF, $F6, $EE, $EC, $06, $01, $FC, $A2, $00, $03, $9F, $EE, $EE, $EF, $FE, $FF
    .byte $FF, $FF, $FE, $FF, $FE, $EE, $EF, $BF, $FE, $00, $00, $3F, $FB, $BB, $7F, $FF
    .byte $FF, $F3, $BB, $B0, $00, $01, $FA, $10, $00, $03, $9F, $FB, $BB, $FF, $FB, $FF
    .byte $FF, $FF, $FB, $BF, $FF, $FB, $BE, $EF, $FC, $0F, $80, $1F, $F6, $EE, $7F, $FF
    .byte $FF, $F6, $EE, $EE, $00, $00, $68, $5F, $FE, $03, $1B, $AE, $AE, $FB, $EE, $FD
    .byte $FF, $FF, $FE, $AB, $BB, $EA, $FF, $BF, $F8, $0B, $FC, $1F, $FF, $BB, $7F, $FF
    .byte $FF, $F3, $BB, $BA, $00, $00, $7B, $0F, $FE, $00, $1F, $BB, $BB, $FF, $FB, $FF
    .byte $FF, $FF, $FB, $BB, $FF, $BB, $BE, $EF, $FC, $07, $FC, $5F, $F6, $EE, $7F, $FF
    .byte $FF, $F6, $EE, $EE, $00, $00, $14, $40, $3C, $00, $0E, $EE, $EE, $FF, $FF, $FF
    .byte $FF, $FF, $FE, $EE, $EE, $EE, $EF, $BF, $FE, $00, $61, $FF, $FF, $BB, $7F, $FF
    .byte $FF, $F3, $BB, $80, $00, $00, $00, $7E, $00, $00, $3F, $BB, $FF, $FF, $BF, $FF
    .byte $FF, $FF, $FF, $BB, $FF, $BB, $BE, $EF, $FF, $E0, $07, $FF, $FF, $EE, $7F, $FF
    .byte $FF, $F6, $EE, $00, $00, $00, $00, $3F, $EE, $80, $2E, $AB, $BF, $BE, $FC, $FF
    .byte $FF, $FF, $FE, $EB, $BB, $AA, $BB, $BF, $EF, $FA, $FF, $FF, $F8, $0B, $7F, $FF
    .byte $FF, $F3, $BA, $00, $00, $C0, $00, $0F, $FE, $00, $3B, $BF, $FF, $FB, $B1, $FF
    .byte $FF, $FF, $F3, $BB, $FF, $BB, $AE, $EF, $BF, $D9, $7F, $FF, $F8, $02, $7F, $FF
    .byte $FF, $F6, $EC, $00, $00, $E0, $00, $00, $00, $00, $EE, $EE, $EF, $EE, $E1, $FF
    .byte $FF, $FF, $F0, $EE, $EE, $EE, $EB, $BF, $EF, $8E, $3F, $FF, $F8, $00, $7F, $FF
    .byte $FF, $F3, $BA, $00, $00, $F0, $00, $00, $00, $00, $BB, $BB, $BF, $BB, $B1, $FF
    .byte $FF, $FF, $E0, $3B, $FF, $BB, $EE, $FF, $BB, $00, $5F, $FF, $F8, $00, $7F, $FF
    .byte $FF, $F6, $E0, $04, $00, $78, $00, $00, $00, $01, $EE, $AA, $AE, $EA, $C0, $7F
    .byte $FF, $FF, $80, $0B, $FF, $EF, $AB, $FF, $EF, $C2, $3F, $FF, $FF, $E0, $7F, $FF
    .byte $FF, $F3, $80, $00, $00, $7C, $00, $00, $00, $00, $3B, $BB, $BB, $BB, $00, $3F
    .byte $FF, $FF, $00, $03, $FF, $FE, $EE, $EF, $BB, $C0, $7F, $FF, $FE, $F8, $7F, $FF
    .byte $FF, $F6, $60, $C0, $00, $7F, $00, $00, $00, $00, $2E, $EE, $EE, $EC, $00, $01
    .byte $3F, $FC, $00, $00, $6E, $EF, $FF, $FB, $EE, $E2, $3F, $FF, $FE, $78, $7F, $FF
    .byte $FF, $F0, $98, $60, $00, $3F, $80, $00, $00, $00, $03, $BB, $BB, $B8, $00, $00
    .byte $00, $00, $00, $00, $01, $BB, $BB, $BA, $BB, $5F, $9F, $FF, $FC, $F8, $7F, $FF
    .byte $FF, $F6, $00, $30, $00, $0F, $C0, $00, $00, $00, $00, $6A, $EE, $A0, $00, $00
    .byte $00, $00, $00, $00, $00, $FF, $FF, $FA, $EE, $83, $FF, $FF, $FC, $F8, $7F, $FF
    .byte $FF, $F4, $00, $00, $00, $07, $E0, $00, $00, $00, $05, $13, $BB, $80, $00, $00
    .byte $00, $00, $00, $00, $00, $2E, $EE, $EA, $9B, $A3, $FF, $FF, $FD, $F0, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $01, $F0, $00, $00, $00, $00, $0E, $EE, $80, $00, $00
    .byte $00, $00, $00, $00, $00, $2F, $FE, $AA, $0E, $ED, $FF, $FF, $F9, $F0, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $78, $00, $00, $00, $00, $03, $BB, $80, $00, $00
    .byte $00, $00, $00, $00, $00, $0A, $BA, $A8, $0B, $FB, $7F, $FF, $F3, $F0, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $3C, $00, $00, $00, $00, $02, $8A, $80, $00, $00
    .byte $00, $00, $00, $00, $00, $02, $FE, $A0, $06, $FE, $FF, $FF, $07, $F0, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $1E, $00, $00, $00, $00, $07, $03, $80, $00, $00
    .byte $00, $00, $00, $00, $00, $02, $AA, $80, $07, $F9, $FF, $FC, $07, $F4, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $0F, $14, $0E, $00, $00, $02, $80, $80, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $AA, $80, $BF, $FF, $BF, $F0, $0F, $F6, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $03, $FF, $FC, $00, $00, $03, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $EA, $0F, $FE, $7C, $77, $80, $1F, $F6, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $01, $FF, $F8, $00, $00, $03, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $28, $7F, $FC, $FE, $80, $00, $1F, $F7, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $FF, $F0, $00, $00, $03, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $20, $37, $3C, $FE, $C0, $00, $BF, $F7, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $07, $7F, $E0, $00, $00, $F3, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $3F, $3E, $FF, $80, $01, $FF, $F7, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $A3, $FF, $C0, $00, $00, $63, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $3F, $FD, $EE, $80, $07, $FF, $F7, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $63, $FF, $C0, $00, $00, $73, $00, $00, $00, $00
    .byte $FF, $00, $00, $00, $00, $00, $08, $1F, $78, $F7, $E8, $9F, $FF, $FC, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $77, $BF, $80, $00, $00, $33, $00, $00, $00, $3F
    .byte $BB, $E0, $00, $00, $00, $00, $00, $1F, $F8, $3B, $55, $7F, $80, $70, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $01, $FF, $00, $00, $00, $3B, $00, $00, $00, $FF
    .byte $3B, $FC, $00, $00, $00, $00, $00, $1F, $FF, $1D, $8E, $E7, $82, $F8, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $FF, $00, $00, $00, $30, $00, $00, $01, $FE
    .byte $F9, $9F, $00, $00, $00, $00, $00, $0F, $FF, $C1, $17, $FF, $FF, $C0, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $0E, $00, $00, $00, $18, $00, $00, $00, $F8
    .byte $FF, $3F, $E0, $00, $04, $00, $00, $0F, $BF, $C2, $EF, $FF, $FF, $80, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $06, $00, $00, $00, $1C, $00, $00, $08, $FB
    .byte $FF, $37, $E0, $00, $00, $00, $00, $0F, $BF, $C1, $1F, $FF, $FF, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $0E, $00, $00, $00, $00, $00, $00, $0E, $00, $00, $1D, $07
    .byte $FF, $E3, $68, $00, $00, $00, $00, $07, $7F, $C7, $3F, $FF, $FE, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $1C, $00, $00, $00, $00, $00, $00, $00, $3F
    .byte $FF, $FB, $F6, $00, $00, $00, $00, $07, $7F, $E1, $7F, $FF, $FC, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $0E, $00, $00, $00, $00, $00, $01, $C6, $7F
    .byte $FF, $FF, $E8, $00, $00, $00, $00, $07, $0F, $F3, $8F, $97, $FC, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $01, $B1, $EF
    .byte $FF, $EF, $B7, $00, $00, $00, $00, $07, $83, $E1, $C6, $00, $78, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $21, $DF
    .byte $FF, $D1, $A2, $00, $00, $40, $00, $03, $00, $F1, $FF, $14, $20, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $3E, $FF
    .byte $FF, $FF, $DF, $00, $00, $00, $00, $03, $06, $70, $7C, $00, $C0, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0F, $FF
    .byte $FF, $FF, $E7, $E0, $00, $00, $00, $03, $87, $F1, $F8, $03, $80, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $1E, $AF
    .byte $FF, $FF, $F7, $00, $00, $00, $00, $03, $8F, $FB, $F8, $20, $00, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $1F, $BF
    .byte $FF, $FF, $BF, $E0, $00, $00, $00, $F3, $8D, $FF, $F8, $5F, $00, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $1E, $FF
    .byte $FF, $FF, $4F, $F0, $00, $00, $01, $E3, $87, $FF, $FC, $6E, $00, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0D, $F7
    .byte $BF, $FF, $EF, $E8, $00, $00, $00, $01, $1F, $FF, $FF, $FE, $00, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0B, $FF
    .byte $9F, $FF, $FD, $F8, $00, $00, $00, $01, $BF, $FF, $FF, $FF, $00, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $07, $FF
    .byte $FF, $FF, $8F, $E8, $00, $00, $00, $01, $BF, $FF, $FF, $FC, $00, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $07, $FF
    .byte $FF, $FF, $FF, $F8, $00, $00, $00, $01, $BF, $FF, $FF, $F8, $00, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $07, $FF
    .byte $FF, $9F, $FF, $F8, $00, $00, $00, $01, $3F, $FF, $FF, $F0, $00, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $FE, $00, $00, $07, $FF
    .byte $1F, $FF, $F5, $FC, $00, $00, $00, $01, $3F, $FF, $FF, $E0, $00, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $03, $FC
    .byte $3F, $FF, $BF, $F8, $00, $00, $00, $01, $3F, $85, $FF, $C0, $00, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $03, $FF
    .byte $F7, $FF, $DF, $F8, $00, $00, $00, $00, $1D, $2A, $07, $80, $00, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $0E, $00, $00, $00, $00, $00, $00, $00, $00, $00, $07, $FF
    .byte $FF, $FF, $FF, $F8, $00, $00, $00, $01, $06, $FF, $00, $00, $00, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $1C, $00, $00, $00, $00, $00, $00, $10, $00, $00, $1F, $FF
    .byte $FF, $FF, $DF, $F8, $00, $00, $00, $01, $17, $3D, $95, $00, $00, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $01, $FF, $80, $00, $07, $FF
    .byte $FF, $FF, $EF, $F8, $00, $00, $00, $00, $0E, $EF, $DA, $00, $00, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $03, $FF
    .byte $FF, $FF, $F7, $F0, $00, $00, $00, $00, $15, $F7, $80, $00, $00, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $03, $FF
    .byte $FF, $FF, $ED, $E0, $00, $00, $00, $00, $0F, $BF, $EC, $00, $00, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $07, $FF
    .byte $FF, $FF, $DC, $E0, $00, $00, $00, $00, $17, $7F, $D8, $00, $00, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $07, $FF
    .byte $FF, $FF, $BC, $C0, $00, $00, $00, $00, $3F, $FF, $F8, $00, $00, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $03, $FF
    .byte $FF, $FF, $DE, $00, $00, $00, $00, $00, $7F, $FF, $F8, $00, $00, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $01, $FF
    .byte $FF, $FF, $FF, $80, $00, $00, $00, $00, $7F, $FF, $F8, $00, $00, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $FF
    .byte $FF, $FB, $FF, $80, $00, $00, $00, $00, $7F, $FF, $F0, $00, $00, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $03, $DF
    .byte $FE, $C1, $F2, $00, $00, $00, $00, $18, $7F, $FF, $F0, $00, $00, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $83
    .byte $00, $1F, $CC, $00, $00, $00, $00, $00, $7F, $FF, $F0, $00, $00, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $03, $00
    .byte $80, $3F, $98, $00, $00, $00, $00, $00, $7F, $FF, $F0, $00, $00, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $E2
    .byte $46, $3E, $60, $00, $00, $00, $00, $00, $7F, $FF, $E0, $00, $00, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $01, $80
    .byte $33, $3C, $00, $00, $00, $00, $00, $00, $00, $C0, $60, $00, $00, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $A0
    .byte $73, $10, $00, $00, $00, $00, $00, $00, $15, $3A, $80, $00, $00, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $E0
    .byte $08, $18, $00, $00, $00, $00, $00, $00, $02, $F6, $00, $00, $00, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $E0
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $17, $B6, $00, $00, $00, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $02, $ED, $80, $00, $00, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $05, $2C, $00, $00, $00, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $20, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $02, $B0, $80, $00, $00, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $70, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $7F, $FF, $00, $00, $00, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $78, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $40, $00, $00, $00, $7F, $FF, $80, $00, $00, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $40, $00, $00, $00, $7F, $FF, $C0, $00, $00, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $7F, $FF, $80, $00, $00, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $7F, $FF, $80, $00, $00, $00, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $7F, $FF, $80, $00, $00, $00, $7F, $FF
    .byte $FF, $F7, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $7F, $FF
    .byte $FF, $F7, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $7F, $FF
    .byte $FF, $F7, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $7F, $FF
    .byte $FF, $F7, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $7F, $FF
    .byte $FF, $F7, $FF, $FF, $3C, $FF, $F3, $3F, $FF, $CF, $9F, $FF, $FF, $FF, $03, $FF
    .byte $CC, $FF, $FF, $F3, $FF, $FF, $F8, $1F, $FE, $0F, $FF, $8F, $FF, $FF, $7F, $FF
    .byte $FF, $F7, $FF, $FF, $18, $FF, $F3, $3F, $FF, $CF, $FF, $FF, $FF, $FF, $CF, $FF
    .byte $CC, $FF, $FF, $FF, $FF, $FF, $FE, $7F, $FE, $7F, $FF, $CF, $FF, $FF, $7F, $FF
    .byte $FF, $F7, $FF, $FF, $00, $FF, $F3, $31, $9E, $49, $10, $E1, $FF, $FF, $CF, $FF
    .byte $CC, $C6, $08, $23, $0F, $FF, $FE, $7F, $FE, $7C, $60, $CC, $70, $FF, $7F, $FF
    .byte $FF, $F7, $FF, $FF, $24, $FF, $F0, $3C, $C0, $C3, $92, $4F, $FF, $FF, $CF, $FF
    .byte $C0, $F2, $38, $F2, $7F, $FF, $FE, $7F, $FE, $1F, $23, $C9, $27, $FF, $7F, $FF
    .byte $FF, $F7, $FF, $FF, $3C, $FF, $F3, $30, $C0, $C7, $92, $63, $FF, $FF, $CF, $FF
    .byte $CC, $C2, $79, $F3, $1F, $FF, $FE, $7F, $FE, $7C, $27, $C8, $31, $FF, $7F, $FF
    .byte $FF, $F7, $FF, $FF, $3C, $FF, $F3, $24, $E1, $C3, $92, $79, $FF, $FF, $CF, $FF
    .byte $CC, $92, $79, $F3, $CF, $FF, $FE, $7F, $FE, $79, $27, $C9, $FC, $FF, $7F, $FF
    .byte $FF, $F7, $FF, $FF, $3C, $9F, $F3, $30, $E1, $C9, $92, $43, $FF, $FF, $CE, $7F
    .byte $CC, $C2, $79, $F2, $1F, $FF, $FE, $73, $FE, $0C, $27, $CC, $61, $FF, $7F, $FF
    .byte $FF, $F7, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $7F, $FF
    .byte $FF, $F7, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $7F, $FF
    .byte $FF, $F7, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $7F, $FF
    .byte $FF, $F7, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $7F, $FF
    .byte $FF, $F7, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $7F, $FF
    .byte $FF, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $7F, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF

;; Room past the picture, which nothing uses.
AUTHPIC_END:
    .byte $FF, $00, $00, $A0, $27, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $EF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $00, $00, $40, $00
    .byte $00, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF

; ----------------------------------------------------------------------------------------------------------------
; Super Extended Color BASIC
; ----------------------------------------------------------------------------------------------------------------

;; The addresses Tandy documents for programs: where Super Extended BASIC's direct page variables start, then the
;; routines that set the video for text or graphics, load the MMU, map the text screen or a block in, and pick a
;; task; then a jump that starts a ROM pack by hand, for EXEC &HE010.
SUPERVAR:
    .dbyt HRMODE                    ; HRMODE and HRWIDTH

;; Inherit: <SUPERVAR>
PRGTEXT:
    .dbyt SETTEXT

;; Inherit: <SUPERVAR>
PRGGRAPH:
    .dbyt SETGRAPH

;; Inherit: <SUPERVAR>
PRGMMU:
    .dbyt SETMMU

;; Inherit: <SUPERVAR>
GETTEXT:
    .dbyt SELTEXT

;; Inherit: <SUPERVAR>
GETBLOK0:
    .dbyt SELBLOK0

;; Inherit: <SUPERVAR>
GETTASK0:
    .dbyt SELTASK0

;; Inherit: <SUPERVAR>
GETTASK1:
    .dbyt SELTASK1

;; Inherit: <SUPERVAR>
EXECCARTVEC:
    JMP EXECCART

;; Three spare entries, never filled in.
SPARE0:
    .dbyt $0000
    .dbyt $0000
    .dbyt $0000

;; Sets the video for the text screen <HRWIDTH> chooses: the 32-column screen, or 40 or 80 columns.
;;
;; Keeps: A, X, Y
SETTEXT:
    PSHS Y,X,A
    LBRN RAMLINK                    ; the hook, never taken
    LDX #IM_TEXT
    LDA HRWIDTH
    BEQ SETVIDEO
    LDX #IM_TEXT40
    CMPA #$01
    BEQ SETVIDEO
    LDX #IM_TEXT80
    BRA SETVIDEO

;; The video's images for the three text screens, each INIT0's then $FF98-$FF9F's, for <SETVIDEO>: the 32-column
;; CoCo compatible screen, then 40 and 80 columns with attributes, from block $36 (<BLOCK6_6>).
IM_TEXT:
    .byte COCO+MMUEN+MC3+MC2
    .byte $00, $00, $00, $00, $0F, $E0
    .byte $00, $00
IM_TEXT40:
    .byte MMUEN+MC3+MC2
    .byte $03, $05, $12, $00, $00, $D8
    .byte $00, $00
IM_TEXT80:
    .byte MMUEN+MC3+MC2
    .byte $03, $15, $12, $00, $00, $D8
    .byte $00, $00

;; Sets the video for the hi-res graphics mode <HRMODE> chooses, putting its resolution from <RESTABLE> in the
;; image first: modes 1 and 2 are 320 pixels across, 3 and 4 are 640.
;;
;; Keeps: A, X, Y
SETGRAPH:
    PSHS Y,X,A
    LBRN RAMLINK                    ; the hook, never taken
    LDX #IM_GRAPH
    LDY #RESTABLE
    LDA HRMODE
    CMPA #$02
    BLS SETGRAPH_MODE
    LDX #IM_GRAPH640
SETGRAPH_MODE:
    SUBA #$01                       ; modes from 0
    LDA A,Y
    STA 2,X
    JMP SETVIDEO

;; The resolution register's value, $FF99, for each HSCREEN mode: 320x192 in 4 and 16 colors, and 640x192 in 2 and
;; 4 colors.
RESTABLE:
    .byte $15
    .byte $1E
    .byte $14
    .byte $1D

;; The video's images for the graphics screens, for <SETVIDEO>: 320 pixels across, then 640, each with the screen
;; at block $30 (<BLOCK6_0>).
IM_GRAPH:
    .byte MMUEN+MC3+MC2
    .byte $80, $00, $00, $00, $00, $C0
    .byte $00, $00
IM_GRAPH640:
    .byte MMUEN+MC3+MC2
    .byte $80, $00, $00, $00, $00, $C0
    .byte $00, $00

;; Loads INIT0 and the video registers, $FF98-$FF9F, from an image, then returns to <SETTEXT>'s or
;; <SETGRAPH>'s caller.
;;
;; In:   X = the image, nine bytes
SETVIDEO:
    LDA ,X+
    STA INIT0
    LDY #VIDEOREG
SETVIDEO_LOOP:
    LDA ,X+
    STA ,Y+
    CMPY #MMUREG
    BCS SETVIDEO_LOOP
    PULS A,X,Y,PC

;; Loads the MMU's registers from <IM_MMU>, BASIC's mapping.
;;
;; Keeps: A, B, X, Y
SETMMU:
    PSHS Y,X,B,A
    LEAX >IM_MMU,PCR
    BSR LOADMMU
    PULS A,B,X,Y,PC

;; Maps a block at $0000-$1FFF, as task 0 and the MMU's image say from now on until the next change, then puts
;; <BLOCK7_0> back in the image, so the next load puts BASIC's own back.
;;
;; In:   B = the block
;; Keeps: A, B, X, Y
SELBLOK0:
    PSHS Y,X,B,A
    LEAX >IM_MMU,PCR
    PSHS X
    STB ,X
    BSR LOADMMU
    LDB #BLOCK7_0
    PULS X
    STB ,X
    PULS A,B,X,Y,PC

;; Maps the hi-res text screen, block $36, at $2000-$3FFF, then puts BASIC's own block back in the MMU's image,
;; so the next load maps it again.
;;
;; Keeps: A, B, X, Y
SELTEXT:
    PSHS Y,X,B,A
    LEAX >IM_MMU,PCR
    PSHS X
    LDB #BLOCK6_6
    STB 1,X
    BSR LOADMMU
    PULS X
    LDB #BLOCK7_1
    STB 1,X
    PULS A,B,X,Y,PC

;; Maps the HGET and HPUT buffers' block, $34, at $C000-$DFFF in task 1, then puts task 1's stack block back in
;; the MMU's image.
;;
;; Keeps: A, B, X, Y
SELBUFF:
    PSHS Y,X,B,A
    LEAX >IM_MMU,PCR
    PSHS X
    LDB #BLOCK6_4
    STB 14,X
    BSR LOADMMU
    PULS X
    LDB #BLOCK6_5
    STB 14,X
    PULS A,B,X,Y,PC

;; The image of the MMU's registers that BASIC keeps: task 0, BASIC's 64K, then task 1, the hi-res graphics screen
;; at $2000-$9FFF and its stack block at $C000.
IM_MMU:
    .byte BLOCK7_0, BLOCK7_1, BLOCK7_2, BLOCK7_3, BLOCK7_4, BLOCK7_5, BLOCK7_6, BLOCK7_7
    .byte BLOCK7_0, BLOCK6_0, BLOCK6_1, BLOCK6_2, BLOCK6_3, BLOCK7_5, BLOCK6_5, BLOCK7_7

;; Loads the MMU's sixteen registers.
;;
;; In:   X = the image
LOADMMU:
    LDY #MMUREG
    LDB #16
LOADMMU_LOOP:
    LDA ,X+
    STA ,Y+
    DECB
    BNE LOADMMU_LOOP
    RTS

;; Goes back to task 0, BASIC's map, from task 1, and to BASIC's stack, which <SELTASK1> left under the return
;; address on the stack, then lets interrupts in again.
;;
;; Keeps: D, X, Y, U
SELTASK0:
    STD V40
    LDD ,S
    STD V42
    LDD 2,S
    STD V44
    CLRB                            ; task 0, and the timer's slow clock
    STB INIT1
    LDS V44
    LDD V42
    PSHS B,A
    LDD V40
    ANDCC #$AF
    RTS

;; Goes to task 1, the hi-res graphics screen's map, with interrupts off: the stack moves to <TMPSTACK>, in task
;; 1's own block, with BASIC's stack pointer under the return address for <SELTASK0>.
;;
;; Keeps: D, X, Y, U
SELTASK1:
    ORCC #$50
    STD V40
    PULS A,B                        ; the return address
    STD V42
    STS V44
    LDB #$01                        ; task 1
    STB INIT1
    LDS #TMPSTACK
    LDD V44
    PSHS B,A
    LDD V42
    PSHS B,A
    LDD V40
    RTS

;; Crunching a line, after Extended BASIC's words and before Disk BASIC's: the patch at <CRUNCH_FUNCTIONS> comes
;; here, so Super Extended BASIC's words, from <EBCOMTAB>, crunch to their tokens, $E2 and up for commands and
;; $A8 and up for functions.
;;
;; In:   U = the table being searched, V41 = nonzero while functions are searched, V42 = the tokens so far
CRUNCH20:
    TST V41
    BNE CRUNCH20_FUNCTIONS
    LDA V42
    CMPA #$62                       ; past Disk BASIC's commands?
    BLS CRUNCH20_COMMANDS
    LDU #COMVEC-5                   ; the next table as Color BASIC goes on
    JMP CRUNCH_SEARCH
CRUNCH20_COMMANDS:
    LDA #$62                        ; Super Extended BASIC's first command
    LDU #EBCOMTAB-10
CRUNCH20_SEARCH:
    STA V42
    JMP CRUNCH_TABLE
CRUNCH20_FUNCTIONS:
    LDA V42
    CMPA #$29                       ; past Disk BASIC's functions?
    BLS CRUNCH20_OURS
    JMP CRUNCH_SEARCH
CRUNCH20_OURS:
    LDA #$29                        ; Super Extended BASIC's first function
    LDU #EBCOMTAB-5
    BRA CRUNCH20_SEARCH

;; Super Extended BASIC's command table, as <COMVEC> holds each ROM's: its 23 commands, their words and the routine
;; that runs them, then its 5 functions, their words and routine, then an empty table, which ends the search.
EBCOMTAB:
    .byte 23
    .dbyt COMDIC20
    .dbyt XCOMMAND20
    .byte 5
    .dbyt FUNDIC20
    .dbyt XFUNCTION20
EBCOMTAB_END:
    .byte $00, $00, $00, $00, $00, $00

;; Listing a line: the patch at <DETOK_TABLE> comes here, so tokens past Disk BASIC's are found in Super Extended
;; BASIC's table, <EBCOMTAB>.
;;
;; In:   U = the table before the next, A = the token, less $80, X = past the token
DETOK20:
    LEAU 10,U
    TST ,U
    LBNE DETOK_FIND                 ; another ROM's table: go on there
    LEAX -1,X                       ; the token again
    LDA ,X+
    ANDA #$7F
    CMPA #$62                       ; below Super Extended BASIC's?
    BCS DETOK20_FUNCTION
    SUBA #$62
    LDU #EBCOMTAB-10
    BRA DETOK20
DETOK20_FUNCTION:
    SUBA #$29                       ; a function: Super Extended BASIC's from 0
    LDU #EBCOMTAB-5
    BRA DETOK20

;; Extended BASIC's command dispatch: the patch at <XCOMMAND_DISK> comes here, so tokens $E2 to $F8 run Super
;; Extended BASIC's commands, through <COMDIS20>, and the rest go to Disk BASIC's.
;;
;; In:   A = the token
XCOMMAND20:
    CMPA #$E2
    BCS XCOMMAND20_DISK
    CMPA #$F8
    BLS XCOMMAND20_OURS
XCOMMAND20_DISK:
    JMP [COMVEC+23]
XCOMMAND20_OURS:
    SUBA #$E2
    LDX #COMDIS20
    JMP GONE_DISPATCH

;; Extended BASIC's function dispatch: the patch at <XFUNCTION_DISK> comes here, so function tokens $A8 to $AC run
;; Super Extended BASIC's functions, through <FUNDIS20>, and the rest go to Disk BASIC's. LPEEK, BUTTON and HPOINT
;; take an argument in parentheses first.
;;
;; In:   B = the token, less $80, times 2
XFUNCTION20:
    CMPB #$52
    BCS XFUNCTION20_DISK
    CMPB #$5A
    BLS XFUNCTION20_OURS
XFUNCTION20_DISK:
    JMP [COMVEC+28]
XFUNCTION20_OURS:
    SUBB #$52
    CMPB #2*2                       ; ERNO and ERLIN take none
    BCC XFUNCTION20_RUN
    PSHS B
    JSR PARENS
    PULS B
XFUNCTION20_RUN:
    LDX #FUNDIS20
    JMP EVAL_FN_DISPATCH

;; Super Extended BASIC's command words, the tokens from $E2.
COMDIC20:
    KEYWORD "WIDTH"
    KEYWORD "PALETTE"
    KEYWORD "HSCREEN"
    KEYWORD "LPOKE"
    KEYWORD "HCLS"
    KEYWORD "HCOLOR"
    KEYWORD "HPAINT"
    KEYWORD "HCIRCLE"
    KEYWORD "HLINE"
    KEYWORD "HGET"
    KEYWORD "HPUT"
    KEYWORD "HBUFF"
    KEYWORD "HPRINT"
    KEYWORD "ERR"
    KEYWORD "BRK"
    KEYWORD "LOCATE"
    KEYWORD "HSTAT"
    KEYWORD "HSET"
    KEYWORD "HRESET"
    KEYWORD "HDRAW"
    KEYWORD "CMP"
    KEYWORD "RGB"
    KEYWORD "ATTR"

;; The routines that run Super Extended BASIC's commands, in token order.
COMDIS20:
    .dbyt WIDTH
    .dbyt PALETTE
    .dbyt HSCREEN
    .dbyt LPOKE
    .dbyt HCLS
    .dbyt HCOLOR
    .dbyt HPAINT
    .dbyt HCIRCLE
    .dbyt HLINE
    .dbyt HGET
    .dbyt HPUT
    .dbyt HBUFF
    .dbyt HPRINT
    .dbyt ERR
    .dbyt BRK
    .dbyt LOCATE
    .dbyt HSTAT
    .dbyt HSET
    .dbyt HRESET
    .dbyt HDRAW
    .dbyt CMP
    .dbyt RGB
    .dbyt ATTR

;; Super Extended BASIC's function words, the tokens $FF then $A8 on.
FUNDIC20:
    KEYWORD "LPEEK"
    KEYWORD "BUTTON"
    KEYWORD "HPOINT"
    KEYWORD "ERNO"
    KEYWORD "ERLIN"

;; The routines that run Super Extended BASIC's functions, in token order.
FUNDIS20:
    .dbyt LPEEK
    .dbyt BUTTON
    .dbyt HPOINT
    .dbyt ERNO
    .dbyt ERLIN

;; Extended BASIC's sign-on: the patch at <XBINIT_SIGNON> comes here, so Microware's copyright follows Tandy's.
XSIGNON20:
    LDX #XSIGNON-1
    JSR STROUT1
    LDX #MWAREMS-1
    JSR STROUT1
    JMP XBINIT_RSTVEC               ; back in the cold start, past its sign-on

;; Disk BASIC 1.0's sign-on, patched by <DSKPATCH>: Disk BASIC 2.0's message instead.
DISK20SIGNON:
    LDX #DISK20MS-1
    JMP DSKSIGNON10+3

;; Disk BASIC 1.1's sign-on, patched by <DSKPATCH>: Disk BASIC 2.1's message instead.
DISK21SIGNON:
    LDX #MWAREMS+27+2
    JMP DSKSIGNON11+3

;; Disk BASIC 2.0's sign-on, which ends with Microware's copyright, <MWAREMS>.
DISK20MS:
    .byte "DISK EXTENDED COLOR BASIC 2.0"
    .byte $0D
    .byte "COPR. 1981, 1986 BY TANDY"
    .byte $0D
    .byte "UNDER LICENSE FROM MICROSOFT"
    .byte $0D

;; Microware's copyright, which Extended and Disk BASIC's sign-ons end with.
MWAREMS:
    .byte "AND MICROWARE SYSTEMS CORP."
    .byte $0D, $0D, $00

;; Disk BASIC 2.1's sign-on.
DISK21MS:
    .byte "DISK EXTENDED COLOR BASIC 2.1"
    .byte $0D
    .byte "COPR. 1982, 1986 BY TANDY"
    .byte $0D
    .byte "UNDER LICENSE FROM MICROSOFT"
    .byte $0D
    .byte "AND MICROWARE SYSTEMS CORP."
    .byte $0D, $0D, $00

;; The end of Extended BASIC's GRINIT: the patch at <GRINIT_END> comes here, so a cold start or NEW also resets
;; Super Extended BASIC: no hi-res screens, ON ERR and ON BRK off, HCOLOR's colors 1 on 0, and no HGET and HPUT
;; buffers. Then it erases the program, as GRINIT did.
GRINIT20:
    CLRA
    CLRB
    LBRN RAMLINK                    ; the hook, never taken
    STB H_CRSATT                    ; no attributes
    STD HRMODE                      ; no hi-res graphics or text
    STD H_ONBRK                     ; no ON BRK
    STD H_ONERR                     ; no ON ERR
    STA H_BCOLOR
    LDA #$01
    STA H_FCOLOR
    LDA #BLOCK6_4                   ; the buffers' block at $0000 for a moment
    STA MMUREG
    LDD #$FFFF                      ; no buffers: the first header's link is $FFFF
    STD $0
    LDA #BLOCK7_0                   ; BASIC's own block back
    STA MMUREG
    JMP ERASEP                      ; the rest of NEW

;; ON: the patch at <ON> comes here, so ON ERR GOTO and ON BRK GOTO go to <ERR> and <BRK>, and anything else goes on
;; as ON n GOTO or GOSUB does.
ON20:
    CMPA #TK_ERR
    BEQ ERR
    CMPA #TK_BRK
    BEQ BRK
    JSR GETBYT                      ; n
    JMP ON_GO

;; Reads GO TO after ON ERR or ON BRK, or raises ?SN ERROR from the caller's caller.
ONGOTO:
    JSR GETNCH
    CMPA #TK_GO
    BNE ONGOTO_SN
    JSR GETNCH
    CMPA #TK_TO
    BNE ONGOTO_SN
    RTS
ONGOTO_SN:
    LEAS 2,S                        ; return past ERR or BRK
    JMP SNERR

;; Runs ON ERR GOTO line: keeps the line to go to when an error happens, and the line the statement is in.
ERR:
    BSR ONGOTO
    JSR GETNCH
    JSR LINGET                      ; the line number, into BINVAL
    LDD BINVAL
    STD H_ONERR
    LDD CURLIN
    STD H_ONERRS
    RTS

;; Runs ON BRK GOTO line: keeps the line to go to when BREAK is pressed, and the line the statement is in.
BRK:
    BSR ONGOTO
    JSR GETNCH
    JSR LINGET
    LDD BINVAL
    STD H_ONBRK
    LDD CURLIN
    STD H_ONBRKS
    RTS

;; Shifts the &H or &O number being read left a digit's bits and adds the digit, as <HEXOCT_SHIFT> did but in
;; three bytes, for LPEEK and LPOKE's addresses: the patch at <HEXOCT_SHIFT> comes here.
;;
;; In:   A = the digit's character, B = its bits, X = the value, three bytes
;; Errors: ?OV ERROR past 24 bits
HEXSHIFT:
    LSL 2,X
    ROL 1,X
    ROL ,X
    LBCS OVERR
    DECB
    BNE HEXSHIFT
    SUBA #'0'
    ADDA 2,X
    STA 2,X
    RTS

;; The octal digits' loop, which the patch at <HEXOCT_OCTAL_CHECK> sends here: a digit goes on to
;; <HEXOCT_OCTAL_DIGIT>, and anything else ends the number with its top byte cleared.
HEXOCTAL:
    LBCS HEXOCT_OCTAL_DIGIT         ; a digit
    JMP HEXPATCH_TOP

;; BREAK while a line is typed: the patch at <LINEIN_BREAK> comes here, to put the text screen back first when a
;; hi-res graphics screen shows.
;;
;; In:   A = the key
;; Out:  carry = set
LINEBRK20:
    CMPA #$03                       ; BREAK?
    ORCC #$01
    BNE LINEBRK20_DONE
    PSHS A,CC
    LDA HRMODE
    BEQ LINEBRK20_TEXT
    CLR HRMODE
    JSR SETTEXT
LINEBRK20_TEXT:
    PULS CC,A
LINEBRK20_DONE:
    JMP LINEIN_BRKDONE

;; BREAK during a program: the patch at <ISCNTC_KEY> comes here. With ON BRK set it goes to that line, and otherwise
;; it puts the text screen back and stops, as STOP does.
;;
;; In:   A = the key
BREAK20:
    CMPA #$03
    BEQ BREAK20_STOP                ; BREAK?
    JMP ISCNTC_NOTBRK
BREAK20_STOP:
    LDA #$01                        ; a break, not an error
    STA H_ERRBRK
    LDA CURLIN                      ; in direct mode?
    INCA
    BEQ BREAK20_TEXT
    LDD H_ONBRK                     ; ON BRK set?
    BNE ONTRAP
BREAK20_TEXT:
    LDA HRMODE
    BEQ BREAK20_END
    JSR SETTEXT
BREAK20_END:
    JMP STOP

;; Goes to the line that ON ERR or ON BRK named, as GOTO does. For an error the stack is reset and the interpreter
;; loop returns to; a missing line raises ?UL ERROR from <ONTRAP_UL>.
;;
;; In:   D = the line, H_ERRBRK = nonzero for BREAK
ONTRAP:
    STD BINVAL
    TST H_ERRBRK                    ; BREAK keeps the stack
    BNE ONTRAP_FIND
    LDS FRETOP                      ; an error: a fresh stack, which returns to the interpreter's loop
    LDD #GONE_LOOP
    PSHS B,A
ONTRAP_FIND:
    JSR SKPLIN                      ; past this line's end
    LEAX 1,X
    LDD BINVAL
    CMPD CURLIN                     ; at or before this line: search from the start
    BHI ONTRAP_SEARCH
    LDX TXTTAB
ONTRAP_SEARCH:
    JSR FINDLN_NEXT
    LBCS ONTRAP_UL
    JMP SETPTR                      ; go there

;; Errors: the patch at <ERROR> comes here. With ON ERR set and a program running, the error's code and line are
;; kept and the program goes on at ON ERR's line. Otherwise the text screen comes back and the error shows, with ?HR
;; and ?HP for Super Extended BASIC's errors, which Color BASIC has no letters for.
;;
;; In:   B = the error's code
ERROR20:
    CLR H_ERRBRK
    LDA CURLIN                      ; in direct mode?
    INCA
    BEQ ERROR20_SHOW
    LDX H_ONERR                     ; ON ERR set?
    BNE ERROR20_TRAP
ERROR20_SHOW:
    PSHS A
    LDA HRMODE
    PULS A
    BEQ ERROR20_HR
    JSR SETTEXT
ERROR20_HR:
    CMPB #ERR_HR
    BNE ERROR20_HP
    JSR NEWLIN                      ; a new line
    JSR OUTQST
    LEAX >BAS20ERR,PCR
ERROR20_CODE:
    JSR ERRCHR                      ; the code's two letters
    JSR ERRCHR
    JMP ERROR_MESSAGE               ; on, as ERROR does after the code
ERROR20_HP:
    CMPB #ERR_HP
    BNE ERROR20_OTHER
    JSR NEWLIN
    JSR OUTQST
    LEAX >BAS20ERR+2,PCR
    JMP ERROR20_CODE
ERROR20_OTHER:
    JMP ERROR_HOOKED                ; the rest of ERROR
ERROR20_TRAP:
    STB H_ERROR
    PSHS B
    LDD CURLIN
    STD H_ERLINE
    PULS B
    CMPB #ERR_OD
    BNE ERROR20_GO
    LDD BINVAL                      ; READ kept its place in the program there
    STD CHARAD
ERROR20_GO:
    TFR X,D                         ; ON ERR's line
    LBRA ONTRAP

;; The letters of Super Extended BASIC's errors: HR, then HP.
BAS20ERR:
    .byte "HR"
    .byte "HP"

;; Resetting the stack, for NEW, RUN and CLEAR: the patch at <RSTSTK_OLDPTR> comes here, so ON ERR and ON BRK go
;; off and ERNO and ERLIN show no error.
;;
;; Keeps: D
RSTSTK20:
    PSHS B,A
    CLRA
    CLRB
    STD OLDPTR                      ; CONT cannot continue
    STD H_ONBRK
    STD H_ONERR
    STD H_ERLINE
    LDA #$FF                        ; no error
    STA H_ERROR
    PULS A,B
    JMP RSTSTK_ARYDIS               ; the rest of RSTSTK

;; Returns ERNO: the number of the last error ON ERR caught, or -1 for none.
ERNO:
    CLRA
    LDB H_ERROR
    CMPB #$FF
    BNE ERNO_NUMBER
    SEX
    BRA ERNO_GIVE
ERNO_NUMBER:
    CMPB #$F1                       ; ?UL ERROR's code complemented?
    BNE ERNO_HALF
    COMB                            ; then 7, an undefined line
ERNO_HALF:
    ASRB                            ; the code, halved, is the number
ERNO_GIVE:
    JMP GIVABF

;; Returns ERLIN: the line the last error ON ERR caught was in.
ERLIN:
    LDD H_ERLINE
    BRA ERNO_GIVE

;; The OK prompt: the patch at <OKPRMT> comes here, so the prompt shows on the text screen WIDTH chose, and HGET and
;; HPUT's buffers are emptied, as their block may have changed.
OKPRMT20:
    JSR SETTEXT
    JSR NEWLIN                      ; a new line
    ORCC #$50
    LDA #BLOCK6_4                   ; the buffers' block at $0000 for a moment
    STA MMUREG
    LDD #$FFFF                      ; no buffers
    STD 0
    LDA #BLOCK7_0                   ; BASIC's own block back
    STA MMUREG
    ANDCC #$AF
    JMP OKPRMT_OK                   ; the rest of the prompt

;; ON ERR or ON BRK's line is missing: raises ?UL ERROR in the line that set the trap.
ONTRAP_UL:
    TST H_ERRBRK
    BEQ ONTRAP_ERRLINE
    LDD H_ONBRKS
    BRA ONTRAP_LINE
ONTRAP_ERRLINE:
    LDD H_ONERRS
ONTRAP_LINE:
    STD CURLIN
    LDB #ERR_UL
    JMP ERROR_HOOKED                ; ERROR past its hook, so ON ERR cannot catch it

;; BREAK during INPUT: the patch in <INPLIN_BREAK> comes here, so with ON BRK set the program goes on at that line,
;; and otherwise stops as before.
INPUTBRK20:
    LDD H_ONBRK
    LBEQ STOPIT                     ; no ON BRK: stop
    PSHS B,A
    LDA #$01
    STA H_ERRBRK
    PULS A,B
    LBRA ONTRAP

;; Runs LPOKE address,value: stores a byte anywhere in the 512K the MMU reaches, the address from 0 to $7FFFF.
;;
;; Errors: ?FC ERROR past 512K
LPOKE:
    JSR FRMNUM
    LBRN RAMLINK                    ; the hook, never taken
    BSR LONGADR                     ; into a block and an offset
    CMPB #BLOCK7_7                  ; past the last block?
    LBHI FCERR
    PSHS X,B
    JSR SYNCOM
    JSR GETBYT
    TFR B,A                         ; the value
    PULS B,X
    CMPB #BLOCK7_7
    LBHI FCERR
    ORCC #$50                       ; no interrupts while BASIC's map is changed
    LBSR SELBLOK0                   ; the block at $0000
    STA ,X
    LBSR SETMMU                     ; BASIC's map back
    ANDCC #$AF
    RTS

;; Returns LPEEK(address): the byte anywhere in the 512K the MMU reaches.
;;
;; Errors: ?FC ERROR past 512K
LPEEK:
    BSR LONGADR
    LBRN RAMLINK                    ; the hook, never taken
    CMPB #BLOCK7_7
    LBHI FCERR
    ORCC #$50
    LBSR SELBLOK0
    LDB ,X
    LBSR SETMMU
    ANDCC #$AF
    JMP GIVB

;; Splits FPA0, an address in the 512K the MMU reaches, into an 8K block and an offset in it.
;;
;; Out:  B = the block, past the last when the address is past 512K; X = the offset, 0 to $1FFF
;; Keeps: A
LONGADR:
    PSHS A
    LDA FP0EXP
    CMPA #$93                       ; past 2^19?
    BLS LONGADR_SPLIT
    LDB #BLOCK7_7+1
    BRA LONGADR_DONE
LONGADR_SPLIT:
    JSR QINT                        ; an integer
    LDD FPA0+2
    ANDA #$1F
    TFR D,X
    LDD FPA0+1                      ; the bits above the offset's 13
    ASRA
    RORB
    ASRA
    RORB
    ASRA
    RORB
    ASRA
    RORB
    ASRA
    RORB
LONGADR_DONE:
    PULS A,PC

;; Returns BUTTON(n): 1 while a joystick button is down, else 0. n is 0 for the right joystick's first button, 1
;; the left's, 2 the right's second, 3 the left's second.
;;
;; Errors: ?FC ERROR past 3
BUTTON:
    JSR INTCNV
    LBRN RAMLINK                    ; the hook, never taken
    CMPB #$03
    LBHI FCERR
    TFR B,A
    CLRB
    COMB
    LDX #PIA0
    STB 2,X                         ; no column strobed: only the buttons pull rows down
    LDB ,X
    CMPB #$0F                       ; none down?
    BEQ BUTTON_UP
    LEAX >BUTTON_TESTS,PCR
    ASLA                            ; four bytes to each test
    ASLA
    JMP A,X
BUTTON_TESTS:
    ANDB #$01
    BRA BUTTON_TEST
    ANDB #$04
    BRA BUTTON_TEST
    ANDB #$02
    BRA BUTTON_TEST
    ANDB #$08
BUTTON_TEST:
    BNE BUTTON_UP
    LDD #1                          ; down
    BRA BUTTON_GIVE
BUTTON_UP:
    CLRA
    CLRB
BUTTON_GIVE:
    JSR GIVABF
    RTS

;; Runs PALETTE: PALETTE RGB or PALETTE CMP sets all sixteen registers to the colors for an RGB or composite
;; monitor, and PALETTE n,color sets one, from 0 to 63. A change waits for an interrupt, so the screen does not
;; flash.
;;
;; Errors: ?FC ERROR for a register past 15
PALETTE:
    CMPA #TK_RGB
    LBRN RAMLINK                    ; the hook, never taken
    BNE PALETTE_CMP
    JSR GETNCH
PALETTE_RGB:
    LEAX >IM_RGB,PCR
    BRA PALETTE_ALL
PALETTE_CMP:
    CMPA #TK_CMP
    BNE PALETTE_ONE
    JSR GETNCH
PALETTE_CMPSET:
    LEAX >IM_CMP,PCR
    BRA PALETTE_ALL
PALETTE_ONE:
    JSR HGETXYS                     ; the register and the color
    LDX #PALETREG
    LDY #IM_PALET
    LDA BINVAL+1
    CMPA #16
    LBCC FCERR
    LEAX A,X
    LEAY A,Y
    LDB VERBEG+1
    CMPB #63                        ; past 63?
    BLS PALETTE_SET
    LDB #63                         ; then 63
PALETTE_SET:
    ORCC #$50
    SYNC                            ; an interrupt first: the change comes during the border
    STB ,X
    STB ,Y
    ANDCC #$AF
    RTS

;; Sets all sixteen palette registers, and their image <IM_PALET>, from a table, after an interrupt.
;;
;; In:   X = the table
PALETTE_ALL:
    PSHS X
    LDY #IM_PALET
    BSR PALETTE_COPY
    PULS X
    LDY #PALETREG
    ORCC #$50
    SYNC
    BSR PALETTE_COPY
    RTS

;; Copies the palette from X to Y, then lets interrupts in again; it copies only the first fifteen.
;;
;; In:   X = from, Y = to
PALETTE_COPY:
    LDB #16-1                       ; one short of the sixteen
PALETTE_COPYLOOP:
    LDA ,X+
    STA ,Y+
    DECB
    BNE PALETTE_COPYLOOP
    ANDCC #$AF
    RTS

;; The palette for a composite monitor, which PALETTE CMP sets: the colors a CoCo 2 shows.
IM_CMP:
    .byte 18, 36, 11, 7, 63, 31
    .byte 9, 38, 0, 18, 0, 63
    .byte 0, 18, 0, 38

;; The palette for an RGB monitor, which PALETTE RGB sets.
IM_RGB:
    .byte 18, 54, 9, 36, 63, 27
    .byte 45, 38, 0, 18, 0, 63
    .byte 0, 18, 0, 38

;; Runs RGB: sets the palette for an RGB monitor, as PALETTE RGB does.
RGB:
    BRA PALETTE_RGB

;; Runs CMP: sets the palette for a composite monitor, as PALETTE CMP does.
CMP:
    BRA PALETTE_CMPSET

;; The palette registers' image, which BASIC keeps since they cannot be read back.
IM_PALET:
    .byte 18, 36, 11, 7, 63, 31
    .byte 9, 38, 0, 18, 0, 63
    .byte 0, 18, 0, 38

;; Runs HSCREEN [mode]: 0, or none, shows the text screen again; 1 to 4 show the hi-res graphics screen, 320x192 in
;; 4 or 16 colors or 640x192 in 2 or 4, cleared to the background color, with the default point at its center.
;;
;; Errors: ?FC ERROR past 4
HSCREEN:
    CMPA #$00                       ; the statement's end?
    LBRN RAMLINK                    ; the hook, never taken
    BNE HSCREEN_MODE
    CLRB
    BRA HSCREEN_SET
HSCREEN_MODE:
    JSR GETBYT
    CMPB #$04
    LBHI FCERR
HSCREEN_SET:
    STB HRMODE
    CMPB #$00
    BNE HSCREEN_GRAPH
    JMP SETTEXT
HSCREEN_GRAPH:
    STB HRMODE
    LDX #HORBYTTAB
    SUBB #$01                       ; modes from 0
    LDA B,X
    STA HORBYT
    CMPB #$01                       ; 320 across?
    BGT HSCREEN_640
    LDD #160
    BRA HSCREEN_CENTER
HSCREEN_640:
    LDD #320
HSCREEN_CENTER:
    STD HORDEF
    LDD #96
    STD VERDEF
    LDB H_BCOLOR
    BSR CLRHIRES
    JMP SETGRAPH

;; The bytes in a row of the hi-res graphics screen, for each HSCREEN mode.
HORBYTTAB:
    .byte 80, 160, 80, 160

;; Runs HCLS [color]: clears the hi-res graphics screen to a color, or to the background color.
;;
;; Errors: ?HR ERROR with no hi-res graphics screen; ?FC ERROR past color 15
HCLS:
    BNE HCLS_COLOR
    LDB H_BCOLOR
    BRA CLRHIRES
HCLS_COLOR:
    BSR HCOLORARG

;; Clears the hi-res graphics screen to a color.
;;
;; In:   B = the color
;; Errors: ?HR ERROR with no hi-res graphics screen
CLRHIRES:
    TST HRMODE
    BEQ HRERR
    BSR PIXELFIL                    ; the color in every pixel of a byte
    JSR SELTASK1
    LDX #HRESSCRN
CLRHIRES_LOOP:
    STB ,X+
    CMPX #HRESSCRN+$8000            ; the screen's 32K
    BNE CLRHIRES_LOOP
    JSR SELTASK0
    RTS

;; Raises ?HR ERROR: a hi-res graphics command with no HSCREEN.
HRERR:
    LDB #ERR_HR
    JMP ERROR

;; Runs HCOLOR [foreground][,background]: the colors, 0 to 15, hi-res graphics and HPRINT draw with.
;;
;; Errors: ?FC ERROR past 15
HCOLOR:
    CMPA #','
    LBRN RAMLINK                    ; the hook, never taken
    BEQ HCOLOR_BACK                 ; no foreground?
    BSR HCOLORARG
    STB H_FCOLOR
    JSR GETCCH
    BEQ HCOLOR_DONE
HCOLOR_BACK:
    JSR SYNCOM
    BSR HCOLORARG
    STB H_BCOLOR
HCOLOR_DONE:
    RTS

;; Reads a color, 0 to 15.
;;
;; Out:  B = the color
;; Errors: ?FC ERROR past 15
HCOLORARG:
    JSR GETBYT
HCOLORCHK:
    CMPB #16
    LBCC FCERR
    RTS

;; Reads the optional color after a command's coordinates and makes it the working color, or the foreground color
;; for HSET and the background for HRESET when there is none, as <GETCOLOR> does for Extended BASIC.
;;
;; Out:  A = the character after it
HGETCOLOR:
    JSR HSETWORK
    JSR GETCCH
    BEQ HGETCOLOR_DONE
    CMPA #')'
    BEQ HGETCOLOR_DONE
    JSR SYNCOM
    CMPA #','                       ; two commas: no color
    BEQ HGETCOLOR_DONE
    JSR HCOLORARG
    BSR HSETWORK_COLOR
HGETCOLOR_DONE:
    JMP GETCCH

;; Makes the foreground color, or the background for HRESET, the working color, as <SETWORK> does for Extended
;; BASIC.
;;
;; Out:  B = the working color in every pixel of a byte
HSETWORK:
    LDB H_FCOLOR
    TST SETFLG
    BNE HSETWORK_COLOR
    LDB H_BCOLOR
HSETWORK_COLOR:
    STB WCOLOR                      ; the color pixels are drawn in
    BSR PIXELFIL
    STB ALLCOL                      ; and a byte of it
    RTS

;; Repeats a color through a byte of the hi-res graphics screen: in each of its 8, 4 or 2 pixels, as the mode has.
;;
;; In:   B = the color
;; Out:  B = the byte
;; Keeps: X
PIXELFIL:
    PSHS X
    LDA HRMODE
    SUBA #$01
    LDX #PIXMASKTAB
    ANDB A,X                        ; the bits one pixel has
    LDA HRMODE                      ; again: A already holds this
    SUBA #$01
    LDX #PIXMULTAB
    LDA A,X
    MUL                             ; one copy of the color for each pixel
    PULS X,PC

;; The bits of a pixel's color in each HSCREEN mode.
PIXMASKTAB:
    .byte $03, $0F, $01, $03

;; What multiplies a pixel's color into every pixel of a byte, in each HSCREEN mode.
PIXMULTAB:
    .byte $55, $11, $FF, $55

;; Runs HSET(x,y[,color]): sets a pixel of the hi-res graphics screen, in the color given or the foreground color.
;;
;; Errors: ?HR ERROR with no hi-res graphics screen
HSET:
    LDA #$01
    BRA HSETRESET

;; Runs HRESET(x,y): sets a pixel of the hi-res graphics screen to the background color.
;;
;; Errors: ?HR ERROR with no hi-res graphics screen
HRESET:
    CLRA
    LBRN RAMLINK                    ; the hook, never taken
HSETRESET:
    TST HRMODE
    BEQ HRERR
    STA SETFLG                      ; 1 for HSET
    JSR SYNLPR
    JSR HGETXY
    TST SETFLG
    BNE HSETRESET_COLOR
    JSR HSETWORK
    BRA HSETRESET_PIXEL
HSETRESET_COLOR:
    JSR HGETCOLOR
HSETRESET_PIXEL:
    JSR SYNRPR
    JSR HCALPOS                     ; the pixel's byte and mask

;; Sets the pixel at <HORBEG> and <VERBEG> to the working color, in task 1.
;;
;; In:   A = the pixel's mask, X = its byte
HPIXSET:
    JSR SELTASK1
    JSR HPIXSET1
    JSR SELTASK0
    RTS

;; Sets a pixel to the working color, as <PIXSET> does for Extended BASIC, with task 1 mapped: <CHGFLG> becomes
;; nonzero when it changes.
;;
;; In:   A = the pixel's mask, X = its byte
HPIXSET1:
    LDB ,X
    PSHS B
    TFR A,B                         ; the mask
    COMA                            ; clear the pixel
    ANDA ,X
    ANDB ALLCOL                     ; the color in it
    PSHS B
    ORA ,S+
    STA ,X
    SUBA ,S+                        ; zero when nothing changed
    ORA CHGFLG
    STA CHGFLG
    RTS

;; Reads two coordinates into <HORBEG> and <VERBEG>, held to the screen's size.
;;
;; Out:  U = HORBEG
HGETXY:
    JSR HGETXYS
HGETXY_DONE:
    LDU #HORBEG

;; Where Extended BASIC scaled coordinates for the mode, which hi-res graphics do not need: it returns.
HNOSCALE:
    RTS
    RTS

;; Reads two coordinates and holds them to the screen's size: the vertical to 191, and the horizontal to 319 or
;; 639, as the mode has.
;;
;; Out:  Y = HORBEG, HORBEG and VERBEG = the coordinates
HGETXYS:
    JSR ADRBYT                      ; the horizontal in BINVAL, the vertical in B
    LDY #HORBEG

;; Holds coordinates to the hi-res graphics screen's size.
;;
;; In:   BINVAL = the horizontal, B = the vertical, Y = where they go
HLIMXY:
    CMPB #192
    BCS HLIMXY_V
    LDB #192-1
HLIMXY_V:
    CLRA
    STD 2,Y
    LDA HRMODE
    CMPA #$02
    BGT HLIMXY_640
    LDD #320-1
    BRA HLIMXY_H
HLIMXY_640:
    LDD #640-1
HLIMXY_H:
    CMPD BINVAL
    BCS HLIMXY_STORE
    LDD BINVAL
HLIMXY_STORE:
    STD ,Y
    RTS

;; Finds the byte and mask of the hi-res graphics screen's pixel at <HORBEG> and <VERBEG>, for the mode's pixel
;; size.
;;
;; Out:  X = the byte, A = the pixel's mask
HCALPOS:
    BSR HCALADR
    JMP ,U

;; <HCALPOS>'s routines for each HSCREEN mode, by the bits in a pixel.
CALTABLE:
    .dbyt G2BITPIX, G4BITPIX, G1BITPIX
    .dbyt G2BITPIX

;; Finds <HCALPOS>'s routine for the mode.
;;
;; Out:  U = the routine
HCALADR:
    LDU #CALTABLE
    LDA HRMODE
    SUBA #$01                       ; modes from 0
    ASLA
    LDU A,U
    RTS

;; The masks of the eight pixels in a byte of two colors, the leftmost first.
PIX1MASK:
    .byte $80, $40, $20, $10, $08, $04
    .byte $02, $01

;; The masks of the four pixels in a byte of four colors.
PIX2MASK:
    .byte $C0, $30, $0C, $03

;; The masks of the two pixels in a byte of sixteen colors.
PIX4MASK:
    .byte $F0, $0F

;; Finds the byte and mask of a pixel on a screen of one bit to a pixel.
;;
;; Out:  X = the byte, A = the mask
;; Keeps: B, U
G1BITPIX:
    PSHS U,B
    LDB HORBYT
    LDA VERBEG+1
    MUL                             ; the row's offset
    ADDD #HRESSCRN
    TFR D,X
    LDD HORBEG
    LSRA                            ; eight pixels to a byte
    RORB
    LSRA
    RORB
    LSRA
    RORB
    LEAX D,X
    LDA HORBEG+1
    ANDA #$07
    LDU #PIX1MASK
    LDA A,U
    PULS B,U,PC

;; Finds the byte and mask of a pixel on a screen of two bits to a pixel.
;;
;; Out:  X = the byte, A = the mask
;; Keeps: B, U
G2BITPIX:
    PSHS U,B
    LDB HORBYT
    LDA VERBEG+1
    MUL
    ADDD #HRESSCRN
    TFR D,X
    LDD HORBEG
    LSRA                            ; four pixels to a byte
    RORB
    LSRA
    RORB
    LEAX D,X
    LDA HORBEG+1
    ANDA #$03
    LDU #PIX2MASK
    LDA A,U
    PULS B,U,PC

;; Finds the byte and mask of a pixel on a screen of four bits to a pixel.
;;
;; Out:  X = the byte, A = the mask
;; Keeps: B, U
G4BITPIX:
    PSHS U,B
    LDB HORBYT
    LDA VERBEG+1
    MUL
    ADDD #HRESSCRN
    TFR D,X
    LDD HORBEG
    LSRA                            ; two pixels to a byte
    RORB
    LEAX D,X
    LDA HORBEG+1
    ANDA #$01
    LDU #PIX4MASK
    LDA A,U
    PULS B,U,PC

;; Returns HPOINT(x,y): the color of a pixel of the hi-res graphics screen.
;;
;; Errors: ?HR ERROR with no hi-res graphics screen
HPOINT:
    TST HRMODE
    LBEQ HRERR
    JSR SYNLPR
    JSR HGETXY
    JSR SYNRPR
    JSR SELTASK1
    JSR HCALPOS
    TFR A,B                         ; the pixel's bits
    ANDB ,X
HPOINT_SHIFT:
    LSRA
    BCS HPOINT_GIVE                 ; down to bit 0?
    LSRB
    BRA HPOINT_SHIFT
HPOINT_GIVE:
    JSR GIVB
    JSR SELTASK0
    RTS

;; Runs HLINE[(x1,y1)]-(x2,y2),PSET|PRESET[,B[F]]: draws a line on the hi-res graphics screen, or with B a box, or
;; with BF a filled box, from the last line's end when the start is left out, as LINE does for Extended BASIC.
;;
;; Errors: ?HR ERROR with no hi-res graphics screen; ?SN ERROR without PSET or PRESET
HLINE:
    TST HRMODE
    LBEQ HRERR
    LBRN RAMLINK                    ; the hook, never taken
    CMPA #'('
    BEQ HLINE_ENDS
    CMPA #TK_MINUS                  ; no start?
    BEQ HLINE_ENDS
    LDB #'@'                        ; HLINE@ is allowed
    JSR SYNCHR
HLINE_ENDS:
    JSR HLINEPTS
    LDX HOREND                      ; the end is the next line's start
    STX HORDEF
    LDX VEREND
    STX VERDEF
    JSR SYNCOM
    CMPA #TK_PRESET
    BEQ HLINE_PRESET
    CMPA #TK_PSET
    LBNE SNERR
    LDB #$01                        ; PSET: the foreground
    .byte $86                       ; LDA #: skips the CLRB below
HLINE_PRESET:
    CLRB                            ; PRESET: the background
    PSHS B
    JSR GETNCH
    JSR HLINESCALE
    PULS B
    STB SETFLG
    JSR HSETWORK
    JSR GETCCH
    LBEQ HDLINE                     ; no box: a line
    JSR SYNCOM
    LDB #'B'
    JSR SYNCHR
    BNE HLINE_FILL                  ; BF?
    BSR HORLINE                     ; a box: its four sides
    BSR VERLINE
    LDX HORBEG
    PSHS X
    LDX HOREND
    STX HORBEG
    BSR VERLINE
    PULS X
    STX HORBEG
    LDX VEREND
    STX VERBEG
    BRA HORLINE
HLINE_FILL:
    LDB #'F'
    JSR SYNCHR
    BRA HLINE_FILLROW
HLINE_UP:
    LEAX -1,X
HLINE_ROW:
    STX VERBEG
HLINE_FILLROW:
    JSR HORLINE
    LDX VERBEG
    CMPX VEREND
    BEQ HLINE_DONE
    BCC HLINE_UP                    ; filling upward?
    LEAX 1,X
    BRA HLINE_ROW
HLINE_DONE:
    RTS

;; Draws a row of pixels in the working color from <HORBEG> to <HOREND>, at <VERBEG>.
HORLINE:
    LDX HORBEG
    PSHS X
    JSR HDIFFX                      ; the width
    BCC HORLINE_COUNT               ; drawing leftward?
    LDX HOREND                      ; then start at the end
    STX HORBEG
HORLINE_COUNT:
    TFR D,Y
    LEAY 1,Y                        ; the pixels, both ends counted
    JSR HCALPOS
    PULS U
    STU HORBEG
    LBSR HRIGHTRTN                  ; the step to the right

;; Sets pixels in the working color, stepping through the routine at U, until Y counts down to zero.
;;
;; In:   A = the first pixel's mask, X = its byte, U = the step, Y = the pixels
HLINEDRAW:
    STA VD7                         ; the mask, while the pixel is set
    JSR HPIXSET
    LDA VD7
    JSR ,U
    LEAY -1,Y
    BNE HLINEDRAW
    RTS
VERLINE_POP:
    PULS A,B                        ; drop the vertical difference

;; Draws a column of pixels in the working color from <VERBEG> to <VEREND>, at <HORBEG>.
VERLINE:
    LDD VERBEG
    PSHS B,A
    JSR HDIFFY                      ; the height
    BCC VERLINE_COUNT
    LDX VEREND
    STX VERBEG
VERLINE_COUNT:
    TFR D,Y
    LEAY 1,Y
    JSR HCALPOS
    PULS U
    STU VERBEG
    LBSR HDOWNRTN                   ; the step down
    BRA HLINEDRAW

;; Draws a line in the working color from <HORBEG>, <VERBEG> to <HOREND>, <VEREND>: a row or a column when it is
;; straight, and otherwise stepping along the longer side, as Extended BASIC's <DLINE> does.
HDLINE:
    LDY #HINCY                      ; downward
    JSR HDIFFY
    BEQ HORLINE                     ; level: a row
    BCC HDLINE_H
    LDY #HDECY                      ; upward
HDLINE_H:
    PSHS B,A
    LDU #HINCX                      ; rightward
    JSR HDIFFX
    BEQ VERLINE_POP                 ; upright: a column
    BCC HDLINE_MAJOR
    LDU #HDECX                      ; leftward
HDLINE_MAJOR:
    CMPD ,S                         ; which side is longer?
    PULS X
    BCC HDLINE_SETUP
    EXG U,Y                         ; the longer side's step in U, its length in D
    EXG D,X
HDLINE_SETUP:
    PSHS U,B,A
    PSHS B,A
    LSRA
    RORB
    BCS HDLINE_FRAME                ; the longer side odd?
    CMPU #HINCY+1                   ; a step right or down, which come first?
    BCS HDLINE_FRAME
    SUBD #1                         ; a step left or up: one less
HDLINE_FRAME:
    PSHS X,B,A
    JSR HCALADR                     ; the pixel finder
HDLINE_LOOP:
    JSR ,U
    JSR HPIXSET
    LDX 6,S                         ; the steps left
    BEQ HDLINE_DONE
    LEAX -1,X
    STX 6,S
    JSR [8,S]                       ; a step along the longer side
    LDD ,S                          ; the shorter side's error
    ADDD 2,S
    STD ,S
    SUBD 4,S
    BCS HDLINE_LOOP                 ; not a whole step yet?
    STD ,S
    JSR ,Y                          ; a step along the shorter side
    BRA HDLINE_LOOP
HDLINE_DONE:
    PULS X
    PULS A,B,X,Y,U,PC

;; Steps <HORBEG> right. <HDLINE> keeps these four steps in this order: right, down, left, up.
HINCX:
    LDX HORBEG
    LEAX 1,X
    STX HORBEG
    RTS

;; Steps <VERBEG> down.
HINCY:
    LDX VERBEG
    LEAX 1,X
    STX VERBEG
    RTS

;; Steps <HORBEG> left.
HDECX:
    LDX HORBEG
    LEAX -1,X
    STX HORBEG
    RTS

;; Steps <VERBEG> up.
HDECY:
    LDX VERBEG
    LEAX -1,X
    STX VERBEG
HDIFF_DONE:
    RTS

;; Finds the height from <VERBEG> to <VEREND>.
;;
;; Out:  D = the height, carry = set when the end is above the start
HDIFFY:
    LDD VEREND
    SUBD VERBEG
HDIFF_ABS:
    BCC HDIFF_DONE
    PSHS CC                         ; which end is greater
    NEGA
    NEGB
    SBCA #$00
    PULS CC,PC

;; Finds the width from <HORBEG> to <HOREND>.
;;
;; Out:  D = the width, carry = set when the end is left of the start
HDIFFX:
    LDD HOREND
    SUBD HORBEG
    BRA HDIFF_ABS

;; Reads a line's ends, [(x1,y1)]-(x2,y2), into <HORBEG>, <VERBEG>, <HOREND> and <VEREND>: the start is the last
;; line's end, <HORDEF> and <VERDEF>, when it is left out.
HLINEPTS:
    LDX HORDEF
    STX HORBEG
    LDX VERDEF
    STX VERBEG
    CMPA #TK_MINUS                  ; no start?
    BEQ HLINEPTS_END
    JSR HPARXY
HLINEPTS_END:
    LDB #TK_MINUS
    JSR SYNCHR
    JSR SYNLPR
    JSR ADRBYT
    LDY #HOREND                     ; the end's coordinates
    JSR HLIMXY
    BRA HPARXY_CLOSE

;; Reads (x,y) into <HORBEG> and <VERBEG>, held to the screen.
HPARXY:
    JSR SYNLPR
    JSR HGETXYS
HPARXY_CLOSE:
    JMP SYNRPR

;; Where Extended BASIC scaled a line's ends, which hi-res graphics do not: it does nothing.
HLINESCALE:
    JSR HGETXY_DONE                 ; U = HORBEG, though the next sets U again
    LDU #HOREND
    JMP HNOSCALE

;; Finds the routine that steps a pixel's byte and mask one pixel right, for the mode.
;;
;; Out:  U = the routine
HRIGHTRTN:
    LDU #HRIGHTTAB
    LDB HRMODE
    SUBB #$01                       ; modes from 0
    ASLB
    LDU B,U
    RTS

;; Finds the routine that steps a pixel's byte one row down.
;;
;; Out:  U = the routine
HDOWNRTN:
    LDU #HDOWN
    RTS

;; The routines that step one pixel right, for each HSCREEN mode.
HRIGHTTAB:
    .dbyt HRIGHT2
    .dbyt HRIGHT4
    .dbyt HRIGHT1
    .dbyt HRIGHT2

;; Steps a pixel's byte and mask one pixel right, at a bit to a pixel.
;;
;; In:   A = the mask, X = the byte
HRIGHT1:
    LSRA
    BCC HRIGHT_DONE
    RORA
    LEAX 1,X
HRIGHT_DONE:
    RTS

;; Steps a pixel's byte and mask one pixel right, at two bits to a pixel.
;;
;; In:   A = the mask, X = the byte
HRIGHT2:
    LSRA
    LSRA
    BCC HRIGHT_DONE
    LDA #$C0                        ; the next byte's first pixel
    LEAX 1,X
    RTS

;; Steps a pixel's byte and mask one pixel right, at four bits to a pixel.
;;
;; In:   A = the mask, X = the byte
HRIGHT4:
    COMA                            ; the other half of the byte
    CMPA #$F0                       ; now the left half: the next byte
    BNE HRIGHT4_DONE
    LEAX 1,X
HRIGHT4_DONE:
    RTS

;; Steps a pixel's byte one row down.
;;
;; In:   X = the byte
HDOWN:
    LDB HORBYT
    ABX
    RTS

;; Runs HCIRCLE[@](x,y),radius[,color[,ratio[,start[,end]]]]: draws a circle, an ellipse or an arc on the hi-res
;; graphics screen, as CIRCLE does for Extended BASIC: 64 short lines around the center, the height scaled by the
;; ratio, from the start to the end, each a fraction of a turn.
;;
;; Errors: ?HR ERROR with no hi-res graphics screen; ?FC ERROR when the height is too great
HCIRCLE:
    TST HRMODE
    LBEQ HRERR
    LBRN RAMLINK                    ; the hook, never taken
    CMPA #'@'                       ; HCIRCLE@ is allowed
    BNE HCIRCLE_ARGS
    JSR GETNCH
HCIRCLE_ARGS:
    JSR HCIRCLIM                    ; the screen's limits, in VD3 and VD5
    JSR HPARXY                      ; the center
    JSR HGETXY_DONE
    LDX ,U                          ; the center into VCB and VCD
    STX VCB
    LDX 2,U
    STX VCD
    JSR SYNCOM
    JSR GETADR
    LDU #VCF                        ; the radius into VCF
    STX ,U
    JSR HNOSCALE                    ; nothing: where Extended BASIC scaled it
    LDA #$01                        ; the foreground, unless a color is given
    STA SETFLG
    JSR HGETCOLOR
    LDX #$100                       ; a ratio of 1, in 256ths
    JSR GETCCH
    BEQ HCIRCLE_RATIO
    JSR SYNCOM
    JSR FRMNUM
    LDA FP0EXP                      ; the ratio times 256
    ADDA #$08
    STA FP0EXP
    JSR ADRCHK
HCIRCLE_RATIO:
    LDA HRMODE
    CMPA #$02                       ; a mode of wide pixels?
    BHI HCIRCLE_START
    TFR X,D                         ; then twice the height
    LEAX D,X
HCIRCLE_START:
    STX VD1
    LDB #$01
    STB SETFLG
    STB VD8                         ; the first point: no line to it
    JSR HCIRCARG                    ; the start, as an eighth of a turn and a 64th in it
    PSHS B,A
    JSR HCIRCARG                    ; the end
    STD VD9
    PULS A,B
HCIRCLE_ARC:
    PSHS B,A
    LDX HOREND                      ; the last point is the next line's start
    STX HORBEG
    LDX VEREND
    STX VERBEG
    LDU #CIRCDATA+2
    ANDA #$01                       ; an odd eighth runs backward through the table
    BEQ HCIRCLE_ENTRY
    NEGB
    ADDB #$08
HCIRCLE_ENTRY:
    ASLB                            ; four bytes to each of the table's entries
    ASLB
    LEAU B,U
    PSHS U
    JSR HCIRCMUL                    ; the horizontal offset, from the sine
    PULS U
    LEAU -2,U                       ; the vertical, from the cosine
    PSHS X
    JSR HCIRCMUL
    PULS Y
    LDA ,S                          ; which eighth?
    ANDA #$03
    BEQ HCIRCLE_SCALE
    CMPA #$03
    BEQ HCIRCLE_SCALE
    EXG X,Y                         ; the second and third, fifth and sixth: the offsets swap
HCIRCLE_SCALE:
    STX HOREND                      ; the horizontal offset
    TFR Y,D                         ; the vertical offset, halved, times the ratio
    LSRA
    RORB
    LDX VD1
    JSR HMUL16
    TFR Y,D
    TSTA
    LBNE FCERR                      ; too tall
    STB VEREND
    TFR U,D
    STA VEREND+1
    LDA ,S                          ; left of the center?
    CMPA #$02
    BCS HCIRCLE_RIGHT
    CMPA #$06
    BCC HCIRCLE_RIGHT
    LDD VCB
    SUBD HOREND
    BCC HCIRCLE_H
    CLRA
    CLRB
    BRA HCIRCLE_H
HCIRCLE_RIGHT:
    LDD VCB
    ADDD HOREND
    BCS HCIRCLE_HMAX
    CMPD VD3                        ; past the right edge?
    BCS HCIRCLE_H
HCIRCLE_HMAX:
    LDD VD3
HCIRCLE_H:
    STD HOREND
    LDA ,S                          ; above the center?
    CMPA #$04
    BCS HCIRCLE_DOWN
    LDD VCD
    SUBD VEREND
    BCC HCIRCLE_V
    CLRA
    CLRB
    BRA HCIRCLE_V
HCIRCLE_DOWN:
    LDD VCD
    ADDD VEREND
    BCS HCIRCLE_VMAX
    CMPD VD5                        ; past the bottom?
    BCS HCIRCLE_V
HCIRCLE_VMAX:
    LDD VD5
HCIRCLE_V:
    STD VEREND
    TST VD8                         ; the first point?
    BNE HCIRCLE_NEXT
    LBSR HDLINE                     ; a line from the last point
HCIRCLE_NEXT:
    PULS A,B
    LSR VD8                         ; the first point is never the end
    BCS HCIRCLE_STEP
    CMPD VD9                        ; at the end?
    BEQ HCIRCLE_DONE
HCIRCLE_STEP:
    INCB
    CMPB #$08                       ; past the eighth's last 64th?
    BNE HCIRCLE_LOOP
    INCA
    CLRB
    ANDA #$07                       ; after the last eighth, 0: the end is 0 when it was not given
HCIRCLE_LOOP:
    JMP HCIRCLE_ARC
HCIRCLE_DONE:
    RTS

;; Puts the hi-res graphics screen's largest coordinates in VD3 and VD5: 319 or 639 across, and 191 down.
HCIRCLIM:
    LDU #VD3
    LDX #640-1
    STX ,U
    LDA HRMODE
    CMPA #$02
    BGT HCIRCLIM_V
    LDX #320-1
    STX ,U
HCIRCLIM_V:
    LDX #192-1
    STX 2,U
    JMP HNOSCALE

;; Reads HCIRCLE's start or end, a fraction of a turn, as 64ths: 0 when there is none.
;;
;; Out:  A = the eighth, B = the 64th in it
HCIRCARG:
    CLRB
    JSR GETCCH
    BEQ HCIRCARG_SPLIT
    JSR SYNCOM
    JSR FRMNUM
    LDA FP0EXP                      ; times 64
    ADDA #$06
    STA FP0EXP
    JSR BYTCHK
    ANDB #$3F
HCIRCARG_SPLIT:
    TFR B,A
    ANDB #$07
    LSRA
    LSRA
    LSRA
    RTS

;; The sines and cosines of the nine points from 0 to an eighth of a turn, in 65536ths: each entry's cosine, then
;; its sine, the first after 1 and 0.
CIRCDATA:
    .dbyt $0000, $0001
    .dbyt $FEC5, $1919
    .dbyt $FB16, $31F2
    .dbyt $F4FB, $4A51
    .dbyt $EC84, $61F9
    .dbyt $E1C7, $78AE
    .dbyt $D4DC, $8E3B
    .dbyt $C5E5, $A269
    .dbyt $B506, $B506

;; Multiplies the radius, VCF, by a sine or cosine from <CIRCDATA>.
;;
;; In:   U = the entry
;; Out:  X = the offset
HCIRCMUL:
    LDX VCF
    LDD ,U
    BEQ HCIRCMUL_DONE               ; 1: the radius itself
    SUBD #1
    BSR HMUL16
    TFR Y,X
HCIRCMUL_DONE:
    RTS

;; Multiplies two 16-bit numbers, as Extended BASIC's <MUL16> does.
;;
;; In:   D = a number, X = the other
;; Out:  Y = the product's high word, U = its low word
HMUL16:
    PSHS U,Y,X,B,A
    CLR 4,S
    LDA 3,S                         ; the low bytes
    MUL
    STD 6,S
    LDD 1,S                         ; the low by the high
    MUL
    ADDB 6,S
    ADCA #$00
    STD 5,S
    LDB ,S                          ; the high by the low
    LDA 3,S
    MUL
    ADDD 5,S
    STD 5,S
    BCC HMUL16_HIGH
    INC 4,S                         ; a carry into the high word
HMUL16_HIGH:
    LDA ,S                          ; the high bytes
    LDB 2,S
    MUL
    ADDD 4,S
    STD 4,S
    PULS A,B,X,Y,U,PC

;; Runs HPAINT[@](x,y)[,color[,border]]: fills the hi-res graphics screen from a point out to a border, as PAINT
;; does for Extended BASIC. The color is the foreground's and the border the color's unless given. Lines still to
;; fill are kept on task 1's stack, six bytes each: the direction, up or down, the row, the left end and the length.
;;
;; Errors: ?HR ERROR with no hi-res graphics screen; ?OM ERROR when the stack runs out
HPAINT:
    TST HRMODE
    LBEQ HRERR
    LBRN RAMLINK                    ; the hook, never taken
    CMPA #'@'                       ; HPAINT@ is allowed
    BNE HPAINT_POINT
    JSR GETNCH
HPAINT_POINT:
    JSR HPARXY
    JSR HGETXY_DONE
    LDA #$01
    STA SETFLG
    JSR HGETCOLOR                   ; the fill color
    LDD WCOLOR                      ; kept while the border's is read
    PSHS B,A
    JSR GETCCH
    BEQ HPAINT_BORDER               ; no border: the fill color's
    JSR HGETCOLOR
HPAINT_BORDER:
    LDA ALLCOL                      ; the border color, in every pixel of a byte
    STA VD8
    PULS A,B
    STD WCOLOR
    JSR SELTASK1
    CLRA                            ; a direction of 0 marks the stack's last line
    PSHS U,X,B,A
    JSR HCIRCLIM
    JSR HCALADR                     ; the pixel finder
    STU VD9
    JSR HPNTLEFT                    ; the first row, left from the point
    BEQ HPAINT_KEEP                 ; at a border already?
    JSR HPNTWIDE                    ; then right
    LDA #$01                        ; the row below, then the row above
    STA VD7
    JSR HPNTSAVE
    NEG VD7
    JSR HPNTSAVE
HPAINT_KEEP:
    STS TMPSTK
HPAINT_NEXT:
    TST CHGFLG                      ; anything filled since?
    BNE HPAINT_LINE
    LDS TMPSTK                      ; no: drop the lines saved since
HPAINT_LINE:
    PULS A,B,X,U                    ; a line still to fill
    CLR CHGFLG
    STS TMPSTK
    LEAX 1,X                        ; one right of where it starts
    STX HORBEG
    STU VD1                         ; the length of the line it came from
    STA VD7
    BEQ HPAINT_DONE                 ; the stack's last line: done
    BMI HPAINT_UP                   ; upward?
    INCB                            ; downward: the next row
    CMPB VD6
    BLS HPAINT_ROW                  ; still on the screen?
    CLRB                            ; off the bottom: dropped
HPAINT_UP:
    TSTB
    BEQ HPAINT_NEXT                 ; off the top: dropped
    DECB
HPAINT_ROW:
    STB VERBEG+1
    JSR HPNTLEFT                    ; left from the start
    BEQ HPAINT_REST
    CMPD #3                         ; three or more filled?
    BCS HPAINT_RIGHT
    LEAX -2,X                       ; then the row back the other way, from its left end
    JSR HPNTBACK
HPAINT_RIGHT:
    JSR HPNTWIDE
HPAINT_SAVE:
    JSR HPNTSAVE
HPAINT_REST:
    COMA                            ; the length filled, negated
    COMB
HPAINT_ALONG:
    ADDD VD1                        ; less than the line it came from?
    STD VD1
    BLE HPAINT_PAST
    JSR HINCX
    JSR HPNTBORDER                  ; a border pixel next?
    BNE HPAINT_GAP
    LDD #$FFFF                      ; one fewer
    BRA HPAINT_ALONG
HPAINT_GAP:
    JSR HDECX
    JSR HPNTMARK                    ; a new start past the border
    BSR HPNTRIGHT
    BRA HPAINT_SAVE
HPAINT_PAST:
    JSR HINCX
    LEAX D,X                        ; the right end of the line it came from
    STX HORBEG
    COMA                            ; how far this row passes it, if it does
    COMB
    SUBD #1
    BLE HPAINT_LOOP
    TFR D,X
    BSR HPNTBACK                    ; that part, back the other way
HPAINT_LOOP:
    JMP HPAINT_NEXT
HPAINT_DONE:
    JSR SELTASK0
    RTS

;; Fills leftward from the point, at <HORBEG> and <VERBEG>, to a border or the screen's left edge.
;;
;; Out:  D and X = the pixels filled, zero = set when none
HPNTLEFT:
    JSR HPNTMARK
    LDY #HDECX
    BRA HPNTSCAN

;; Fills rightward from one past the point to a border or the screen's right edge.
;;
;; Out:  D and X = the pixels filled, zero = set when none
HPNTRIGHT:
    LDY #HINCX
    JSR ,Y

;; Fills along the row, a step at a time through the routine at Y, until a border or an edge.
;;
;; In:   Y = the step, <HINCX> or <HDECX>
;; Out:  D and X = the pixels filled, zero = set when none
HPNTSCAN:
    LDU ZERO
    LDX HORBEG
HPNTSCAN_LOOP:
    BMI HPNTSCAN_DONE               ; past the left edge?
    CMPX VD3                        ; past the right?
    BHI HPNTSCAN_DONE
    PSHS U,Y
    BSR HPNTBORDER
    BEQ HPNTSCAN_BORDER
    JSR HPIXSET1                    ; fill it
    PULS Y,U
    LEAU 1,U
    JSR ,Y
    BRA HPNTSCAN_LOOP
HPNTSCAN_BORDER:
    PULS Y,U
HPNTSCAN_DONE:
    TFR U,D
    TFR D,X
    SUBD ZERO
    RTS

;; Checks whether the pixel at <HORBEG> and <VERBEG> is the border's color, in VD8.
;;
;; Out:  zero = set for the border, A = its mask, X = its byte
HPNTBORDER:
    JSR [VD9]
    TFR A,B
    ANDB VD8
    PSHS B,A
    ANDA ,X
    CMPA 1,S
    PULS A,B,PC

;; Fills rightward after a leftward fill, from where the leftward one began; <HOREND> becomes the row's left end.
;;
;; In:   D = the pixels filled leftward
;; Out:  D = the row's length, X = the pixels filled, less one
HPNTWIDE:
    STD VCD
    LDY HOREND
    BSR HPNTMARK
    STY HORBEG
    BSR HPNTRIGHT
    LDX VCD
    LEAX D,X
    ADDD #1
    RTS

;; Saves a line to fill on the stack, in the direction opposite to the one being filled.
;;
;; In:   D = kept in VCB; X = the line's length
;; Out:  D = as it came
HPNTBACK:
    STD VCB
    PULS Y
    LDD HORBEG
    PSHS X,B,A
    LDA VD7
    NEGA
HPNTPUSH:
    LDB VERBEG+1
    PSHS B,A
    PSHS Y
    LDB #$06
    JSR HPNTROOM
    LDD VCB
    RTS

;; Saves a line to fill on the stack, in the direction being filled, from <HOREND>.
;;
;; In:   D = kept in VCB; X = the line's length
;; Out:  D = as it came
HPNTSAVE:
    STD VCB
    PULS Y
    LDD HOREND
    PSHS X,B,A
    LDA VD7
    BRA HPNTPUSH

;; Keeps the point's horizontal coordinate in <HOREND>.
HPNTMARK:
    LDX HORBEG
    STX HOREND
    RTS

;; Checks that the stack has room for some bytes more, in task 1's stack block.
;;
;; In:   B = the bytes, up to 127
;; Errors: ?OM ERROR when it has not
HPNTROOM:
    NEGB
    LEAS B,S
    CMPS #TMPSTACK-$2000-14         ; the block's bottom, less the 14 bytes the ROM's vectors hide
    LBCS HPNTROOM_OM
    NEGB
    LEAS B,S
    RTS
HPNTROOM_OM:
    LDS #TMPSTACK-2                 ; a stack to leave task 1 with
    JSR SELTASK0
    JMP OMERR

;; Runs HBUFF n,size: makes buffer n, 1 to 255, of size bytes for HGET and HPUT, in block $34; HBUFF 0 frees them
;; all. Each buffer follows the last, with a header: the next one's address, 0 after the last, its number and its
;; size. The first header's address is $FFFF while there are none.
;;
;; Errors: ?FC ERROR past 255; ?DD ERROR when n exists; ?OM ERROR past the block's 7.75K
HBUFF:
    JSR GETADR
    LBRN RAMLINK                    ; the hook, never taken
    CMPX #255
    LBHI FCERR
    STX VD1
    BEQ HBUFF_MAP                   ; 0: no size
    JSR SYNCOM
    JSR GETADR
    STX VD3                         ; the size
HBUFF_MAP:
    JSR SELBUFF                     ; the buffers' block at $C000
    JSR SELTASK1
    LDD VD1
    TSTB
    BNE HBUFF_FIND                  ; free them all?
    LDD #$FFFF
    STD HRESBUFF
    BRA HBUFF_DONE
HBUFF_FIND:
    LDY #HRESBUFF
    LDD ,Y
    CMPD #$FFFF                     ; none yet?
    BNE HBUFF_LAST
    BSR HBUFFROOM                   ; room for the first?
    BRA HBUFF_HEADER
HBUFF_LAST:
    LDB VD1+1
HBUFF_LOOP:
    CMPB 2,Y                        ; this number already?
    BEQ HBUFF_DD
    LDU ,Y
    BEQ HBUFF_ADD                   ; the last?
    TFR U,Y
    BRA HBUFF_LOOP
HBUFF_ADD:
    TFR Y,U
    LDD 3,Y
    LEAY 5,Y                        ; past its header and data
    LEAY D,Y
    BSR HBUFFROOM
    STY ,U                          ; the last one links to this
HBUFF_HEADER:
    LDD #0                          ; the new last
    STD ,Y
    LDB VD1+1
    STB 2,Y
    LDD VD3
    STD 3,Y
HBUFF_DONE:
    JSR SELTASK0
    JSR SETMMU
    RTS

;; Checks that a buffer of the size asked for fits from Y.
;;
;; In:   Y = where its header goes, VD3 = its size
;; Errors: ?OM ERROR when it does not
HBUFFROOM:
    TFR Y,X
    LEAX 5,X
    LDD VD3
    LEAX D,X
    CMPX #HRESBUFF+$1F00
    BHI HBUFF_OM
    RTS
HBUFF_DD:
    LDB #ERR_DD
    BRA HBUFF_ERROR
HBUFF_OM:
    LDB #ERR_OM
HBUFF_ERROR:
    LDS #TMPSTACK-2                 ; a stack to leave task 1 with
    JSR SELTASK0
    JSR SETMMU
    JMP ERROR

;; Runs HGET[@](x1,y1)-(x2,y2),n: copies a rectangle of the hi-res graphics screen into HBUFF's buffer n, as GET
;; does for Extended BASIC, whole bytes at a time.
;;
;; Errors: ?HR ERROR with no hi-res graphics screen; ?FC ERROR when there is no buffer n or it is too small
HGET:
    LDX #HGETBYTE                   ; the byte's copy
    STX VD5
    CLRB                            ; 0: HGET
    BRA HGETPUT

;; Runs HPUT[@](x1,y1)-(x2,y2),n[,action]: copies HBUFF's buffer n onto a rectangle of the hi-res graphics screen,
;; as PUT does for Extended BASIC: PSET as it was, the default; PRESET inverted; AND, OR, or NOT, which inverts the
;; screen rather than the buffer.
;;
;; Errors: ?HR ERROR with no hi-res graphics screen; ?FC ERROR when there is no buffer n or it is too small; ?SN
;; ERROR for an action HPUT does not have
HPUT:
    LDX #HPUTPSET                   ; PSET's copy, unless another is given
    STX VD5
    LDB #$01                        ; 1: HPUT
HGETPUT:
    TST HRMODE
    LBEQ HRERR
    LBRN RAMLINK                    ; the hook, never taken
    STB VD8
    CMPA #'@'                       ; HGET@ and HPUT@ are allowed
    BNE HGETPUT_RECT
    JSR GETNCH
HGETPUT_RECT:
    JSR HLINEPTS
    JSR SYNCOM
    JSR GETBYT
    STB VD3                         ; the buffer
    CLR VD4                         ; no action
    JSR GETCCH
    BEQ HGETPUT_MAP
    COM VD4                         ; an action
    JSR SYNCOM
    TST VD8                         ; HPUT?
    BNE HGETPUT_ACTION
    LBRA SNERR                      ; HGET takes none
HGETPUT_ACTION:
    LDB #$05
    LDX #HPUTTAB
HGETPUT_FIND:
    LDU ,X++
    CMPA ,X+                        ; the action's token?
    BEQ HGETPUT_FOUND
    DECB
    BNE HGETPUT_FIND
    JMP SNERR
HGETPUT_FOUND:
    STU VD5
    JSR GETNCH
HGETPUT_MAP:
    JSR SELBUFF                     ; the buffers' block at $C000
    JSR SELTASK1
    LDB VD3
    JSR HBUFADR                     ; the buffer's data, in VCF and VD1
    LDD HORBEG
    CMPD HOREND                     ; the corners in order
    BLE HGETPUT_V
    LDX HOREND
    STX HORBEG
    STD HOREND
HGETPUT_V:
    LDD VERBEG
    CMPD VEREND
    BLE HGETPUT_BYTES
    LDX VEREND
    STX VERBEG
    STD VEREND
HGETPUT_BYTES:
    LDA HRMODE
    LDB #$F8                        ; eight pixels to a byte
    CMPA #$03
    BEQ HGETPUT_ROUND
    LDB #$FC                        ; four pixels to a byte
    CMPA #$02
    BNE HGETPUT_ROUND
    LDB #$FE                        ; two pixels to a byte
HGETPUT_ROUND:
    TFR B,A
    ANDA HORBEG+1                   ; the left edge down to a byte's start
    STA HORBEG+1
    ANDB HOREND+1                   ; and the right edge
    STB HOREND+1
    JSR HDIFFX
    STD HOREND
    JSR HDIFFY
    ADDD #1                         ; the rows, both ends counted
    STD VEREND
    LDA HRMODE                      ; the width in bytes
    CMPA #$02
    BEQ HGETPUT_TWO
    CMPA #$03
    BNE HGETPUT_FOUR
    LSR HOREND
    ROR HOREND+1
HGETPUT_FOUR:
    LSR HOREND
    ROR HOREND+1
HGETPUT_TWO:
    LSR HOREND
    ROR HOREND+1
    LDD HOREND
    ADDD #1                         ; both ends counted
    STD HOREND
    JSR HCALPOS                     ; the first byte
    LDY VD5                         ; the copy
HGETPUT_ROW:
    LDB HOREND+1
    PSHS X
HGETPUT_BYTE:
    JSR ,Y
    DECB
    BNE HGETPUT_BYTE
    PULS X
    JSR HDOWN                       ; the next row
    DEC VEREND+1
    BNE HGETPUT_ROW
    JSR SELTASK0
    JSR SETMMU
    RTS

;; HGET's copy: a byte from the screen into the buffer.
;;
;; In:   X = the screen's byte
HGETBYTE:
    LDA ,X+
    BSR HBUFNEXT
    STA ,U
    RTS

;; Steps to the buffer's next byte.
;;
;; Out:  U = the byte
;; Errors: ?FC ERROR past the buffer's end
HBUFNEXT:
    LDU VCF
    LEAU 1,U
    STU VCF
    CMPU VD1
    BHI HBUFFC
    RTS

;; Raises ?FC ERROR from task 1: goes back to task 0 and BASIC's map first.
HBUFFC:
    LDS #TMPSTACK-2                 ; a stack to leave task 1 with
    JSR SELTASK0
    JSR SETMMU
    JMP FCERR

;; HPUT's actions: each copy's routine and the token that names it.
HPUTTAB:
    .dbyt HPUTPSET
    .byte TK_PSET
    .dbyt HPUTPRESET
    .byte TK_PRESET
    .dbyt HPUTOR
    .byte TK_OR
    .dbyt HPUTAND
    .byte TK_AND
    .dbyt HPUTNOT
    .byte TK_NOT

;; HPUT's PSET: a byte from the buffer onto the screen.
;;
;; In:   X = the screen's byte
HPUTPSET:
    BSR HBUFNEXT
    LDA ,U
    STA ,X+
    RTS

;; HPUT's PRESET: a byte from the buffer, inverted, onto the screen.
;;
;; In:   X = the screen's byte
HPUTPRESET:
    BSR HBUFNEXT
    LDA ,U
    COMA
    STA ,X+
    RTS

;; HPUT's AND: a byte from the buffer ANDed with the screen's.
;;
;; In:   X = the screen's byte
HPUTAND:
    BSR HBUFNEXT
    LDA ,U
    ANDA ,X
    STA ,X+
    RTS

;; HPUT's OR: a byte from the buffer ORed with the screen's.
;;
;; In:   X = the screen's byte
HPUTOR:
    BSR HBUFNEXT
    LDA ,U
    ORA ,X
    STA ,X+
    RTS

;; HPUT's NOT: the screen's byte inverted; the buffer's byte is stepped past but not used.
;;
;; In:   X = the screen's byte
HPUTNOT:
    BSR HBUFNEXT
    LDA ,X                          ; the screen's byte, not the buffer's
    COMA
    STA ,X+
    RTS

;; Finds HBUFF's buffer, with task 1 and the buffers' block mapped: VCF becomes one before its data, and VD1 its
;; data's end.
;;
;; In:   B = the buffer's number
;; Errors: ?FC ERROR when there is no such buffer
HBUFADR:
    LDY #HRESBUFF
    LDA ,Y
    CMPA #$FF                       ; none at all?
    BNE HBUFADR_CHECK
    JMP HBUFFC
HBUFADR_NEXT:
    LDY ,Y
    LBEQ HBUFFC
HBUFADR_CHECK:
    CMPB 2,Y
    BNE HBUFADR_NEXT
    LDD 3,Y
    LEAY 4,Y                        ; one before the data
    STY VCF
    LEAY 1,Y
    LEAY D,Y
    STY VD1
    RTS

;; Runs HPRINT(column,row),expression: draws a string or a number on the hi-res graphics screen in the foreground
;; color, with the 8x8 characters of <HIRESCHR>, from a character column and row: up to 40 columns in modes 1 and 2
;; and 80 in 3 and 4, and 24 rows. What passes the right edge is left off, and control characters show as spaces.
;;
;; Errors: ?HR ERROR with no hi-res graphics screen
HPRINT:
    TST HRMODE
    LBEQ HRERR
    LBRN RAMLINK                    ; the hook, never taken
    JSR SYNLPR
    JSR HGETXYS                     ; the column and row
    JSR SYNRPR
    JSR SYNCOM
    JSR FRMEVL
    TST VALTYP                      ; a number?
    BNE HPRINT_STRING
    JSR FOUT                        ; then as PRINT shows it
    JSR STRLX
HPRINT_STRING:
    JSR FREFAC
    STB H_PCOUNT
    LDY #H_PBUF                     ; the string into the buffer
HPRINT_COPY:
    DECB
    BMI HPRINT_FIT
    LDA ,X+
    STA ,Y+
    BRA HPRINT_COPY
HPRINT_FIT:
    LDA HRMODE
    LDB #40
    CMPA #$03                       ; 640 across?
    BCS HPRINT_ROOM
    LDB #80
HPRINT_ROOM:
    CLRA
    SUBD HORBEG                     ; the columns left on the row
    BMI HPRINT_EXIT
    CMPB H_PCOUNT                   ; more than the string has?
    BHI HPRINT_ROW
    STB H_PCOUNT                    ; then only what fits
    BEQ HPRINT_EXIT
HPRINT_ROW:
    LDA #ROWMAX-1
    CMPA VERBEG+1                   ; below the last row?
    BGE HPRINT_PLACE
    STA VERBEG+1                    ; then the last
HPRINT_PLACE:
    JSR HPRINTPOS                   ; the column and row in pixels
    JSR HCALPOS
    LDY #H_PBUF
    LDB H_PCOUNT
HPRINT_CHARS:
    LDA ,Y
    ANDA #$7F                       ; graphics characters as text
    SUBA #$20                       ; from space, the font's first
    BPL HPRINT_NEXTCHAR
    LDA #$00                        ; a control character: a space
HPRINT_NEXTCHAR:
    STA ,Y+
    DECB
    BGT HPRINT_CHARS
    LDA HRMODE                      ; the byte drawer for the mode
    DECA
    ASLA
    LDY #HPRINTTAB
    LDY A,Y
    STY VD1
    LDA #$08                        ; eight rows of pixels to a character
    STA VD3
    LDY #H_PBUF
    LDU #HIRESCHR
    LDB H_FCOLOR                    ; the foreground, in every pixel of a byte
    JSR PIXELFIL
    STB ALLCOL
    JSR SELTASK1
    LDA H_PCOUNT
HPRINT_LINE:
    PSHS Y,X,A
HPRINT_BYTE:
    LDB ,Y+
    CLRA
    ASLB                            ; eight bytes to a character
    ASLB
    ROLA
    ASLB
    ROLA
    LDA D,U                         ; this row of it
    JSR [VD1]
    DEC H_PCOUNT
    BGT HPRINT_BYTE
    PULS A,X,Y
    DEC VD3
    BEQ HPRINT_DONE
    STA H_PCOUNT
    LEAU 1,U
    JSR HDOWN
    BRA HPRINT_LINE
HPRINT_DONE:
    JSR SELTASK0
HPRINT_EXIT:
    RTS

;; HPRINT's routines that draw a row of a character, eight pixels, for each HSCREEN mode.
HPRINTTAB:
    .dbyt HPRINT2
    .dbyt HPRINT4
    .dbyt HPRINT1
    .dbyt HPRINT2

;; Draws a byte of pixels in the foreground color where the mask has them, leaving the rest: a row of a
;; character at one bit to a pixel, and the routine the others draw through.
;;
;; In:   A = the mask, X = the screen's byte
;; Out:  X = the next byte
HPRINT1:
    PSHS A
    COMA                            ; a hole where the character goes
    ANDA ,X
    STA ,X
    PULS A
    ANDA ALLCOL                     ; the character, colored, into it
    ORA ,X
    STA ,X+
    RTS

;; Draws a row of a character at two bits to a pixel: two bytes, each four pixels of the row.
;;
;; In:   A = the row, X = the screen's byte
HPRINT2:
    PSHS Y
    LDY #HPRINT2TAB
    TFR A,B
    LSRA                            ; the left four pixels
    LSRA
    LSRA
    LSRA
    LDA A,Y
    JSR HPRINT1
    ANDB #$0F
    LDA B,Y
    JSR HPRINT1
    PULS Y
    RTS

;; Each four pixels of a character's row, as a mask of two bits to a pixel.
HPRINT2TAB:
    .byte $00, $03, $0C, $0F, $30, $33
    .byte $3C, $3F, $C0, $C3, $CC, $CF
    .byte $F0, $F3, $FC, $FF

;; Draws a row of a character at four bits to a pixel: four bytes, each two pixels of the row.
;;
;; In:   A = the row, X = the screen's byte
HPRINT4:
    PSHS Y,A
    LDY #HPRINT4TAB
    LSRA                            ; the left four pixels
    LSRA
    LSRA
    LSRA
    ASLA                            ; two bytes to each entry
    LDD A,Y
    JSR HPRINT1
    TFR B,A
    JSR HPRINT1
    PULS A
    ANDA #$0F
    ASLA
    LDD A,Y
    JSR HPRINT1
    TFR B,A
    JSR HPRINT1
    PULS Y
    RTS

;; Each four pixels of a character's row, as a mask of four bits to a pixel, two bytes.
HPRINT4TAB:
    .dbyt $0000, $000F, $00F0
    .dbyt $00FF, $0F00, $0F0F
    .dbyt $0FF0, $0FFF, $F000
    .dbyt $F00F, $F0F0, $F0FF
    .dbyt $FF00, $FF0F, $FFF0
    .dbyt $FFFF

;; Turns HPRINT's column and row into pixels, eight to a character.
HPRINTPOS:
    LDD HORBEG
    ASLB                            ; the column times eight
    ASLB
    ROLA
    ASLB
    ROLA
    STD HORBEG
    LDA VERBEG+1
    ASLA                            ; the row times eight
    ASLA
    ASLA
    STA VERBEG+1
    RTS

;; HPRINT's characters, 8x8 pixels, from space to DEL: each eight rows, the top row first.
HIRESCHR:
    .byte $00, $00, $00, $00, $00, $00, $00, $00 ; space
    .byte $10, $10, $10, $10, $10, $00, $10, $00 ; '!'
    .byte $28, $28, $28, $00, $00, $00, $00, $00 ; '"'
    .byte $28, $28, $7C, $28, $7C, $28, $28, $00 ; '#'
    .byte $10, $3C, $50, $38, $14, $78, $10, $00 ; '$'
    .byte $60, $64, $08, $10, $20, $4C, $0C, $00 ; '%'
    .byte $20, $50, $50, $20, $54, $48, $34, $00 ; '&'
    .byte $10, $10, $20, $00, $00, $00, $00, $00 ; '''
    .byte $08, $10, $20, $20, $20, $10, $08, $00 ; '('
    .byte $20, $10, $08, $08, $08, $10, $20, $00 ; ')'
    .byte $00, $10, $54, $38, $38, $54, $10, $00 ; '*'
    .byte $00, $10, $10, $7C, $10, $10, $00, $00 ; '+'
    .byte $00, $00, $00, $00, $00, $10, $10, $20 ; ','
    .byte $00, $00, $00, $7C, $00, $00, $00, $00 ; '-'
    .byte $00, $00, $00, $00, $00, $00, $10, $00 ; '.'
    .byte $00, $04, $08, $10, $20, $40, $00, $00 ; '/'
    .byte $38, $44, $4C, $54, $64, $44, $38, $00 ; '0'
    .byte $10, $30, $10, $10, $10, $10, $38, $00 ; '1'
    .byte $38, $44, $04, $38, $40, $40, $7C, $00 ; '2'
    .byte $38, $44, $04, $08, $04, $44, $38, $00 ; '3'
    .byte $08, $18, $28, $48, $7C, $08, $08, $00 ; '4'
    .byte $7C, $40, $78, $04, $04, $44, $38, $00 ; '5'
    .byte $38, $40, $40, $78, $44, $44, $38, $00 ; '6'
    .byte $7C, $04, $08, $10, $20, $40, $40, $00 ; '7'
    .byte $38, $44, $44, $38, $44, $44, $38, $00 ; '8'
    .byte $38, $44, $44, $38, $04, $04, $38, $00 ; '9'
    .byte $00, $00, $10, $00, $00, $10, $00, $00 ; ':'
    .byte $00, $00, $10, $00, $00, $10, $10, $20 ; ';'
    .byte $08, $10, $20, $40, $20, $10, $08, $00 ; '<'
    .byte $00, $00, $7C, $00, $7C, $00, $00, $00 ; '='
    .byte $20, $10, $08, $04, $08, $10, $20, $00 ; '>'
    .byte $38, $44, $04, $08, $10, $00, $10, $00 ; '?'
    .byte $38, $44, $04, $34, $4C, $4C, $38, $00 ; '@'
    .byte $10, $28, $44, $44, $7C, $44, $44, $00 ; 'A'
    .byte $78, $24, $24, $38, $24, $24, $78, $00 ; 'B'
    .byte $38, $44, $40, $40, $40, $44, $38, $00 ; 'C'
    .byte $78, $24, $24, $24, $24, $24, $78, $00 ; 'D'
    .byte $7C, $40, $40, $70, $40, $40, $7C, $00 ; 'E'
    .byte $7C, $40, $40, $70, $40, $40, $40, $00 ; 'F'
    .byte $38, $44, $40, $40, $4C, $44, $38, $00 ; 'G'
    .byte $44, $44, $44, $7C, $44, $44, $44, $00 ; 'H'
    .byte $38, $10, $10, $10, $10, $10, $38, $00 ; 'I'
    .byte $04, $04, $04, $04, $04, $44, $38, $00 ; 'J'
    .byte $44, $48, $50, $60, $50, $48, $44, $00 ; 'K'
    .byte $40, $40, $40, $40, $40, $40, $7C, $00 ; 'L'
    .byte $44, $6C, $54, $54, $44, $44, $44, $00 ; 'M'
    .byte $44, $44, $64, $54, $4C, $44, $44, $00 ; 'N'
    .byte $38, $44, $44, $44, $44, $44, $38, $00 ; 'O'
    .byte $78, $44, $44, $78, $40, $40, $40, $00 ; 'P'
    .byte $38, $44, $44, $44, $54, $48, $34, $00 ; 'Q'
    .byte $78, $44, $44, $78, $50, $48, $44, $00 ; 'R'
    .byte $38, $44, $40, $38, $04, $44, $38, $00 ; 'S'
    .byte $7C, $10, $10, $10, $10, $10, $10, $00 ; 'T'
    .byte $44, $44, $44, $44, $44, $44, $38, $00 ; 'U'
    .byte $44, $44, $44, $28, $28, $10, $10, $00 ; 'V'
    .byte $44, $44, $44, $44, $54, $6C, $44, $00 ; 'W'
    .byte $44, $44, $28, $10, $28, $44, $44, $00 ; 'X'
    .byte $44, $44, $28, $10, $10, $10, $10, $00 ; 'Y'
    .byte $7C, $04, $08, $10, $20, $40, $7C, $00 ; 'Z'
    .byte $38, $20, $20, $20, $20, $20, $38, $00 ; '['
    .byte $00, $40, $20, $10, $08, $04, $00, $00 ; '\'
    .byte $38, $08, $08, $08, $08, $08, $38, $00 ; ']'
    .byte $10, $38, $54, $10, $10, $10, $10, $00 ; '^'
    .byte $00, $10, $20, $7C, $20, $10, $00, $00 ; '_'
    .byte $10, $28, $44, $00, $00, $00, $00, $00 ; '`'
    .byte $00, $00, $38, $04, $3C, $44, $3C, $00 ; 'a'
    .byte $40, $40, $58, $64, $44, $64, $58, $00 ; 'b'
    .byte $00, $00, $38, $44, $40, $44, $38, $00 ; 'c'
    .byte $04, $04, $34, $4C, $44, $4C, $34, $00 ; 'd'
    .byte $00, $00, $38, $44, $7C, $40, $38, $00 ; 'e'
    .byte $08, $14, $10, $38, $10, $10, $10, $00 ; 'f'
    .byte $00, $00, $34, $4C, $4C, $34, $04, $38 ; 'g'
    .byte $40, $40, $58, $64, $44, $44, $44, $00 ; 'h'
    .byte $00, $10, $00, $30, $10, $10, $38, $00 ; 'i'
    .byte $00, $04, $00, $04, $04, $04, $44, $38 ; 'j'
    .byte $40, $40, $48, $50, $60, $50, $48, $00 ; 'k'
    .byte $30, $10, $10, $10, $10, $10, $38, $00 ; 'l'
    .byte $00, $00, $68, $54, $54, $54, $54, $00 ; 'm'
    .byte $00, $00, $58, $64, $44, $44, $44, $00 ; 'n'
    .byte $00, $00, $38, $44, $44, $44, $38, $00 ; 'o'
    .byte $00, $00, $78, $44, $44, $78, $40, $40 ; 'p'
    .byte $00, $00, $3C, $44, $44, $3C, $04, $04 ; 'q'
    .byte $00, $00, $58, $64, $40, $40, $40, $00 ; 'r'
    .byte $00, $00, $3C, $40, $38, $04, $78, $00 ; 's'
    .byte $20, $20, $70, $20, $20, $24, $18, $00 ; 't'
    .byte $00, $00, $44, $44, $44, $4C, $34, $00 ; 'u'
    .byte $00, $00, $44, $44, $44, $28, $10, $00 ; 'v'
    .byte $00, $00, $44, $54, $54, $28, $28, $00 ; 'w'
    .byte $00, $00, $44, $28, $10, $28, $44, $00 ; 'x'
    .byte $00, $00, $44, $44, $44, $3C, $04, $38 ; 'y'
    .byte $00, $00, $7C, $08, $10, $20, $7C, $00 ; 'z'
    .byte $08, $10, $10, $20, $10, $10, $08, $00 ; '{'
    .byte $10, $10, $10, $00, $10, $10, $10, $00 ; '|'
    .byte $20, $10, $10, $08, $10, $10, $20, $00 ; '}'
    .byte $20, $54, $08, $00, $00, $00, $00, $00 ; '~'
    .byte $00, $00, $00, $00, $00, $00, $7C, $00 ; DEL

;; Runs HDRAW string: draws on the hi-res graphics screen as DRAW does for Extended BASIC, with its commands: U, D,
;; L, R, E, F, G and H to move and draw, M to move to a point or by an offset, C for the color, A for the angle,
;; S for the scale, N and B for a move that does not keep its place or does not draw, and X to run a string
;; variable's commands. A number after a command may be =variable;.
;;
;; Errors: ?HR ERROR with no hi-res graphics screen; ?FC ERROR for a command or number HDRAW does not take
HDRAW:
    TST HRMODE
    LBEQ HRERR
    LBRN RAMLINK                    ; the hook, never taken
    LDX #0                          ; a string of no length at address 0 ends the drawing
    LDB #$01
    PSHS X,B
    STB SETFLG
    STX VD5                         ; no N or B yet
    JSR HSETWORK
    JSR FRMEVL
HDRAW_STRING:
    JSR FRESTR
    BRA HDRAW_START

;; Reads a command's number, or =variable;.
;;
;; Out:  D = the number, also in VD3
HDRAW_NUMBER:
    JSR HDRAWCHR
    JMP HDRAWVAL
HDRAW_POP:
    PULS B,X                        ; the string X interrupted
HDRAW_START:
    STB VD8
    BEQ HDRAW_POP
    STX VD9                         ; the string's place
    LBEQ NEGACCD_DONE               ; address 0: the end
HDRAW_NEXT:
    TST VD8
    BEQ HDRAW_POP
    JSR HDRAWCHR
    CMPA #';'                       ; separators are skipped
    BEQ HDRAW_NEXT
    CMPA #$27                       ; ' also separates
    BEQ HDRAW_NEXT
    CMPA #'N'                       ; N: the next move keeps no place
    BNE HDRAW_B
    COM VD5
    BRA HDRAW_NEXT
HDRAW_B:
    CMPA #'B'                       ; B: the next move draws nothing
    BNE HDRAW_X
    COM VD6
    BRA HDRAW_NEXT
HDRAW_X:
    CMPA #'X'
    LBEQ HDRAW_SUB
    CMPA #'M'
    LBEQ HDRAW_M
    PSHS A
    LDB #$01                        ; 1 when no number follows
    CLR VD3
    STB VD4
    TST VD8
    BEQ HDRAW_LETTER
    JSR HDRAWCHR
    JSR ISLETC                      ; a letter: no number
    PSHS CC
    JSR HDRAWBACK                   ; back to the character
    PULS CC
    BCC HDRAW_LETTER
    BSR HDRAW_NUMBER
HDRAW_LETTER:
    PULS A
    CMPA #'C'
    BEQ HDRAW_C
    CMPA #'A'
    BEQ HDRAW_A
    CMPA #'S'
    BEQ HDRAW_S
    CMPA #'U'
    BEQ HDRAW_U
    CMPA #'D'
    BEQ HDRAW_D
    CMPA #'L'
    BEQ HDRAW_L
    CMPA #'R'
    BEQ HDRAW_R
    SUBA #'E'                       ; E, F, G and H: diagonals
    BEQ HDRAW_E
    DECA
    BEQ HDRAW_F
    DECA
    BEQ HDRAW_G
    DECA
    BEQ HDRAW_H
    JMP FCERR
HDRAW_C:
    JSR HCOLORCHK
    STB H_FCOLOR
    JSR HSETWORK
    LBRA HDRAW_NEXT
HDRAW_A:
    CMPB #$04
    LBCC FCERR
    STB ANGLE
    LBRA HDRAW_NEXT
HDRAW_S:
    CMPB #63
    LBCC FCERR
    STB SCALE
    LBRA HDRAW_NEXT
HDRAW_H:
    LDA VD3                         ; H: up and left
    BSR NEGACCD
    BRA HDRAW_DIAG
HDRAW_F:
    LDA VD3                         ; F: down and right
HDRAW_DIAG:
    TFR D,X
    BRA HDRAWBY
HDRAW_E:
    LDA VD3                         ; E: up and right
    TFR D,X
    BSR NEGACCD
    EXG D,X
    BRA HDRAWBY
HDRAW_G:
    LDA VD3                         ; G: down and left
    TFR D,X
    BSR NEGACCD
    BRA HDRAWBY
HDRAW_R:
    LDA VD3
HDRAW_LEVEL:
    LDX #0                          ; no vertical move
    BRA HDRAWBY
HDRAW_L:
    LDA VD3
    BSR NEGACCD
    BRA HDRAW_LEVEL
HDRAW_D:
    LDA VD3
    BRA HDRAW_UPRIGHT
HDRAW_U:
    LDA VD3
    BSR NEGACCD
HDRAW_UPRIGHT:
    LDX #0                          ; no horizontal move
    EXG X,D
    BRA HDRAWBY
HDRAW_SUB:
    JSR HDRAWVAR                    ; the variable's string
    LDB #$02                        ; room for the string being run, on the stack
    JSR GETSTK
    LDB VD8
    LDX VD9
    PSHS X,B
    JMP HDRAW_STRING

;; Scales an offset by HDRAW's S: a quarter of it for each step of the scale, or the offset itself at 0.
;;
;; In:   X = the offset
;; Out:  D = the scaled offset
HDRAWSCALE:
    LDB SCALE
    BEQ HDRAWSCALE_NONE
    CLRA
    EXG D,X
    STA ,-S                         ; its sign
    BPL HDRAWSCALE_MUL
    BSR NEGACCD                     ; made positive
HDRAWSCALE_MUL:
    JSR HMUL16
    TFR U,D
    LSRA                            ; the quarters
    RORB
    LSRA
    RORB
    TST ,S+
    BPL NEGACCD_DONE

;; Negates D.
NEGACCD:
    NEGA
    NEGB
    SBCA #$00
NEGACCD_DONE:
    RTS
HDRAWSCALE_NONE:
    TFR X,D
    RTS

;; Moves HDRAW's place by an offset, scaled and turned by its scale and angle, and draws a line to it unless B came
;; before, as <DRAWBY> does for Extended BASIC.
;;
;; In:   D = the horizontal offset, X = the vertical offset
HDRAWBY:
    PSHS B,A
    BSR HDRAWSCALE
    PULS X
    PSHS B,A
    BSR HDRAWSCALE
    PULS X
    LDY ANGLE                       ; the angle and the scale
    PSHS Y
HDRAWBY_TURN:
    TST ,S
    BEQ HDRAWBY_ADD
    EXG X,D                         ; a quarter turn
    BSR NEGACCD
    DEC ,S
    BRA HDRAWBY_TURN
HDRAWBY_ADD:
    PULS Y
    LDU #0                          ; left of the edge: the edge
    ADDD HORDEF
    BMI HDRAWBY_V
    TFR D,U
HDRAWBY_V:
    TFR X,D
    LDX #0
    ADDD VERDEF
    BMI HDRAWTO
    TFR D,X

;; Moves HDRAW's place to a point, held to the screen, and draws a line to it unless B came before; with N the
;; place stays where it was.
;;
;; In:   U = the horizontal coordinate, X = the vertical coordinate
HDRAWTO:
    CMPU #640
    BCS HDRAWTO_320
    LDU #640-1
HDRAWTO_320:
    LDA HRMODE
    CMPA #$02
    BGT HDRAWTO_V
    CMPU #320
    BCS HDRAWTO_V
    LDU #320-1
HDRAWTO_V:
    CMPX #192
    BCS HDRAWTO_LINE
    LDX #192-1
HDRAWTO_LINE:
    LDD HORDEF
    STD HORBEG
    LDD VERDEF
    STD VERBEG
    STX VEREND
    STU HOREND
    TST VD5                         ; N?
    BNE HDRAWTO_DRAW
    STX VERDEF                      ; the new place
    STU HORDEF
HDRAWTO_DRAW:
    JSR HLINESCALE
    TST VD6                         ; B?
    BNE HDRAWTO_DONE
    JSR HDLINE
HDRAWTO_DONE:
    CLR VD5                         ; N and B last for one move
    CLR VD6
    JMP HDRAW_NEXT

;; HDRAW's M: Mx,y moves to a point, and M+x,y or M-x,y by an offset.
HDRAW_M:
    JSR HDRAWCHR                    ; + or - before the first number: an offset
    PSHS A
    JSR HDRAW_MNUM
    PSHS B,A
    JSR HDRAWCHR
    CMPA #','
    LBNE FCERR
    JSR HDRAW_MNEXT
    TFR D,X
    PULS U
    PULS A
    CMPA #'+'                       ; an offset?
    BEQ HDRAW_MBY
    CMPA #'-'
    BNE HDRAWTO
HDRAW_MBY:
    TFR U,D
    JMP HDRAWBY

;; Reads one of M's numbers, with a sign when it has one.
;;
;; Out:  D = the number
HDRAW_MNEXT:
    JSR HDRAWCHR
HDRAW_MNUM:
    CMPA #'+'
    BEQ HDRAW_MPLUS
    CMPA #'-'
    BEQ HDRAW_MSIGN
    JSR HDRAWBACK                   ; no sign: back to the number
HDRAW_MPLUS:
    CLRA
HDRAW_MSIGN:
    PSHS A                          ; 0 for +, else -
    JSR HDRAW_NUMBER
    TST ,S+
    BEQ HDRAW_MDONE
    NEGB                            ; negated, though B alone is not enough when the low byte is 0
    SBCA #$00
HDRAW_MDONE:
    RTS

;; Reads HDRAW's next character, skipping spaces.
;;
;; Out:  A = the character
;; Errors: ?FC ERROR past the string's end
;; Keeps: X
HDRAWCHR:
    PSHS X
HDRAWCHR_LOOP:
    TST VD8
    LBEQ FCERR
    LDX VD9
    LDA ,X+
    STX VD9
    DEC VD8
    CMPA #' '
    BEQ HDRAWCHR_LOOP
    PULS X,PC

;; Reads a command's number: =variable; or digits, up to the screen's width.
;;
;; In:   A = the number's first character
;; Out:  D = the number, also in VD3
;; Errors: ?FC ERROR when it is not a number, or past the screen's width
HDRAWVAL:
    CMPA #'='
    BNE HDRAWVAL_DIGITS
    PSHS U,Y
    BSR HDRAWVAR
    JSR POSCHK                      ; its value, a positive integer
    STD VD3
    PULS Y,U,PC
HDRAWVAL_DIGITS:
    JSR HDRAWDIGIT
    LBCS FCERR
    CLR VD3
    CLR VD4
HDRAWVAL_DIGIT:
    SUBA #'0'
    STA VD7
    LDD VD3
    BSR HMUL10                      ; times ten
    ADDB VD7
    ADCA #$00
    STD VD3
    LDA HRMODE
    CMPA #$02                       ; 640 across?
    BGT HDRAWVAL_640
    LDD #320-1
    BRA HDRAWVAL_CHECK
HDRAWVAL_640:
    LDD #640-1
HDRAWVAL_CHECK:
    CMPD VD3
    LBLT FCERR
    LDD VD3                         ; again: D is reloaded below
    TST VD8
    BEQ HDRAWVAL_DONE
    JSR HDRAWCHR
    JSR HDRAWDIGIT
    BCC HDRAWVAL_DIGIT

;; Steps HDRAW's string back a character.
;;
;; Out:  D = VD3
HDRAWBACK:
    INC VD8
    LDX VD9
    LEAX -1,X
    STX VD9
HDRAWVAL_DONE:
    LDD VD3
    RTS

;; Multiplies D by ten.
HMUL10:
    ASLB
    ROLA
    PSHS B,A
    ASLB
    ROLA
    ASLB
    ROLA
    ADDD ,S++
    RTS

;; Checks for a digit.
;;
;; In:   A = the character
;; Out:  carry = clear for 0 to 9
HDRAWDIGIT:
    CMPA #'0'
    BCS HDRAWDIGIT_DONE
    SUBA #'9'+1                     ; carry clear only from '0' to '9'
    SUBA #-('9'+1) & $FF
HDRAWDIGIT_DONE:
    RTS

;; Reads the variable a command names, up to the ; that ends it, as BASIC would read it in an expression.
;;
;; Out:  FPA0 = its value, a number or a string's descriptor
HDRAWVAR:
    LDX VD9
    PSHS X
    JSR HDRAWCHR
    JSR ISLETC                      ; a variable starts with a letter
    LBCS FCERR
HDRAWVAR_END:
    JSR HDRAWCHR
    CMPA #';'
    BNE HDRAWVAR_END
    PULS X
    LDU CHARAD                      ; BASIC's place, kept
    PSHS U
    STX CHARAD                      ; BASIC reads from the string
    JSR EVAL_VAR
    PULS X
    STX CHARAD
    RTS

;; Runs WIDTH 32|40|80: the text screen BASIC prints on, the 32-column CoCo compatible screen or the 40 or 80-column
;; hi-res screen, cleared, with any hi-res graphics screen gone.
;;
;; Errors: ?FC ERROR for any other width
WIDTH:
    CLR HRMODE
    LBRN RAMLINK                    ; the hook, never taken
    CMPA #$00                       ; no width?
    BEQ WIDTH_FC
    JSR GETBYT
    CMPB #32
    BEQ COL32
    CMPB #40
    BEQ COL40
    CMPB #80
    BEQ COL80
WIDTH_FC:
    JMP FCERR

;; WIDTH 32: the CoCo compatible screen, cleared.
COL32:
    CLRA
    STA HRWIDTH
    JSR CLRSCN
    LBSR SETTEXT
    RTS

;; WIDTH 40: the 40-column screen, cleared.
COL40:
    LDA #$01
    STA HRWIDTH
    LBSR HTEXTON                    ; the text screen at $2000
    LDA #40
    LDB #ROWMAX
    STD H_COLUMN
    LDD #HRESSCRN+40*ROWMAX*2       ; two bytes to a character: it and its attributes
COL40_END:
    STD H_DISPEN
    BSR HCLRTEXT
    LBSR HTEXTOFF                   ; BASIC's block back
    LBSR SETTEXT
    RTS

;; WIDTH 80: the 80-column screen, cleared.
COL80:
    LDA #$02
    STA HRWIDTH
    LBSR HTEXTON
    LDA #80
    LDB #ROWMAX
    STD H_COLUMN
    LDD #HRESSCRN+80*ROWMAX*2
    BRA COL40_END

;; Clears the hi-res text screen to spaces in the attributes <H_CRSATT> holds, and puts the cursor at its top left.
;; The screen must be mapped in, as <SELTEXT> maps it.
;;
;; Out:  X = the screen's start
HCLRTEXT:
    LDX #HRESSCRN
    LBRN RAMLINK                    ; the hook, never taken
    STX H_CRSLOC
    LDA #' '
    LDB H_CRSATT

;; Fills the hi-res text screen from X to its end.
;;
;; In:   A = the character, B = its attributes, X = where to start
HCLRTEXT_LOOP:
    STD ,X++
    CMPX H_DISPEN
    BCS HCLRTEXT_LOOP
    LDX #HRESSCRN
    CLRA
    STA H_CURSX
    STA H_CURSY
    RTS

;; CLS on the hi-res text screen, from <CLS3>: CLS or CLS 0 clears it in the attributes it has; CLS 1 to 8 clears
;; it with the color's palette register as the border and as the characters' attributes; past 8 it clears it to
;; plain spaces, with a message, as Color BASIC's CLS does: Microware's, or once, for CLS 100, the authors'.
;;
;; In:   CC = <CLS>'s, zero = set when CLS has no color
CLS20:
    PULS CC
    LBRN RAMLINK                    ; the hook, never taken
    BEQ CLS20_PLAIN
    JSR GETBYT
    TSTB
    BEQ CLS20_PLAIN
    CMPB #$08                       ; past 8?
    BHI CLS20_MSG
    DECB                            ; colors from 0
    LEAY >IM_PALET,PCR
    LDA B,Y                         ; the color's palette value
    STA V_BORDER
    LBSR SETBORDER
    STB H_CRSATT                    ; the color as the attributes: the background, on the 40 and 80-column screens
    LDA #' '
    LBSR HTEXTON
    LDX #HRESSCRN
    STX H_CRSLOC
    BSR HCLRTEXT_LOOP
CLS20_DONE:
    LBSR HTEXTOFF
    RTS
CLS20_PLAIN:
    LBSR HTEXTON
    BSR HCLRTEXT
    BRA CLS20_DONE
CLS20_MSG:
    CLR H_CRSATT
    LDA IM_PALET
    STA V_BORDER
    BSR SETBORDER
    CMPB #100
CLS20_AUTHORS:
    BEQ CLS20_SHOWNAMES             ; the authors once: this branch becomes NOP, NOP
    BSR HTEXTON
    BSR HCLRTEXT
    BSR HTEXTOFF
    LDX #MICROMS-1
    JMP STROUT1

;; The message CLS past 8 shows on the hi-res text screen.
MICROMS:
    .byte "Microware Systems Corp."
    .byte $0D, $00

;; The authors' names, which <AUTHNAMES> decodes here at start-up, for CLS 100 to show once.
AUTHORMS:
    .byte $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00
CLS20_SHOWNAMES:
    BSR HTEXTON
    LBSR HCLRTEXT
    BSR HTEXTOFF
    LDX #AUTHORMS-1
    JSR STROUT1
    PSHS X
    LEAX >CLS20_AUTHORS,PCR         ; the branch to here, in <CLS20>
    LDA #$12                        ; NOP
    STA ,X+
    STA ,X
    LEAX >AUTHORMS,PCR              ; and the names and this code too, up to the loop
CLS20_ERASE:
    STA ,X+
    CMPX #CLS20_ERASE
    BCS CLS20_ERASE
    PULS X
    RTS

;; Typing a line: the patch at <LINEIN_CLEAR> comes here, so the line's input clears the text screen in use.
LINEIN20:
    TST HRWIDTH
    BNE LINEIN20_HIRES
    JSR CLRSCN
LINEIN20_GO:
    JMP LINEIN                      ; the rest of LINEIN
LINEIN20_HIRES:
    LBSR CLS20_PLAIN
    BRA LINEIN20_GO

;; Puts a border color in the 40 and 80-column screens' video images.
;;
;; In:   A = the color
;; Keeps: Y
SETBORDER:
    PSHS Y
    LEAY >IM_TEXT40,PCR
    STA 3,Y                         ; $FF9A in the 40-column image
    STA 12,Y                        ; and in the 80-column one
    PULS Y,PC

;; Maps the hi-res text screen in at $2000, with interrupts off.
HTEXTON:
    ORCC #$50
    LBSR SELTEXT
    RTS

;; Maps BASIC's own RAM back at $2000, and lets interrupts in.
HTEXTOFF:
    LBSR SETMMU
    ANDCC #$AF
    RTS

;; Waits for a key on the hi-res text screen, blinking its cursor, from <WAITKY3>.
;;
;; Out:  A = the key
WAITKY20:
    BSR HBLINK
    JSR KEYIN
    BEQ WAITKY20
    PULS B,X,PC

;; Blinks the hi-res text screen's cursor: every eleventh call underlines it or not, then waits a moment.
HBLINK:
    DEC BLKCNT
    BNE HBLINK_WAIT
    LDB #11
    STB BLKCNT
    BSR HTEXTON
    LDX H_CRSLOC
    LDA 1,X
    BITA #$40                       ; underlined now?
    BEQ HBLINK_ON
    LDA H_CRSATT
    BRA HBLINK_SET
HBLINK_ON:
    LDA H_CRSATT
    ORA #$40                        ; underlined
HBLINK_SET:
    STA 1,X
    BSR HTEXTOFF
HBLINK_WAIT:
    LDX #DEBDEL
    JMP WAITX

;; Prints a character on the hi-res text screen, from <PUTCHR3>: backspace and carriage return move the cursor,
;; other control characters are ignored, and the screen scrolls when the cursor passes the bottom. The cursor is
;; an underlined space.
;;
;; In:   A = the character, and A, B and X on the stack, which it pulls and returns past
PUTCHR20:
    BSR HTEXTON
    LBRN RAMLINK                    ; the hook, never taken
    LDX H_CRSLOC
    CMPA #$08
    BNE PUTCHR20_CR
    CMPX #HRESSCRN                  ; at the top left?
    BEQ PUTCHR20_DONE
    BSR HBACKSP
    BRA PUTCHR20_DONE
PUTCHR20_CR:
    CMPA #$0D
    BNE PUTCHR20_CHAR
    BSR HNEWLINE
    BRA PUTCHR20_SCROLL
PUTCHR20_CHAR:
    CMPA #$20                       ; a control character?
    BCS PUTCHR20_DONE
    LDB H_CRSATT                    ; in the attributes characters print in
    STD ,X
    BSR HCURFWD
PUTCHR20_SCROLL:
    CMPX H_DISPEN                   ; past the screen's end?
    BCS PUTCHR20_DONE
    BSR HSCROLL
PUTCHR20_DONE:
    BSR HTEXTOFF
    PULS A,B,X,PC

;; Moves the hi-res text cursor back a character, erasing the one it was on.
;;
;; In:   X = the cursor's address
HBACKSP:
    PSHS B,A
    LDA #' '
    LDB H_CRSATT
    STD ,X
    ORB #$40                        ; the cursor: underlined
    STD -2,X
    LEAX -2,X
    STX H_CRSLOC
    LDD H_CURSX
    DECA
    BPL HCURSX                      ; wrapped back past the left edge?
    DECB
    STB H_CURSY
    LDA H_COLUMN                    ; then the last column
    DECA
HCURSX:
    STA H_CURSX
    PULS A,B,PC

;; Moves the hi-res text cursor forward a character, to the next row past the right edge.
;;
;; In:   X = the cursor's address
;; Out:  X = the new address
HCURFWD:
    PSHS B,A
    LDA #$20                        ; the cursor: an underlined space
    LDB H_CRSATT
    ORB #$40
    LEAX 2,X
    STD ,X
    STX H_CRSLOC
    LDD H_CURSX
    INCA
    CMPA H_COLUMN
    BCS HCURSX
    INCB
    STB H_CURSY
    CLRA
    BRA HCURSX

;; Blanks the rest of the hi-res text cursor's row and moves it to the next row's start.
;;
;; In:   X = the cursor's address
;; Out:  X = the new address
HNEWLINE:
    PSHS B,A
    LDA #' '
    LDB H_CRSATT
HNEWLINE_LOOP:
    STD ,X++
    PSHS A
    LDA H_CURSX
    INCA
    STA H_CURSX
    CMPA H_COLUMN
    PULS A
    BCS HNEWLINE_LOOP
    STX H_CRSLOC
    CLR H_CURSX
    INC H_CURSY
    LDA #$20                        ; the cursor
    LDB H_CRSATT                    ; B holds this already
    ORB #$40
    STD ,X
    PULS A,B,PC

;; Scrolls the hi-res text screen up a row and blanks the last, with the cursor at its start.
;;
;; Out:  X = the cursor's address
HSCROLL:
    PSHS B,A
    LDX #HRESSCRN
    LDA H_COLUMN
    CMPA #40                        ; 80 columns?
    BNE HSCROLL80
HSCROLL40:
    LDD 2*40,X
    STD ,X++
    CMPX #HRESSCRN+(ROWMAX-1)*40*2
    BCS HSCROLL40
HSCROLL_DONE:
    BSR HLASTROW
    PULS A,B,PC
HSCROLL80:
    LDD >80*2,X
    STD ,X++
    CMPX #HRESSCRN+(ROWMAX-1)*80*2
    BCS HSCROLL80
    BRA HSCROLL_DONE

;; Blanks the hi-res text screen from X to its end and puts the cursor at X, in the last row.
;;
;; In:   X = where the last row starts
HLASTROW:
    CLR H_CURSX
    LDA #ROWMAX-1
    STA H_CURSY
    LDA #' '
    LDB H_CRSATT
    PSHS X
HLASTROW_LOOP:
    STD ,X++
    CMPX H_DISPEN
    BNE HLASTROW_LOOP
    CLR H_CURSX                     ; again: it was cleared above
    PULS X
    LDA #$20                        ; the cursor
    LDB H_CRSATT
    ORB #$40
    STD ,X
    STX H_CRSLOC
    RTS

;; Starting a new line: the patch at <NEWLIN> comes here, so the hi-res text screen's cursor column counts.
NEWLIN20:
    TST DEVNUM                      ; the screen?
    BNE NEWLIN20_LORES
    TST HRWIDTH
    BNE NEWLIN20_HIRES
NEWLIN20_LORES:
    JSR SETPRM
    JMP NEWLIN_CHECK                ; the rest of NEWLIN
NEWLIN20_HIRES:
    LBSR HTEXTON
    TST H_CURSX                     ; at a row's start?
    PSHS CC
    LBSR HTEXTOFF
    PULS CC
    LBNE PRNTCR                     ; no: a new line
    RTS

;; PRINT @: the patch in <PRINT_AT> comes here, since PRINT @ is only for the 32-column screen; on the hi-res text
;; screen it raises ?HP ERROR.
;;
;; In:   D = the position
PRINTAT20:
    TST HRWIDTH
    BNE HPERR                       ; the hi-res text screen?
    JSR SETCUR                      ; the cursor to the position, as before
    JMP PRINT_AT_COMMA

;; Raises ?HP ERROR: a command for the 32-column screen used on the hi-res text screen, or LOCATE or ATTR without it.
HPERR:
    LDB #ERR_HP
    JMP ERROR

;; Runs LOCATE column,row: moves the hi-res text screen's cursor.
;;
;; Errors: ?HP ERROR on the 32-column screen; ?FC ERROR past the screen's columns or 24 rows
LOCATE:
    LDB HRWIDTH
    LBRN RAMLINK                    ; the hook, never taken
    BEQ HPERR
    PSHS B
    JSR HGETXYS
    LDA BINVAL+1
    PULS B
    CMPB #$01                       ; 40 columns?
    BNE LOCATE_80
    CMPA #40
    BRA LOCATE_CHECK
LOCATE_80:
    CMPA #80
LOCATE_CHECK:
    LBCC FCERR
    LDB VERBEG+1
    CMPB #ROWMAX
    BCC LOCATE_CHECK
    PSHS B,A
    LBSR HTEXTON
    STD H_CURSX                     ; the new column and row
    LDX H_CRSLOC
    LDA H_CRSATT                    ; the old cursor without its underline
    STA 1,X
    LDA H_COLUMN
    ASLA                            ; two bytes to a character
    MUL
    LDX #HRESSCRN                   ; the row's start
    LEAX D,X
    PULS A,B
    ASLA
    TFR A,B
    ABX
    LDA H_CRSATT                    ; the new cursor underlined
    ORA #$40
    STA 1,X
    STX H_CRSLOC
    LBSR HTEXTOFF
    RTS

;; Runs HSTAT character$,attributes,column,row: puts the hi-res text cursor's character, its attributes and its
;; place into four variables.
;;
;; Errors: ?HP ERROR on the 32-column screen; ?TM ERROR for a variable of the wrong type
HSTAT:
    TST HRWIDTH
    LBRN RAMLINK                    ; the hook, never taken
    BEQ HPERR
    LBSR HTEXTON
    LDX H_CRSLOC
    LDD ,X                          ; the character under the cursor and its attributes
    STD VCB
    LDD H_CURSX                     ; the column and row
    STD VCD
    LBSR HTEXTOFF
    JSR PTRGET                      ; the first variable
    STX VARDES
    JSR SYNCOM
    LDB #$01
    JSR GETSPA                      ; a one-character string
    LDA VCB
    JSR STRSET                      ; again: the string's descriptor is set already
    STA ,X
    JSR PUTNEW
    LDX VARDES
    TST -1,X                        ; a string variable?
    LBPL TMERR
    LDY FPA0+2
    LDB #$05                        ; its descriptor into the variable
HSTAT_COPY:
    LDA ,Y+
    STA ,X+
    DECB
    BNE HSTAT_COPY
    LDX TEMPPT                      ; off the string stack, though its last entry pointer stays
    LEAX -5,X
    STX TEMPPT
    JSR PTRGET                      ; the second variable: the attributes
    STX VARDES
    JSR SYNCOM
    CLRA
    LDB VCB+1
    JSR GIVABF
    LDX VARDES
    TST -1,X                        ; a numeric variable?
    LBMI TMERR
    JSR MOVMF
    JSR PTRGET                      ; the third: the column
    STX VARDES
    JSR SYNCOM
    CLRA
    LDB VCD
    JSR GIVABF
    LDX VARDES
    TST -1,X
    LBMI TMERR
    JSR MOVMF
    JSR PTRGET                      ; the fourth: the row
    STX VARDES
    CLRA
    LDB VCD+1
    JSR GIVABF
    LDX VARDES
    TST -1,X
    LBMI TMERR
    JSR MOVMF
    RTS

;; Runs ATTR foreground,background[,B][,U]: the attributes the hi-res text screen prints in, the colors 0 to 7 and
;; blinking or underlined.
;;
;; Errors: ?FC ERROR for a color past 7, or anything but B or U
ATTR:
    JSR GETBYT
    LBRN RAMLINK                    ; the hook, never taken
    CMPB #$08
    LBCC FCERR
    ASLB                            ; the foreground in bits 3-5
    ASLB
    ASLB
    PSHS B
    JSR GETCCH
    JSR SYNCOM
    JSR GETBYT
    CMPB #$08
    LBCC FCERR
    ORB ,S                          ; the background in bits 0-2
    LEAS 1,S
    ANDB #$3F                       ; nothing above them yet
    PSHS B
    JSR GETCCH
ATTR_FLAGS:
    BEQ ATTR_SET
    JSR SYNCOM
    CMPA #'B'
    BNE ATTR_U
    PULS B
    ORB #$80                        ; blinking
    PSHS B
    JSR GETNCH
    BRA ATTR_FLAGS
ATTR_U:
    CMPA #'U'
    LBNE FCERR
    PULS B
    ORB #$40                        ; underlined
    PSHS B
    JSR GETNCH
    BRA ATTR_FLAGS
ATTR_SET:
    PULS B
    STB H_CRSATT
    RTS

;; Room past Super Extended BASIC to the constant page, which nothing uses.
SUPEREND:
    .byte $00, $00, $00, $00, $38, $44, $40, $40, $40, $44, $38, $10, $44, $00, $44, $44
    .byte $44, $4C, $34, $00, $08, $10, $38, $44, $7C, $40, $38, $00, $10, $28, $38, $04
    .byte $3C, $44, $3C, $00, $28, $00, $38, $04, $3C, $44, $3C, $00, $20, $10, $38, $04
    .byte $3C, $44, $3C, $00, $10, $00, $38, $04, $3C, $44, $3C, $00, $00, $00, $38, $44
    .byte $40, $44, $38, $10, $10, $28, $38, $44, $7C, $40, $38, $00, $28, $00, $38, $44
    .byte $7C, $40, $38, $00, $20, $10, $38, $44, $7C, $40, $38, $00, $28, $00, $30, $10
    .byte $10, $10, $38, $00, $10, $28, $00, $30, $10, $10, $38, $00, $00, $18, $24, $38
    .byte $24, $24, $38, $40, $44, $10, $28, $44, $7C, $44, $44, $00, $10, $10, $28, $44
    .byte $7C, $44, $44, $00, $08, $10, $38, $44, $44, $44, $38, $00, $00, $00, $68, $14
    .byte $3C, $50, $3C, $00, $3C, $50, $50, $78, $50, $50, $5C, $00, $10, $28, $38, $44
    .byte $44, $44, $38, $00, $28, $00, $38, $44, $44, $44, $38, $00, $00, $00, $38, $4C
    .byte $54, $64, $38, $00, $10, $28, $00, $44, $44, $4C, $34, $00, $20, $10, $44, $44
    .byte $44, $4C, $34, $00, $38, $4C, $54, $54, $54, $64, $38, $00, $44, $38, $44, $44
    .byte $44, $44, $38, $00, $28, $44, $44, $44, $44, $44, $38, $00, $38, $40, $38, $44
    .byte $38, $04, $38, $00, $08, $14, $10, $38, $10, $50, $3C, $00, $10, $10, $7C, $10
    .byte $10, $00, $7C, $00, $10, $28, $10, $00, $00, $00, $00, $00, $08, $14, $10, $38
    .byte $10, $10, $20, $40, $00, $10, $18, $1C, $1C, $18, $10, $00, $00, $08, $18, $38
    .byte $38, $18, $08, $00, $00, $00, $00, $7E, $3C, $18, $00, $00, $00, $00, $18, $3C
    .byte $7E, $00, $00, $00, $00, $FF, $00, $FF, $FF, $00, $FF, $00, $00, $00, $30, $3C
    .byte $14, $1C, $00, $00, $00, $7E, $42, $5A, $5A, $42, $7E, $00, $00, $7E, $7E, $00
    .byte $00, $7E, $7E, $00, $00, $3C, $3C, $3C, $3C, $3C, $3C, $00, $00, $00, $7E, $7E
    .byte $7E, $7E, $00, $00, $00, $7E, $24, $18, $18, $24, $7E, $00, $00, $7F, $00, $7F
    .byte $7F, $00, $7F, $00, $00, $FE, $00, $FE, $FE, $00, $FE, $00, $38, $44, $40, $40
    .byte $40, $44, $38, $10, $44, $00, $44, $44, $44, $4C, $34, $00, $08, $10, $38, $44
    .byte $7C, $40, $38, $00, $10, $28, $38, $04, $3C, $44, $3C, $00, $28, $00, $38, $04
    .byte $3C, $44, $3C, $00, $20, $10, $38, $04, $3C, $44, $3C, $00, $10, $00, $38, $04
    .byte $3C, $44, $3C, $00, $00, $00, $38, $44, $40, $44, $38, $10, $10, $28, $38, $44
    .byte $7C, $40, $38, $00, $28, $00, $38, $44, $7C, $40, $38, $00, $20, $10, $38, $44
    .byte $7C, $40, $38, $00, $28, $00, $30, $10, $10, $10, $38, $00, $10, $28, $00, $30
    .byte $10, $10, $38, $00, $00, $18, $24, $38, $24, $24, $38, $40, $44, $10, $28, $44
    .byte $7C, $44, $44, $00, $10, $10, $28, $44, $7C, $44, $44, $00, $08, $10, $38, $44
    .byte $44, $44, $38, $00, $00, $00, $68, $14, $3C, $50, $3C, $00, $3C, $50, $50, $78
    .byte $50, $50, $5C, $00, $10, $28, $38, $44, $44, $44, $38, $00, $28, $00, $38, $44
    .byte $44, $44, $38, $00, $00, $00, $38, $4C, $54, $64, $38, $00, $10, $28, $00, $44
    .byte $44, $4C, $34, $00, $20, $10, $44, $44, $44, $4C, $34, $00, $38, $4C, $54, $54
    .byte $54, $64, $38, $00, $44, $38, $44, $44, $44, $44, $38, $00, $28, $44, $44, $44
    .byte $44, $44, $38, $00, $38, $40, $38, $44, $38, $04, $38, $00, $08, $14, $10, $38
    .byte $10, $50, $3C, $00, $10, $10, $7C, $10, $10, $00, $7C, $00, $10, $28, $10, $00
    .byte $00, $00, $00, $00, $08, $14, $10, $38, $10, $10, $20, $40, $00, $10, $18, $1C
    .byte $1C, $18, $10, $00, $00, $08, $18, $38, $38, $18, $08, $00, $00, $00, $00, $7E
    .byte $3C, $18, $00, $00, $00, $00, $18, $3C, $7E, $00, $00, $00, $00, $FF, $00, $FF
    .byte $FF, $00, $FF, $00, $00, $00, $30, $3C, $14, $1C, $00, $00, $00, $7E, $42, $5A
    .byte $5A, $42, $7E, $00, $00, $7E, $7E, $00, $00, $7E, $7E, $00, $00, $3C, $3C, $3C
    .byte $3C, $3C, $3C, $00, $00, $00, $7E, $7E, $7E, $7E, $00, $00, $00, $7E, $24, $18
    .byte $18, $24, $7E, $00, $00, $7F, $00, $7F, $7F, $00, $7F, $00, $00, $FE, $00, $FE
    .byte $FE, $00, $FE, $00, $38, $44, $40, $40, $40, $44, $38, $10, $44, $00, $44, $44
    .byte $44, $4C, $34, $00, $08, $10, $38, $44, $7C, $40, $38, $00, $10, $28, $38, $04
    .byte $3C, $44, $3C, $00, $28, $00, $38, $04, $3C, $44, $3C, $00, $20, $10, $38, $04
    .byte $3C, $44, $3C, $00, $10, $00, $38, $04, $3C, $44, $3C, $00, $00, $00, $38, $44
    .byte $40, $44, $38, $10, $10, $28, $38, $44, $7C, $40, $38, $00, $28, $00, $38, $44
    .byte $7C, $40, $38, $00, $20, $10, $38, $44, $7C, $40, $38, $00, $28, $00, $30, $10
    .byte $10, $10, $38, $00, $10, $28, $00, $30, $10, $10, $38, $00, $00, $18, $24, $38
    .byte $24, $24, $38, $40, $44, $10, $28, $44, $7C, $44, $44, $00, $10, $10, $28, $44
    .byte $7C, $44, $44, $00, $08, $10, $38, $44, $44, $44, $38, $00, $00, $00, $68, $14
    .byte $3C, $50, $3C, $00, $3C, $50, $50, $78, $50, $50, $5C, $00, $10, $28, $38, $44
    .byte $44, $44, $38, $00, $28, $00, $38, $44, $44, $44, $38, $00, $00, $00, $38, $4C
    .byte $54, $64, $38, $00, $10, $28, $00, $44, $44, $4C, $34, $00, $20, $10, $44, $44
    .byte $44, $4C, $34, $00, $38, $4C, $54, $54, $54, $64, $38, $00, $44, $38, $44, $44
    .byte $44, $44, $38, $00, $28, $44, $44, $44, $44, $44, $38, $00, $38, $40, $38, $44
    .byte $38, $04, $38, $00, $08, $14, $10, $38, $10, $50, $3C, $00, $10, $10, $7C, $10
    .byte $10, $00, $7C, $00, $10, $28, $10, $00, $00, $00, $00, $00, $08, $14, $10, $38
    .byte $10, $10, $20, $40, $00, $10, $18, $1C, $1C, $18, $10, $00, $00, $08, $18, $38
    .byte $38, $18, $08, $00, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF

; ----------------------------------------------------------------------------------------------------------------
; The constant page's and the I/O page's place, which the GIME never reads from the ROM, and the vectors
; ----------------------------------------------------------------------------------------------------------------

;; What the ROM holds under the constant page and the I/O page, which the GIME maps elsewhere: a pattern of $FF
;; and $00, eight bytes of each.
ROMFILL:
    .repeat 16
    .res 8, $FF
    .res 8, $00
    .endrepeat
    .repeat 15
    .res 8, $00
    .res 8, $FF
    .endrepeat

;; The 6809's interrupt vectors, which the GIME reads from here whatever the ROM's map: each points to the
;; constant page's jump, from <INTIMAGE>, and RESET to <INTRESET>, as Color BASIC's own do in the CoCo 3.
VECTORS:
    .dbyt 0                         ; reserved
    .dbyt INT_SWI3                  ; SWI3
    .dbyt INT_SWI2                  ; SWI2
    .dbyt INT_FIRQ                  ; FIRQ
    .dbyt INT_IRQ                   ; IRQ
    .dbyt INT_SWI                   ; SWI
    .dbyt INT_NMI                   ; NMI
    .dbyt INTRESET                  ; RESET
