; COMMODORE BASIC 4: MONITOR AND DISK KERNAL WORKSPACE
;
; These are the kernal's own addresses in Basic4.mac, not allocations. The monitor and disk
; routines share this storage with the editor and kernal; including this file emits no bytes.

; Kernal zero-page workspace.
CINV = $90                          ;; two-byte RAM IRQ vector
SATUS = $96                         ;; kernal I/O status byte, also named <CQSTAT>
VERCK = $9D                         ;; LOAD or VERIFY selector
LDTND = $AE                         ;; number of entries in the logical-file tables
DFLTO = $B0                         ;; default output device
WSW = $B3                           ;; cassette write flag, reused to save the catalog output channel
SAVX = $B4                          ;; monitor's current command index
TMPC = $B5                          ;; monitor character or byte count
CNTDN = $BA                         ;; cassette countdown, reused to save the catalog output device
EAL = $C9                           ;; low byte of the monitor SAVE end address
EAH = $CA                           ;; high byte of the monitor SAVE end address
FNLEN = $D1                         ;; current filename length
LA = $D2                            ;; current logical file number
SA = $D3                            ;; current secondary address
FA = $D4                            ;; current primary device address
FNADR = $DA                         ;; two-byte current filename pointer
WRAP = $DE                          ;; monitor address-wrap flag
TMP0 = $FB                          ;; two-byte monitor address and scratch pointer
TMP2 = $FD                          ;; second two-byte monitor address
FNADR2 = $FD                        ;; second filename pointer, sharing <TMP2>
BAD = $0100                         ;; monitor hexadecimal-byte scratch

; Monitor's saved registers and kernal file tables.
PCH = $0200                         ;; saved program-counter high byte
PCL = $0201                         ;; saved program-counter low byte
FLGS = $0202                        ;; saved processor status
ACC = $0203                         ;; saved accumulator
XR = $0204                          ;; saved X register
YR = $0205                          ;; saved Y register
SP = $0206                          ;; saved stack pointer
INVH = $0207                        ;; saved IRQ vector high byte
INVL = $0208                        ;; saved IRQ vector low byte
SAVNAM = $0209                      ;; monitor filename buffer
LAT = $0251                         ;; logical-file-number table
FAT = $025B                         ;; primary-device-number table
SAT = $0265                         ;; secondary-address table
FNLEN2 = $033A                      ;; second filename length
RECPOS = $033A                      ;; relative-record position, sharing <FNLEN2>
DRIVE1 = $033B                      ;; first drive number
DRIVE2 = $033C                      ;; second drive number
DIDCHK = $033D                      ;; disk-ID-seen flag, sharing <LRECL>
LRECL = $033D                       ;; relative-record length, sharing <DIDCHK>
PRSCHK = $033E                      ;; parsed disk-parameter flags
DISKID = $033F                      ;; two-byte disk ID
KCOUNT = $0341                      ;; disk-message template counter
TBUF2 = $0342                       ;; first filename storage
TBUFF = $0353                       ;; disk-command output buffer
USRCMD = $03FA                      ;; indirect vector for unrecognized monitor commands

; Editor and kernal entries used by this ROM.
PRT = $E202                         ;; screen editor character output
MS1 = $F000                         ;; base of the kernal messages
MSG1 = $F000                        ;; message base, also named <MS1>
MS3 = $F017                         ;; file-not-open message
MSG30 = $F0B6                       ;; confirmation message
MSG31 = $F0C5                       ;; bad-disk message
TALK = $F0D2                        ;; address a serial-bus talker
LISTN = $F0D5                       ;; address a serial-bus listener
MSG = $F185                         ;; print a kernal message by offset
SECND = $F193                       ;; send a secondary talk address
UNTLK = $F1AE                       ;; release the serial-bus talker
UNLSN = $F1B9                       ;; release the serial-bus listener
ACPTR = $F1C0                       ;; receive a byte from the serial bus
GETIN = $F205                       ;; get a character without waiting
BASIN = $F215                       ;; read a character from the selected input
BSOUT = $F266                       ;; write a character to the selected output
CLRCH = $F2A6                       ;; restore the default I/O channels
CLRCHN = $F2A6                      ;; same channel-reset entry as <CLRCH>
JLTLK = $F2C1                       ;; find a logical file in the kernal table
JZ100 = $F2CD                       ;; load the selected file's table entry
CLOS5 = $F2E2                       ;; close the selected logical file
FCLOSE = $F2E2                      ;; close entry, also named <CLOS5>
CLOS10 = $F2E7                      ;; close a file at a known table position
STOP1 = $F335                       ;; test the STOP key
LD15 = $F356                        ;; monitor load entry
LOADNP = $F408                      ;; BASIC load without parsing a filename
OPENIB = $F4B4                      ;; send an OPEN command on the serial bus
OP94 = $F563                        ;; open the filename prepared by a disk command
FOPEN = $F565                       ;; open using the current kernal file fields
ERMSG = $F5AF                       ;; report a kernal message as an error
SV3 = $F6E0                         ;; BASIC save entry
SV5 = $F6E3                         ;; monitor save entry
CHKIN = $F7AF                       ;; select a logical input channel
CHKOUT = $F7FE                      ;; select a logical output channel
TWAIT = $F92B                       ;; wait for the tape operation to finish
SPERR = $10                         ;; kernal status bit for a load or verify error
CR = $0D                            ;; carriage-return character
ONTK = $91                          ;; BASIC's ON token used by the disk parser
NCMDS = 8                           ;; number of built-in monitor commands
