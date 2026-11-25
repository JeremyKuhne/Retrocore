;; ALTAIR MULTI-BOOT LOADER (MBL) PROM ($FE00-$FEFF)
;;
;; MITS's MBL loads a MITS paper tape or cassette from any of the terminal boards, without the bootstrap an operator
;; would otherwise key in: it skips the tape's leader and its checksum loader, and reads the load records that follow
;; itself, which is why one loader serves every version of BASIC. The operator sets the sense switches A11-A8 to the
;; device the tape is on, and, for BASIC 4.0 and later, A15-A12 to the terminal's, then starts at $FE00.
;;
;; The loader first sets up the boards it might read from, then finds the top of RAM, puts its stack under it and builds
;; a routine below the stack that reads a byte from the chosen device and adds it to a checksum in B: a status IN, an
;; ANI and a JZ or JNZ back, then the data IN. DEVICE_TABLE gives each device's data port, the jump and the mask; the
;; status port is the one below the data port.
;;
;; A tape is a leader of bytes that each give the length of the checksum loader after it, the checksum loader, then
;; load records, each $3C, a byte count, a load address and that many bytes, then their checksum (which includes the
;; address), and an end record, $78 and the program's start address, where the loader jumps.
;;
;; On an error the loader stores a code at $0000 and HL at $0001 (for 'M' the address that failed, otherwise the
;; reading routine's), lights INTE with EI, and sends the code to every terminal board forever: 'I' for a device
;; number above 6, 'M' for RAM that did not keep a byte or ended off a page, 'O' for a load that would overwrite the
;; reading routine, and 'C' for a checksum that did not match.
;;
;; The labels follow Geoff Harrison's disassembly of a dump Grant Stockly provided.
;;
;; Maintained by hand. AltairDiskTests check that it assembles byte-identically to the PROM.

.cpu I8080

SENSE_SWITCHES = $FF                ;; the front panel's sense switches: A11-A8 the device the tape is on

; The terminal boards the loader sets up, and sends an error code to.
SIO_DATA = $01                      ;; the 88-SIO's data port
PIO_DATA = $05                      ;; the 88-PIO's data port
SIO2_CONTROL = $10                  ;; the 88-2SIO's first port's control register
SIO2_DATA = $11                     ;; the 88-2SIO's first port's data register
PIO4_DATA_B0 = $23                  ;; the 88-4PIO's first port's section B data register

; Tape record tokens.
LOAD_RECORD = $3C                   ;; starts a load record
END_RECORD = $78                    ;; starts the end record, with the program's start address

DEVICES = 7                         ;; the devices DEVICE_TABLE has

; The instructions the reading routine is built from.
OP_IN = $DB                         ;; IN port
OP_ANI = $E6                        ;; ANI mask
OP_PUSH_PSW = $F5                   ;; PUSH PSW
OP_ADD_B = $80                      ;; ADD B
OP_MOV_B_A = $47                    ;; MOV B,A
OP_POP_PSW = $F1                    ;; POP PSW
OP_RET = $C9                        ;; RET

        .org $FE00

;; Sets up the boards, finds the top of RAM, builds the reading routine for the device the sense switches name, then
;; loads the tape and runs it.
MBL:    di

        ; The 88-4PIO's ports ($20-$27) and the 88-2SIO's first port, whichever are there.
        xra a
        out $20
        out $21
        out $24
        out $25
        out $26
        out $22
        cma
        out $23
        out $27
        mvi a,$0C
        out $24
        mvi a,$2C
        out $20
        out $22
        out $26
        mvi a,$03
        out $27
        out SIO2_CONTROL
        mvi a,$11
        out SIO2_CONTROL

        ; The first byte from $0000 that does not keep its complement is the top of RAM, which must be a page's start.
        lxi h,$FFFF
SCAN_RAM:
        inx h
        mov a,m
        mov b,a
        cma
        mov m,a
        cmp m
        mov m,b
        jz SCAN_RAM
        xra a
        cmp l
        jnz MEMORY_ERROR

        ; The stack 14 bytes under the top of RAM, and the reading routine 14 bytes under that.
        lxi b,$FFF2
        dad b
        sphl
        dad b
        push h

        ; The device's entry in DEVICE_TABLE.
        in SENSE_SWITCHES
        ani $0F
        cpi DEVICES
        jp DEVICE_ERROR
        lxi h,DEVICE_TABLE
        inr b
        mov c,a
        add a
        add c
        mov c,a
        dad b

        ; Builds the reading routine on the stack, from its end: IN status, ANI mask, JZ or JNZ back to the IN,
        ; IN data, PUSH PSW, ADD B, MOV B,A, POP PSW, RET.
        pop d
        lxi b,(OP_RET << 8) | OP_POP_PSW
        push b
        lxi b,(OP_MOV_B_A << 8) | OP_ADD_B
        push b
        mvi b,OP_PUSH_PSW
        mov c,m
        mov a,c
        push b
        mvi b,OP_IN
        mov c,d
        push b
        mov b,e
        inx h
        mov c,m
        push b
        inx h
        mov b,m
        mvi c,OP_ANI
        push b
        dcr a
        mov b,a
        mvi c,OP_IN
        push b
        xchg

        mvi a,$04
        out $27

        ; The leader: its first byte, read after one thrown away, is the checksum loader's length.
        call READ_BYTE
        call READ_BYTE
        mov c,a
SKIP_LEADER:
        call READ_BYTE
        cmp c
        jz SKIP_LEADER

        ; The checksum loader, the rest of its bytes.
        dcr c
SKIP_LOADER:
        call READ_BYTE
        dcr c
        jnz SKIP_LOADER

        ; The records, until the end record.
FIND_RECORD:
        call READ_BYTE
        cpi LOAD_RECORD
        jz LOAD
        cpi END_RECORD
        jnz FIND_RECORD
        call READ_BYTE
        mov c,a
        call READ_BYTE
        mov l,c
        mov h,a

;; Reads a byte from the device, with the routine built under the stack; at the end of the tape, jumps to the program
;; loaded.
;; In: HL = the reading routine, B = the checksum so far
;; Out: A = the byte, B = the checksum with it added
;; Uses: A, B
;; Keeps: C, D, E, H, L
READ_BYTE:
        pchl

        ; A load record: its byte count, its load address in DE, then its bytes.
LOAD:   call READ_BYTE
        mov c,a
        mvi b,0
        call READ_BYTE
        mov e,a
        call READ_BYTE
        mov d,a
LOAD_1: mov a,d
        cmp h
        mvi a,'O'
        jz ERROR
        call READ_BYTE
        xchg
        mov m,a
        cmp m
MEMORY_ERROR:
        mvi a,'M'
        jnz ERROR
        inx h
        xchg
        dcr c
        jnz LOAD_1

        ; The record's checksum.
        mov c,b
        call READ_BYTE
        cmp c
        jz FIND_RECORD
        mvi a,'C'
        .byte $01                   ; LXI B over the next instruction
DEVICE_ERROR:
        mvi a,'I'

;; Gives up: stores the code at $0000 and HL at $0001, lights INTE and sends the code to every terminal board, forever.
;; In: A = the code, HL = the address involved
ERROR:  sta $0000
        shld $0001
        ei
ERROR_1:
        out SIO_DATA
        out SIO2_DATA
        out PIO_DATA
        out PIO4_DATA_B0
        jmp ERROR_1

;; Each device's data port, the jump that waits for a byte (JZ or JNZ) and the status mask, by its sense switch number.
DEVICE_TABLE:
        .byte SIO2_DATA, $CA, $01   ; 0: the 88-2SIO, two stop bits
        .byte SIO2_DATA, $CA, $01   ; 1: the 88-2SIO, one stop bit
        .byte SIO_DATA, $C2, $01    ; 2: the 88-SIO
        .byte $07, $C2, $01         ; 3: the 88-ACR
        .byte $21, $CA, $80         ; 4: the 88-4PIO
        .byte PIO_DATA, $CA, $02    ; 5: the 88-PIO
        .byte $25, $CA, $40         ; 6: the high-speed paper tape reader

        .assert * = $FF00, "The PROM is 256 bytes."
