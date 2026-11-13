;; TRS-80 COLOR COMPUTER COLOR BASIC ($A000-$BFFF), VERSIONS 1.0 TO 1.3
;;
;; Color BASIC is the Color Computer's 8K ROM: Microsoft BASIC for the 6809 with Radio Shack's drivers for the
;; keyboard, screen, cassette, printer, joysticks and sound.
;;
;; The first fourteen bytes are the documented ROM calls: each is the address of a routine, so a program calls
;; one with `JSR [POLCAT]` or `JSR [CHROUT]` (<POLCAT>, <CHROUT>). The interrupt vectors at the top of the ROM
;; (<VECTRS>) point into page 1 of RAM, where each is a JMP that Extended and Disk BASIC can change. The same way,
;; BASIC calls most of its device handling through the RAM hooks <RVEC0> to <RVEC24>, each a three-byte
;; instruction that the later ROMs replace with a JMP to their own code.
;;
;; BASIC itself follows Microsoft's design. A program line is stored crunched (<CRUNCH>), with each reserved word
;; a one-byte token: commands from $80, and functions as $FF and a second byte. The interpreter (<NEWSTT>) finds a
;; token's routine through the tables in <COMVEC>, one for each ROM, so Extended and Disk BASIC add their words
;; without changing this one. Errors load their code into B and jump to <ERROR>. Numbers are five-byte floating
;; point, an exponent and four bytes of mantissa, in <FPA0> and <FPA1> while they are worked on.
;;
;; Assembles byte-identically to Color BASIC 1.0, 1.1, 1.2 or 1.3: VERSION selects the version (12, the
;; default, or 10, 11 or 13). 1.0 starts up through U rather than Y and starts the program at $0601; 1.0 and 1.1
;; scan the keyboard with their own routines and have no busy check before printing; 1.3 sets the SAM for 16K or
;; 64K chips only.
;;
;; Labels follow the names Microsoft's BASIC and Spectral Associates' Color BASIC Unravelled use where they have
;; them, such as <TXTTAB>, <FRMEVL> and <NEWSTT>, and the ROM calls' names Radio Shack documents. The comments are
;; our own.
;;
;; Maintained by hand. CocoRomSourceTests check that each version assembles byte-identically to its ROM.

.ifndef VERSION
VERSION = 12
.endif
.assert (VERSION = 10) | (VERSION = 11) | (VERSION = 12) | (VERSION = 13), "VERSION is 10, 11, 12 or 13."
.ifndef COCO3
COCO3 = 0
.endif
.assert (COCO3 = 0) | (VERSION = 12), "The CoCo 3's Color BASIC is 1.2, patched."

.cpu M6809

.include "ColorBasicEquates.asm"
.if COCO3
.include "Coco3Equates.asm"
.include "ExtendedBasicEntries.asm"
.include "Coco3Entries.asm"
.endif

.org $A000

;; The ROM calls Radio Shack documents: each holds the address of a routine, so a program calls one with
;; `JSR [POLCAT]`, and later ROMs can move a routine without moving its entry.
;;
;; See: <KEYIN>, <PUTCHR>, <CASON>, <GETBLK>, <SNDBLK>, <GETJOY>, <WRLDR>
POLCAT:
    .dbyt KEYIN                     ; POLCAT: reads the keyboard, returning a key in A or zero
;; Inherit: <POLCAT>
CHROUT:
    .dbyt PUTCHR                    ; CHROUT: prints the character in A on the device in DEVNUM
;; Inherit: <POLCAT>
CSRDON:
    .dbyt CASON                     ; CSRDON: starts the cassette motor and finds a leader
;; Inherit: <POLCAT>
BLKIN:
    .dbyt GETBLK                    ; BLKIN: reads a cassette block into the buffer at CBUFAD
;; Inherit: <POLCAT>
BLKOUT:
    .dbyt SNDBLK                    ; BLKOUT: writes a cassette block from the buffer at CBUFAD
;; Inherit: <POLCAT>
JOYIN:
    .dbyt GETJOY                    ; JOYIN: reads the joysticks into POTVAL
;; Inherit: <POLCAT>
WRTLDR:
    .dbyt WRLDR                     ; WRTLDR: starts the cassette motor and writes a leader

;; Restarts BASIC after RESET: warm starts through <RSTVEC> when <RSTFLG> holds $55 and the warm start's first
;; instruction is NOP, and otherwise cold starts.
;;
;; <RESVEC> sets up the hardware first, then comes here.
WARMCK:
    LDS #LINBUF+LBUFMX+1            ; the stack starts at the top of the line input buffer
    LDA #$37
    STA PIA1+3                      ; CB1 on its rising edge, sound on: let the cartridge's interrupt in
    LDA RSTFLG
    CMPA #$55                       ; a warm start set up?
    BNE COLDST
    LDX RSTVEC
    LDA ,X
    CMPA #$12                       ; does the warm start begin with NOP?
    BNE COLDST
    JMP ,X

.if VERSION = 10
;; Inherit:
RESVEC:
    LDU #WARMCK
;; Sets up the PIAs, the SAM and the direct page as at power on, then jumps to U.
;;
;; The SAM is set for 16K chips when the RAM size jumper says so, and otherwise left at 4K.
;;
;; In:   U = where to go next
;; Out:  DP = 0
INITHW:
    CLRB
    TFR B,DP
    LDX #PIA0
    CLR 1,X                         ; the control registers: reach the direction registers
    CLR 3,X
    CLR ,X                          ; port A, the rows, all inputs
    LDD #$FF34
    STA 2,X                         ; port B, the columns, all outputs
    STB 1,X                         ; both control registers: data registers, interrupts off
    STB 3,X
    LDX #PIA1
    CLR 1,X
    CLR 3,X
    DECA                            ; A = $FE
    STA ,X                          ; port A: bit 0, the cassette, in; the DAC and serial out
    LDA #$F8
    STA 2,X                         ; port B: bits 0-2 in, the VDG's mode bits out
    STB 1,X
    STB 3,X
    CLR 2,X                         ; the VDG in its text mode
    LDA #$02
    STA ,X                          ; serial output marking
    LDA 2,X                         ; the RAM size jumper, in bit 2
    LDX #SAMREG
    LDB #16                         ; clear all sixteen of the SAM's bits
@sam:
    STA ,X++
    DECB
    BNE @sam
    STA SAMREG+9                    ; set display offset bit 0: the text screen at $0400
    ANDA #$04
    BEQ @done                       ; 4K chips
    STA -5,X                        ; 16K chips: set M0
@done:
    JMP ,U

;; Cold starts BASIC: clears the bottom 1K of RAM and the screen, copies the direct page's and page 1's starting
;; values, points the RAM hooks at RTS, finds the top of RAM, starts Extended BASIC when it is there, and signs
;; on.
COLDST:
    LDX #0
@clear:
    CLR ,X+
    CMPX #VIDRAM
    BNE @clear
    JSR CLRSCN
    LDX #DPIMAG
    LDU #CMPMID
    LDB #28
    JSR MOVEXU                      ; the direct page's starting values and GETNCH
    LDU #IRQVEC
    LDB #30
    JSR MOVEXU                      ; page 1's vectors, seed, keyboard settings and command table
    LDX #SNERR
    STX 3,U                         ; the USR0-USR9 addresses start at ?SN ERROR
    STX 8,U
    LDX #RVEC0
    LDA #$39                        ; RTS in each of the hooks
@hooks:
    STA ,X+
    CMPX #STRSTK
    BNE @hooks
    STA LINHDR-1                    ; RTS, an end for the line before the input buffer
    LDX #VIDRAM+512
    CLR ,X+                         ; the zero byte before the program, which starts at $0601
    STX TXTTAB
@size:
    LDA 2,X                         ; RAM if a complemented byte reads back complemented
    COMA
    STA 2,X
    CMPA 2,X
    BNE @top                        ; the top of RAM, or ROM
    LEAX 1,X
    COM 1,X                         ; put the byte back
    BRA @size
@top:
    STX TOPRAM
    STX MEMSIZ
    STX STRTAB
    LEAX -200,X                     ; 200 bytes of string space
    STX FRETOP
    TFR X,S                         ; the stack just below it
.else
;; The RESET vector: sets up the PIAs and the SAM, then checks for a warm start.
RESVEC:
    LEAY WARMCK,PCR
;; Sets up the PIAs, the SAM and the direct page as at power on, then jumps to Y.
;;
;; PIA 0's ports read the keyboard's rows and drive its columns; PIA 1's drive the DAC, the VDG and serial
;; output and read the cassette, serial input and the RAM size jumper. The SAM's control bits are all cleared,
;; for a text screen at $0400, then set for the RAM the jumper says: 4K, 16K or 64K chips.
;;
;; In:   Y = where to go next
;; Out:  DP = 0
INITHW:
.if COCO3
    LDA #BLOCK7_2
    STA MMUREG+2                    ; logical block 2 back to its own RAM: the start-up used it for the ROM's copy
    LDX #PIA1
    LDD #$FF34
    CLR 1,X                         ; PIA 1's control registers: reach the direction registers
    CLR 3,X
    DECA                            ; A = $FE
    STA ,X                          ; port A: bit 0, the cassette, in; the DAC and serial out
    LDA #$F8
    STA 2,X                         ; port B: bits 0-2 in, the VDG's mode bits out
    STB 1,X                         ; both control registers: data registers, interrupts off, CA2 and CB2
    STB 3,X                         ;   outputs, low
    CLR 2,X                         ; the VDG in its text mode
    LDA #$02
    STA ,X                          ; serial output marking
    LDA #$FF
    LDX #PIA0
    CLR 1,X                         ; PIA 0's control registers: reach the direction registers
    CLR 3,X
    CLR ,X                          ; port A, the rows, all inputs
    STA 2,X                         ; port B, the columns, all outputs
    STB 1,X                         ; both control registers as for PIA 1
    STB 3,X
    JMP INITHW_DONE                 ; the GIME has set the memory up: the SAM's bits stay as they are

;; Starts a ROM pack by hand, for EXEC &HE010 (<EXECCARTVEC>): maps the cartridge's ROM in and jumps to it.
EXECCART:
    JSR CARTROM
    JMP ROMPAK
    ; the rest of 1.2's memory size check, left in place and never run
    BITB 2,X
    BEQ INITHW_DONE
    CLR -2,X
    BITB 2,X
    BEQ INITHW_64K
    LEAU -2,U
.else
    LDX #PIA1
    CLR -3,X                        ; PIA 0's control registers: reach the direction registers
    CLR -1,X
    CLR -4,X                        ; port A, the rows, all inputs
    LDD #$FF34
    STA -2,X                        ; port B, the columns, all outputs
    STB -3,X                        ; both control registers: data registers, interrupts off, CA2 and CB2
    STB -1,X                        ;   outputs, low
    CLR 1,X                         ; PIA 1's control registers: reach the direction registers
    CLR 3,X
    DECA                            ; A = $FE
    STA ,X                          ; port A: bit 0, the cassette, in; the DAC and serial out
    LDA #$F8
    STA 2,X                         ; port B: bits 0-2 in, the VDG's mode bits out
    STB 1,X                         ; both control registers as for PIA 0
    STB 3,X
    CLR 2,X                         ; the VDG in its text mode
    LDB #$02
    STB ,X                          ; serial output marking
    LDU #SAMREG
    LDB #16                         ; clear all sixteen of the SAM's bits
INITHW_SAM:
    STA ,U++
    DECB
    BNE INITHW_SAM
    STA SAMREG+9                    ; set display offset bit 0: the text screen at $0400
    TFR B,DP
    LDB #$04                        ; the RAM size jumper reads on port B bit 2
.if VERSION = 13
    CLR -2,X                        ; strobe the columns low
    BITB 2,X
    BEQ @ram64                      ; low: 64K chips
    STA -5,U                        ; 16K chips: set M0
    STA -11,U                       ;   and P1
    BRA INITHW_DONE
@ram64:
    NOP
    NOP
.else
    STA -2,X                        ; strobe the columns high
    BITB 2,X
    BEQ INITHW_DONE                 ; low with the columns high: 4K chips, the SAM's reset size
    CLR -2,X                        ; strobe the columns low
    BITB 2,X
    BEQ INITHW_64K                  ; low with the columns low: 64K chips
    LEAU -2,U                       ; 16K chips: set M0 rather than M1
.endif
.endif
INITHW_64K:
    STA -3,U                        ; set the SAM's memory size bit
INITHW_DONE:
    JMP ,Y

;; Cold starts BASIC: clears the bottom 1K of RAM and the screen, finds the top of RAM, copies the direct page's
;; and page 1's starting values, points the RAM hooks at RTS, starts Extended BASIC when it is there, and signs
;; on.
COLDST:
    LDX #VIDRAM+1                   ; clear $0000-$03FF, two bytes at a time
COLDST_CLEAR:
    CLR ,--X
    LEAX 1,X
    BNE COLDST_CLEAR
    JSR CLRSCN                      ; X = the screen
    CLR ,X+                         ; the zero byte before the program, which starts at $0401
    STX TXTTAB
.if COCO3
    LDX #$7FFF                      ; BASIC has the bottom 32K: the GIME maps the rest
    BRA COLDST_TOP
    .repeat 10
    NOP                             ; where the RAM test was
    .endrepeat
.else
COLDST_SIZE:
    LDA 2,X                         ; RAM if a complemented byte reads back complemented
    COMA
    STA 2,X
    CMPA 2,X
    BNE COLDST_TOP                  ; the top of RAM, or ROM
    LEAX 1,X
    COM 1,X                         ; put the byte back
    BRA COLDST_SIZE
.endif
COLDST_TOP:
    STX TOPRAM
    STX MEMSIZ
    STX STRTAB
    LEAX -200,X                     ; 200 bytes of string space
    STX FRETOP
    TFR X,S                         ; the stack just below it
    LDX #DPIMAG
    LDU #CMPMID
    LDB #28
    JSR MOVEXU                      ; the direct page's starting values and GETNCH
    LDU #IRQVEC
    LDB #30
    JSR MOVEXU                      ; page 1's vectors, seed, keyboard settings and command table
    LDX -12,X                       ; X = the ?FC ERROR routine, from the EXEC address in DPIMAG
    STX 3,U                         ; the USR0-USR9 addresses start at it
    STX 8,U
    LDX #RVEC0
    LDD #$394B                      ; RTS in each of the 25 hooks' 75 bytes
COLDST_HOOKS:
    STA ,X+
    DECB
    BNE COLDST_HOOKS
    STA LINHDR-1                    ; RTS, an end for the line before the input buffer
.endif
    JSR ERASEP
.if COCO3
    JMP EXBAS+2                     ; Extended BASIC is always there, and signs on

;; Waits for a key, blinking the cursor, then blanks it, on the hi-res text screen when one is in use; the
;; start-up patches <WAITKY> to come here.
;;
;; Out:  A = the key
WAITKY3:
    PSHS B,X
    TST HRWIDTH
    LBNE HWAITKY                    ; a hi-res text screen
WAITKY3_LOOP:
    JSR BLINK
    JSR KEYIN
    BEQ WAITKY3_LOOP
    JMP WAITKY_BLANK
    .byte RSTVEC                    ; the last byte of 1.2's STX RSTVEC, left in place
.else
    LDX #$4558                      ; "EX": the start of Extended BASIC's ROM?
    CMPX EXBAS
    LBEQ EXBAS+2                    ; then it signs on instead
    ANDCC #$AF                      ; clear the interrupt and fast-interrupt masks
    LDX #SIGNON-1
    JSR STROUT1
    LDX #BAWMST
    STX RSTVEC                      ; RESET now warm starts here
.endif
COLDST_RSTFLG:
    LDA #$55
    STA RSTFLG
    BRA BAWMST_OK

;; The warm start <RSTVEC> holds: BASIC keeps its program, closes files, clears the screen and prompts.
;;
;; It must start with NOP, which <WARMCK> checks for.
BAWMST:
    NOP
    CLR DEVNUM                      ; output to the screen
    JSR RSTSTK
    ANDCC #$AF                      ; clear the interrupt and fast-interrupt masks
.if COCO3
    JSR CLS                         ; through its hook, which clears the hi-res text screen in use
.else
    JSR CLRSCN
.endif
BAWMST_OK:
    JMP OKPRMT

;; The FIRQ handler: starts the ROM pack when its CART line interrupted, and otherwise returns.
FIRQSV:
    TST PIA1+3                      ; CB1's interrupt flag
    BMI CARTST
    RTI

;; Starts the ROM pack in the cartridge port: waits a moment, then sets up the hardware and jumps to $C000 with
;; <RSTFLG> cleared, so RESET cold starts.
CARTST:
.if COCO3
    JSR CARTFIRQ                    ; the CoCo 3's interrupt vectors invalid, and the ROM mapped in
.else
    JSR DELAY
.endif
    JSR DELAY
.if VERSION = 10
    LDU #CARTGO
.else
    LEAY CARTGO,PCR
.endif
    JMP INITHW
CARTGO:
    CLR RSTFLG
    JMP ROMPAK

;; The direct page's starting values from <CMPMID> to <EXECJP>, and the <GETNCH> routine after them: 28 bytes
;; that <COLDST> copies to $008F.
DPIMAG:
    .byte 18                        ; CMPMID
    .byte 24                        ; CMP0
    .byte 10                        ; CMP1
    .dbyt 128                       ; SYNCLN
    .byte 11                        ; BLKCNT
.if VERSION < 12
    .dbyt 87                        ; LPTBTD: 600 baud
.else
    .dbyt 88                        ; LPTBTD: 600 baud
.endif
    .dbyt 1                         ; LPTLND
    .byte 16                        ; LPTCFW
    .byte 112                       ; LPTLCF
    .byte 132                       ; LPTWID
    .byte 0                         ; LPTPOS
    .dbyt FCERR                     ; EXECJP: ?FC ERROR until a program sets it
    .logicalorg GETNCH
    .assert * = GETNCH, "GETNCH's copy lands at GETNCH."
    INC <CHARAD+1                   ; GETNCH: step to the next character
    BNE @current
    INC <CHARAD
@current:
    .assert * = GETCCH, "GETCCH's copy lands at GETCCH."
    LDA >$0000                      ; GETCCH: the character at CHARAD, the operand here
    JMP BROMHK                      ; sets the flags for a digit, a colon or the end
    .logicalorg

;; Page 1's starting values from <IRQVEC> to the end of Color BASIC's <COMVEC> table: 30 bytes that <COLDST>
;; copies to $010C.
PG1IMG:
    JMP BIRQSV                      ; IRQVEC: the 60 Hz interrupt
    JMP FIRQSV                      ; FRQVEC: the cartridge
    JMP FCERR                       ; USRJMP: ?FC ERROR
    .byte $80, $4F, $C7, $52, $59   ; RVSEED
    .byte $FF                       ; CASFLG: upper case
    .dbyt DEBDEL                    ; DEBVAL
    JMP SNERR                       ; EXPJMP: ?SN ERROR until Extended BASIC
    .byte 53                        ; COMVEC: 53 commands
    .dbyt COMWRD                     ;   their reserved words
    .dbyt COMDSP                     ;   and their routines
    .byte 20                        ;   20 functions
    .dbyt FUNWRD                     ;   their reserved words
    .dbyt FUNDSP                     ;   and their routines

;; The sign-on message, ended by a zero.
SIGNON:
    .byte "COLOR BASIC "
.if VERSION = 10
    .byte "1.0"
.elseif VERSION = 11
    .byte "1.1"
.elseif VERSION = 12
    .byte "1.2"
.else
    .byte "1.3"
.endif
.if VERSION < 12
    .byte $0D, "(C) 1980 TANDY", 0
.else
    .byte $0D, "(C) 1982 TANDY", 0
.endif
;; Microsoft's name, ended by a zero.
MSFT:
    .byte "MICROSOFT", $0D, 0
;; Reads a character from the console, as <CONIN> does, without bit 7.
;;
;; Out:  A = the character
INCHR:
    BSR CONIN
    ANDA #$7F
    RTS

;; Reads a character from the console: the keyboard, blinking the cursor until a key is pressed, or the next
;; character of the cassette file.
;;
;; Out:  A = the character, CINBFL = $FF at the cassette file's end
;; Calls: RVEC4
CONIN:
    JSR RVEC4
    CLR CINBFL
    TST DEVNUM
    BEQ WAITKY                      ; the screen: wait for a key
    TST CINCTR
    BNE CONIN_TAPE
    COM CINBFL                      ; nothing left: the end of the file
    RTS
CONIN_TAPE:
    PSHS B,X,Y,U
    LDX CINPTR
    LDA ,X+
    PSHS A
    STX CINPTR
    DEC CINCTR
    BNE CONIN_DONE
    JSR RDDATA                       ; the buffer is empty: read the next block
CONIN_DONE:
    PULS A,B,X,Y,U,PC

;; The delay between the cursor's color changes, and the keyboard's debounce delay, in <DELAYX>'s loops.
;;
;; <BLINK> waits this long after each call, so the cursor changes color about every eleventh; <COLDST> copies it
;; into <DEBVAL> from <PG1IMG>, and <KEYIN> waits <DEBVAL>'s loops before it takes a key.
;; See: <BLINK>, <DEBVAL>, <KEYIN>
DEBDEL = $045E

;; Blinks the cursor: every eleventh call changes its color, then waits a moment.
;;
;; Uses: A, X
BLINK:
    DEC BLKCNT
    BNE BLINK_WAIT
    LDB #11
    STB BLKCNT
    LDX CURPOS
    LDA ,X
    ADDA #$10                       ; the next color
    ORA #$8F                        ; a solid block
    STA ,X
BLINK_WAIT:
    LDX #DEBDEL
;; Waits while X counts down, as <WAITX> does.
DELAYX:
    JMP WAITX

;; Waits for a key, blinking the cursor, then blanks the cursor.
;;
;; Out:  A = the key
WAITKY:
    PSHS B,X
WAITKY_LOOP:
    BSR BLINK
    BSR KEYIN
    BEQ WAITKY_LOOP
WAITKY_BLANK:
    LDB #$60                        ; a space, as the screen stores it
    STB [CURPOS]
WAITKY_DONE:
    PULS B,X,PC

.if VERSION >= 12
;; Checks quickly whether any key or joystick button is down, and reads the key when one is.
;;
;; Out:  A = the key, or zero, zero = set when none
KEYCHK:
.if COCO3
    JMP KEYIN                       ; always scan the whole keyboard
    .repeat 7
    RTS
    .endrepeat
.else
    CLR PIA0+2                      ; strobe every column
    LDA PIA0
    COMA
    ASLA                            ; drop the joystick comparator
    BEQ KEYRD_DONE                  ; nothing down
.endif
;; Scans the keyboard for a key newly pressed, debounces it and turns it into ASCII.
;;
;; Each column is strobed in turn and its rows compared with what <KEYBUF> held, so only a key that has just gone
;; down counts. The key's number, eight for each row plus the column, gives a letter directly, and the other keys
;; through <CONTAB>. SHIFT-0 toggles <CASFLG> instead of returning a key. The key must still be down after
;; <DEBVAL>'s delay, and no joystick button down, or it is ignored.
;;
;; Out:  A = the key, or zero, zero = set when none
KEYIN:
    PSHS B,X,U
    LDU #PIA0
    LDX #KEYBUF
    CLRA
    DECA                            ; A = -1, the column counter, and the carry clear
    PSHS A,X                        ; 0,S the column, 1-2,S scratch
    STA 2,U                         ; no column strobed
KEYIN_COLUMN:
    ROL 2,U                         ; strobe the next column: its 0 bit moves left
    BCC KEYIN_DONE                  ; all eight done
    INC <<0,S
    BSR KEYRD
    STA 1,S
    EORA ,X                         ; the rows that changed
    ANDA ,X                         ;   and are down now
    LDB 1,S
    STB ,X+
    TSTA
    BEQ KEYIN_COLUMN
    LDB 2,U
    STB 2,S                         ; keep the strobe, to read the key again after the delay
    LDB #$F8
KEYIN_ROW:
    ADDB #8                         ; eight for each row
    LSRA
    BCC KEYIN_ROW
    ADDB <<0,S                      ; plus the column: the key's number, 0-50
    BEQ KEYIN_AT
    CMPB #26
    BHI KEYIN_OTHER
    ORB #$40                        ; a letter, in upper case
    BSR SHIFTQ
    ORA CASFLG
    BNE KEYIN_DEBOUNCE              ; upper case unless lower case and no SHIFT
    ORB #$20
KEYIN_DEBOUNCE:
    STB <<0,S
    LDX DEBVAL
    BSR DELAYX
    LDB #$FF                        ; no column: only a joystick button reads low
    BSR KEYSTB
    INCA
    BNE KEYIN_DONE                  ; a button is down
    LDB 2,S
    BSR KEYSTB
    CMPA 1,S                        ; is the key still down?
KEYIN_DONE:
    PULS A,X
    BNE KEYIN_NONE
    CMPA #$12                       ; SHIFT-0?
    BNE KEYIN_EXIT
    COM CASFLG
KEYIN_NONE:
    CLRA
KEYIN_EXIT:
    PULS B,X,U,PC

;; Tests the SHIFT key.
;;
;; In:   U = <PIA0>
;; Out:  A = $40 when SHIFT is down, else zero
SHIFTQ:
    LDA #$7F                        ; strobe SHIFT's column
    STA 2,U
    LDA ,U
    COMA
    ANDA #$40                       ; SHIFT's row
    RTS

;; Strobes a column and reads the keyboard's rows.
;;
;; In:   B = the strobe, U = <PIA0>
;; Out:  A = the rows, a 0 bit for each key down
KEYSTB:
    STB 2,U
;; Reads the keyboard's rows with the joystick comparator's bit set, and SHIFT's row set too when its column is
;; strobed, so SHIFT never counts as a key.
;;
;; In:   U = <PIA0>
;; Out:  A = the rows
KEYRD:
    LDA ,U
    ORA #$80
    TST 2,U
    BMI KEYRD_DONE                  ; SHIFT's column not strobed
    ORA #$C0
KEYRD_DONE:
    RTS
KEYIN_AT:
    LDB #51                         ; @'s entry in CONTAB
KEYIN_OTHER:
    LDX #CONTAB-$36                 ; keys 27-32: the arrows, the space bar and 0
    CMPB #33
    BLO KEYIN_CONTROL
    LDX #CONTAB-$54                 ; keys 48-51: ENTER, CLEAR, BREAK and @
    CMPB #48
    BHS KEYIN_CONTROL
    BSR SHIFTQ                      ; keys 33-47: the digits and punctuation
    CMPB #43
    BLS KEYIN_SHIFTED
    EORA #$40                       ; , - . / shift the other way
KEYIN_SHIFTED:
    TSTA
    BNE KEYIN_DEBOUNCE
    ADDB #$10                       ; unshifted: the ASCII digit or punctuation
    BRA KEYIN_DEBOUNCE
KEYIN_CONTROL:
    ASLB                            ; two entries a key: unshifted, then shifted
    BSR SHIFTQ
    BEQ KEYIN_TABLE
    INCB
KEYIN_TABLE:
    LDB B,X
    BRA KEYIN_DEBOUNCE
.elseif VERSION = 11
;; Inherit:
KEYCHK:
;; Inherit:
KEYIN:
    PSHS B,X,U
    BSR KEYIN_SCAN
    TSTA
    PULS B,X,U,PC
KEYIN_SCAN:
    LDU #PIA0
    LDX #KEYBUF
    CLRA
    DECA                            ; A = -1, the column counter
    PSHS A,X                        ; 0,S the column, 1-2,S scratch
    STA 2,U                         ; no column strobed
    .byte $21                       ; BRN: skips the COMB below the first time
KEYIN_COLUMN:
    COMB                            ; the carry set
    ROL 2,U                         ; strobe the next column
    BCC WAITKY_DONE                 ; all eight done: back through WAITKY's exit
    INC <<0,S
    BSR KEYRD
    STA 1,S
    EORA ,X
    ANDA ,X
    LDB 1,S
    STB ,X+
    TSTA
    BEQ KEYIN_COLUMN
    LDB 2,U
    STB 2,S
    LDB #$F8
KEYIN_ROW:
    ADDB #8
    LSRA
    BCC KEYIN_ROW
    ADDB <<0,S
    BEQ KEYIN_AT
    CMPB #26
    BHI KEYIN_OTHER
    ORB #$40
    BSR SHIFTQ
    BEQ KEYIN_DEBOUNCE              ; SHIFT down: upper case
    LDA CASFLG
    BNE KEYIN_DEBOUNCE
    ORB #$20
KEYIN_DEBOUNCE:
    STB <<0,S
    LDX DEBVAL
    JSR WAITX
    LDB #$FF
    BSR KEYSTB
    INCA
    BNE KEYIN_DONE                  ; a joystick button is down
    LDB 2,S
    BSR KEYSTB
    CMPA 1,S
KEYIN_DONE:
    PULS A
    BNE KEYIN_NONE
    CMPA #$12
    BNE KEYIN_EXIT
    COM CASFLG
KEYIN_NONE:
    CLRA
KEYIN_EXIT:
    PULS X,PC

;; Tests the SHIFT key.
;;
;; In:   U = <PIA0>
;; Out:  A = zero when SHIFT is down, else $40
SHIFTQ:
    LDA #$7F
    STA 2,U
    LDA ,U
    ANDA #$40
    RTS

;; Inherit:
KEYSTB:
    STB 2,U
;; Inherit:
KEYRD:
    LDA ,U
    ORA #$80
    TST 2,U
    BMI KEYRD_DONE
    ORA #$C0
KEYRD_DONE:
    RTS
KEYIN_AT:
    LDB #51
KEYIN_OTHER:
    LDX #CONTAB-$36
    CMPB #33
    BLO KEYIN_CONTROL
    LDX #CONTAB-$54
    CMPB #48
    BHS KEYIN_CONTROL
    BSR SHIFTQ
    CMPB #43
    BLS KEYIN_SHIFTED
    EORA #$40
KEYIN_SHIFTED:
    TSTA
    BEQ KEYIN_DEBOUNCE
    ADDB #$10
    BRA KEYIN_DEBOUNCE
KEYIN_CONTROL:
    ASLB
    BSR SHIFTQ
    BNE KEYIN_TABLE
    INCB
KEYIN_TABLE:
    LDB B,X
    BRA KEYIN_DEBOUNCE
    .byte 0                         ; unused
.else
;; Inherit:
KEYCHK:
;; Inherit:
KEYIN:
    PSHS B,X
    BSR KEYIN_SCAN
    TSTA
    PULS B,X,PC
KEYIN_SCAN:
    LEAS -3,S                       ; 0,S the column, 1-2,S scratch
    LDX #KEYBUF
    CLR <<0,S
    LDB #$FE                        ; the first column
    STB PIA0+2
KEYIN_COLUMN:
    BSR KEYRD
    STA 1,S
    EORA ,X
    ANDA ,X
    LDB 1,S
    STB ,X+
    TSTA
    BNE KEYIN_FOUND
    INC <<0,S
    COMB                            ; the carry set
    ROL PIA0+2                      ; strobe the next column
    BCS KEYIN_COLUMN
    PULS B,X,PC                     ; all eight done
KEYIN_FOUND:
    LDB PIA0+2
    STB 2,S
    LDB #$F8
KEYIN_ROW:
    ADDB #8
    LSRA
    BCC KEYIN_ROW
    ADDB <<0,S
    BEQ KEYIN_AT
    CMPB #26
    BHI KEYIN_OTHER
    ORB #$40
    BSR SHIFTQ
    BEQ KEYIN_DEBOUNCE              ; SHIFT down: upper case
    LDA CASFLG
    BNE KEYIN_DEBOUNCE
    ORB #$20
KEYIN_DEBOUNCE:
    STB <<0,S
    LDX DEBVAL
    JSR WAITX
    LDB 2,S
    STB PIA0+2
    BSR KEYRD
    CMPA 1,S
KEYIN_DONE:
    PULS A
    BNE KEYIN_NONE
    CMPA #$12
    BNE KEYIN_EXIT
    COM CASFLG
KEYIN_NONE:
    CLRA
KEYIN_EXIT:
    PULS X,PC

;; Tests the SHIFT key.
;;
;; Out:  A = zero when SHIFT is down, else $40
SHIFTQ:
    LDA #$7F
    STA PIA0+2
    LDA PIA0
    ANDA #$40
    RTS

;; Inherit:
KEYRD:
    LDA PIA0
    ORA #$80
    TST PIA0+2
    BMI KEYRD_DONE
    ORA #$C0
KEYRD_DONE:
    RTS
KEYIN_AT:
    LDB #51
KEYIN_OTHER:
    LDX #CONTAB-$36
    CMPB #33
    BLO KEYIN_CONTROL
    LDX #CONTAB-$54
    CMPB #48
    BHS KEYIN_CONTROL
    BSR SHIFTQ
    CMPB #43
    BLS KEYIN_SHIFTED
    EORA #$40
KEYIN_SHIFTED:
    TSTA
    BEQ KEYIN_DEBOUNCE
    ADDB #$10
    BRA KEYIN_DEBOUNCE
KEYIN_CONTROL:
    ASLB
    BSR SHIFTQ
    BNE KEYIN_TABLE
    INCB
KEYIN_TABLE:
    LDB B,X
    BRA KEYIN_DEBOUNCE
.endif

;; The codes of the keys that are not letters, digits or punctuation, unshifted and then shifted.
CONTAB:
    .byte $5E, $5F                  ; up arrow, shifted _
    .byte $0A, $5B                  ; down arrow, shifted [
    .byte $08, $15                  ; left arrow (backspace), shifted Control-U
    .byte $09, $5D                  ; right arrow, shifted ]
    .byte $20, $20                  ; space bar
    .byte $30, $12                  ; 0, shifted for the case toggle
    .byte $0D, $0D                  ; ENTER
    .byte $0C, $5C                  ; CLEAR, shifted \
    .byte $03, $03                  ; BREAK
    .byte $40, $13                  ; @, shifted Control-S
;; Writes a character to the device in <DEVNUM>: the screen, the printer, or the cassette file's buffer, which
;; is written as a block when it fills.
;;
;; In:   A = the character
;; Calls: RVEC3
PUTCHR:
    JSR RVEC3
    PSHS B
    LDB DEVNUM
    INCB                            ; -2 the printer, -1 the cassette, 0 the screen
    PULS B
    BMI PRINTR
    BNE SCRCHR
    PSHS A,B,X
    LDB FILSTA
    DECB
    BEQ PUTCHR_DONE                 ; the file is open for input: nothing to write
    LDB CINCTR
    INCB
    BNE PUTCHR_TAPE
    BSR WDATBK                      ; the buffer is full: write it
PUTCHR_TAPE:
    LDX CINPTR
    STA ,X+
    STX CINPTR
    INC CINCTR
PUTCHR_DONE:
    PULS A,B,X,PC

;; Writes the cassette buffer as a data block, then starts a new one.
;;
;; Uses: B, X
WDATBK:
    LDB #1                          ; a data block
;; Writes the cassette buffer's <CINCTR> bytes as a block, then starts a new one.
;;
;; In:   B = the block's type: 0 the header, 1 data, $FF the end of the file
;; Uses: B, X
WRBLK:
    STB BLKTYP
    LDX #CASBUF
    STX CBUFAD
    LDB CINCTR
    STB BLKLEN
    PSHS A,Y,U
    JSR WRLDBK
    PULS A,Y,U
    JMP EMPTYB

;; Sends a character to the serial printer at <LPTBTD>'s rate, waiting while the printer is busy, and counts
;; its column so a full line or a carriage return ends with the line delay.
;;
;; In:   A = the character
PRINTR:
    PSHS CC,A,B,X
    ORCC #$50                       ; no interrupts while the bits are timed
.if VERSION = 10
    BSR SERMRK
    ASLA                            ; the start bit, a 0, below the character's low seven bits
    LDB #8
PRINTR_BIT:
    PSHS B
    CLRB
    LSRA                            ; the next bit, low first, to B's bit 1
    ROLB
    ROLB
    STB PIA1
    BSR BAUDLY
    NOP
    NOP
    NOP
    BSR BAUDLY
    PULS B
    DECB
    BNE PRINTR_BIT
.else
.if VERSION > 11
PRINTR_BUSY:
    LDB PIA1+2                      ; bit 0 high while the printer is busy
    LSRB
    BCS PRINTR_BUSY
.endif
    BSR SERMRK
    CLRB
    BSR SERBIT                      ; the start bit
    LDB #8
PRINTR_BIT:
    PSHS B
    CLRB
    LSRA                            ; the next bit, low first, to B's bit 1
    ROLB
    ASLB
    BSR SERBIT
    PULS B
    DECB
    BNE PRINTR_BIT
.endif
    BSR SERMRK                      ; the stop bit
    PULS CC,A
    CMPA #$0D
    BEQ PRINTR_CR
    INC LPTPOS
    LDB LPTPOS
    CMPB LPTWID
    BLO PRINTR_READY
PRINTR_CR:
    CLR LPTPOS
    BSR CRDLY
    BSR CRDLY
PRINTR_READY:
    LDB PIA1+2
    LSRB
    BCS PRINTR_READY
    PULS B,X,PC
.if VERSION = 11
    .byte 0, 0, 0, 0, 0, 0          ; unused
.endif

;; Sends a marking bit, a 1, to the serial port.
SERMRK:
    LDB #$02
;; Sends a bit to the serial port and holds it for a bit time.
;;
;; In:   B = the bit, in bit 1
SERBIT:
    STB PIA1
    BSR BAUDLY
;; Waits half a bit time at the printer's baud rate.
BAUDLY:
    LDX LPTBTD
    .byte $8C                       ; CMPX #: skips the LDX below
;; Waits the printer's carriage return delay.
CRDLY:
    LDX LPTLND
    JMP WAITX

;; Writes a character to the screen at the cursor and scrolls when the cursor passes the bottom.
;;
;; Backspace erases the character before the cursor, a carriage return blanks the rest of the line, and other
;; control characters are ignored. Text is stored as the VDG shows it: $40-$5F upper case, $60-$7F punctuation
;; and digits, and lower case as inverse upper case. Graphics characters, with bit 7 set, are stored as they are.
;;
;; In:   A = the character
SCRCHR:
    PSHS A,B,X
SCRCHR_SAVED:
    LDX CURPOS
    CMPA #$08
    BNE SCRCHR_ENTER
    CMPX #VIDRAM
    BEQ SCRCHR_DONE                 ; nothing before the top left
    LDA #$60
    STA ,-X
    BRA SCRCHR_CURSOR
SCRCHR_ENTER:
    CMPA #$0D
    BNE SCRCHR_TEXT
    LDX CURPOS
SCRCHR_BLANK:
    LDA #$60
    STA ,X+
    TFR X,D
    BITB #$1F                       ; to the start of the next line
    BNE SCRCHR_BLANK
    BRA SCRCHR_CURSOR
SCRCHR_TEXT:
    CMPA #$20
    BLO SCRCHR_DONE
    TSTA
    BMI SCRCHR_STORE                ; graphics
    CMPA #$40
    BLO SCRCHR_FLIP                 ; digits and punctuation
    CMPA #$60
    BLO SCRCHR_STORE                ; upper case
    ANDA #$DF                       ; lower case: inverse upper case
SCRCHR_FLIP:
    EORA #$40
SCRCHR_STORE:
    STA ,X+
SCRCHR_CURSOR:
    STX CURPOS
    CMPX #VIDRAM+511
    BLS SCRCHR_DONE
    LDX #VIDRAM                     ; past the bottom: move every line up one
SCRCHR_SCROLL:
    LDD 32,X
    STD ,X++
    CMPX #VIDRAM+480
    BLO SCRCHR_SCROLL
    LDB #$60
    JSR SCRFIL                       ; blank the bottom line and put the cursor there
SCRCHR_DONE:
    PULS A,B,X,PC

;; Sets the print parameters, <DEVCFW> to <DEVWID>, for the device in <DEVNUM>: 16-column fields on the
;; 32-column screen, the printer's own settings, or no line length for the cassette.
;;
;; Calls: RVEC2
SETPRM:
    JSR RVEC2
    PSHS A,B,X
    CLR PRTDEV
    LDA DEVNUM
    BEQ SETPRM_SCREEN
    INCA
    BEQ SETPRM_TAPE
    LDX LPTCFW                      ; the printer: its field width and last field
    LDD LPTWID                      ;   its width and position
    BRA SETPRM_STORE
SETPRM_SCREEN:
    LDB CURPOS+1
    ANDB #$1F                       ; the cursor's column
    LDX #$1010                      ; 16-column fields, the last at column 16
    LDA #32
SETPRM_STORE:
    STX DEVCFW
    STB DEVPOS
    STA DEVWID
    PULS A,B,X,PC
SETPRM_TAPE:
    COM PRTDEV
    LDX #$0100                      ; 1-column fields, no last field
    CLRA                            ; no line length, at column 0
    CLRB
    BRA SETPRM_STORE

;; Clears the screen, then reads a line as <LINEIN> does.
LINEIN_CLEAR:
    JSR CLRSCN
;; Reads a line of up to <LBUFMX> characters from the console into <LINBUF>, echoing it.
;;
;; The left arrow erases a character, SHIFT-left arrow the whole line, and CLEAR the screen and the line. BREAK
;; ends the line with the carry set; ENTER, or the end of a cassette file, ends it with the carry clear. A zero
;; follows the line.
;;
;; Out:  X = <LINBUF>, carry = set when BREAK ended the line
;; Calls: RVEC12
LINEIN:
    JSR RVEC12
    CLR IKEYIM
    LDX #LINBUF+1
    LDB #1                          ; one more than the characters so far
LINEIN_KEY:
    JSR INCHR
    TST CINBFL
    BNE LINEIN_END                  ; the cassette file ended
    TST DEVNUM
    BNE LINEIN_ENTER                ; from the cassette: no editing keys
    CMPA #$0C
    BEQ LINEIN_CLEAR
    CMPA #$08
    BNE LINEIN_ERASE
    DECB
    BEQ LINEIN                      ; nothing to erase
    LEAX -1,X
    BRA LINEIN_ECHO
LINEIN_ERASE:
    CMPA #$15
    BNE LINEIN_BREAK
LINEIN_ERASE_LOOP:
    DECB
    BEQ LINEIN
    LDA #$08
    JSR PUTCHR
    BRA LINEIN_ERASE_LOOP
LINEIN_BREAK:
    CMPA #$03
    ORCC #$01                       ; BREAK: the carry set
    BEQ LINEIN_DONE
LINEIN_ENTER:
    CMPA #$0D
    BNE LINEIN_CHAR
LINEIN_END:
    CLRA                            ; the carry clear
LINEIN_DONE:
    PSHS CC
    JSR PRNTCR
    CLR ,X
    LDX #LINBUF
    PULS CC,PC
LINEIN_CHAR:
    CMPA #$20
    BLO LINEIN_KEY                  ; other control characters
    CMPA #$7B
    BHS LINEIN_KEY
    CMPB #LBUFMX
    BHS LINEIN_KEY                  ; the line is full
    STA ,X+
    INCB
LINEIN_ECHO:
    JSR PUTCHR
    BRA LINEIN_KEY
;; Checks that the device in <DEVNUM> can be read: the screen, or the cassette when its file is open for
;; input. Disk BASIC adds its files through the hook.
;;
;; Errors: ?NO ERROR when the cassette file is closed, ?FM ERROR when it is open for output
;; Calls: RVEC5
CHKIN:
    JSR RVEC5
    LDA DEVNUM
    BEQ CHKIN_DONE                  ; the screen
    INCA
    BNE CHKIN_MODE                  ; not the cassette: the printer cannot be read
    LDA FILSTA
    BNE CHKIN_OPEN
;; Raises ?NO ERROR: the file is not open.
NOTOPN:
    LDB #ERR_NO
    JMP ERROR
CHKIN_OPEN:
    DECA
    BEQ CHKIN_DONE                  ; open for input
CHKIN_MODE:
    JMP FMERR

;; Checks that the device in <DEVNUM> can be written: the screen, the printer, or the cassette when its file is
;; open for output.
;;
;; Errors: ?NO ERROR when the cassette file is closed, ?FM ERROR when it is open for input
;; Calls: RVEC6
CHKOUT:
    JSR RVEC6
    LDA DEVNUM
    INCA
    BNE CHKIN_DONE                  ; not the cassette
    LDA FILSTA
    BEQ NOTOPN
    DECA
    BEQ CHKIN_MODE                  ; open for input
CHKIN_DONE:
    RTS

;; Runs CLOSE: with no devices closes every file, and otherwise each device listed.
CLOSE:
    BEQ CLSALL
    JSR GETDEV                       ; the first device
CLOSE_NEXT:
    BSR CLSONE
    JSR GETCCH
    BEQ CLSONE_DONE
    JSR COMDEV                       ; a comma and the next device
    BRA CLOSE_NEXT

;; Closes every file: in Color BASIC, the cassette's.
;;
;; Calls: RVEC7
CLSALL:
    JSR RVEC7
CLSALL_CASSETTE:
    LDA #$FF                        ; the cassette
    STA DEVNUM
;; Closes the file on the device in <DEVNUM>, then sets <DEVNUM> to the screen. A cassette file open for output
;; writes what is left in its buffer, then the end of file block.
;;
;; Calls: RVEC8
CLSONE:
    JSR RVEC8
    LDA DEVNUM
    CLR DEVNUM
    INCA
    BNE CLSONE_DONE                 ; not the cassette
    LDA FILSTA
    CMPA #2
    BNE CLSONE_SHUT                 ; not open for output
    LDA CINCTR
.if VERSION = 10
    BEQ CLSONE_SHUT                 ; empty: no end of file block
.else
    BEQ CLSONE_EOF
.endif
    JSR WDATBK
CLSONE_EOF:
    LDB #$FF
    JSR WRBLK
CLSONE_SHUT:
    CLR FILSTA
CLSONE_DONE:
    RTS

;; Runs CSAVE: writes the program to the cassette as a header and then blocks of 255 bytes, or with ,A as text,
;; as LIST would show it.
CSAVE:
    JSR GETNAM
    JSR GETCCH
    BEQ CSAVE_BINARY
    JSR SYNCOM                       ; ,A
    LDB #'A'
    JSR SYNCHR
    BNE CLSONE_DONE
    CLRA                            ; a BASIC program
    JSR WRHDRT                       ;   in text
    LDA #$FF
    STA DEVNUM
    CLRA
    JMP LIST                      ; LIST it to the cassette
CSAVE_BINARY:
    CLRA                            ; a BASIC program
    LDX ZERO                        ;   not in text, with no gaps
    JSR WRHDR
    CLR FILSTA
    INC BLKTYP                      ; data blocks from here
    JSR WRLDR
    LDX TXTTAB
CSAVE_BLOCK:
    STX CBUFAD
    LDA #255
    STA BLKLEN
    LDD VARTAB
    SUBD CBUFAD                     ; the bytes left
    BEQ CSAVE_END
    CMPD #255
    BHS CSAVE_SEND
    STB BLKLEN                      ; the last, shorter block
CSAVE_SEND:
    JSR SNDBLK
    BRA CSAVE_BLOCK
CSAVE_END:
    NEG BLKTYP                      ; $FF: the end of the file
    CLR BLKLEN
    JMP WRBLKE

;; Runs CLOAD and, with M, CLOADM: finds the named file on the cassette and loads a program, in binary or text,
;; in place of the one in memory.
CLOAD:
    CLR FILSTA
    CMPA #'M'
    BEQ CLOADM
    LEAS 2,S                        ; not back to the interpreter: the load ends at OKPRMT
    JSR NAMEND
    JSR FINDFL                       ; find the file's header
    TST CASBUF+10
    BEQ CLOAD_BINARY                ; no gaps: a binary program
    LDA CASBUF+9
    BEQ CLOAD_MODE                  ; gaps but not text
    JSR ERASEP                       ; text: NEW, then read the file as typed lines
    LDA #$FF
    STA DEVNUM
    INC FILSTA                      ; open for input
    JSR RDDATA
    JMP MAINLP

;; Ends loading a program in text: closes the cassette file and prompts.
;;
;; Calls: RVEC13
LDEND:
    JSR RVEC13
    JSR CLSONE
    JMP OKPRMT
CLOAD_BINARY:
    LDA CASBUF+8
    BEQ CLOAD_PROGRAM               ; a BASIC program
CLOAD_MODE:
    JMP FMERR
CLOAD_PROGRAM:
    JSR ERASEP
    JSR CASON
    LDX TXTTAB
CLOAD_BLOCK:
    STX CBUFAD
    LDD CBUFAD
    INCA                            ; room for a block's 256 bytes?
    JSR CHKMEM
    JSR GETBLK
    BNE CLOAD_FAILED
    LDA BLKTYP
    BEQ CLOAD_FAILED                ; a header in the middle
    BPL CLOAD_BLOCK
    STX VARTAB                      ; the end of file block: the program ends here
    BSR CLOAD_MOTOR
    LDX #MSGOK-1
    JSR STROUT1
    JMP EDITLN_DONE
CLOAD_FAILED:
    JSR ERASEP
CLOAD_IO:
    JMP IOERR

;; Runs CLOADM: loads a machine language file to its own address, or offset by the number after a comma, and
;; sets <EXECJP> to its start.
CLOADM:
    JSR GETNCH                      ; past the M
    BSR GETNAM
    JSR FINDFL
CLOADM_OFFSET:
    LDX ZERO                        ; the offset
    JSR GETCCH
    BEQ CLOADM_HEADER
    JSR SYNCOM
    JSR GETADR
CLOADM_HEADER:
    LDA CASBUF+8
    CMPA #2
    BNE CLOAD_MODE                  ; not machine language
    LDD CASBUF+11
    LEAU D,X
    STU EXECJP
    TST CASBUF+10
    BNE CLOAD_MODE                  ; gaps
    LDD CASBUF+13
    LEAX D,X
    STX CBUFAD
    JSR CASON
CLOADM_BLOCK:
    JSR GETBLK
    BNE CLOAD_IO
    STX CBUFAD
    TST BLKTYP
    BEQ CLOAD_IO
    BPL CLOADM_BLOCK
CLOAD_MOTOR:
    JMP MOTOROFF

;; Runs EXEC: jumps to the address given, or to <EXECJP>, the last CLOADM's start, and keeps the address given.
EXEC:
    BEQ EXEC_GO
    JSR GETADR
    STX EXECJP
EXEC_GO:
    JMP [EXECJP]

;; Checks for BREAK, except while reading the cassette.
;;
;; Calls: RVEC11
CHKBRK:
    JSR RVEC11
    LDA DEVNUM
    INCA
    BEQ GETNAM_DONE
    JMP ISCNTC

;; Moves the cursor for PRINT @ to the position the expression gives, 0-511.
;;
;; Errors: ?FC ERROR past 511
SETCUR:
    JSR NXTINT
    SUBD #511
    LBHI FCERR
    ADDD #VIDRAM+511
    STD CURPOS
    RTS

;; Runs the INKEY$ function: the key pressed since the last call, or the one the BREAK check saw, as a one-letter
;; string, or an empty string when none was.
INKEY:
    LDA IKEYIM
    BNE INKEY_KEY
    JSR KEYIN
INKEY_KEY:
    CLR IKEYIM
    STA FPA0+3
    LBNE CHRSTR
    STA STRDES
    JMP CHRSTR_DONE

;; Reads a cassette file's name, if one follows, into <CFNBUF>: its length, then the name padded with spaces to
;; eight characters.
GETNAM:
    LDX #CFNBUF
    CLR ,X+
    LDA #' '
GETNAM_BLANK:
    STA ,X+
    CMPX #CASBUF
    BNE GETNAM_BLANK
    JSR GETCCH
    BEQ GETNAM_DONE
    JSR FRMEVL
    JSR FRESTR                       ; B = its length, X = its text
    LDU #CFNBUF
    STB ,U+
    BEQ GETNAM_DONE
    .byte $8C                       ; CMPX #: skips the LDB below
;; Copies eight bytes from X to U.
MOVE8:
    LDB #8
;; Copies B bytes from X to U.
;;
;; In:   B = the count, X = from, U = to
;; Out:  X, U = just past the bytes
MOVEXU:
    LDA ,X+
    STA ,U+
    DECB
    BNE MOVEXU
GETNAM_DONE:
    RTS
;; Reads a comma, then a device number, as <GETDEV> does.
COMDEV:
    JSR SYNCOM
;; Reads a device number, with or without #, and makes it the device in <DEVNUM>.
;;
;; In:   A = the current character
GETDEV:
    CMPA #'#'
    BNE GETDEV_NUMBER
    JSR GETNCH
GETDEV_NUMBER:
    JSR FRMNUM
;; Makes the number in FPA0 the device in <DEVNUM>: -2 the printer, -1 the cassette, 0 the screen, or one Disk
;; BASIC adds through the hook.
;;
;; Errors: ?DN ERROR for any other number
;; Calls: RVEC1
SETDEV:
    JSR INTCNV                      ; D = the number
    ROLB
    ADCA #0
    BNE DNERR                       ; not -128 to 127
    RORB
    STB DEVNUM
    JSR RVEC1
    BEQ SETDEV_DONE
    BPL DNERR
    CMPB #$FE                       ; -2, the printer
    BLT DNERR
SETDEV_DONE:
    RTS

;; Reads a cassette file's name, which must end the statement.
NAMEND:
    BSR GETNAM
NAMEND_CHECK:
    JSR GETCCH
;; Raises ?SN ERROR unless the statement has ended.
;;
;; In:   zero = set at the statement's end, as <GETCCH> leaves it
ENDSTM:
    BEQ SETDEV_DONE
    JMP SNERR

;; Runs the EOF function: -1 when the cassette file being read has no characters left, else 0.
;;
;; Calls: RVEC14
EOF:
    JSR RVEC14
    LDA DEVNUM
    PSHS A
    BSR SETDEV
    JSR CHKIN
EOF_CHECK:
    CLRB
    LDA DEVNUM
    BEQ EOF_RESULT                  ; the screen never ends
    TST CINCTR
    BNE EOF_RESULT
    COMB
EOF_RESULT:
    PULS A
    STA DEVNUM
;; Returns B, sign extended, as the function's result.
;;
;; In:   B = the result
SGNB:
    SEX
    JMP GIVABF

;; Runs SKIPF: finds the named file, or the next, and reads past it.
SKIPF:
    BSR NAMEND
    BSR FINDFL
    JSR SKIPFL
    BNE IOERR
    RTS

;; Runs OPEN "I" or OPEN "O": opens the cassette for reading or writing a file of data in text. The screen and,
;; for output, the printer open too, with nothing to do.
;;
;; Calls: RVEC0
OPEN:
    JSR RVEC0
    JSR FRMEVL
    JSR FIRSTC                       ; the mode's first letter
    PSHS B
    BSR COMDEV
OPEN_NAME:
    JSR SYNCOM
    BSR NAMEND
    LDA DEVNUM
    CLR DEVNUM
    PULS B
    CMPB #'I'
    BEQ OPENIN
    CMPB #'O'
    BEQ OPENOUT
;; Raises ?FM ERROR: a file used in the wrong mode.
FMERR:
    LDB #ERR_FM
    .byte $8C                       ; CMPX #: skips the LDB below
;; Raises ?IO ERROR: the cassette could not be read.
IOERR:
    LDB #ERR_IO
    .byte $8C                       ; CMPX #: skips the LDB below
;; Raises ?AO ERROR: the file is already open.
AOERR:
    LDB #ERR_AO
    .byte $8C                       ; CMPX #: skips the LDB below
;; Raises ?DN ERROR: a device number out of range.
DNERR:
    LDB #ERR_DN
    JMP ERROR
OPENIN:
    INCA
    BMI FMERR                       ; the printer cannot be read
    BNE OPEN_DONE                   ; the screen
    BSR FINDFL
    LDA CASBUF+9
    ANDA CASBUF+10
    BEQ FMERR                       ; not text with gaps: not a data file
    INC FILSTA                      ; open for input
;; Reads the cassette file's next data block into the buffer, and sets the buffer's count and pointer.
;;
;; Errors: ?IO ERROR when the block cannot be read, or is a header
RDDATA:
    JSR RDBLK
    BNE IOERR
    TST BLKTYP
    BEQ IOERR
    BMI OPEN_DONE                   ; the end of the file: nothing left
    LDA BLKLEN
    BEQ RDDATA                      ; an empty block
RDDATA_COUNT:
    STA CINCTR
    BRA EMPTYB_PTR

;; Finds the named file's header on the cassette.
;;
;; Errors: ?AO ERROR when a file is already open, ?IO ERROR when the cassette cannot be read
FINDFL:
    TST FILSTA
    BNE AOERR
    BSR SEARCH
    BNE IOERR
;; Empties the cassette buffer.
EMPTYB:
    CLR CINCTR
EMPTYB_PTR:
    LDX #CASBUF
    STX CINPTR
OPEN_DONE:
    RTS
OPENOUT:
    INCA
    BNE OPEN_DONE                   ; the screen or the printer
    INCA                            ; a data file
;; Writes the header of a file in text with gaps, as <WRHDR> does.
;;
;; In:   A = the file's type
WRHDRT:
    LDX #$FFFF                      ; in text, with gaps between blocks
;; Writes a cassette file's header with the name in <CFNBUF>, opening the file for output.
;;
;; In:   A = the file's type: 0 a BASIC program, 1 data, 2 machine language
;;       X = the text flag in the high byte and the gap flag in the low
;; Errors: ?AO ERROR when a file is already open
WRHDR:
    TST FILSTA
    BNE AOERR
    LDU #CASBUF
    STU CBUFAD
    STA 8,U
    STX 9,U
    LDX #CFNBUF+1
    JSR MOVE8
    CLR BLKTYP                      ; a header
    LDA #15
    STA BLKLEN
    JSR WRLDBK
    LDA #2                          ; open for output
    STA FILSTA
    BRA EMPTYB

;; Searches the cassette for the header of the file named in <CFNBUF>, or for any file when no name was given.
;;
;; In direct mode the screen shows S while searching and each file's name as it passes, then F when the file
;; is found.
;;
;; Out:  zero = set when found, else <CSRERR> holds the error
SEARCH:
    LDX #CASBUF
    STX CBUFAD
SEARCH_NEXT:
    LDA CURLIN
    INCA
    BNE SEARCH_HEADER               ; running a program: nothing shown
    JSR CLRSCN
    LDX CURPOS
    LDB #'S'
    STB ,X++
    STX CURPOS
SEARCH_HEADER:
    BSR RDBLK
    ORB BLKTYP
    BNE SEARCH_DONE                 ; an error, or not a header
    LDX #CASBUF
    LDU #CFNBUF+1
    LDB #8
    CLR ,-S                         ; the differences
SEARCH_COMPARE:
    LDA ,X+
    LDY CURLIN
    LEAY 1,Y
    BNE SEARCH_SHOWN
    CLR DEVNUM
    JSR PUTCHR                      ; show the name in direct mode
SEARCH_SHOWN:
    SUBA ,U+
    ORA ,S
    STA ,S
    DECB
    BNE SEARCH_COMPARE
    LDA ,S+
    BEQ SEARCH_FOUND
    TST -9,U                        ; any name given?
    BEQ SEARCH_FOUND
    BSR SKIPFL
    BNE SEARCH_DONE
    BRA SEARCH_NEXT
SEARCH_FOUND:
    LDA #'F'
    BSR SHOWIND
    CLRA
SEARCH_DONE:
    RTS

;; Reads past the rest of a cassette file, its blocks with or without gaps, to its end.
;;
;; Out:  zero = set at the end of the file, else <CSRERR> holds the error
SKIPFL:
    TST CASBUF+10
    BNE SKIPFL_GAPS
    JSR CASON
SKIPFL_CONTINUOUS:
    BSR GETBLK
    BSR SKIPFL_CHECK
    BRA SKIPFL_CONTINUOUS
SKIPFL_GAPS:
    BSR RDBLK
    BSR SKIPFL_CHECK
    BRA SKIPFL_GAPS
SKIPFL_CHECK:
    BNE SKIPFL_END                  ; an error
    LDA BLKTYP
    NEGA
.if VERSION = 10
    BMI FLPIND                      ; a data block: flip the indicator, and read on
.else
    BMI SHOWIND_DONE                ; a data block: read on
.endif
    DECA                            ; the end of the file: 0; a header: -1
SKIPFL_END:
    STA CSRERR
    LEAS 2,S                        ; out of the loop
    BRA RDBLK_END
;; Inverts the character at the top left of the screen, the cassette's activity indicator, in direct mode.
FLPIND:
    LDA VIDRAM
    EORA #$40
;; Shows a character at the top left of the screen in direct mode.
;;
;; In:   A = the character, as the screen stores it
SHOWIND:
    LDB CURLIN
    INCB
    BNE SHOWIND_DONE                ; a program is running
    STA VIDRAM
SHOWIND_DONE:
    RTS

;; Starts the motor, reads a block as <GETBLK> does, and stops the motor, for files with gaps between blocks.
;;
;; Out:  B = <CSRERR>, zero = set when the block was read
RDBLK:
    BSR CASON
    BSR GETBLK
RDBLK_END:
    JSR MOTOROFF
    LDB CSRERR
    RTS

;; Reads a cassette block into the buffer at <CBUFAD>: waits for the $3C sync byte, then reads the block's type,
;; length, data and checksum. The motor must already be running and the leader found.
;;
;; Out:  BLKTYP, BLKLEN = the block's type and length, X = just past its data
;;       zero = set when read, else <CSRERR> = 1 for a bad checksum or 2 when RAM did not hold a byte
GETBLK:
    ORCC #$50                       ; no interrupts while the cycles are timed
    BSR FLPIND
    LDX CBUFAD
    CLRA
GETBLK_SYNC:
    BSR RDBIT                       ; shift bits in until they make $3C
    RORA
    CMPA #$3C
    BNE GETBLK_SYNC
    BSR RDBYTE
    STA BLKTYP
    BSR RDBYTE
    STA BLKLEN
    ADDA BLKTYP
    STA CCKSUM
    LDA BLKLEN
    STA CSRERR                      ; counts the data bytes
    BEQ GETBLK_SUM
GETBLK_DATA:
    BSR RDBYTE
    STA ,X
    CMPA ,X+
    BNE GETBLK_MEMORY
    ADDA CCKSUM
    STA CCKSUM
    DEC CSRERR
    BNE GETBLK_DATA
GETBLK_SUM:
    BSR RDBYTE
    SUBA CCKSUM
    BEQ GETBLK_DONE
    LDA #1                          ; a bad checksum
    .byte $8C                       ; CMPX #: skips the LDA below
GETBLK_MEMORY:
    LDA #2                          ; the byte did not stay in RAM
GETBLK_DONE:
    STA CSRERR
    RTS

;; Reads a byte from the cassette, low bit first.
;;
;; Out:  A = the byte
RDBYTE:
    LDA #8
    STA CPULWD
RDBYTE_BIT:
    BSR RDBIT
    RORA
    DEC CPULWD
    BNE RDBYTE_BIT
    RTS

;; Reads a bit from the cassette: a cycle shorter than <CMPMID> is a 1 (2400 Hz), a longer one a 0 (1200 Hz).
;;
;; Out:  carry = the bit
RDBIT:
    BSR RDCYC
    LDB CPERTM
    DECB
    CMPB CMPMID
    RTS

;; Times one cycle of the cassette signal, starting on the transition <CBTPHA> chose when the leader was found.
;;
;; Out:  CPERTM = the cycle's length
RDCYC:
    CLR CPERTM
    TST CBTPHA
    BNE WAITHI2
;; Waits for the cassette input to go low, then high, counting in <CPERTM>.
WAITLO:
    BSR CASIN
    BCS WAITLO
;; Waits for the cassette input to go high, counting in <CPERTM>.
WAITHI:
    BSR CASIN
    BCC WAITHI
    RTS

;; Samples the cassette input, counting the sample in <CPERTM>.
;;
;; Out:  carry = the input
CASIN:
    INC CPERTM
    LDB PIA1
    RORB
    RTS
;; Waits for the cassette input to go high, then low, counting in <CPERTM>.
WAITHI2:
    BSR CASIN
    BCC WAITHI2
;; Waits for the cassette input to go low, counting in <CPERTM>.
WAITLO2:
    BSR CASIN
    BCS WAITLO2
    RTS

;; Starts the cassette motor and finds a leader: 96 cycles in a row alternating between 1200 and 2400 Hz, as a
;; leader's $55 bytes make. The transition they were timed from, high to low or low to high, goes in <CBTPHA>
;; for <RDCYC>.
CASON:
    ORCC #$50
    BSR MOTORON
    CLR CPULWD                      ; counts the pattern found so far
CASON_RISE:
    BSR WAITLO
CASON_FALL:
    BSR PERLO
    BHI CASON_FALL_LONG             ; a 1200 Hz half cycle
CASON_RISE_SHORT:
    BSR PERHI
    BLO CASON_FALL_SHORT            ; two 2400 Hz half cycles together
    DEC CPULWD                      ; one more found on the rising edges
    LDA CPULWD
    CMPA #$A0                       ; -96
CASON_COUNT:
    BNE CASON_RISE
    STA CBTPHA                      ; 0 for the falling edge, $A0 for the rising
    RTS
CASON_FALL_LONG:
    BSR PERHI
    BHI CASON_FALL                  ; two 1200 Hz half cycles together
CASON_FALL_SHORT:
    BSR PERLO
    BLO CASON_RISE_SHORT
    INC CPULWD                      ; one more found on the falling edges
    LDA CPULWD
    SUBA #96
    BRA CASON_COUNT

;; Times the cassette input until it goes high, then compares the time with the 1200 and 2400 Hz limits.
;;
;; The flags are left from comparing the time with <CMP1>: a branch on higher finds a time too long for 2400 Hz,
;; and one on lower a time short enough for it. A time too long even for 1200 Hz also clears <CPULWD>.
;;
;; Out:  B = the time, carry = set when short enough for 2400 Hz
PERHI:
    CLR CPERTM
    BSR WAITHI
    BRA PERCMP
;; Times the cassette input until it goes low, as <PERHI> does.
PERLO:
    CLR CPERTM
    BSR WAITLO2
PERCMP:
    LDB CPERTM
    CMPB CMP0
    BHI PERCMP_DROPOUT              ; too long even for 1200 Hz: start the count again
    CMPB CMP1
    RTS
PERCMP_DROPOUT:
    CLR CPULWD
    RTS

;; Runs MOTOR ON and MOTOR OFF.
MOTOR:
    TFR A,B
    JSR GETNCH
    CMPB #TK_OFF
    BEQ MOTOROFF
    CMPB #TK_ON
    JSR ENDSTM
;; Starts the cassette motor and waits for it to come up to speed.
MOTORON:
    LDA PIA1+1
    ORA #$08                        ; CA2 high: the motor's relay
    BSR SETMOT
;; Waits about half a second.
DELAY:
    LDX ZERO
;; Waits while X counts down to zero.
;;
;; In:   X = the count
WAITX:
    LEAX -1,X
    BNE WAITX
    RTS

;; Starts the cassette motor and writes a leader of <SYNCLN> $55 bytes.
WRLDR:
    ORCC #$50
    BSR MOTORON
    LDX SYNCLN
WRLDR_BYTE:
    BSR SND55
    LEAX -1,X
    BNE WRLDR_BYTE
    RTS

;; Writes a leader and then a block, then stops the motor.
WRLDBK:
    BSR WRLDR
;; Writes a block, then stops the motor.
WRBLKE:
    BSR SNDBLK
;; Stops the cassette motor and lets interrupts in again.
MOTOROFF:
    ANDCC #$AF
    LDA PIA1+1
    ANDA #$F7                       ; CA2 low
SETMOT:
    STA PIA1+1
    RTS

;; Writes a cassette block from the buffer at <CBUFAD>: $55, the $3C sync byte, the block's type and length, its
;; data, its checksum and $55 again.
;;
;; In:   BLKTYP, BLKLEN = the block's type and length
SNDBLK:
    ORCC #$50
    LDB BLKLEN
    STB CSRERR
    LDA BLKLEN
    BEQ SNDBLK_HEADER
    LDX CBUFAD
SNDBLK_SUM:
    ADDA ,X+
    DECB
    BNE SNDBLK_SUM
SNDBLK_HEADER:
    ADDA BLKTYP
    STA CCKSUM                      ; the checksum: type, length and data
    LDX CBUFAD
    BSR SND55
    LDA #$3C
    BSR SNDBYT
    LDA BLKTYP
    BSR SNDBYT
    LDA BLKLEN
    BSR SNDBYT
    TSTA
    BEQ SNDBLK_END
SNDBLK_DATA:
    LDA ,X+
    BSR SNDBYT
    DEC CSRERR
    BNE SNDBLK_DATA
SNDBLK_END:
    LDA CCKSUM
    BSR SNDBYT
;; Writes a $55 byte to the cassette.
SND55:
    LDA #$55
;; Writes a byte to the cassette, low bit first: a 0 as one cycle of 1200 Hz, a 1 as one of 2400 Hz, each cycle
;; played through the DAC from <SINTAB>.
;;
;; In:   A = the byte
SNDBYT:
    PSHS A
    LDB #1                          ; the bit being sent
SNDBYT_BIT:
    LDA CLSTSN
    STA PIA1
    LDY #SINTAB
    BITB ,S
    BNE SNDBYT_HIGH
SNDBYT_LOW:
    LDA ,Y+                         ; a 0: every entry
    CMPY #SINTAB+36
    BEQ SNDBYT_NEXT
    STA PIA1
    BRA SNDBYT_LOW
SNDBYT_HIGH:
    LDA ,Y++                        ; a 1: every other entry, twice the frequency
    CMPY #SINTAB+36
    BEQ SNDBYT_NEXT
    STA PIA1
    BRA SNDBYT_HIGH
SNDBYT_NEXT:
    STA CLSTSN
    ASLB
    BCC SNDBYT_BIT
    PULS A,PC

;; One cycle of a sine wave in 36 steps, as PIA 1's port A writes it: the DAC's value in bits 2-7, and serial
;; output marking in bit 1.
SINTAB:
    .byte $82, $92, $AA, $BA, $CA, $DA, $EA, $F2, $FA, $FA, $FA, $F2, $EA, $DA, $CA, $BA
    .byte $AA, $92, $7A, $6A, $52, $42, $32, $22, $12, $0A, $02, $02, $02, $0A, $12, $22
    .byte $32, $42, $52, $6A

;; Runs SET(x,y,c): lights a graphics block on the text screen, in color c (1-8), or with c = 0 in the color the
;; character cell already has.
;;
;; Errors: ?FC ERROR for a color past 8
SET:
    BSR GRPAREN                       ; X = the cell, GRBLOK = the block's bit
    PSHS X
    JSR COMBYT                       ; B = the color
    PULS X
    CMPB #8
    BHI GRCELL_RANGE
    DECB
    BMI SET_KEEP
    LDA #$10
    MUL                             ; the color in bits 4-6
    BRA SET_COLOR
SET_KEEP:
    LDB ,X
    BPL SET_BLACK                   ; not graphics: black
    ANDB #$70                       ; the cell's color
    .byte $21                       ; BRN: skips the CLRB below
SET_BLACK:
    CLRB
SET_COLOR:
    PSHS B
    BSR CKRPAR
    LDA ,X
    BMI SET_PIXELS
    CLRA                            ; text: start with no blocks lit
SET_PIXELS:
    ANDA #$0F
    ORA GRBLOK
    ORA ,S+
;; Stores a graphics character, with bit 7 set, in its screen cell.
;;
;; In:   A = the character, X = the cell
SETGR:
    ORA #$80
    STA ,X
    RTS
;; Runs RESET(x,y): turns off a graphics block on the text screen, making the cell an empty graphics character
;; if it held text.
RESET:
    BSR GRPAREN
    BSR CKRPAR
    CLRA
    LDB ,X
    BPL SETGR                       ; text: an empty block
    COM GRBLOK
    ANDB GRBLOK
    STB ,X
    RTS

;; Reads (x,y, as SET, RESET and POINT start, and finds the graphics block, as <GRCELL> does.
GRPAREN:
    JSR SYNLPR
;; Reads x,y and finds the graphics block on the text screen: 64 by 32 blocks, four to a character cell.
;;
;; Out:  X = the cell, GRBLOK = the block's bit in it: 8 top left, 4 top right, 2 bottom left, 1 bottom right
;; Errors: ?FC ERROR for x past 63 or y past 31
;; Calls: RVEC21
GRCELL:
    JSR RVEC21
    JSR GETBYT
    CMPB #63
    BHI GRCELL_RANGE
    PSHS B
    JSR COMBYT
    CMPB #31
GRCELL_RANGE:
    BHI FCERR1
    PSHS B
    LSRB                            ; the cell's row
    LDA #32
    MUL
    LDX #VIDRAM
    LEAX D,X
    LDB 1,S
    LSRB                            ; the cell's column
    ABX
    PULS A,B
    ANDA #1                         ; the block within the cell: y's low bit
    RORB                            ;   and x's
    ROLA
    LDB #$10
GRCELL_BIT:
    LSRB
    DECA
    BPL GRCELL_BIT
    STB GRBLOK
    RTS

;; Runs the POINT(x,y) function: -1 when the cell holds text, 0 when the block is off, and its color (1-8) when on.
POINT:
    BSR GRCELL
    LDB #$FF
    LDA ,X
    BPL POINT_RESULT                ; text
    ANDA GRBLOK
    BEQ POINT_LIT                   ; off: 0
    LDB ,X
    LSRB
    LSRB
    LSRB
    LSRB
    ANDB #7                         ; the color, less one
POINT_LIT:
    INCB
POINT_RESULT:
    JSR SGNB
;; Checks for ), as <SYNRPR> does.
CKRPAR:
    JMP SYNRPR

;; Runs CLS: clears the screen to spaces, or to graphics blocks of color 0-8. A color past 8 shows a message.
;;
;; Calls: RVEC22
CLS:
    JSR RVEC22
CLS_HOOKED:
    BEQ CLRSCN
    JSR GETBYT
    CMPB #8
    BHI CLS_MSFT
    TSTB
    BEQ CLS_FILL                    ; 0: black
    DECB
    LDA #$10
    MUL
    ORB #$0F                        ; all four blocks lit in the color
CLS_FILL:
    ORB #$80
    .byte $8C                       ; CMPX #: skips the LDB below
;; Clears the screen to spaces and puts the cursor at the top left.
;;
;; Out:  X = the end of the screen plus one
CLRSCN:
    LDB #$60
    LDX #VIDRAM
;; Fills the screen from X to its end, and puts the cursor at X.
;;
;; In:   B = the character, X = where to start
SCRFIL:
    STX CURPOS
SCRFIL_LOOP:
    STB ,X+
    CMPX #VIDRAM+511
    BLS SCRFIL_LOOP
    RTS
CLS_MSFT:
    BSR CLRSCN
    LDX #MSFT-1
    JMP STROUT1

;; Reads a comma, then a byte from 1 to 255, as <GETB1> does.
COMB1:
    JSR SYNCOM
;; Reads a byte from 1 to 255.
;;
;; Out:  B = the byte
;; Errors: ?FC ERROR for 0
GETB1:
    JSR GETBYT
    TSTB
    BNE SNDON_DONE
;; Raises ?FC ERROR.
FCERR1:
    JMP FCERR

;; Runs SOUND tone,duration: plays a square wave through the DAC, its pitch rising with the tone (1-255), for
;; the duration in fifteenths of a second, which the 60 Hz interrupt counts down.
SOUND:
    BSR GETB1
    STB SNDTON
    BSR COMB1
SOUND_DURATION:
    LDA #4
    MUL                             ; the duration in 60ths of a second
    STD SNDDUR
    LDA PIA0+3
    ORA #$01                        ; let the field sync interrupt in, to count the duration
    STA PIA0+3
    CLR ARYDIS
    BSR SELMUX                      ; B = 0: the DAC to the sound output
    BSR SNDON
SOUND_CYCLE:
    BSR SNDHI
    LDA #$FE
    BSR SNDOUT
    BSR SNDHI
    LDA #$02
    BSR SNDOUT
    LDX SNDDUR
    BNE SOUND_CYCLE
;; Turns the sound output off.
SNDOFF:
    CLRA
    .byte $8C                       ; CMPX #: skips the LDA below
;; Turns the sound output on: PIA 1's CB2 high.
SNDON:
    LDA #$08
    STA ,-S
    LDA PIA1+3
    ANDA #$F7
    ORA ,S+
    STA PIA1+3
SNDON_DONE:
    RTS
;; Sends the DAC's middle value, then waits, as <SNDOUT> does.
SNDHI:
    LDA #$7E
;; Sends a value to the DAC, then waits the tone's half cycle.
;;
;; In:   A = the value
SNDOUT:
    STA PIA1
    LDA SNDTON
SNDOUT_WAIT:
    INCA
    BNE SNDOUT_WAIT
    RTS

;; Runs AUDIO ON and AUDIO OFF: plays the cassette's input through the sound output, or stops it.
AUDIO:
    TFR A,B
    JSR GETNCH
    CMPB #TK_OFF
    BEQ SNDOFF
    SUBB #TK_ON
    JSR ENDSTM
    INCB                            ; 1: the cassette
    BSR SELMUX
    BRA SNDON

;; Selects the analog multiplexer's input, which the joystick comparator and the sound output take: 0 the DAC,
;; 1 the cassette, 2 the cartridge, 3 none, or the joystick axis to read.
;;
;; In:   B = the input: bit 0 goes to PIA 0's CA2, bit 1 to its CB2
;; Uses: A, B, U
SELMUX:
    LDU #PIA0+1
    BSR SELMUX_BIT
SELMUX_BIT:
    LDA ,U
    ANDA #$F7
    ASRB
    BCC SELMUX_STORE
    ORA #$08
SELMUX_STORE:
    STA ,U++
    RTS

;; The IRQ handler: on the 60 Hz field sync interrupt counts <SNDDUR> down.
BIRQSV:
    LDA PIA0+3
    BPL BIRQSV_DONE                 ; not the field sync
    LDA PIA0+2                      ; acknowledge it
BIRQSV_SOUND:
    LDX >SNDDUR
    BEQ BIRQSV_DONE
    LEAX -1,X
    STX >SNDDUR
BIRQSV_DONE:
    RTI

;; Runs the JOYSTK(n) function: a joystick axis, 0-63. JOYSTK(0) reads all four; the others give what that read
;; found: 0 and 1 the right joystick's horizontal and vertical, 2 and 3 the left's.
;;
;; Errors: ?FC ERROR past 3
JOYSTK:
    JSR BYTCHK
    CMPB #3
    LBHI FCERR
    TSTB
    BNE JOYSTK_READ
    BSR GETJOY
JOYSTK_READ:
    LDX #POTVAL
    LDB FPA0+3
    LDB B,X
    JMP GIVB

;; Reads the four joystick axes into <POTVAL>: for each, a six-bit search with the DAC against the
;; comparator, repeated until two readings agree, up to ten times.
GETJOY:
    BSR SNDOFF
    LDX #POTVAL+4
    LDB #3                          ; the axis, 3 down to 0
GETJOY_STICK:
    LDA #10                         ; the tries left
    STD ,--S
    BSR SELMUX
GETJOY_TRY:
    LDD #$4080                      ; A, the bit being found; B, the trial value, halfway
GETJOY_BIT:
    STA ,-S                         ; the step: half the current difference
    ORB #$02                        ; serial output marking
    STB PIA1
    EORB #$02
    LDA PIA0
    BMI GETJOY_HIGH                 ; the joystick is above the DAC
    SUBB ,S
    .byte $8C                       ; CMPX #: skips the ADDB below
GETJOY_HIGH:
    ADDB ,S
    LDA ,S+
    LSRA
    CMPA #$01
    BNE GETJOY_BIT
    LSRB                            ; the six bits, down from the DAC's 2-7
    LSRB
    CMPB -1,X                       ; the same as the last try?
    BEQ GETJOY_SAVE
    DEC ,S
    BNE GETJOY_TRY
GETJOY_SAVE:
    STB ,-X
    LDD ,S++
    DECB
    BPL GETJOY_STICK
    RTS

;; The end of <GETNCH> and <GETCCH>: sets the flags for the character, skipping spaces.
;;
;; In:   A = the character
;; Out:  carry = set for a digit, zero = set at the end of a statement: a zero or a colon
BROMHK:
    CMPA #':'
    BHS BROMHK_DONE                 ; a colon or past it: zero set for a colon, carry clear
    CMPA #' '
    BNE BROMHK_DIGIT
    JMP GETNCH                      ; skip the space
BROMHK_DIGIT:
    SUBA #'0'
    SUBA #$D0                       ; carry set for '0'-'9', A unchanged
BROMHK_DONE:
    RTS
;; The functions' routines, in token order from $FF $80.
FUNDSP:
    .dbyt SGN
    .dbyt INT
    .dbyt ABS
    .dbyt USRJMP
    .dbyt RND
    .dbyt SIN
    .dbyt PEEK
    .dbyt LEN
    .dbyt STR
    .dbyt VAL
    .dbyt ASC
    .dbyt CHR
    .dbyt EOF
    .dbyt JOYSTK
    .dbyt LEFT
    .dbyt RIGHT
    .dbyt MID
    .dbyt POINT
    .dbyt INKEY
    .dbyt MEM

;; The operators: each one's precedence, then its routine, in token order from <TK_PLUS>.
OPTAB:
    .byte $79
    .dbyt FPADD                     ; +
    .byte $79
    .dbyt FPSUB                     ; -
    .byte $7B
    .dbyt FPMUL                     ; *
    .byte $7B
    .dbyt FPDIV                     ; /
    .byte $7F
    .dbyt EXPJMP                    ; ^
    .byte $50
    .dbyt ANDOP                     ; AND
    .byte $46
    .dbyt OROP                      ; OR

;; The commands' and operators' reserved words, in token order from $80.
COMWRD:
    KEYWORD "FOR"
    KEYWORD "GO"
    KEYWORD "REM"
    KEYWORD "'"
    KEYWORD "ELSE"
    KEYWORD "IF"
    KEYWORD "DATA"
    KEYWORD "PRINT"
    KEYWORD "ON"
    KEYWORD "INPUT"
    KEYWORD "END"
    KEYWORD "NEXT"
    KEYWORD "DIM"
    KEYWORD "READ"
    KEYWORD "RUN"
    KEYWORD "RESTORE"
    KEYWORD "RETURN"
    KEYWORD "STOP"
    KEYWORD "POKE"
    KEYWORD "CONT"
    KEYWORD "LIST"
    KEYWORD "CLEAR"
    KEYWORD "NEW"
    KEYWORD "CLOAD"
    KEYWORD "CSAVE"
    KEYWORD "OPEN"
    KEYWORD "CLOSE"
    KEYWORD "LLIST"
    KEYWORD "SET"
    KEYWORD "RESET"
    KEYWORD "CLS"
    KEYWORD "MOTOR"
    KEYWORD "SOUND"
    KEYWORD "AUDIO"
    KEYWORD "EXEC"
    KEYWORD "SKIPF"
    KEYWORD "TAB("
    KEYWORD "TO"
    KEYWORD "SUB"
    KEYWORD "THEN"
    KEYWORD "NOT"
    KEYWORD "STEP"
    KEYWORD "OFF"
    KEYWORD "+"
    KEYWORD "-"
    KEYWORD "*"
    KEYWORD "/"
    KEYWORD "^"
    KEYWORD "AND"
    KEYWORD "OR"
    KEYWORD ">"
    KEYWORD "="
    KEYWORD "<"

;; The functions' reserved words, in token order from $FF $80.
FUNWRD:
    KEYWORD "SGN"
    KEYWORD "INT"
    KEYWORD "ABS"
    KEYWORD "USR"
    KEYWORD "RND"
    KEYWORD "SIN"
    KEYWORD "PEEK"
    KEYWORD "LEN"
    KEYWORD "STR$"
    KEYWORD "VAL"
    KEYWORD "ASC"
    KEYWORD "CHR$"
    KEYWORD "EOF"
    KEYWORD "JOYSTK"
    KEYWORD "LEFT$"
    KEYWORD "RIGHT$"
    KEYWORD "MID$"
    KEYWORD "POINT"
    KEYWORD "INKEY$"
    KEYWORD "MEM"

;; The commands' routines, in token order from $80 to <TK_SKIPF>.
COMDSP:
    .dbyt FOR
    .dbyt GO
    .dbyt REM
    .dbyt REM                       ; '
    .dbyt REM                       ; ELSE: skip the rest of the line
    .dbyt IF
    .dbyt DATA
    .dbyt PRINT
    .dbyt ON
    .dbyt INPUT
    .dbyt END
    .dbyt NEXT
    .dbyt DIM
    .dbyt READ
    .dbyt RUN
    .dbyt RESTORE
    .dbyt RETURN
    .dbyt STOP
    .dbyt POKE
    .dbyt CONT
    .dbyt LIST
    .dbyt CLEAR
    .dbyt NEW
    .dbyt CLOAD
    .dbyt CSAVE
    .dbyt OPEN
    .dbyt CLOSE
    .dbyt LLIST
    .dbyt SET
    .dbyt RESET
    .dbyt CLS
    .dbyt MOTOR
    .dbyt SOUND
    .dbyt AUDIO
    .dbyt EXEC
    .dbyt SKIPF

;; The errors' two-letter names, in code order.
ERRTAB:
    .byte "NF", "SN", "RG", "OD", "FC", "OV", "OM", "UL", "BS", "DD", "/0", "ID", "TM", "OS", "LS", "ST"
    .byte "CN", "FD", "AO", "DN", "IO", "FM", "NO", "IE", "DS"

;; " ERROR", after an error's name.
MSGERR:
    .byte " ERROR", 0
;; " IN ", before the line an error happened in.
MSGIN:
    .byte " IN ", 0
;; The prompt: OK on a line of its own.
MSGOK:
    .byte $0D, "OK", $0D, 0
;; BREAK, on a line of its own.
MSGBRK:
    .byte $0D, "BREAK", 0
;; Searches the stack for the FOR of a loop: the one whose variable is in <VARDES>, or with <VARDES> zero the
;; innermost, whose variable it then sets.
;;
;; Out:  X = the FOR's entry, zero = set when found
FNDFOR:
    LEAX 4,S                        ; past this routine's and its caller's returns
FNDFOR_NEXT:
    LDB #18                         ; a FOR entry's size
    STX TEMPTR
    LDA ,X
    SUBA #TK_FOR
    BNE FNDFOR_DONE                 ; not a FOR entry: the end of the loops
    LDX 1,X                         ; its variable
    STX TMPTR1
    LDX VARDES
    BEQ FNDFOR_FIRST
    CMPX TMPTR1
    BEQ FNDFOR_DONE
    LDX TEMPTR
    ABX
    BRA FNDFOR_NEXT
FNDFOR_FIRST:
    LDX TMPTR1
    STX VARDES
FNDFOR_DONE:
    LDX TEMPTR
    TSTA
    RTS

;; Checks for room, then moves a block of memory up, as <MOVEUP_UNCHECKED> does.
;;
;; In:   D = the block's new end
MOVEUP:
    BSR CHKMEM
;; Moves the bytes from <V47> up to <V43> so that they end at <V41>, starting from the top.
;;
;; Out:  V45 = the block's new start
MOVEUP_UNCHECKED:
    LDU V41
    LEAU 1,U
    LDX V43
    LEAX 1,X
MOVEUP_LOOP:
    LDA ,-X
    PSHU A
    CMPX V47
    BNE MOVEUP_LOOP
    STU V45
CHKMEM_DONE:
    RTS

;; Checks that B more words fit on the stack.
;;
;; In:   B = the words
;; Errors: ?OM ERROR when they don't
GETSTK:
    CLRA
    ASLB
    ADDD ARYEND
;; Checks that memory up to D, and 58 bytes more, stays below the stack.
;;
;; In:   D = the address
;; Errors: ?OM ERROR when it doesn't
CHKMEM:
    ADDD #58
    BLO OMERR
    STS BOTSTK
    CMPD BOTSTK
    BLO CHKMEM_DONE
;; Raises ?OM ERROR: out of memory.
OMERR:
    LDB #ERR_OM
;; The error handler: stops the cassette and the sound, resets the stack, shows ?, the error's name and ERROR,
;; and the line when a program was running, then prompts.
;;
;; In:   B = the error's code
;; Calls: RVEC16, RVEC17
ERROR:
    JSR RVEC16
    JSR RVEC17
    JSR MOTOROFF
    JSR SNDOFF
    JSR RSTSTK
    CLR DEVNUM
    JSR NEWLIN                       ; at the start of a line
    JSR OUTQST                       ; ?
    LDX #ERRTAB
ERROR_SHOW:
    ABX
    BSR ERRCHR
    BSR ERRCHR
    LDX #MSGERR-1
;; Shows a message, then the line number when a program was running, then prompts.
;;
;; In:   X = the message, less one
REPORT:
    JSR STROUT1
    LDA CURLIN
    INCA
    BEQ OKPRMT                      ; direct mode
    JSR INPRT                      ; IN and the line
;; Prompts with OK, then runs the direct-mode loop, <MAINLP>.
OKPRMT:
    JSR NEWLIN
    LDX #MSGOK
    JSR STROUT1
;; The direct-mode loop: reads a line, then adds it to the program when it starts with a line number, and runs it
;; otherwise. A line read from a cassette file must be numbered.
;;
;; Errors: ?DS ERROR for an unnumbered line in a file
MAINLP:
    JSR LINEIN
    LDU #$FFFF
    STU CURLIN                      ; direct mode
    BCS MAINLP                      ; BREAK
    TST CINBFL
    LBNE LDEND                      ; the file's end
    STX CHARAD
    JSR GETNCH
    BEQ MAINLP                      ; an empty line
    BCS EDITLN                      ; a line number
    LDB #ERR_DS
    TST DEVNUM
    BNE ERROR
    JSR CRUNCH                       ; crunch it
MAINLP_RUN:
    JMP GONE                       ;   and run it
;; Shows one character of an error's name.
;;
;; In:   X = the character
ERRCHR:
    LDA ,X+
    JMP OUTCH

;; Adds a numbered line to the program, replacing the line with its number, or deletes that line when nothing
;; follows the number. Variables are cleared and the lines relinked.
EDITLN:
    JSR LINGET                       ; BINVAL = the line number
EDITLN_NUMBER:
    LDX BINVAL
    STX LINHDR                      ; the number goes before the text, ready to copy
    JSR CRUNCH                       ; crunch the rest: B = its length
    STB TMPLOC
    BSR FINDLN
    BLO EDITLN_INSERT               ; no line with that number
    LDD V47
    SUBD ,X                         ; minus the old line's length
    ADDD VARTAB
    STD VARTAB
    LDU ,X                          ; close up the gap
EDITLN_CLOSE:
    PULU A
    STA ,X+
    CMPX VARTAB
    BNE EDITLN_CLOSE
EDITLN_INSERT:
    LDA LINBUF
    BEQ EDITLN_DONE                 ; only a number: the line is deleted
    LDD VARTAB
    STD V43
    ADDB TMPLOC
    ADCA #0
    STD V41
    JSR MOVEUP                      ; make room where the line goes
    LDU #LINHDR-2                   ; the link, the number and the text
EDITLN_COPY:
    PULU A
    STA ,X+
    CMPX V45
    BNE EDITLN_COPY
    LDX V41
    STX VARTAB
EDITLN_DONE:
    BSR CLRVAR
    BSR LINKLN
    BRA MAINLP

;; Relinks the program: sets each line's link to the line after it.
LINKLN:
    LDX TXTTAB
LINKLN_LINE:
    LDD ,X
    BEQ LINKLN_DONE                 ; the zero link after the last line
    LEAU 4,X                        ; the text
LINKLN_END:
    LDA ,U+
    BNE LINKLN_END
    STU ,X
    LDX ,X
    BRA LINKLN_LINE

;; Finds the program line numbered <BINVAL>, or the first line after it.
;;
;; Out:  X, V47 = the line, or the one after it, carry = set when no line has the number
FINDLN:
    LDD BINVAL
    LDX TXTTAB
FINDLN_NEXT:
    LDU ,X
    BEQ FINDLN_PAST                 ; the end of the program
    CMPD 2,X
    BLS FINDLN_DONE                 ; this line's number or past it
    LDX ,X
    BRA FINDLN_NEXT
FINDLN_PAST:
    ORCC #$01
FINDLN_DONE:
    STX V47
LINKLN_DONE:
    RTS

;; Runs NEW: erases the program and the variables.
NEW:
    BNE FINDLN_DONE                 ; something follows: an error later
;; Erases the program, then clears the variables as <CLRVAR> does.
ERASEP:
    LDX TXTTAB
    CLR ,X+
    CLR ,X+                         ; a zero link: no lines
    STX VARTAB
;; Clears the variables, strings and arrays, restores DATA, points the program at its start and resets the
;; stack, as RUN does.
CLRVAR:
    LDX TXTTAB
    JSR SETPTR
;; Clears the strings, variables and arrays, restores DATA and resets the stack.
CLRSTR:
    LDX MEMSIZ
    STX STRTAB
    JSR RESTORE
    LDX VARTAB
    STX ARYTAB
    STX ARYEND
;; Resets the stack below the strings, empties the string descriptor stack, and forgets where a program stopped,
;; so CONT cannot continue it.
RSTSTK:
    LDX #STRSTK
    STX TEMPPT
    LDX ,S                          ; the return address
    LDS FRETOP
    CLR ,-S                         ; a zero ends the FOR search
    CLR OLDPTR
    CLR OLDPTR+1
    CLR ARYDIS
    JMP ,X

;; Runs FOR v=start TO end STEP s: sets the variable, then puts on the stack an 18-byte entry: the FOR token, the
;; variable's address, the step and its sign, the end, the line number and where the loop's body starts. An
;; entry already there for the variable is replaced.
FOR:
    LDA #$80
    STA ARYDIS                      ; the variable must not be an array
    JSR LET                      ; the assignment: v=start
    JSR FNDFOR
    LEAS 2,S
    BNE FOR_NEW
    LDX TEMPTR                      ; drop the variable's old loop and those inside it
    LEAS B,X
FOR_NEW:
    LDB #9
    JSR GETSTK
    JSR SKPSTM                       ; X = the end of the statement
    LDD CURLIN
    PSHS A,B,X
    LDB #TK_TO
    JSR SYNCHR
    JSR CKNUM
    JSR FRMNUM                       ; the end value
    LDB FP0SGN
    ORB #$7F
    ANDB FPA0
    STB FPA0                        ; packed form: the sign in the mantissa's top bit
    LDY #FORSTP
    JMP PUSHF0                      ; push it, then come back to FORSTP
;; Finishes FOR: pushes the step, 1 unless STEP gives one, its sign, the variable's address and the FOR token.
FORSTP:
    LDX #FPONE
    JSR MOVFM
    JSR GETCCH
    CMPA #TK_STEP
    BNE FORSTP_PUSH
    JSR GETNCH
    JSR FRMNUM
FORSTP_PUSH:
    JSR SIGN
    JSR PUSHFP
    LDD VARDES
    PSHS A,B
    LDA #TK_FOR
    PSHS A
;; The interpreter's loop: checks for BREAK, then runs the next statement, moving to the next line at a line's
;; end, and ends the program after its last line.
;;
;; Errors: ?SN ERROR when a statement is followed by anything but a colon or the line's end
;; Calls: RVEC20
NEWSTT:
    JSR RVEC20
    ANDCC #$AF                      ; let interrupts in
    BSR ISCNTC
    LDX CHARAD
    STX TINPTR                      ; where this statement starts, for STOP and CONT
    LDA ,X+
    BEQ NEWSTT_LINE
    CMPA #':'
    BEQ GONE
SNERR1:
    JMP SNERR
NEWSTT_LINE:
    LDA ,X++                        ; the next line's link: zero after the last line
    STA ENDFLG
    BEQ ENDPRG
    LDD ,X+
    STD CURLIN
    STX CHARAD                      ; just before the line's text
;; Runs the statement at the next character, then goes back to <NEWSTT>.
GONE:
    JSR GETNCH
    BSR GONE2
    BRA NEWSTT
;; Runs the statement that starts with the character in A: a command's token through <COMDSP>, a later ROM's
;; through its table in <COMVEC>, and anything else as an assignment, as LET would.
;;
;; In:   A = the statement's first character, zero = set at the statement's end
GONE2:
    BEQ CONT_DONE
    TSTA
    LBPL LET                     ; not a token: an assignment
    CMPA #TK_SKIPF
    BHI GONE_EXT
    LDX COMVEC+3                    ; the command table
GONE_DISPATCH:
    ASLA                            ; two bytes a command, from $80
    TFR A,B
    ABX
    JSR GETNCH
    JMP [,X]
GONE_EXT:
    CMPA #TK_LESS
    BLS SNERR1                      ; an operator or a word that is not a command
    JMP [COMVEC+13]                 ; Extended BASIC's commands

;; Runs RESTORE: READ starts again at the program's first DATA.
RESTORE:
    LDX TXTTAB
    LEAX -1,X
RESTORE_SET:
    STX DATPTR
    RTS

;; Checks the keyboard while a program runs: BREAK stops it, SHIFT-@ pauses it until another key is pressed, and
;; any other key is kept for INKEY$.
ISCNTC:
    JSR KEYCHK
    BEQ ISCNTC_DONE
ISCNTC_KEY:
    CMPA #$03                       ; BREAK
    BEQ STOP
    CMPA #$13                       ; SHIFT-@
    BEQ ISCNTC_PAUSE
    STA IKEYIM
ISCNTC_DONE:
    RTS
ISCNTC_PAUSE:
    JSR KEYIN
    BEQ ISCNTC_PAUSE
    BRA ISCNTC_KEY

;; Runs END: closes the files and ends the program with OK.
END:
    JSR CLSALL
    JSR GETCCH
    BRA STOP_CHECK                  ; the carry clear: END
;; Runs STOP, as BREAK does: stops the program with BREAK and the line, where CONT can continue it.
STOP:
    ORCC #$01                       ; the carry set: STOP
STOP_CHECK:
    BNE CONT_DONE                   ; something follows: an error later
    LDX CHARAD
    STX TINPTR
;; Stops the program, as END when the carry is clear and as STOP when it is set.
;;
;; In:   carry = set for STOP
STOPIT:
    ROR ENDFLG
    LEAS 2,S                        ; not back to the interpreter
;; Ends the program: keeps where it stopped, for CONT, then prompts with OK after END or shows BREAK after STOP.
ENDPRG:
    LDX CURLIN
    CMPX #$FFFF
    BEQ ENDPRG_MSG                  ; direct mode: nothing to continue
    STX OLDTXT
    LDX TINPTR
    STX OLDPTR
ENDPRG_MSG:
    CLR DEVNUM
    LDX #MSGBRK-1
    TST ENDFLG
    LBPL OKPRMT
    JMP REPORT

;; Runs CONT: continues the program where STOP or BREAK stopped it.
;;
;; Errors: ?CN ERROR when it cannot be continued
CONT:
    BNE CONT_DONE
    LDB #ERR_CN
    LDX OLDPTR
    LBEQ ERROR
    STX CHARAD
    LDX OLDTXT
    STX CURLIN
CONT_DONE:
    RTS

;; Runs CLEAR size,top: sets aside size bytes of string space below top, the highest address BASIC may use, and
;; clears the variables.
;;
;; Errors: ?OM ERROR when there is not room
CLEAR:
    BEQ CLEAR_DONE
    JSR POSINT                      ; D = the string space
    PSHS A,B
    LDX MEMSIZ
    JSR GETCCH
    BEQ CLEAR_SIZE
    JSR SYNCOM
    JSR GETADR                       ; X = the top
    LEAX -1,X
    CMPX TOPRAM
    BHI CLEAR_OM
CLEAR_SIZE:
    TFR X,D
    SUBD ,S++
    BLO CLEAR_OM
    TFR D,U                         ; the start of string space
    SUBD #58
    BLO CLEAR_OM
    SUBD VARTAB
    BLO CLEAR_OM
    STU FRETOP
    STX MEMSIZ
CLEAR_DONE:
    JMP CLRSTR
CLEAR_OM:
    JMP OMERR

;; Runs RUN: closes the files, clears the variables and runs the program from its start, or from the line given.
;;
;; Calls: RVEC18
RUN:
    JSR RVEC18
    JSR CLSALL
    JSR GETCCH
    LBEQ CLRVAR
    JSR CLRSTR
    BRA RUN_LINE

;; Runs GOTO and GOSUB, which start with the token GO: GOSUB pushes the line and the place after it, then both go
;; to the line.
;;
;; Errors: ?SN ERROR when TO or SUB does not follow
GO:
    TFR A,B
GO_NEXT:
    JSR GETNCH
    CMPB #TK_TO
    BEQ GOTO
    CMPB #TK_SUB
    BNE SNERR2
    LDB #3
    JSR GETSTK
    LDU CHARAD
    LDX CURLIN
    LDA #TK_SUB
    PSHS A,X,U                      ; the GOSUB's entry: its token, line and place
RUN_LINE:
    BSR GOTO
    JMP NEWSTT
;; Goes to the line whose number follows, searching from the next line when the number is higher.
;;
;; Errors: ?UL ERROR when there is no such line
GOTO:
    JSR GETCCH
    JSR LINGET                       ; BINVAL = the line number
    BSR SKPLIN
    LEAX 1,X                        ; the next line
    LDD BINVAL
    CMPD CURLIN
    BHI GOTO_FIND
    LDX TXTTAB
GOTO_FIND:
    JSR FINDLN_NEXT
    BLO ULERR
;; Points <CHARAD> just before X, where <GETNCH> reads next.
;;
;; In:   X = the next character
SETPTR:
    LEAX -1,X
    STX CHARAD
SETPTR_DONE:
    RTS

;; Runs RETURN: drops the loops inside the subroutine, then continues after its GOSUB.
;;
;; Errors: ?RG ERROR without a GOSUB
RETURN:
    BNE SETPTR_DONE
    LDA #$FF
    STA VARDES                      ; matches no FOR, so the search passes them all
    JSR FNDFOR
    TFR X,S
    CMPA #TK_SUB-TK_FOR
    BEQ RETURN_POP
    LDB #ERR_RG
    .byte $8C                       ; CMPX #: skips the LDB below
;; Raises ?UL ERROR: an undefined line.
ULERR:
    LDB #ERR_UL
    JMP ERROR
SNERR2:
    JMP SNERR
RETURN_POP:
    PULS A,X,U
    STX CURLIN
    STU CHARAD
;; Runs DATA, which READ reads and running skips: goes to the statement's end.
DATA:
    BSR SKPSTM
    .byte $8C                       ; CMPX #: skips the BSR below
;; Runs REM and ': goes to the line's end.
REM:
    BSR SKPLIN
    STX CHARAD
SKIP_DONE:
    RTS

;; Finds the end of the statement: a colon or the line's end, outside quotes.
;;
;; Out:  X = the end
SKPSTM:
    LDB #':'
    .byte $86                       ; LDA #: skips the CLRB below
;; Finds the end of the line, counting the IFs on the way in <IFCTR>.
;;
;; Out:  X = the end
SKPLIN:
    CLRB
    STB CHARAC
    CLRB
    LDX CHARAD
SKIP_QUOTE:
    TFR B,A                         ; swap the terminators: inside quotes only the line's end ends it
    LDB CHARAC
    STA CHARAC
SKIP_CHAR:
    LDA ,X
    BEQ SKIP_DONE
    PSHS B
    CMPA ,S+
    BEQ SKIP_DONE
    LEAX 1,X
    CMPA #'"'
    BEQ SKIP_QUOTE
    INCA
    BNE SKIP_IF
    LEAX 1,X                        ; $FF: a function token's second byte
SKIP_IF:
    CMPA #TK_IF+1
    BNE SKIP_CHAR
    INC IFCTR
    BRA SKIP_CHAR
;; Runs IF condition THEN statements ELSE statements: a false condition skips to the ELSE that matches this IF,
;; or to the line's end. THEN or ELSE followed by a line number goes to that line; GOTO may take THEN's place.
;;
;; Errors: ?SN ERROR when THEN or GOTO does not follow the condition
IF:
    JSR FRMNUM
    JSR GETCCH
    CMPA #TK_GO
    BEQ IF_TEST
    LDB #TK_THEN
    JSR SYNCHR
IF_TEST:
    LDA FP0EXP
    BNE IF_THEN                     ; true
    CLR IFCTR
IF_SKIP:
    BSR DATA                        ; to the next statement
    TSTA
    BEQ SKIP_DONE                   ; the line's end
    JSR GETNCH
    CMPA #TK_ELSE
    BNE IF_SKIP
    DEC IFCTR                       ; an ELSE: this IF's, unless an inner IF claims it
    BPL IF_SKIP
    JSR GETNCH
IF_THEN:
    JSR GETCCH
    LBCS GOTO                       ; a line number
    JMP GONE2

;; Runs ON n GOTO and ON n GOSUB: goes to the nth line number in the list, or on to the next statement when n is
;; 0 or past the list's end.
;;
;; Errors: ?SN ERROR when GOTO or GOSUB does not follow
ON:
    JSR GETBYT                       ; FPA0+3 = n
    LDB #TK_GO
    JSR SYNCHR
    PSHS A                          ; TO or SUB
    CMPA #TK_SUB
    BEQ ON_COUNT
    CMPA #TK_TO
ON_CHECK:
    BNE SNERR2
ON_COUNT:
    DEC FPA0+3
    BNE ON_SKIP
    PULS B
    JMP GO_NEXT
ON_SKIP:
    JSR GETNCH
    BSR LINGET
    CMPA #','
    BEQ ON_COUNT
    PULS B,PC

;; Reads a line number, 0-63999.
;;
;; In:   A = the first character, carry = set when it is a digit
;; Out:  BINVAL = the number, A = the character after it
;; Errors: ?SN ERROR past 63999
LINGET:
    LDX ZERO
    STX BINVAL
LINGET_DIGIT:
    BCC LINGET_DONE                 ; not a digit
    SUBA #'0'
    STA CHARAC
    LDD BINVAL
    CMPA #$18                       ; 6400 or more: times 10 is too big
    BHI ON_CHECK
    ASLB                            ; times 10: times 4, plus itself, times 2
    ROLA
    ASLB
    ROLA
    ADDD BINVAL
    ASLB
    ROLA
    ADDB CHARAC
    ADCA #0
    STD BINVAL
    JSR GETNCH
    BRA LINGET_DIGIT

;; Runs LET, the assignment v=expression, which needs no LET.
;;
;; Errors: ?SN ERROR without =, ?TM ERROR when the types differ
LET:
    JSR PTRGET
    STX VARDES
    LDB #TK_EQUAL
    JSR SYNCHR
    LDA VALTYP
    PSHS A
    JSR FRMEVL
LET_VALUE:
    PULS A
    RORA                            ; the variable's type, in the carry
    JSR CKTYPE
    LBEQ MOVVAR                      ; numeric: store FPA0
;; Assigns the string in FPA0 to the string variable at <VARDES>, first copying it into string space unless it
;; is a literal in the program or a string just made there.
LETSTR:
    LDX FPA0+2                      ; the string's descriptor
    LDD FRETOP
    CMPD 2,X
    BHS LETSTR_STORE                ; its text is in the program
    CMPX VARTAB
    BLO LETSTR_STORE                ; a temporary descriptor: the string is new
LETSTR_COPY:
    LDB ,X
    JSR STRINI                       ; room for a copy
    LDX V4D
    JSR MOVSTR
    LDX #STRDES
LETSTR_STORE:
    STX V4D
    JSR FRETMS                       ; free the temporary descriptor
    LDU V4D
    LDX VARDES
    PULU A,B,Y                      ; the length and the text's address
    STA ,X
    STY 2,X
LINGET_DONE:
    RTS

;; ?REDO, asking for INPUT's line again.
MSGRDO:
    .byte "?REDO", $0D, 0

;; Handles an item INPUT or READ could not use: ?FD ERROR from a file, ?SN ERROR in the DATA's line for READ,
;; and for INPUT ?REDO and the INPUT statement again.
BADINP:
    LDB #ERR_FD
    TST DEVNUM
    BEQ BADINP_READ
BADINP_ERROR:
    JMP ERROR
BADINP_READ:
    LDA INPFLG
    BEQ BADINP_REDO
    LDX DATTXT
    STX CURLIN
    JMP SNERR
BADINP_REDO:
    LDX #MSGRDO-1
    JSR STROUT1
    LDX TINPTR
    STX CHARAD
    RTS

;; Runs INPUT: reads values for the variables listed from the keyboard, after an optional prompt in quotes, or
;; with # from a file.
;;
;; Errors: ?ID ERROR in direct mode
INPUT:
    LDB #ERR_ID
    LDX CURLIN
    LEAX 1,X
    BEQ BADINP_ERROR
    BSR INPDEV
    CLR DEVNUM
    RTS
INPDEV:
    CMPA #'#'
    BNE INPDEV_PROMPT
    JSR GETDEV
    JSR CHKIN
INPDEV_FILE:
    JSR SYNCOM
INPDEV_PROMPT:
    CMPA #'"'
    BNE INPDEV_LINE
    JSR STRLIT                      ; the prompt
    LDB #';'
    JSR SYNCHR
    JSR STRPRT
INPDEV_LINE:
    LDX #LINBUF
    CLR ,X
    TST DEVNUM
    BNE INPRD                       ; a file: its first line is read for the first variable
    BSR INPLIN
    LDB #','
    STB ,X
    BRA INPRD
;; Shows ? and a space, then reads a line of input. BREAK stops the program.
;;
;; Errors: ?IE ERROR at a file's end
INPLIN:
    JSR OUTQST
    JSR OUTSPC
INPLIN_READ:
    JSR LINEIN
    BCC INPLIN_END
    LEAS 4,S
    JMP STOPIT
INPLIN_END:
    LDB #ERR_IE
    TST CINBFL
    BNE BADINP_ERROR
    RTS

;; Runs READ: takes values for the variables listed from the DATA statements, in order.
;;
;; Errors: ?OD ERROR past the last DATA
READ:
    LDX DATPTR
    .byte $86                       ; LDA #: skips the CLRA below, so A is not zero
;; Reads values for INPUT, from X, or for READ, into each variable listed.
;;
;; In:   A = 0 for INPUT, else READ, X = where the values start
INPRD:
    CLRA
    STA INPFLG
    STX DATTMP
INPRD_VAR:
    JSR PTRGET
    STX VARDES
    LDX CHARAD
    STX BINVAL                      ; the statement's place
    LDX DATTMP
    LDA ,X
    BNE INPRD_ITEM
    LDA INPFLG
    BNE READ_DATA                   ; READ: find the next DATA
    JSR RVEC10
    JSR OUTQST                       ; INPUT: ?? and another line
    BSR INPLIN
INPRD_ITEM:
    STX CHARAD
    JSR GETNCH
    LDB VALTYP
    BEQ INPRD_NUMBER
    LDX CHARAD
    STA CHARAC
    CMPA #'"'
    BEQ INPRD_STRING                ; a quoted string ends at the quote
    LEAX -1,X
    CLRA
    STA CHARAC
    JSR SETPRM
    TST PRTDEV
    BNE INPRD_STRING                ; from the cassette: the whole line
    LDA #':'
    STA CHARAC
    LDA #','
INPRD_STRING:
    STA ENDCHR
    JSR STRLT3
    JSR STRLIT_END
    JSR LETSTR
    BRA INPRD_NEXT
INPRD_NUMBER:
    JSR FIN
    JSR MOVVAR
INPRD_NEXT:
    JSR GETCCH
    BEQ INPRD_STEP
    CMPA #','
    LBNE BADINP
INPRD_STEP:
    LDX CHARAD
    STX DATTMP
    LDX BINVAL
    STX CHARAD
    JSR GETCCH
    BEQ INPRD_END
    JSR SYNCOM
    BRA INPRD_VAR
READ_DATA:
    STX CHARAD
    JSR SKPSTM
    LEAX 1,X
    TSTA
    BNE READ_FIND
    LDB #ERR_OD                     ; the line's end: on to the next line
    LDU ,X++
    BEQ NEXT_ERROR                       ; no more lines
    LDD ,X++
    STD DATTXT
READ_FIND:
    LDA ,X
    CMPA #TK_DATA
    BNE READ_DATA
    BRA INPRD_ITEM
INPRD_END:
    LDX DATTMP
    LDB INPFLG
    LBNE RESTORE_SET                ; READ: the next item comes from here
    LDA ,X
    BEQ INPRD_EXIT
    LDX #MSGXTR-1                   ; INPUT had more than it needed
    JMP STROUT1
INPRD_EXIT:
    RTS

;; ?EXTRA IGNORED, after an INPUT line with values left over.
MSGXTR:
    .byte "?EXTRA IGNORED", $0D, 0
;; Runs NEXT, or NEXT v1,v2: steps the loop's variable and goes back to the loop's body, or ends the loop when the
;; variable has passed the end.
;;
;; Errors: ?NF ERROR without a matching FOR
NEXT:
    BNE NEXT_VAR
    LDX ZERO                        ; no variable: the innermost loop
    BRA NEXT_FIND
NEXT_VAR:
    JSR PTRGET
NEXT_FIND:
    STX VARDES
    JSR FNDFOR
    BEQ NEXT_STEP
    LDB #ERR_NF
NEXT_ERROR:
    BRA ERRJMP
NEXT_STEP:
    TFR X,S                         ; drop the loops inside this one
    LEAX 3,X
    JSR MOVFM                       ; FPA0 = the step
    LDA 8,S
    STA FP0SGN
    LDX VARDES
    JSR FADDX                       ; add the variable
    JSR MOVVAR                       ;   and store it back
    LEAX 9,S
    JSR FCOMP                       ; compare with the end
    SUBB 8,S                        ;   in the step's direction
    BEQ NEXT_DONE
    LDX 14,S                        ; not past it: back to the loop's body
    STX CURLIN
    LDX 16,S
    STX CHARAD
NEXT_LOOP:
    JMP NEWSTT
NEXT_DONE:
    LEAS 18,S                       ; the loop is over: drop its entry
    JSR GETCCH
    CMPA #','
    BNE NEXT_LOOP
    JSR GETNCH
    BSR NEXT_VAR                    ; NEXT the next variable listed

;; Evaluates an expression, which must be numeric.
;;
;; Out:  FPA0 = its value
;; Errors: ?TM ERROR for a string
FRMNUM:
    BSR FRMEVL
;; Checks that the value just evaluated is numeric.
;;
;; Errors: ?TM ERROR for a string
CKNUM:
    ANDCC #$FE
    .byte $7D                       ; TST >: skips the ORCC below
;; Checks that the value just evaluated is a string.
;;
;; Errors: ?TM ERROR for a number
CKSTR:
    ORCC #$01
;; Checks the value's type: a string when the carry is set, a number when it is clear.
;;
;; In:   carry = set for a string
;; Errors: ?TM ERROR when the type differs
CKTYPE:
    TST VALTYP
    BCS CKTYPE_STRING
    BPL INPRD_EXIT
    .byte $8C                       ; CMPX #: skips the BMI below
CKTYPE_STRING:
    BMI INPRD_EXIT
    LDB #ERR_TM
;; Jumps to the error handler.
;;
;; In:   B = the error's code
ERRJMP:
    JMP ERROR

;; Evaluates an expression, numeric or string.
;;
;; Out:  FPA0 = a number's value, or its +2,+3 a string's descriptor; VALTYP = its type
FRMEVL:
    BSR BACKUP
FRMEVL_START:
    CLRA                            ; the lowest precedence: the whole expression
    .byte $8C                       ; CMPX #: skips the PSHS below
;; Evaluates an expression as far as operators of higher precedence than A go, comparing first when B holds the
;; relational operators seen.
;;
;; Operators wait on the stack with their precedence, their routine and the value on their left, and are applied
;; when an operator of no higher precedence follows: $46 OR, $50 AND, $5A NOT, $64 the comparisons, $79 + and -,
;; $7B * and /, $7D unary minus and $7F ^.
;;
;; In:   A = the precedence, B = the relational operators
EVLPRC:
    PSHS B
    PSHS A
    LDB #1
    JSR GETSTK
    JSR EVAL                        ; the first term
FRMEVL_TERM:
    CLR TRELFL
EVLPRC_OPERATOR:
    JSR GETCCH
EVLPRC_RELATION:
    SUBA #TK_GREATER
    BLO EVLPRC_ARITH
    CMPA #3
    BHS EVLPRC_ARITH                ; not >, = or <
    CMPA #1                         ; bit 0 >, bit 1 =, bit 2 <
    ROLA
    EORA TRELFL
    CMPA TRELFL
    BLO SNERR3                      ; the same operator twice
    STA TRELFL
    JSR GETNCH
    BRA EVLPRC_RELATION
EVLPRC_ARITH:
    LDB TRELFL
    BNE EVLPRC_COMPARE
    LBHS EVLPRC_END                 ; past the operators
    ADDA #7                         ; + to OR: 0-6
    BHS EVLPRC_END                  ; before them
    ADCA VALTYP
    LBEQ CAT                      ; + after a string: join them
    ADCA #$FF
    PSHS A
    ASLA                            ; three bytes an operator in OPTAB
    ADDA ,S+
    LDX #OPTAB
    LEAX A,X
EVLPRC_TABLE:
    PULS A                          ; the precedence waiting
    CMPA ,X
    BHS EVLPRC_CHECK                ; no lower than this operator's: apply it first
    BSR CKNUM
EVLPRC_PUSH:
    PSHS A
    BSR PUSHOP                      ; this operator waits; evaluate its right side
    LDX RELPTR
    PULS A
    BNE EVLPRC_PREVIOUS
    TSTA
    LBEQ EVLPRC_EXP
    BRA EVLPRC_APPLY
EVLPRC_COMPARE:
    ASL VALTYP
    ROLB                            ; bit 0: the operands are strings
    BSR BACKUP
    LDX #RELENT
    STB TRELFL
    CLR VALTYP
    BRA EVLPRC_TABLE

;; Moves <CHARAD> back one character.
BACKUP:
    LDX CHARAD
    JMP SETPTR

;; The comparisons' entry, as in <OPTAB>: their precedence and their routine.
RELENT:
    .byte $64
    .dbyt RELOP
EVLPRC_PREVIOUS:
    CMPA ,X
    BHS EVLPRC_APPLY
    BRA EVLPRC_PUSH

;; Pushes an operator's routine and the value on its left, then evaluates its right side as far as its
;; precedence goes.
;;
;; In:   X = the operator's entry
PUSHOP:
    LDD 1,X
    PSHS A,B
    BSR PUSHPR
    LDB TRELFL
    LBRA EVLPRC
SNERR3:
    JMP SNERR

;; Pushes FPA0 with its sign under the return address, and loads the operator's precedence.
;;
;; In:   X = the operator's entry
;; Out:  A = its precedence
PUSHPR:
    LDB FP0SGN
    LDA ,X
;; Pushes FPA0, with the sign in B, under the return address.
;;
;; In:   B = the sign
PUSHFP:
    PULS Y
    PSHS B
;; Pushes FPA0, unpacked: its exponent, then its mantissa; the return address comes from Y.
;;
;; In:   Y = where to return
PUSHF0:
    LDB FP0EXP
    LDX FPA0
    LDU FPA0+2
    PSHS B,X,U
    JMP ,Y
EVLPRC_END:
    LDX ZERO
    LDA ,S+
    BEQ EVLPRC_EXP                  ; nothing waiting
EVLPRC_CHECK:
    CMPA #$64
    BEQ EVLPRC_SAVE                 ; a comparison works on strings too
    JSR CKNUM
EVLPRC_SAVE:
    STX RELPTR
EVLPRC_APPLY:
    PULS B                          ; the relational operators and the type
    CMPA #$5A
    BEQ EVLPRC_DONE                 ; NOT: done by EVAL_NOT
    CMPA #$7D
    BEQ EVLPRC_DONE                 ; unary minus: done by EVAL_MINUS
    LSRB
    STB RELFLG
    PULS A,X,U                      ; FPA1 = the value on the left
    STA FP1EXP
    STX FPA1
    STU FPA1+2
    PULS B
    STB FP1SGN
    EORB FP0SGN
    STB RESSGN                      ; then the operator's routine returns through the stack
EVLPRC_EXP:
    LDB FP0EXP
EVLPRC_DONE:
    RTS

;; Evaluates a term: a number, a string in quotes, a variable, a function, an expression in parentheses, or one
;; after NOT, + or -.
;;
;; Out:  FPA0 = its value, VALTYP = its type
;; Calls: RVEC15
EVAL:
    JSR RVEC15
    CLR VALTYP
EVAL_NEXT:
    JSR GETNCH
    BHS EVAL_OTHER
EVAL_NUMBER:
    JMP FIN                      ; a number
EVAL_OTHER:
    JSR ISLETC
    BHS EVAL_VAR                       ; a letter: a variable
    CMPA #'.'
    BEQ EVAL_NUMBER
    CMPA #TK_MINUS
    BEQ EVAL_MINUS
    CMPA #TK_PLUS
.if VERSION < 12
    BEQ EVAL_NEXT                   ; unary plus does nothing
.else
    BEQ EVAL                        ; unary plus does nothing
.endif
    CMPA #'"'
    BNE EVAL_NOT
;; Evaluates the string in quotes at <CHARAD>, making a temporary descriptor for it.
STRLIT:
    LDX CHARAD
    JSR STRLT2
;; Moves <CHARAD> to the end of the string just scanned, kept in <COEFPT>.
STRLIT_END:
    LDX COEFPT
    STX CHARAD
    RTS
EVAL_NOT:
    CMPA #TK_NOT
    BNE EVAL_FUNCTION
    LDA #$5A                        ; NOT's precedence
    JSR EVLPRC
    JSR INTCNV
    COMA
    COMB
    JMP GIVABF
EVAL_FUNCTION:
    INCA
    BEQ EVAL_FN                      ; $FF: a function
;; Evaluates an expression in parentheses.
;;
;; Errors: ?SN ERROR without the parentheses
PARENS:
    BSR SYNLPR
    JSR FRMEVL
;; Checks that ) comes next and moves past it.
SYNRPR:
    LDB #')'
    .byte $8C                       ; CMPX #: skips the LDB below
;; Checks that ( comes next and moves past it.
SYNLPR:
    LDB #'('
    .byte $8C                       ; CMPX #: skips the LDB below
;; Checks that a comma comes next and moves past it.
SYNCOM:
    LDB #','
;; Checks that the character in B comes next and moves past it.
;;
;; In:   B = the character
;; Out:  A = the character after it, as <GETNCH> leaves it
;; Errors: ?SN ERROR when another character comes
SYNCHR:
    CMPB [CHARAD]
    BNE SNERR
    JMP GETNCH
;; Raises ?SN ERROR: a syntax error.
SNERR:
    LDB #ERR_SN
    JMP ERROR
EVAL_MINUS:
    LDA #$7D                        ; unary minus's precedence
    JSR EVLPRC
    JMP NEGATE
EVAL_VAR:
    JSR PTRGET                       ; X = the variable
    STX FPA0+2
    LDA VALTYP
    BNE EVLPRC_DONE                 ; a string: its descriptor is enough
    JMP MOVFM
EVAL_FN:
    JSR GETNCH                      ; the function's token
    TFR A,B
    ASLB                            ; its place, times two
    JSR GETNCH
    CMPB #19*2
    BLS EVAL_FN_COLOR
    JMP [COMVEC+18]                 ; Extended BASIC's functions
EVAL_FN_COLOR:
    PSHS B
    CMPB #(TK_LEFT-$80)*2
    BLO EVAL_FN_PARENS              ; one numeric argument in parentheses
    CMPB #(TK_INKEY-$80)*2
    BHS EVAL_FN_CALL                ; INKEY$ and MEM: no argument
    BSR SYNLPR
    LDA ,S
    CMPA #(TK_POINT-$80)*2
    BHS EVAL_FN_CALL                ; POINT reads its own arguments
    JSR FRMEVL                      ; LEFT$, RIGHT$ and MID$: a string
    BSR SYNCOM
    JSR CKSTR
    PULS A
    LDU FPA0+2
    PSHS A,U
    JSR GETBYT                       ;   and a number
    PULS A
    PSHS A,B
    .byte $8E                       ; LDX #: skips the BSR below
EVAL_FN_PARENS:
    BSR PARENS
EVAL_FN_CALL:
    PULS B
    LDX COMVEC+8                    ; the function table
EVAL_FN_DISPATCH:
    ABX
    JSR [,X]
    JMP CKNUM

;; The OR operator: the bitwise OR of two integers, -32768 to 32767.
OROP:
    .byte $86                       ; LDA #: skips the CLRA below, so A is not zero
;; The AND operator: the bitwise AND of two integers, -32768 to 32767.
ANDOP:
    CLRA
    STA TMPLOC                      ; zero for AND
    JSR INTCNV
    STD CHARAC                      ; the right side
    JSR MOVFA                       ; FPA0 = the left side
    JSR INTCNV
    TST TMPLOC
    BNE ANDOP_OR
    ANDA CHARAC
    ANDB ENDCHR
    BRA ANDOP_GIVE
ANDOP_OR:
    ORA CHARAC
    ORB ENDCHR
ANDOP_GIVE:
    JMP GIVABF

;; The comparisons: compares the two numbers or strings, then gives -1 when the relation <RELFLG> asks for holds
;; and 0 when it doesn't. Strings compare by their characters, then their lengths.
RELOP:
    JSR CKTYPE
    BNE RELOP_STRING
    LDA FP1SGN                      ; pack FPA1, the left side
    ORA #$7F
    ANDA FPA1
    STA FPA1
    LDX #FP1EXP
    JSR FCOMP                       ; B = the comparison: -1, 0 or 1
    BRA RELOP_RESULT
RELOP_STRING:
    CLR VALTYP
    DEC TRELFL
    JSR FREFAC                       ; the right string
    STB STRDES
    STX STRDES+2
    LDX FPA1+2
    JSR FRETMP                       ; the left string
    LDA STRDES
    PSHS B
    SUBA ,S+                        ; compare the lengths
    BEQ RELOP_LENGTH
    LDA #1
    BHS RELOP_LENGTH
    LDB STRDES                      ; the right is longer: compare as far as the shorter
    NEGA
RELOP_LENGTH:
    STA FP0SGN                      ; the result if the shorter matches
    LDU STRDES+2
    INCB
RELOP_NEXT:
    DECB
    BNE RELOP_COMPARE
    LDB FP0SGN
    BRA RELOP_RESULT
RELOP_COMPARE:
    LDA ,X+
    CMPA ,U+
    BEQ RELOP_NEXT
    LDB #$FF
    BHS RELOP_RESULT
    NEGB
RELOP_RESULT:
    ADDB #1                         ; 0 less, 1 equal, 2 greater
    ROLB                            ; the matching relational bit: <, = or >
    ANDB RELFLG
    BEQ RELOP_GIVE
    LDB #$FF
RELOP_GIVE:
    JMP BTOFP
DIM_NEXT:
    JSR SYNCOM
;; Runs DIM: makes each array listed, with the sizes given.
;;
;; Errors: ?DD ERROR for an array that already exists
DIM:
    LDB #1                          ; DIMFLG: making arrays
    BSR PTRGT2
    JSR GETCCH
    BNE DIM_NEXT
    RTS

;; Finds the variable whose name is next, making it when it does not exist: a simple variable, or with ( an array
;; element. A variable read before it is set is not made: its value is <ZERO>.
;;
;; Only the first two characters of a name count; $ makes it a string, and its second character then has bit 7
;; set. A simple variable takes seven bytes after the program: its name, then a number or a string's descriptor.
;;
;; Out:  X, VARPTR = the variable's value, VALTYP = its type
;; Errors: ?SN ERROR when no letter starts the name
PTRGET:
    CLRB
    JSR GETCCH
;; Finds or makes a variable, as <PTRGET> does, or with B nonzero makes an array, as DIM does.
;;
;; In:   A = the name's first character, B = <DIMFLG>
PTRGT2:
    STB DIMFLG
PTRGT2_NAME:
    STA VARNAM
    JSR GETCCH
    BSR ISLETC
    LBLO SNERR
    CLRB
    STB VALTYP
    JSR GETNCH
    BLO PTRGET_SECOND               ; a digit
    BSR ISLETC
    BLO PTRGET_TYPE                 ; neither: a one-character name
PTRGET_SECOND:
    TFR A,B
PTRGET_SKIP:
    JSR GETNCH                      ; the rest of the name does not count
    BLO PTRGET_SKIP
    BSR ISLETC
    BHS PTRGET_SKIP
PTRGET_TYPE:
    CMPA #'$'
    BNE PTRGET_NAME
    COM VALTYP                      ; a string
    ADDB #$80
    JSR GETNCH
PTRGET_NAME:
    STB VARNAM+1
    ORA ARYDIS                      ; an array cannot be found where ARYDIS forbids one
    SUBA #'('
    LBEQ ARRAY
    CLR ARYDIS
    LDX VARTAB
    LDD VARNAM
PTRGET_SEARCH:
    CMPX ARYTAB
    BEQ PTRGET_NEW
    CMPD ,X++
    BEQ PTRGET_FOUND
    LEAX 5,X
    BRA PTRGET_SEARCH

;; Tests for a letter.
;;
;; In:   A = the character
;; Out:  carry = clear for 'A'-'Z'
ISLETC:
    CMPA #'A'
    BLO ISLETC_DONE
    SUBA #'Z'+1
    SUBA #$A5                       ; A as it was, the carry set past 'Z'
ISLETC_DONE:
    RTS

PTRGET_NEW:
    LDX #ZERO
    LDU ,S
    CMPU #EVAL_VAR+3
    BEQ PTRGET_DONE                 ; read in an expression: zero, without making it
    LDD ARYEND
    STD V43
    ADDD #7
    STD V41
    LDX ARYTAB
    STX V47
    JSR MOVEUP                      ; move the arrays up seven bytes
    LDX V41
    STX ARYEND
    LDX V45
    STX ARYTAB
    LDX V47
    LDD VARNAM
    STD ,X++
    CLRA
    CLRB
    STD ,X                          ; a zero value
    STD 2,X
    STA 4,X
PTRGET_FOUND:
    STX VARPTR
PTRGET_DONE:
    RTS

;; -32768 in packed floating point.
M32768:
    .byte $90, $80, $00, $00, $00

;; Moves past the current character, then evaluates an integer from 0 to 32767, as <POSINT> does.
NXTINT:
    JSR GETNCH
;; Evaluates an integer from 0 to 32767.
;;
;; Out:  D = the integer
;; Errors: ?FC ERROR when negative or too big
POSINT:
    JSR FRMNUM
;; Converts FPA0, which must not be negative, to an integer, as <INTCNV> does.
POSCHK:
    LDA FP0SGN
    BMI FCERR
;; Converts FPA0 to an integer from -32768 to 32767.
;;
;; Out:  D = the integer
;; Errors: ?TM ERROR for a string, from 1.2 on, ?FC ERROR out of range
INTCNV:
.if VERSION >= 12
    JSR CKNUM
.endif
    LDA FP0EXP
    CMPA #$90
    BLO INTCNV_OK                   ; below 32768
    LDX #M32768
    JSR FCOMP
    BNE FCERR                       ; only -32768 is allowed so far out
INTCNV_OK:
    JSR QINT
    LDD FPA0+2
    RTS

;; Finds an array element, or with <DIMFLG> set makes the array: each subscript is evaluated and pushed, then
;; the arrays after the variables are searched. An array used before DIM is made with 11 elements to a
;; dimension.
;;
;; An array is its name, its size, the number of dimensions, each dimension's size, then five bytes an element.
;;
;; Out:  X, VARPTR = the element
;; Errors: ?BS ERROR for a subscript out of range or a different number of them, ?DD ERROR when DIM finds the
;;         array made
ARRAY:
.if VERSION >= 12
    LDD DIMFLG                      ; DIMFLG and VALTYP
    PSHS A,B
    NOP
.else
    LDB DIMFLG
    LDA VALTYP
    PSHS A,B
.endif
    CLRB                            ; the number of subscripts
ARRAY_SUBSCRIPT:
    LDX VARNAM
    PSHS B,X
    BSR NXTINT
    PULS B,X,Y
    STX VARNAM
    LDU FPA0+2
    PSHS Y,U                        ; the subscript under the count
    INCB
    JSR GETCCH
    CMPA #','
    BEQ ARRAY_SUBSCRIPT
    STB TMPLOC
    JSR SYNRPR
    PULS A,B
.if VERSION >= 12
    STD DIMFLG
.else
    STA VALTYP
    STB DIMFLG
.endif
    LDX ARYTAB
ARRAY_SEARCH:
    CMPX ARYEND
    BEQ ARRAY_NEW
    LDD VARNAM
    CMPD ,X
    BEQ ARRAY_FOUND
    LDD 2,X                         ; its size
    LEAX D,X
    BRA ARRAY_SEARCH
ARRAY_FOUND:
    LDB #ERR_DD
    LDA DIMFLG
    BNE ARRAY_ERROR
    LDB TMPLOC
    CMPB 4,X
    BEQ ARRAY_ELEMENT
;; Raises ?BS ERROR: a subscript out of range.
BSERR:
    LDB #ERR_BS
    .byte $8C                       ; CMPX #: skips the LDB below
;; Raises ?FC ERROR: an illegal function call, such as an argument out of range.
FCERR:
    LDB #ERR_FC
ARRAY_ERROR:
    JMP ERROR
ARRAY_NEW:
    LDD #5                          ; bytes an element
    STD COEFPT
    LDD VARNAM
    STD ,X
    LDB TMPLOC
    STB 4,X
    JSR GETSTK
    STX V41
ARRAY_DIM:
    LDB #11                         ; without DIM: 0 to 10
    CLRA
    TST DIMFLG
    BEQ ARRAY_SIZE
    PULS A,B
    ADDD #1                         ; DIM's subscript plus one
ARRAY_SIZE:
    STD 5,X
    BSR ARYMUL                      ; the size so far, times this dimension
    STD COEFPT
    LEAX 2,X
    DEC TMPLOC
    BNE ARRAY_DIM
    STX TEMPTR                      ; the first element
    ADDD TEMPTR
    LBLO OMERR
    TFR D,X
    JSR CHKMEM
    SUBD #53
    STD ARYEND
    CLRA
ARRAY_CLEAR:
    LEAX -1,X
    STA 5,X
    CMPX TEMPTR
    BNE ARRAY_CLEAR
    LDX V41
    LDA ARYEND
    SUBD V41
    STD 2,X                         ; the array's size
    LDA DIMFLG
    BNE ARRAY_DONE
ARRAY_ELEMENT:
    LDB 4,X
    STB TMPLOC
    CLRA
    CLRB
ARRAY_INDEX:
    STD COEFPT
    PULS A,B
    STD FPA0+2
    CMPD 5,X
    BHS ARYMUL_BS                   ; past the dimension
    LDU COEFPT
    BEQ ARRAY_STEP
    BSR ARYMUL
    ADDD FPA0+2
ARRAY_STEP:
    LEAX 2,X
    DEC TMPLOC
    BNE ARRAY_INDEX
    STD ,--S                        ; times five bytes an element
    ASLB
    ROLA
    ASLB
    ROLA
    ADDD ,S++
    LEAX D,X
    LEAX 5,X
    STX VARPTR
ARRAY_DONE:
    RTS

;; Multiplies <COEFPT> by a dimension's size, for an array's size or an element's place.
;;
;; In:   X = the array's dimension, less 5
;; Out:  D = the product
;; Errors: ?BS ERROR past 65535
ARYMUL:
    LDA #16
    STA V45
    LDD 5,X
    STD BOTSTK
    CLRA
    CLRB
ARYMUL_BIT:
    ASLB
    ROLA
    BLO ARYMUL_BS
    ASL COEFPT+1
    ROL COEFPT
    BHS ARYMUL_NEXT
    ADDD BOTSTK
    BLO ARYMUL_BS
ARYMUL_NEXT:
    DEC V45
    BNE ARYMUL_BIT
    RTS
ARYMUL_BS:
    JMP BSERR

;; Runs the MEM function: the free memory between the arrays and the stack.
MEM:
    TFR S,D
    SUBD ARYEND
    .byte $21                       ; BRN: skips the CLRA below
;; Returns B, 0-255, as a function's result.
;;
;; In:   B = the result
GIVB:
    CLRA
;; Returns D, -32768 to 32767, as a function's result.
;;
;; In:   D = the result
GIVABF:
    CLR VALTYP
    STD FPA0
    LDB #$90                        ; the binary point after 16 bits
    JMP FLTD

;; Runs the STR$ function: a number as the text PRINT shows.
STR:
    JSR CKNUM
    LDU #STRBUF+2
    JSR FOUTU
    LEAS 2,S
    LDX #STRBUF+1
    BRA STRLT2
;; Reserves room in string space for a string, keeping X in <V4D>, as <STRSPA> does.
;;
;; In:   B = the length, X = kept
STRINI:
    STX V4D
;; Reserves room in string space for a string and puts it in the temporary descriptor <STRDES>.
;;
;; In:   B = the length
;; Out:  X = the room
STRSPA:
    BSR GETSPA
;; Sets the temporary descriptor <STRDES>.
;;
;; In:   B = the length, X = the text
STRSET:
    STX STRDES+2
    STB STRDES
    RTS

;; Scans the string that starts at X, as <STRLT2> does.
STRLX:
    LEAX -1,X
;; Scans a string in quotes, its quote at X, and pushes its descriptor.
;;
;; In:   X = the opening quote
STRLT2:
    LDA #'"'
STRLT2_ENDS:
    STA CHARAC
    STA ENDCHR
;; Scans a string from X+1 to a zero or either terminator, then pushes its descriptor, copying it into string space
;; first when it is in a buffer. A closing quote is skipped.
;;
;; In:   X = the character before it, CHARAC and ENDCHR = the terminators
;; Out:  COEFPT = where the scan stopped
STRLT3:
    LEAX 1,X
    STX RESSGN                      ; its start
    STX STRDES+2
    LDB #$FF
STRLT3_CHAR:
    INCB
    LDA ,X+
    BEQ STRLT3_BACK
    CMPA CHARAC
    BEQ STRLT3_END
    CMPA ENDCHR
    BNE STRLT3_CHAR
STRLT3_END:
    CMPA #'"'
    BEQ STRLT3_DONE                 ; past the quote
STRLT3_BACK:
    LEAX -1,X
STRLT3_DONE:
    STX COEFPT
    STB STRDES
    LDU RESSGN
    CMPU #STRBUF+2
    BHI PUTNEW                      ; in the program: used where it is
    BSR STRINI
    LDX RESSGN
    JSR MOVINS
;; Pushes the temporary descriptor <STRDES> onto the string descriptor stack, making it the value in FPA0.
;;
;; Errors: ?ST ERROR when the stack is full
PUTNEW:
    LDX TEMPPT
    CMPX #STRSTK+40
    BNE PUTNEW_STORE
    LDB #ERR_ST
PUTNEW_ERROR:
    JMP ERROR
PUTNEW_STORE:
    LDA STRDES
    STA <<0,X
    LDD STRDES+2
    STD 2,X
    LDA #$FF
    STA VALTYP
    STX LASTPT
    STX FPA0+2
    LEAX 5,X
    STX TEMPPT
    RTS

;; Reserves room for a string at the bottom of the strings in use, collecting garbage once when there is not
;; enough.
;;
;; In:   B = the length
;; Out:  X, FRESPC = the room
;; Errors: ?OS ERROR when there is not enough even then
GETSPA:
    CLR GARBFL
GETSPA_TRY:
    CLRA
    PSHS A,B
    LDD STRTAB
    SUBD ,S+
    CMPD FRETOP
    BLO GETSPA_FULL
    STD STRTAB
    LDX STRTAB
    LEAX 1,X
    STX FRESPC
    PULS B,PC
GETSPA_FULL:
    LDB #ERR_OS
    COM GARBFL
    BEQ PUTNEW_ERROR                ; collected already
    BSR GARBAG
    PULS B
    BRA GETSPA_TRY

;; Collects garbage: moves the strings still in use to the top of string space, leaving the room the others took
;; free. Each pass finds the highest string not yet moved, among the temporary descriptors, the variables and the
;; arrays, and moves it up.
GARBAG:
    LDX MEMSIZ
GARBAG_PASS:
    STX STRTAB
    CLRA
    CLRB
    STD V4B                         ; the descriptor of the string to move
    LDX FRETOP
    STX V47                         ; its address
    LDX #STRSTK
GARBAG_TEMPS:
    CMPX TEMPPT
    BEQ GARBAG_VARS
    BSR GARBAG_CHECK
    BRA GARBAG_TEMPS
GARBAG_VARS:
    LDX VARTAB
GARBAG_VAR:
    CMPX ARYTAB
    BEQ GARBAG_ARRAYS
    BSR GARBAG_SIMPLE
    BRA GARBAG_VAR
GARBAG_ARRAYS:
    STX V41
GARBAG_ARRAY:
    LDX V41
GARBAG_NEXT:
    CMPX ARYEND
    BEQ GARBAG_MOVE
    LDD 2,X
    ADDD V41
    STD V41                         ; the next array
    LDA 1,X
    BPL GARBAG_ARRAY                ; not a string array
    LDB 4,X
    ASLB
    ADDB #5
    ABX                             ; its first element
GARBAG_ELEMENT:
    CMPX V41
    BEQ GARBAG_NEXT
    BSR GARBAG_CHECK
    BRA GARBAG_ELEMENT
GARBAG_SIMPLE:
    LDA 1,X
    LEAX 2,X
    BPL GARBAG_SKIP                 ; not a string
GARBAG_CHECK:
    LDB ,X
    BEQ GARBAG_SKIP                 ; empty
    LDD 2,X
    CMPD STRTAB
    BHI GARBAG_SKIP                 ; moved already
    CMPD V47
    BLS GARBAG_SKIP                 ; lower than the highest found
    STX V4B
    STD V47
GARBAG_SKIP:
    LEAX 5,X
GARBAG_DONE:
    RTS
GARBAG_MOVE:
    LDX V4B
    BEQ GARBAG_DONE                 ; nothing left to move
    CLRA
    LDB ,X
    DECB
    ADDD V47
    STD V43
    LDX STRTAB
    STX V41
    JSR MOVEUP_UNCHECKED
    LDX V4B
    LDD V45
    STD 2,X
    LDX V45
    LEAX -1,X
    JMP GARBAG_PASS

;; Joins two strings for +.
;;
;; Errors: ?LS ERROR when the result is longer than 255
CAT:
    LDD FPA0+2
    PSHS A,B                        ; the left string
    JSR EVAL
    JSR CKSTR
    PULS X
    STX RESSGN
    LDB ,X
    LDX FPA0+2
    ADDB ,X
    BHS CAT_ROOM
    LDB #ERR_LS
    JMP ERROR
CAT_ROOM:
    JSR STRINI
    LDX RESSGN
    LDB ,X
    BSR MOVSTR                      ; the left string
    LDX V4D
    BSR FRETMP
    BSR MOVINS                      ; then the right
    LDX RESSGN
    BSR FRETMP
    JSR PUTNEW
    JMP EVLPRC_OPERATOR

;; Copies a string into the room at <FRESPC>.
;;
;; In:   B = its length, X = its descriptor
MOVSTR:
    LDX 2,X
;; Copies B bytes from X into the room at <FRESPC>, and moves <FRESPC> past them.
;;
;; In:   B = the count, X = the bytes
MOVINS:
    LDU FRESPC
    INCB
    BRA MOVINS_COUNT
MOVINS_LOOP:
    LDA ,X+
    STA ,U+
MOVINS_COUNT:
    DECB
    BNE MOVINS_LOOP
    STU FRESPC
    RTS

;; Checks that the value is a string, then frees it, as <FREFAC> does.
FRESTR:
    JSR CKSTR
;; Frees the string in FPA0, as <FRETMP> does.
FREFAC:
    LDX FPA0+2
;; Frees a string: drops its descriptor from the stack when it was the last pushed, and gives back its room when
;; it was the last made.
;;
;; In:   X = its descriptor
;; Out:  B = its length, X = its text
FRETMP:
    LDB ,X
    BSR FRETMS
    BNE FRETMP_KEEP
    LDX 2+5,X                       ; the descriptor just dropped
    LEAX -1,X
    CMPX STRTAB
    BNE FRETMP_DONE
    PSHS B
    ADDD STRTAB
    STD STRTAB
    PULS B
FRETMP_DONE:
    LEAX 1,X
    RTS
FRETMP_KEEP:
    LDX 2,X
    RTS

;; Drops a descriptor from the string descriptor stack when it is the last pushed.
;;
;; In:   X = the descriptor
;; Out:  zero = set when dropped
FRETMS:
    CMPX LASTPT
    BNE FRETMS_DONE
    STX TEMPPT
    LEAX -5,X
    STX LASTPT
    CLRA
FRETMS_DONE:
    RTS

;; Runs the LEN function: a string's length.
LEN:
    BSR LENSTR
LEN_GIVE:
    JMP GIVB
;; Frees the string in FPA0 and gives its length.
;;
;; Out:  B = the length, X = the text, zero = set when empty
LENSTR:
    BSR FRESTR
    CLR VALTYP
    TSTB
    RTS

;; Runs the CHR$ function: a one-character string.
CHR:
    JSR BYTCHK
;; Makes a one-character string of the character in <FPA0>+3, as the function's result.
CHRSTR:
    LDB #1
    JSR GETSPA
    LDA FPA0+3
    JSR STRSET
    STA ,X
CHRSTR_DONE:
    LEAS 2,S                        ; past the function call's numeric check
;; Pushes the temporary descriptor, as a function's string result.
STRDONE:
    JMP PUTNEW

;; Runs the ASC function: a string's first character code.
ASC:
    BSR FIRSTC
    BRA LEN_GIVE
;; Gives the first character of the string in FPA0.
;;
;; Out:  B = the character
;; Errors: ?FC ERROR for an empty string
FIRSTC:
    BSR LENSTR
    BEQ FCERR2
    LDB ,X
    RTS

;; Runs the LEFT$(s,n) function: the string's first n characters.
LEFT:
    BSR STRARG
LEFT_START:
    CLRA                            ; from the first character
LEFT_LIMIT:
    CMPB ,X
    BLS SUBSTR
    LDB ,X                          ; no more than the string has
    CLRA
;; Makes a string of part of another as a function's result.
;;
;; In:   A = where the part starts, B = its length, V4D = the string's descriptor
SUBSTR:
    PSHS A,B
    JSR STRSPA
    LDX V4D
    BSR FRETMP
    PULS B
    ABX
    PULS B
    JSR MOVINS
    BRA STRDONE

;; Runs the RIGHT$(s,n) function: the string's last n characters.
RIGHT:
    BSR STRARG
    SUBA ,X
    NEGA                            ; start at the length less n
    BRA LEFT_LIMIT

;; Runs the MID$(s,start,n) function: n characters from the start'th, or to the end without n.
;;
;; Errors: ?FC ERROR for a start of 0
MID:
    LDB #$FF                        ; no n: as many as there are
    STB FPA0+3
    JSR GETCCH
    CMPA #')'
    BEQ MID_START
    JSR SYNCOM
    BSR GETBYT
MID_START:
    BSR STRARG
    BEQ FCERR2
    CLRB
    DECA                            ; from 0
    CMPA ,X
    BHS SUBSTR                      ; past the end: an empty string
    TFR A,B
    SUBB ,X
    NEGB                            ; what is left
    CMPB FPA0+3
    BLS SUBSTR
    LDB FPA0+3
    BRA SUBSTR

;; Takes the arguments the function call left on the stack for LEFT$, RIGHT$ and MID$, after checking for ).
;;
;; Out:  A, B = the number, V4D, X = the string's descriptor, zero = set when the number is 0
STRARG:
    JSR SYNRPR
    LDU ,S
    LDX 5,S
    STX V4D
    LDA 4,S
    LDB 4,S
    LEAS 7,S
    TFR U,PC
FCERR2:
    JMP FCERR

;; Moves past the current character, then evaluates a number from 0 to 255, as <GETBYT> does.
NXTBYT:
    JSR GETNCH
;; Evaluates a number from 0 to 255.
;;
;; Out:  B, FPA0+3 = the number, A = the current character, as <GETCCH> leaves it
;; Errors: ?FC ERROR out of range
GETBYT:
    JSR FRMNUM
;; Converts FPA0 to a number from 0 to 255, as <GETBYT> does.
BYTCHK:
    JSR POSCHK
    TSTA
    BNE FCERR2
    JMP GETCCH

;; Runs the VAL function: the number a string starts with, or 0.
VAL:
    JSR LENSTR
    LBEQ ZEROF0                     ; empty: 0
    LDU CHARAD
    STX CHARAD                      ; read the string as if it were the program
    ABX
    LDA ,X
    PSHS A,X,U
    CLR ,X                          ; end it with a zero for now
    JSR GETCCH
    JSR FIN
    PULS A,X,U
    STA ,X
    STU CHARAD
    RTS

;; Evaluates an address, then a comma and a number from 0 to 255, as POKE takes.
;;
;; Out:  BINVAL = the address, B = the number
ADRBYT:
    BSR GETADR
    STX BINVAL
;; Checks for a comma, then evaluates a number from 0 to 255.
;;
;; Out:  B = the number
COMBYT:
    JSR SYNCOM
    BRA GETBYT

;; Evaluates an address, 0-65535.
;;
;; Out:  X = the address
;; Errors: ?FC ERROR out of range
GETADR:
    JSR FRMNUM
;; Converts FPA0 to an address, as <GETADR> does.
ADRCHK:
    LDA FP0SGN
    BMI FCERR2
    LDA FP0EXP
    CMPA #$90
    BHI FCERR2
    JSR QINT
    LDX FPA0+2
    RTS

;; Runs the PEEK function: the byte at an address.
PEEK:
    BSR ADRCHK
    LDB ,X
    JMP GIVB

;; Runs POKE address,value: stores a byte.
POKE:
    BSR ADRBYT
    LDX BINVAL
    STB ,X
    RTS
;; Runs LLIST: lists the program on the printer, as LIST does.
LLIST:
    LDB #$FE                        ; the printer
    STB DEVNUM
    JSR GETCCH
;; Runs LIST, LIST n, LIST n-, LIST -m or LIST n-m: shows the program's lines in that range, then prompts.
LIST:
    PSHS CC                         ; zero set: no range
    JSR LINGET
    JSR FINDLN
    STX LSTTXT
    PULS CC
    BEQ LIST_ALL
    JSR GETCCH
    BEQ LIST_RANGE                  ; one line
    CMPA #TK_MINUS
    BNE LIST_DONE
    JSR GETNCH
    BEQ LIST_ALL                    ; to the end
    JSR LINGET
    BEQ LIST_RANGE
LIST_DONE:
    RTS
LIST_ALL:
    LDU #$FFFF
    STU BINVAL
LIST_RANGE:
    LEAS 2,S                        ; not back to the interpreter
    LDX LSTTXT
LIST_LINE:
    JSR NEWLIN
    JSR CHKBRK
    LDD ,X
    BNE LIST_SHOW
LIST_END:
    JSR CLSONE
    CLR DEVNUM
    JMP OKPRMT
LIST_SHOW:
    STX LSTTXT
    LDD 2,X
    CMPD BINVAL
    BHI LIST_END                    ; past the range
    JSR LINPRT                       ; the line number
    JSR OUTSPC
    LDX LSTTXT
    BSR DETOK
    LDX [LSTTXT]
    LDU #LINBUF+1
LIST_TEXT:
    LDA ,U+
    BEQ LIST_LINE
    JSR OUTCH
    BRA LIST_TEXT

;; Expands a program line's tokens back into their words in the line input buffer, from <LINBUF>+1. A colon
;; before ELSE or ', which CRUNCH put there, is left out, and a token no table knows shows as !.
;;
;; In:   X = the line
;; Calls: RVEC24
DETOK:
    JSR RVEC24
    LEAX 4,X                        ; past the link and the line number
    LDY #LINBUF+1
DETOK_CHAR:
    LDA ,X+
    BEQ DETOK_DONE
    BMI DETOK_TOKEN
    CMPA #':'
    BNE DETOK_PUT
    LDB ,X
    CMPB #TK_ELSE
    BEQ DETOK_CHAR
    CMPB #TK_APOS
    BEQ DETOK_CHAR
    .byte $8C                       ; CMPX #: skips the LDA below
DETOK_BANG:
    LDA #'!'
DETOK_PUT:
    BSR DETOK_STORE
    BRA DETOK_CHAR
DETOK_TOKEN:
    LDU #COMVEC-10
    CMPA #$FF
    BNE DETOK_FIND
    LDA ,X+                         ; a function: its second byte
    LEAU 5,U                        ; and the functions' half of each table
DETOK_FIND:
    ANDA #$7F
DETOK_TABLE:
    LEAU 10,U                       ; the next ROM's table
    TST ,U
    BEQ DETOK_BANG                  ; no ROM has it
    SUBA ,U
    BPL DETOK_TABLE
    ADDA ,U                         ; its place in this table
    LDU 1,U
DETOK_SKIP:
    DECA
    BMI DETOK_COPY
DETOK_WORD:
    TST ,U+                         ; skip a word: to its last letter, with bit 7 set
    BPL DETOK_WORD
    BRA DETOK_SKIP
DETOK_COPY:
    LDA ,U
    BSR DETOK_STORE
    TST ,U+
    BPL DETOK_COPY
    BRA DETOK_CHAR
DETOK_STORE:
    CMPY #LINBUF+LBUFMX
    BHS DETOK_DONE                  ; the buffer is full
    ANDA #$7F
    STA ,Y+
    CLR ,Y
DETOK_DONE:
    RTS

;; Crunches the line at <CHARAD> into <LINBUF>: each reserved word, in Color BASIC's table or a later ROM's,
;; becomes its token, or $FF and a token for a function. ? becomes PRINT, and ' and ELSE get a colon before
;; them. A quoted string, a variable's name and what follows REM, ' or DATA stay as they are.
;;
;; Out:  D = the crunched line's length, with the two zeros after it and its line number,
;;       CHARAD = the line, less one
;; Calls: RVEC23
CRUNCH:
    JSR RVEC23
    LDX CHARAD
    LDU #LINBUF
CRUNCH_STATEMENT:
    CLR V43                         ; not in a name
    CLR V44                         ; not in DATA
CRUNCH_CHAR:
    LDA ,X+
    BEQ CRUNCH_STORE
    TST V43
    BEQ CRUNCH_TEXT
    JSR ISLETC                      ; letters and digits continue a name
    BHS CRUNCH_STORE
    CMPA #'0'
    BLO CRUNCH_NAME_END
    CMPA #'9'
    BLS CRUNCH_STORE
CRUNCH_NAME_END:
    CLR V43
CRUNCH_TEXT:
    CMPA #' '
    BEQ CRUNCH_STORE
    STA V42
    CMPA #'"'
    BEQ CRUNCH_QUOTE
    TST V44
    BEQ CRUNCH_QUESTION
CRUNCH_STORE:
    STA ,U+
    BEQ CRUNCH_END
    CMPA #':'
    BEQ CRUNCH_STATEMENT
CRUNCH_NEXT:
    BRA CRUNCH_CHAR
CRUNCH_END:
    CLR ,U+                         ; two zeros: no next line yet
    CLR ,U+
    TFR U,D
    SUBD #LINHDR
    LDX #LINBUF-1
    STX CHARAD
    RTS
CRUNCH_QUESTION:
    CMPA #'?'
    BNE CRUNCH_APOSTROPHE
    LDA #TK_PRINT
    BRA CRUNCH_STORE
CRUNCH_APOSTROPHE:
    CMPA #$27                       ; '
    BNE CRUNCH_DIGIT
    LDD #(':'*256)+TK_APOS
    STD ,U++
CRUNCH_REST:
    CLR V42                         ; to the line's end
CRUNCH_RAW:
    LDA ,X+
    BEQ CRUNCH_STORE
    CMPA V42
    BEQ CRUNCH_STORE
CRUNCH_QUOTE:
    STA ,U+
    BRA CRUNCH_RAW
CRUNCH_DIGIT:
    CMPA #'0'
    BLO CRUNCH_WORD
    CMPA #';'+1
    BLO CRUNCH_STORE                ; digits, colon and semicolon
CRUNCH_WORD:
    LEAX -1,X
    PSHS X,U
    CLR V41                         ; commands first, then $FF: functions
    LDU #COMVEC-10
CRUNCH_PASS:
    CLR V42                         ; the token, less $80
CRUNCH_TABLE:
    LEAU 10,U                       ; the next ROM's table
    LDA ,U
    BEQ CRUNCH_FUNCTIONS
    LDY 1,U
CRUNCH_TRY:
    LDX ,S
CRUNCH_MATCH:
    LDB ,Y+
    SUBB ,X+
    BEQ CRUNCH_MATCH
    CMPB #$80
    BNE CRUNCH_MISS                 ; not unless only the last letter's bit 7 differs
    LEAS 2,S                        ; a reserved word: drop the text's start
    PULS U
    ORB V42                         ; the token
    LDA V41
    BNE CRUNCH_TWO                  ; a function: $FF, then the token
    CMPB #TK_ELSE
    BNE CRUNCH_TOKEN
    LDA #':'
CRUNCH_TWO:
    STD ,U++
    BRA CRUNCH_NEXT
CRUNCH_TOKEN:
    STB ,U+
    CMPB #TK_DATA
    BNE CRUNCH_REM
    INC V44
CRUNCH_REM:
    CMPB #TK_REM
    BEQ CRUNCH_REST
CRUNCH_LOOP:
    BRA CRUNCH_NEXT
CRUNCH_FUNCTIONS:
    LDU #COMVEC+5-10
    COM V41
    BNE CRUNCH_PASS
    PULS X,U                        ; no reserved word: the character as it is
    LDA ,X+
    STA ,U+
    JSR ISLETC
    BLO CRUNCH_LOOP
    COM V43                         ; a letter starts a name
    BRA CRUNCH_LOOP
CRUNCH_MISS:
    INC V42
    DECA
    BEQ CRUNCH_TABLE                ; this ROM's words are done
    LEAY -1,Y
CRUNCH_SKIP:
    LDB ,Y+                         ; to the next word
    BPL CRUNCH_SKIP
    BRA CRUNCH_TRY
;; Runs PRINT: shows each item listed, numbers and strings; a comma moves to the next print zone, a semicolon
;; joins items, and TAB( moves to a column. A list that does not end with either ends the line. PRINT @ starts at
;; a screen position, and PRINT # writes to a device.
PRINT:
    BEQ PRNTCR
    BSR PRINT_AT
    CLR DEVNUM
    RTS
PRINT_AT:
    CMPA #'@'
    BNE PRINT_DEV
    JSR SETCUR
    BRA PRINT_COMMA
PRINT_DEV:
    CMPA #'#'
    BNE PRINTL
    JSR GETDEV
    JSR CHKOUT
PRINT_COMMA:
    JSR GETCCH
    BEQ PRNTCR
    JSR SYNCOM
;; Prints the list of items that follows.
;;
;; Calls: RVEC9
PRINTL:
    JSR RVEC9
PRINTL_END:
    BEQ NEWLIN_DONE
PRINTL_ITEM:
    CMPA #TK_TAB
    BEQ PRINTL_TAB
    CMPA #','
    BEQ PRINTL_FIELD
    CMPA #';'
    BEQ PRINTL_SKIP
    JSR FRMEVL
    LDA VALTYP
    PSHS A
    BNE PRINTL_STRING
    JSR FOUT                      ; a number: its text, with a space or - before it
    JSR STRLX
PRINTL_STRING:
    BSR STRPRT
    PULS B
    JSR SETPRM
    TST PRTDEV
    BEQ PRINTL_SPACE
    BSR PRNTCR                      ; to the cassette: each item on its own line
    JSR GETCCH
    BRA PRINTL_END
PRINTL_SPACE:
    TSTB
    BNE PRINTL_NEXT                 ; a string
    JSR GETCCH
    CMPA #','
    BEQ PRINTL_FIELD
    BSR OUTSPC                      ; a space after a number
PRINTL_NEXT:
    JSR GETCCH
    BNE PRINTL_ITEM
;; Ends the line: prints a carriage return.
PRNTCR:
    LDA #$0D
    BRA OUTCH

;; Starts a new line unless the device is at the start of one.
NEWLIN:
    JSR SETPRM
    BEQ PRNTCR                      ; the cassette: always
    LDA DEVPOS
    BNE PRNTCR
NEWLIN_DONE:
    RTS
PRINTL_FIELD:
    JSR SETPRM
    BEQ PRINTL_ANY
    LDB DEVPOS
    CMPB DEVLCF
    BLO PRINTL_ZONE
    BSR PRNTCR                      ; past the last zone: a new line
    BRA PRINTL_SKIP
PRINTL_ANY:
    LDB DEVPOS
PRINTL_ZONE:
    SUBB DEVCFW                     ; the spaces to the next zone
    BHS PRINTL_ZONE
    NEGB
    BRA PRINTL_PAD
PRINTL_TAB:
    JSR NXTBYT
    CMPA #')'
    LBNE SNERR
    JSR SETPRM
    SUBB DEVPOS
    BLS PRINTL_SKIP                 ; at or past the column
PRINTL_PAD:
    TST PRTDEV
    BNE PRINTL_SKIP
PRINTL_SPACES:
    BSR OUTSPC
    DECB
    BNE PRINTL_SPACES
PRINTL_SKIP:
    JSR GETNCH
    JMP PRINTL_END

;; Prints a message: the text from X+1 to a zero or a quote.
;;
;; In:   X = the text, less one
STROUT1:
    JSR STRLT2
;; Prints the string in FPA0, freeing it.
STRPRT:
    JSR FREFAC
STRPRT_COUNT:
    INCB
STRPRT_CHAR:
    DECB
    BEQ NEWLIN_DONE
    LDA ,X+
    BSR OUTCH
    BRA STRPRT_CHAR

;; Prints a space.
OUTSPC:
    LDA #' '
    .byte $8C                       ; CMPX #: skips the LDA below
;; Prints a question mark.
OUTQST:
    LDA #'?'
;; Prints a character, as <PUTCHR> does.
;;
;; In:   A = the character
OUTCH:
    JMP PUTCHR
;; Adds 0.5 to FPA0, as <FADDX> does.
ADDHLF:
    LDX #FHALF
    BRA FADDX

;; Subtracts FPA0 from the packed number at X.
;;
;; In:   X = the number
;; Out:  FPA0 = the difference
FSUBX:
    JSR CONUPK
;; The - operator: subtracts FPA0 from FPA1.
;;
;; Out:  FPA0 = the difference
FPSUB:
    COM FP0SGN
    COM RESSGN
    BRA FPADD

;; Adds the packed number at X to FPA0.
;;
;; In:   X = the number
;; Out:  FPA0 = the sum
FADDX:
    JSR CONUPK
;; The + operator: adds FPA1 to FPA0. The smaller is shifted right to line up with the larger, a negative one is
;; added in two's complement, and the sum is normalized and rounded.
;;
;; In:   B = FPA0's exponent
;; Out:  FPA0 = the sum
;; Errors: ?OV ERROR when it is too big
FPADD:
    TSTB
    LBEQ MOVFA                      ; FPA0 is zero: the sum is FPA1
    LDX #FP1EXP                     ; shift FPA1
FPADD_ALIGN:
    TFR A,B
    TSTB
    BEQ FPADD_DONE                  ; FPA1 is zero
    SUBB FP0EXP
    BEQ FPADD_BYTES
.if VERSION < 12
    BMI FPADD_SHIFT                 ; FPA0 is larger
.else
    BLO FPADD_SHIFT                 ; FPA0 is larger
.endif
    STA FP0EXP                      ; FPA1 is larger: the sum has its exponent and sign
    LDA FP1SGN
    STA FP0SGN
    LDX #FP0EXP                     ; shift FPA0
    NEGB
FPADD_SHIFT:
    CMPB #$F8
    BLE FPADD_BYTES                 ; a byte or more
    CLRA
    LSR 1,X
    JSR SHIFTR_LOW
FPADD_SUM:
    LDB RESSGN
    BPL FPADD_ADD
    COM 1,X                         ; the signs differ: add its complement
    COM 2,X
    COM 3,X
    COM 4,X
    COMA
    ADCA #0
FPADD_ADD:
    STA FPSBYT
    LDA FPA0+3
    ADCA FPA1+3
    STA FPA0+3
    LDA FPA0+2
    ADCA FPA1+2
    STA FPA0+2
    LDA FPA0+1
    ADCA FPA1+1
    STA FPA0+1
    LDA FPA0
    ADCA FPA1
    STA FPA0
    TSTB
    BPL FPADD_CARRY
FPADD_SIGN:
    BLO NORMAL                      ; no borrow: positive
    BSR NEGFAC
;; Normalizes FPA0: shifts its mantissa left until bit 7 is set, taking the shifts from its exponent, then rounds
;; on the fifth byte.
NORMAL:
    CLRB
NORMAL_BYTE:
    LDA FPA0
    BNE NORMAL_TEST
    LDA FPA0+1                      ; a whole byte at a time while the top is zero
    STA FPA0
    LDA FPA0+2
    STA FPA0+1
    LDA FPA0+3
    STA FPA0+2
    LDA FPSBYT
    STA FPA0+3
    CLR FPSBYT
    ADDB #8
    CMPB #40
    BLT NORMAL_BYTE
;; Sets FPA0 to zero.
ZEROF0:
    CLRA
ZEROF0_EXP:
    STA FP0EXP
    STA FP0SGN
FPADD_DONE:
    RTS
FPADD_BYTES:
    BSR SHIFTR
    CLRB
    BRA FPADD_SUM
NORMAL_BIT:
    INCB
    ASL FPSBYT
    ROL FPA0+3
    ROL FPA0+2
    ROL FPA0+1
    ROL FPA0
NORMAL_TEST:
    BPL NORMAL_BIT
    LDA FP0EXP
    PSHS B
    SUBA ,S+
    STA FP0EXP
    BLS ZEROF0                      ; too small: zero
    .byte $8C                       ; CMPX #: skips the BCS below
FPADD_CARRY:
    BCS ROUND_UP                    ; the sum carried: shift it right
    ASL FPSBYT
    LDA #0
    STA FPSBYT
    BRA ROUND
ROUND_UP:
    INC FP0EXP
    BEQ OVERR
    ROR FPA0
    ROR FPA0+1
    ROR FPA0+2
    ROR FPA0+3
;; Rounds FPA0 up when the carry is set.
ROUND:
    BCC ROUND_DONE
    BSR INCMAN
    BEQ ROUND_UP                    ; the mantissa overflowed
ROUND_DONE:
    RTS

;; Negates FPA0: its sign, and its mantissa in two's complement.
NEGFAC:
    COM FP0SGN
;; Complements FPA0's mantissa, then adds one.
COMMAN:
    COM FPA0
    COM FPA0+1
    COM FPA0+2
    COM FPA0+3
;; Adds one to FPA0's mantissa.
;;
;; Out:  zero = set when it overflowed to zero
INCMAN:
    LDX FPA0+2
    LEAX 1,X
    STX FPA0+2
    BNE INCMAN_DONE
    LDX FPA0
    LEAX 1,X
    STX FPA0
INCMAN_DONE:
    RTS

;; Raises ?OV ERROR: a number too big.
OVERR:
    LDB #ERR_OV
    JMP ERROR

;; Shifts the multiply's product, FPA2, right a whole byte, as <SHIFTR> does.
SHFTF2:
    LDX #FPA2-1
SHIFTR_BYTE:
    LDA 4,X                         ; a whole byte: the low byte to the fifth
    STA FPSBYT
    LDA 3,X
    STA 4,X
    LDA 2,X
    STA 3,X
    LDA 1,X
    STA 2,X
    LDA FPCARY
    STA 1,X
;; Shifts the mantissa after X right by -B bits: whole bytes, then bits.
;;
;; In:   B = minus the bits, X = the number's exponent, FPCARY = what fills from the left
;; Out:  A = the bits shifted out
SHIFTR:
    ADDB #8
    BLE SHIFTR_BYTE
    LDA FPSBYT
    SUBB #8
    BEQ SHIFTR_DONE
SHIFTR_BIT:
    ASR 1,X
SHIFTR_LOW:
    ROR 2,X
    ROR 3,X
    ROR 4,X
    RORA
    INCB
    BNE SHIFTR_BIT
SHIFTR_DONE:
    RTS

;; 1 in packed floating point.
FPONE:
    .byte $81, $00, $00, $00, $00

;; Multiplies FPA0 by the packed number at X.
;;
;; In:   X = the number
;; Out:  FPA0 = the product
FMULX:
    BSR CONUPK
;; The * operator: multiplies FPA0 by FPA1, a byte of FPA0 at a time, low byte first, into FPA2. The low bytes of
;; the product are kept in <VAB>-<VAE>, which RND uses.
;;
;; In:   B = FPA0's exponent
;; Out:  FPA0 = the product
;; Errors: ?OV ERROR when it is too big
FPMUL:
    BEQ MULBYT_DONE                 ; FPA0 is zero
    BSR MULDIV
;; Multiplies FPA0's mantissa by FPA1's, then normalizes.
FMULT:
    LDA #0
    STA FPA2
    STA FPA2+1
    STA FPA2+2
    STA FPA2+3
    LDB FPA0+3
    BSR MULBYT
    LDB FPSBYT
    STB VAE
    LDB FPA0+2
    BSR MULBYT
    LDB FPSBYT
    STB VAD
    LDB FPA0+1
    BSR MULBYT
    LDB FPSBYT
    STB VAC
    LDB FPA0
    BSR MULBYT_NONZERO
    LDB FPSBYT
    STB VAB
    JSR MOVF2
    JMP NORMAL

;; Adds FPA1 times one byte of FPA0 to FPA2, shifting FPA2 right a bit for each of the byte's bits.
;;
;; In:   B = the byte
MULBYT:
    BEQ SHFTF2                      ; zero: just shift a byte
MULBYT_NONZERO:
    COMA                            ; the carry set: a bit that ends the loop
MULBYT_BIT:
    LDA FPA2
    RORB
    BEQ MULBYT_DONE
    BCC MULBYT_SHIFT
    LDA FPA2+3
    ADDA FPA1+3
    STA FPA2+3
    LDA FPA2+2
    ADCA FPA1+2
    STA FPA2+2
    LDA FPA2+1
    ADCA FPA1+1
    STA FPA2+1
    LDA FPA2
    ADCA FPA1
MULBYT_SHIFT:
    RORA
    STA FPA2
    ROR FPA2+1
    ROR FPA2+2
    ROR FPA2+3
    ROR FPSBYT
    CLRA
    BRA MULBYT_BIT
MULBYT_DONE:
    RTS

;; Unpacks the number at X into FPA1, and sets the result's sign.
;;
;; In:   X = the packed number
;; Out:  FPA1 = it, RESSGN = the product of the signs, B = FPA0's exponent
CONUPK:
    LDD 1,X
    STA FP1SGN
    ORA #$80                        ; the mantissa's top bit, which packing drops
    STD FPA1
    LDB FP1SGN
    EORB FP0SGN
    STB RESSGN
    LDD 3,X
    STD FPA1+2
    LDA ,X
    STA FP1EXP
    LDB FP0EXP
    RTS
;; Works out the exponent of a product or quotient: adds FPA1's exponent to FPA0's and sets the result's sign.
;; A result too small is zero, and the caller's work is skipped.
;;
;; In:   A = FPA1's exponent
;; Errors: ?OV ERROR when too big
MULDIV:
    TSTA
    BEQ MULDIV_ZERO
    ADDA FP0EXP
    RORA                            ; the carry and bit 7: out of range when they differ
    ROLA
    BVC MULDIV_ZERO
    ADDA #$80
    STA FP0EXP
    BEQ MULDIV_RANGE
    LDA RESSGN
    STA FP0SGN
    RTS
;; Handles a result out of range: zero when FPA0 is negative, ?OV ERROR when it is positive.
MULDIV_SIGN:
    LDA FP0SGN
    COMA
    BRA MULDIV_RANGE
MULDIV_ZERO:
    LEAS 2,S                        ; not back to the caller
MULDIV_RANGE:
    LBPL ZEROF0
OVERR2:
    JMP OVERR

;; Multiplies FPA0 by 10: times 4, plus itself, times 2.
;;
;; Errors: ?OV ERROR when too big
MUL10:
    JSR MOVAF
    BEQ MUL10_DONE
    ADDA #2
    BLO OVERR2
    CLR RESSGN
    JSR FPADD_ALIGN
    INC FP0EXP
    BEQ OVERR2
MUL10_DONE:
    RTS

;; 10 in packed floating point.
FTEN:
    .byte $84, $20, $00, $00, $00

;; Divides FPA0 by 10.
DIV10:
    JSR MOVAF
    LDX #FTEN
    CLRB
;; Divides the packed number at X by FPA1, as <FPDIV> does after unpacking it into FPA0.
;;
;; In:   B = the result's sign, X = the dividend
DIVIDE:
    STB RESSGN
    JSR MOVFM
    .byte $8C                       ; CMPX #: skips the BSR below
;; Divides the packed number at X by FPA0.
;;
;; In:   X = the dividend
FDIVX:
    BSR CONUPK
;; The / operator: divides FPA1 by FPA0, comparing and subtracting a bit at a time into FPA2.
;;
;; In:   B = FPA0's exponent
;; Out:  FPA0 = the quotient
;; Errors: ?/0 ERROR when FPA0 is zero, ?OV ERROR when the quotient is too big
FPDIV:
    BEQ DV0ERR
    NEG FP0EXP
    BSR MULDIV
    INC FP0EXP
    BEQ OVERR2
    LDX #FPA2
    LDB #4                          ; four bytes of quotient
    STB TMPLOC
    LDB #1                          ; a bit that marks a full byte when it shifts out
FPDIV_COMPARE:
    LDA FPA0
    CMPA FPA1
    BNE FPDIV_BIT
    LDA FPA0+1
    CMPA FPA1+1
    BNE FPDIV_BIT
    LDA FPA0+2
    CMPA FPA1+2
    BNE FPDIV_BIT
    LDA FPA0+3
    CMPA FPA1+3
    BNE FPDIV_BIT
    COMA                            ; equal: the carry set, as for less
FPDIV_BIT:
    TFR CC,A                        ; the carry: FPA0 fits into FPA1
    ROLB
    BHS FPDIV_TEST
    STB ,X+                         ; a byte of quotient
    DEC TMPLOC
    BMI FPDIV_DONE
    BEQ FPDIV_ROUND
    LDB #1
FPDIV_TEST:
    TFR A,CC
    BLO FPDIV_SUBTRACT
FPDIV_SHIFT:
    ASL FPA1+3
    ROL FPA1+2
    ROL FPA1+1
    ROL FPA1
    BLO FPDIV_BIT                   ; a bit out of the top: it fits
    BMI FPDIV_COMPARE
    BRA FPDIV_BIT
FPDIV_SUBTRACT:
    LDA FPA1+3
    SUBA FPA0+3
    STA FPA1+3
    LDA FPA1+2
    SBCA FPA0+2
    STA FPA1+2
    LDA FPA1+1
    SBCA FPA0+1
    STA FPA1+1
    LDA FPA1
    SBCA FPA0
    STA FPA1
    BRA FPDIV_SHIFT
FPDIV_ROUND:
    LDB #$40                        ; two more bits, for rounding
    BRA FPDIV_TEST
FPDIV_DONE:
    RORB
    RORB
    RORB
    STB FPSBYT
    BSR MOVF2
    JMP NORMAL
;; Raises ?/0 ERROR: division by zero.
DV0ERR:
    LDB #ERR_DV0
    JMP ERROR

;; Moves FPA2's mantissa into FPA0's.
MOVF2:
    LDX FPA2
    STX FPA0
    LDX FPA2+2
    STX FPA0+2
    RTS

;; Unpacks the number at X into FPA0.
;;
;; In:   X = the packed number
;; Keeps: A
MOVFM:
    PSHS A
    LDD 1,X
    STA FP0SGN
    ORA #$80                        ; the mantissa's top bit
    STD FPA0
    CLR FPSBYT
    LDB ,X
    LDX 3,X
    STX FPA0+2
    STB FP0EXP
    PULS A,PC

;; Packs FPA0 into <V45>.
MOVV45:
    LDX #V45
    BRA MOVMF
;; Packs FPA0 into <V40>.
MOVV40:
    LDX #V40
    .byte $8C                       ; CMPX #: skips the LDX below
;; Packs FPA0 into the variable at <VARDES>.
MOVVAR:
    LDX VARDES
;; Packs FPA0 into five bytes at X: the exponent, then the mantissa with the sign in its top bit.
;;
;; In:   X = where
MOVMF:
    LDA FP0EXP
    STA ,X
    LDA FP0SGN
    ORA #$7F
    ANDA FPA0
    STA 1,X
    LDA FPA0+1
    STA 2,X
    LDU FPA0+2
    STU 3,X
    RTS

;; Copies FPA1 into FPA0.
;;
;; Out:  A = the sign
MOVFA:
    LDA FP1SGN
MOVFA_SIGN:
    STA FP0SGN
    LDX FP1EXP                      ; the exponent and the mantissa's top byte
    STX FP0EXP
    CLR FPSBYT
    LDA FPA1+1
    STA FPA0+1
    LDA FP0SGN
    LDX FPA1+2
    STX FPA0+2
    RTS

;; Copies FPA0 into FPA1.
;;
;; Out:  A = the exponent, zero = set when FPA0 is zero
MOVAF:
    LDD FP0EXP
    STD FP1EXP
    LDX FPA0+1
    STX FPA1+1
    LDX FPA0+3
    STX FPA1+3
    TSTA
    RTS

;; Gives FPA0's sign.
;;
;; Out:  B = 0 when zero, 1 when positive, -1 when negative
SIGN:
    LDB FP0EXP
    BEQ SIGN_DONE
SIGN_FPA0:
    LDB FP0SGN
SIGN_B:
    ROLB
    LDB #$FF
    BLO SIGN_DONE
    NEGB
SIGN_DONE:
    RTS

;; Runs the SGN function: -1, 0 or 1 as the number is negative, zero or positive.
SGN:
    BSR SIGN
;; Makes B, a signed number, the value in FPA0.
;;
;; In:   B = the number
BTOFP:
    STB FPA0
    CLR FPA0+1
    LDB #$88                        ; the binary point after 8 bits
;; Makes the signed number in <FPA0>, its binary point after B less $80 bits, the value in FPA0.
;;
;; In:   B = the exponent
FLTD:
    LDA FPA0
    SUBA #$80                       ; the carry clear when negative
FLTD_EXP:
    STB FP0EXP
    LDD ZERO
    STD FPA0+2
    STA FPSBYT
    STA FP0SGN
    JMP FPADD_SIGN

;; Runs the ABS function: the number without its sign.
ABS:
    CLR FP0SGN
    RTS
;; Compares FPA0 with the packed number at X.
;;
;; In:   X = the number
;; Out:  B = 0 when equal, 1 when FPA0 is larger, -1 when smaller, zero = set when equal
FCOMP:
    LDB ,X
    BEQ SIGN                        ; X is zero: FPA0's sign decides
    LDB 1,X
    EORB FP0SGN
    BMI SIGN_FPA0                   ; the signs differ
FCOMP_SAME:
    LDB FP0EXP
    CMPB ,X
    BNE FCOMP_DIFFER
    LDB 1,X
    ORB #$7F
    ANDB FPA0
    CMPB 1,X
    BNE FCOMP_DIFFER
    LDB FPA0+1
    CMPB 2,X
    BNE FCOMP_DIFFER
    LDB FPA0+2
    CMPB 3,X
    BNE FCOMP_DIFFER
    LDB FPA0+3
    SUBB 4,X
    BNE FCOMP_DIFFER
    RTS
FCOMP_DIFFER:
    RORB                            ; the borrow: FPA0 the smaller in size
    EORB FP0SGN                     ;   and the larger when negative
    BRA SIGN_B

;; Truncates FPA0 to a 32-bit integer in its mantissa, two's complement when negative.
;;
;; Out:  FPA0..FPA0+3 = the integer
QINT:
    LDB FP0EXP
    BEQ QINT_ZERO
    SUBB #$A0                       ; minus the bits to shift
    LDA FP0SGN
    BPL QINT_SHIFT
    COM FPCARY                      ; negative: fill with ones
    JSR COMMAN
QINT_SHIFT:
    LDX #FP0EXP
    CMPB #$F8
    BGT QINT_BITS
    JSR SHIFTR
    CLR FPCARY
    RTS
QINT_BITS:
    CLR FPCARY
    LDA FP0SGN
    ROLA
    ROR FPA0
    JMP SHIFTR_LOW

;; Runs the INT function: the largest whole number not greater than the number.
INT:
    LDB FP0EXP
    CMPB #$A0
    BHS INT_DONE                    ; too big to have a fraction
    BSR QINT
    STB FPSBYT
    LDA FP0SGN
    STB FP0SGN
    SUBA #$80                       ; the carry clear when negative
    LDA #$A0
    STA FP0EXP
    LDA FPA0+3
    STA CHARAC
    JMP FPADD_SIGN
QINT_ZERO:
    STB FPA0
    STB FPA0+1
    STB FPA0+2
    STB FPA0+3
INT_DONE:
    RTS

;; Reads a number from the program's text at <CHARAD>: digits with a point and an exponent, E then a sign and
;; digits, signed or not.
;;
;; In:   A = the first character, carry = set when it is a digit
;; Out:  FPA0 = the number
;; Calls: RVEC19
FIN:
    LDX ZERO
    STX FP0SGN                      ; and COEFCT: the number's sign
    STX FP0EXP
    STX FPA0+1
    STX FPA0+2
    STX V47                         ; the exponent and its sign
    STX V45                         ; the digits after the point, and the point seen
    BLO FIN_DIGIT
    JSR RVEC19
    CMPA #'-'
    BNE FIN_PLUS
    COM COEFCT
    BRA FIN_NEXT
FIN_PLUS:
    CMPA #'+'
    BNE FIN_CHAR
FIN_NEXT:
    JSR GETNCH
    BLO FIN_DIGIT
FIN_CHAR:
    CMPA #'.'
    BEQ FIN_POINT
    CMPA #'E'
    BNE FIN_SCALE
    JSR GETNCH
    BLO FIN_EXP_DIGIT
    CMPA #TK_MINUS
    BEQ FIN_EXP_MINUS
    CMPA #'-'
    BEQ FIN_EXP_MINUS
    CMPA #TK_PLUS
    BEQ FIN_EXP_NEXT
    CMPA #'+'
    BEQ FIN_EXP_NEXT
    BRA FIN_EXP_END
FIN_EXP_MINUS:
    COM V48
FIN_EXP_NEXT:
    JSR GETNCH
    BLO FIN_EXP_DIGIT
FIN_EXP_END:
    TST V48
    BEQ FIN_SCALE
    NEG V47
    BRA FIN_SCALE
FIN_POINT:
    COM V46
    BNE FIN_NEXT                    ; the first point; a second ends the number
FIN_SCALE:
    LDA V47
    SUBA V45                        ; the exponent less the digits after the point
    STA V47
    BEQ FIN_SIGN
    BPL FIN_MULTIPLY
FIN_DIVIDE:
    JSR DIV10
    INC V47
    BNE FIN_DIVIDE
    BRA FIN_SIGN
FIN_MULTIPLY:
    JSR MUL10
    DEC V47
    BNE FIN_MULTIPLY
FIN_SIGN:
    LDA COEFCT
    BPL INT_DONE
    JMP NEGATE
FIN_DIGIT:
    LDB V45
    SUBB V46                        ; one more after the point, once it is seen
    STB V45
    PSHS A
    JSR MUL10
    PULS B
    SUBB #'0'
    BSR FADDB
    BRA FIN_NEXT

;; Adds B, 0-127, to FPA0.
;;
;; In:   B = the number
FADDB:
    JSR MOVV40
    JSR BTOFP
    LDX #V40
    JMP FADDX
FIN_EXP_DIGIT:
    LDB V47                         ; the exponent times 10
    ASLB
    ASLB
    ADDB V47
    ASLB
    SUBA #'0'
    PSHS B
    ADDA ,S+
    STA V47
    BRA FIN_EXP_NEXT

;; 99999999.9 in packed floating point.
FMAX9:
    .byte $9B, $3E, $BC, $1F, $FD
;; 999999999 in packed floating point.
FMAX10:
    .byte $9E, $6E, $6B, $27, $FD
;; 1E9 in packed floating point.
FBILN:
    .byte $9E, $6E, $6B, $28, $00
;; Prints " IN " and the line being run, after an error's or BREAK's message.
INPRT:
    LDX #MSGIN-1
    BSR LINPRT_OUT
    LDD CURLIN
;; Prints a number from 0 to 65535, such as a line number.
;;
;; In:   D = the number
LINPRT:
    STD FPA0
    LDB #$90                        ; the binary point after 16 bits
    COMA                            ; the carry set: positive
    JSR FLTD_EXP
    BSR FOUT
LINPRT_OUT:
    JMP STROUT1

;; Turns FPA0 into the text PRINT shows, at <STRBUF>+3, as <FOUTU> does.
FOUT:
    LDU #STRBUF+3
;; Turns FPA0 into text: a space or a minus sign, then up to nine digits with a point where it falls, or a digit,
;; the point, the rest and an exponent E+nn or E-nn when the number is very large or small. Trailing zeros after
;; the point are left off.
;;
;; In:   U = where the text goes
;; Out:  X = <STRBUF>+3, the text, ended by a zero
FOUTU:
    LDA #' '
    LDB FP0SGN
    BPL FOUT_SIGN
    LDA #'-'
FOUT_SIGN:
    STA ,U+
    STU COEFPT
    STA FP0SGN                      ; positive from here on
    LDA #'0'
    LDB FP0EXP
    LBEQ FOUT_ZERO
    CLRA                            ; the power of ten, so far
    CMPB #$80
    BHI FOUT_SCALE
    LDX #FBILN                      ; below 1: times a billion first
    JSR FMULX
    LDA #-9 & $FF
FOUT_SCALE:
    STA V45
FOUT_LARGE:
    LDX #FMAX10
    JSR FCOMP_SAME
    BGT FOUT_DIVIDE                 ; above 999999999: divide by 10
FOUT_SMALL:
    LDX #FMAX9
    JSR FCOMP_SAME
    BGT FOUT_DIGITS                 ; nine digits before the point
    JSR MUL10
    DEC V45
    BRA FOUT_SMALL
FOUT_DIVIDE:
    JSR DIV10
    INC V45
    BRA FOUT_LARGE
FOUT_DIGITS:
    JSR ADDHLF
    JSR QINT                        ; nine digits, rounded, as an integer
    LDB #1                          ; digits before the point
    LDA V45
    ADDA #10
    BMI FOUT_FORMAT                 ; too small: an exponent
    CMPA #11
    BHS FOUT_FORMAT                 ; too large: an exponent
    DECA                            ; the point's place: no exponent
    TFR A,B
    LDA #2
FOUT_FORMAT:
    DECA
    DECA
    STA V47                         ; the exponent, or zero
    STB V45
    BGT FOUT_TABLE
    LDU COEFPT                      ; the point comes first
    LDA #'.'
    STA ,U+
    TSTB
    BEQ FOUT_TABLE
    LDA #'0'
    STA ,U+
FOUT_TABLE:
    LDX #FPWRTB
    LDB #$80                        ; bit 7: subtracting
FOUT_DIGIT:
    LDA FPA0+3                      ; add or subtract the power until the sign changes
    ADDA 3,X
    STA FPA0+3
    LDA FPA0+2
    ADCA 2,X
    STA FPA0+2
    LDA FPA0+1
    ADCA 1,X
    STA FPA0+1
    LDA FPA0
    ADCA ,X
    STA FPA0
    INCB
    RORB
    ROLB
    BVC FOUT_DIGIT
    BHS FOUT_STORE
    SUBB #11                        ; counting down: the digit is 10 less the count
    NEGB
FOUT_STORE:
    ADDB #'0'-1
    LEAX 4,X
    TFR B,A
    ANDA #$7F
    STA ,U+
    DEC V45
    BNE FOUT_NEXT
    LDA #'.'
    STA ,U+
FOUT_NEXT:
    COMB                            ; the other direction for the next power
    ANDB #$80
    CMPX #FPWRTB+36
    BNE FOUT_DIGIT
FOUT_TRIM:
    LDA ,-U                         ; drop trailing zeros
    CMPA #'0'
    BEQ FOUT_TRIM
    CMPA #'.'
    BNE FOUT_EXPONENT
    LEAU -1,U                       ; and a trailing point
FOUT_EXPONENT:
    LDA #'+'
    LDB V47
    BEQ FOUT_END
    BPL FOUT_E
    LDA #'-'
    NEGB
FOUT_E:
    STA 2,U
    LDA #'E'
    STA 1,U
    LDA #'0'-1
FOUT_TENS:
    INCA
    SUBB #10
    BHS FOUT_TENS
    ADDB #'9'+1
    STD 3,U                         ; its two digits
    CLR 5,U
    BRA FOUT_DONE
FOUT_ZERO:
    STA ,U
FOUT_END:
    CLR 1,U
FOUT_DONE:
    LDX #STRBUF+3
    RTS

;; 0.5 in packed floating point.
FHALF:
    .byte $80, $00, $00, $00, $00

;; The powers of ten FOUT takes the digits out with, as 32-bit integers, their signs alternating: -10^8, 10^7,
;; -10^6, 10^5, -10^4, 10^3, -10^2, 10 and -1.
FPWRTB:
    .byte $FA, $0A, $1F, $00
    .byte $00, $98, $96, $80
    .byte $FF, $F0, $BD, $C0
    .byte $00, $01, $86, $A0
    .byte $FF, $FF, $D8, $F0
    .byte $00, $00, $03, $E8
    .byte $FF, $FF, $FF, $9C
    .byte $00, $00, $00, $0A
    .byte $FF, $FF, $FF, $FF
;; Negates FPA0, unless it is zero.
NEGATE:
    LDA FP0EXP
    BEQ NEGATE_DONE
    COM FP0SGN
NEGATE_DONE:
    RTS

;; Evaluates an odd polynomial at FPA0: x times a polynomial in x squared, with the coefficients at X.
;;
;; In:   X = the coefficients, as <POLY> takes them
ODDPOL:
    STX COEFPT
    JSR MOVV40                      ; keep x
    BSR MULX                        ; x squared
    BSR POLY
    LDX #V40                        ; times x
;; Multiplies FPA0 by the packed number at X, as <FMULX> does.
MULX:
    JMP FMULX

;; Evaluates a polynomial at FPA0, with the coefficients at X, as <POLY> does.
POLYX:
    STX COEFPT
;; Evaluates a polynomial at FPA0 by Horner's rule: the coefficients at <COEFPT> are its degree, then the
;; coefficients from the highest power down, packed.
;;
;; Out:  FPA0 = the value
POLY:
    JSR MOVV45                      ; keep x
    LDX COEFPT
    LDB ,X+
    STB COEFCT
    STX COEFPT
POLY_TERM:
    BSR MULX                        ; times x, or the first coefficient
    LDX COEFPT
    LEAX 5,X
    STX COEFPT
    JSR FADDX                       ; plus the next coefficient
    LDX #V45
    DEC COEFCT
    BNE POLY_TERM
    RTS

;; Runs the RND function: RND(n) a whole number from 1 to n; RND(0) a fraction from 0 to 1; and RND(-n) a
;; fraction that starts the sequence again from -n.
;;
;; Each number comes from the last: the seed times a constant, plus a constant, its low 32 bits kept.
RND:
    JSR SIGN
    BMI RNDNEW                      ; the number itself as the seed
    BEQ RND01
    BSR RND_INT
    JSR MOVV40                      ; n
    BSR RND01
    LDX #V40
    BSR MULX
    LDX #FPONE
    JSR FADDX                       ; times n, plus 1
RND_INT:
    JMP INT
;; Makes the next random fraction, from 0 to 1, from the seed in <RVSEED>.
RND01:
    LDX RVSEED+1
    STX FPA0
    LDX RVSEED+3
    STX FPA0+2
;; Makes a random fraction from the mantissa in FPA0, and keeps it as the seed.
RNDNEW:
    LDX RNDMUL
    STX FPA1
    LDX RNDMUL+2
    STX FPA1+2
    JSR FMULT                       ; the product's low bytes are in VAB-VAE
    LDD VAD
    ADDD #$658B
    STD RVSEED+3
    STD FPA0+2
    LDD VAB
    ADCB #$B0
    ADCA #$05                       ; plus $05B0658B
    STD RVSEED+1
    STD FPA0
    CLR FP0SGN
    LDA #$80                        ; a fraction
    STA FP0EXP
    LDA FPA2+2
    STA FPSBYT
    JMP NORMAL

;; The random numbers' multiplier.
RNDMUL:
    .dbyt $40E6, $4DAB

;; Runs the SIN function: the sine of an angle in radians. The angle is reduced to a fraction of a turn, folded
;; into a quarter turn, then a series of odd powers gives the sine.
SIN:
    JSR MOVAF
    LDX #FTWOPI
    LDB FP1SGN
    JSR DIVIDE                      ; turns
    JSR MOVAF
    BSR RND_INT
    CLR RESSGN
    LDA FP1EXP
    LDB FP0EXP
    JSR FPSUB                       ; the fraction of a turn
    LDX #FQTR
    JSR FSUBX                       ; a quarter less it
    LDA FP0SGN
    PSHS A
    BPL SIN_NEGATE
    JSR ADDHLF
    LDA FP0SGN
    BMI SIN_QUARTER
    COM RELFLG
SIN_NEGATE:
    JSR NEGATE
SIN_QUARTER:
    LDX #FQTR
    JSR FADDX
    PULS A
    TSTA
    BPL SIN_SERIES
    JSR NEGATE
SIN_SERIES:
    LDX #SINCOF
    JMP ODDPOL

;; 2 times pi in packed floating point.
FTWOPI:
    .byte $83, $49, $0F, $DA, $A2
;; 0.25 in packed floating point.
FQTR:
    .byte $7F, $00, $00, $00, $00
;; The sine's series in turns, for <ODDPOL>: its degree, then six coefficients, highest first.
SINCOF:
    .byte 5
    .byte $84, $E6, $1A, $2D, $1B
    .byte $86, $28, $07, $FB, $F8
    .byte $87, $99, $68, $89, $01
    .byte $87, $23, $35, $DF, $E1
    .byte $86, $A5, $5D, $E7, $28
    .byte $83, $49, $0F, $DA, $A2
;; Two numbers nothing uses.
UNUSED:
    .byte $A1, $54, $46, $8F, $13
    .byte $8F, $52, $43, $89, $CD

;; The 6809's interrupt vectors: each points to page 1's JMP, which later ROMs can change, except RESET's.
;;
;; On the CoCo 3 they point to the GIME's constant page, <INT_SWI3> to <INT_NMI>, whose jumps start-up copies from
;; <INTIMAGE>, and RESET goes to <INTRESET>, which maps the whole ROM in and starts the CoCo 3 at <COCO3RESET>.
VECTRS:
    .dbyt SEARCH                    ; reserved
.if COCO3
    .dbyt INT_SWI3                  ; SWI3
    .dbyt INT_SWI2                  ; SWI2
    .dbyt INT_FIRQ                  ; FIRQ
    .dbyt INT_IRQ                   ; IRQ
    .dbyt INT_SWI                   ; SWI
    .dbyt INT_NMI                   ; NMI
    .dbyt INTRESET                  ; RESET
.else
    .dbyt SW3VEC                    ; SWI3
    .dbyt SW2VEC                    ; SWI2
    .dbyt FRQVEC                    ; FIRQ
    .dbyt IRQVEC                    ; IRQ
    .dbyt SWIVEC                    ; SWI
    .dbyt NMIVEC                    ; NMI
    .dbyt RESVEC                    ; RESET
.endif
