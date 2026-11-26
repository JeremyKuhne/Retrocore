;; ALTAIR DISK BOOT LOADER 4.1 (DBL) PROM ($FF00-$FFFF)
;;
;; MITS's 88-DBL boots the 88-DCDD's drive 0: the operator sets the front panel's address switches to $FF00 and runs.
;; The PROM's first instructions copy the loader into RAM at $2C00, as the PROM is too slow to run from, and jump to
;; it. The loader sets up the terminal boards, waits for drive 0 to be ready, loads its head and steps it out to
;; track 0, then reads the disk from track 0, sector 0 into memory from $0000, until it has read the byte count the
;; sectors' headers give, and jumps to $0000.
;;
;; Each sector is 137 bytes: a track byte with bit 7 set, the 16-bit count of bytes to load, 128 bytes of data, a stop
;; byte of $FF and a checksum of the data. The loader reads the first 134 of them into a buffer after itself, then
;; moves the 128 data bytes to their place, checking each write to memory, adding up the checksum and checking the
;; stop byte and the checksum after. A bad sector is read up to 16 times in all. The disk's sectors are interleaved
;; 2:1, so a track's even sectors are read first and then its odd ones.
;;
;; On an error the loader stores a code at $0000, 'C' for a sector that could not be read or 'M' for memory that did
;; not keep what was written, and the address involved at $0001, lights the front panel's INTE with EI, and sends the
;; code to every terminal board forever.
;;
;; The sector loop reads two bytes a pass, the second without waiting for NRDA: the controller holds each byte for one
;; byte time, 32 us, and the second IN comes 66-90 cycles after the first byte's NRDA. Burcon's CP/M has a NOP
;; before that IN, which this PROM lacks, leaving little margin for a drive turning slowly.
;;
;; The labels follow Martin Eberhard's 2012 disassembly of an EPROM labeled "DBL 4.1" from a MITS turnkey board.
;;
;; Maintained by hand. AltairDiskTests check that it assembles byte-identically to the PROM.

.cpu I8080

LOAD_ADDRESS = $0000                ;; where the loaded program goes, and where it starts
RUN_ADDRESS = $2C00                 ;; where the loader runs, copied from the PROM
RETRIES = $10                       ;; how many times a bad sector is read before the loader gives up

SENSE_SWITCHES = $FF                ;; the front panel's sense switches: A12 up for one stop bit on the 88-2SIO

; The terminal boards the loader sets up, and sends an error code to.
SIO_DATA = $01                      ;; the 88-SIO's data port
PIO_DATA = $05                      ;; the 88-PIO's data port
SIO2_CONTROL = $10                  ;; the 88-2SIO's first port's control register
SIO2_DATA = $11                     ;; the 88-2SIO's first port's data register
PIO4_DATA_B0 = $23                  ;; the 88-4PIO's first port's section B data register
PIO4_CONTROL_B0 = $22               ;; the 88-4PIO's first port's section B control register
SIO2_MASTER_RESET = %00000011       ;; resets an ACIA

; The 88-DCDD's registers.
DISK_STATUS = $08                   ;; drive status when read, its bits low when true
DISK_SELECT = $08                   ;; drive select when written
DISK_SECTOR = $09                   ;; the sector position when read
DISK_CONTROL = $09                  ;; drive commands when written
DISK_DATA = $0A                     ;; the disk's bytes when read

; Drive status bits, each 0 when true.
MOVE_OK = $02                       ;; the head may be stepped
ENABLED = $08                       ;; a drive is selected and ready
TRACK_ZERO = $40                    ;; the head is on track 0

; Drive select and command values.
DISABLE = $80                       ;; DISK_SELECT: deselects every drive
STEP_IN = $01                       ;; DISK_CONTROL: steps the head in a track
STEP_OUT = $02                      ;; DISK_CONTROL: steps the head out a track
HEAD_LOAD = $04                     ;; DISK_CONTROL: loads the head against the disk

SECTOR_BYTES = $86                  ;; the bytes of a sector the loader reads: all but the last three

        .org $FF00

;; Copies the loader into RAM at RUN_ADDRESS and runs it there.
COPY:   lxi h,LOADER_IMAGE
        lxi d,RUN_ADDRESS
        mvi c,BUFFER-LOADER
COPY_1: mov a,m
        stax d
        inx h
        inx d
        dcr c
        jnz COPY_1
        jmp RUN_ADDRESS

LOADER_IMAGE:
        .logicalorg RUN_ADDRESS

;; Sets up the terminal boards and drive 0, seeks track 0 and reads the disk into memory from LOAD_ADDRESS, then runs
;; it.
LOADER: di                          ; INTE off: no error yet

        ; The 88-4PIO's port B as outputs, for the error code, strobing CB2 on each write. The listing says input, but
        ; the MC6820's direction bits are 1 for an output.
        xra a
        out PIO4_CONTROL_B0
        cma
        out PIO4_DATA_B0
        mvi a,$2C
        out PIO4_CONTROL_B0

        ; The 88-2SIO's first port: 8 bits, no parity, and one stop bit with A12 up, else two.
        mvi a,SIO2_MASTER_RESET
        out SIO2_CONTROL
        in SENSE_SWITCHES
        ani $10
        rrc
        rrc
        adi $10
        out SIO2_CONTROL

        lxi sp,STACK

        ; Drive 0, once it is ready, with its head loaded.
WAIT_ENABLED:
        xra a
        out DISK_SELECT
        in DISK_STATUS
        ani ENABLED
        jnz WAIT_ENABLED
        mvi a,HEAD_LOAD
        out DISK_CONTROL
        jmp CHECK_TRACK_ZERO

        ; Steps out until the head is on track 0.
SEEK_TRACK_ZERO:
        in DISK_STATUS
        ani MOVE_OK
        jnz SEEK_TRACK_ZERO
        mvi a,STEP_OUT
        out DISK_CONTROL
CHECK_TRACK_ZERO:
        in DISK_STATUS
        ani TRACK_ZERO
        jnz SEEK_TRACK_ZERO

        lxi d,LOAD_ADDRESS

        ; Each track: the even sectors, then the odd ones.
NEXT_TRACK:
        mvi b,0
NEXT_SECTOR:
        mvi a,RETRIES

        ; Reads sector B into BUFFER, A tries left and DE where its data goes.
READ_SECTOR:
        push psw
        push d
        push b
        push d
        lxi d,$8000 | SECTOR_BYTES
        lxi h,BUFFER
WAIT_SECTOR:
        in DISK_SECTOR
        rar
        jc WAIT_SECTOR
        ani $1F
        cmp b
        jnz WAIT_SECTOR

        ; Two bytes a pass, the first once NRDA says it has come, the second a byte time later.
WAIT_DATA:
        in DISK_STATUS
        ora a
        jm WAIT_DATA
        in DISK_DATA
        mov m,a
        inx h
        dcr e
        jz SECTOR_READ
        dcr e
        in DISK_DATA
        mov m,a
        inx h
        jnz WAIT_DATA
SECTOR_READ:

        ; Moves the data to DE, checking each write and adding up the checksum.
        pop h
        lxi d,BUFFER+3
        lxi b,$0080
MOVE:   ldax d
        mov m,a
        cmp m
        jnz MEMORY_ERROR
        add b
        mov b,a
        inx d
        inx h
        dcr c
        jnz MOVE

        ; The stop byte is $FF, and the checksum follows it.
        ldax d
        cpi $FF
        jnz READ_CHECKED
        inx d
        ldax d
        cmp b
READ_CHECKED:
        pop b
        xchg
        jnz BAD_SECTOR

        ; Done once DE has reached the count in the sector's header.
        pop psw
        pop psw
        lhld BUFFER+1
        call COMPARE
        jnc DONE

        ; The next even sector, the first odd one after sector 30, or the next track after sector 31.
        inr b
        inr b
        mov a,b
        cpi $20
        jc NEXT_SECTOR
        mvi b,1
        jz NEXT_SECTOR
WAIT_STEP:
        in DISK_STATUS
        ani MOVE_OK
        jnz WAIT_STEP
        mvi a,STEP_IN
        out DISK_CONTROL
        jmp NEXT_TRACK

DONE:   mvi a,DISABLE
        out DISK_SELECT
        jmp LOAD_ADDRESS

        ; A bad sector is read again, until its tries run out.
BAD_SECTOR:
        pop d
        pop psw
        dcr a
        jnz READ_SECTOR

;; Gives up on a sector: stores 'C' at LOAD_ADDRESS and the buffer address at LOAD_ADDRESS+1, BUFFER+$83 for a bad stop
;; byte or BUFFER+$84 for a bad checksum, then hangs as ERROR_HANG does.
;; In: HL = the buffer address
SECTOR_ERROR:
        mvi a,'C'
        .byte $01                   ; LXI B over the next instruction

;; Gives up on memory that did not keep a byte: stores 'M' at LOAD_ADDRESS and the address at LOAD_ADDRESS+1, then
;; hangs as ERROR_HANG does.
;; In: HL = the address
MEMORY_ERROR:
        mvi a,'M'
        ei                          ; INTE on, for the front panel's light
        sta LOAD_ADDRESS
        shld LOAD_ADDRESS+1
        mov b,a
        mvi a,DISABLE
        out DISK_SELECT
        mov a,b

;; Sends the error code to every terminal board, forever.
;; In: A = the code
ERROR_HANG:
        out SIO_DATA
        out SIO2_DATA
        out PIO_DATA
        out PIO4_DATA_B0
        jmp ERROR_HANG

;; Compares DE with HL.
;; In: DE, HL = the values
;; Out: carry = set if HL is greater
;; Uses: A
;; Keeps: B, C, D, E, H, L
COMPARE:
        mov a,d
        cmp h
        rnz
        mov a,e
        cmp l
        ret

; The sector buffer follows the loader in RAM; the PROM holds only its first two bytes, which fill the PROM.
BUFFER: .word $0000
        .logicalorg

        .assert * = $10000, "The PROM is 256 bytes."

BUFFER_BYTES = $86                  ;; the buffer: the sector bytes the loader reads
STACK_BYTES = 8                     ;; the stack's room, after the buffer
STACK = BUFFER + BUFFER_BYTES + STACK_BYTES ;; the stack's top
