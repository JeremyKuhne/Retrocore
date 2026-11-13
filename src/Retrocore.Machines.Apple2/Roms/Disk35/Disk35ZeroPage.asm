;; THE CARD'S PAGE ZERO, AS THE ROM SETS IT UP
;;
;; STARTUP copies $8001-$80BB to the card's page zero, and $80BC-$80BF (the signature) once the rest is
;; ready. Its first bytes are the mailbox the host reads and writes at $C800 with bank 0 latched. The vectors
;; at $72-$8C are JMP instructions that the control calls can repoint and put back.

.logicalorg $0000
CARDSTATE:                        ;; bit 7 = the card waits for a command; the host writes the command here
    .byte $FF
CARDDATA:                         ;; the host writes $FF; the card's bit 7 = busy, 0 = done (no data), else bank*2+half of the data
    .byte $FF
CARDCOMMAND:                      ;; the host's command byte: bit 7 = a ProDOS call, bit 6 = an extended call
    .byte $00
CARDUNIT:                         ;; the unit number (0 = the controller)
    .byte $FF
CARDPROGRESS:                     ;; the host's copy of a block being written, on a IIgs: $C0, $C1, $D0 done
    .byte $00
PARAMLO:                          ;; the status or control code, or the block number's low byte
    .byte $FF
PARAMMID:                         ;; the block number's middle byte
    .byte $FF
PARAMHI:                          ;; the block number's high byte
    .byte $00
PARAM3:                           ;; the next parameter
    .byte $00
PARAM4:                           ;; commands $0D/$0E: the extra blocks, low byte
    .byte $00
PARAM5:                           ;; commands $0D/$0E: the extra blocks, high byte
    .byte $00
COUNTLO:                          ;; the byte count of the list or data, both ways
    .byte $00
COUNTHI:
    .byte $00
CURTRACK:                         ;; each drive's head position ($FF unknown; bit 6 = the second side's track, from a header)
    .byte $FF, $FF
SIDES:                            ;; each drive's disk: bit 7 = two sides
    .byte $80, $80
FORMATBYTE:                       ;; each drive's last address field's format byte
    .byte $00, $00
SAVEDRIVE:                        ;; a drive or count kept across calls
    .byte $00
TRACK:                            ;; the track to reach
    .byte $FF
SECTOR:                           ;; the sector to read
    .byte $FF
SIDE:                             ;; the side: 0, or $20 for the second
    .byte $FF
HIGHBYTE:                         ;; the bus packet's high bits
    .byte $FF
HIGHGROUP:                        ;; a 7-byte group's high bits, or the groups left
    .byte $FF
PACKETTYPE:                       ;; the bus packet's type: $80 command, $82 data
    .byte $FF
SECTORS:                          ;; the sectors in the track
    .byte $00
CYLINDER:                         ;; the track times 2, plus the side
    .byte $FF
SECTORCOUNT:                      ;; sectors left to read or write
    .byte $FF, $00
HEADERSUM:                        ;; an address field's or packet's checksum
    .byte $FF
CHECKSUM0:                        ;; the GCR data checksums
    .byte $00
CHECKSUM1:
    .byte $00
CHECKSUM2:
    .byte $00
CHECKSUMNIB:                      ;; the checksums' high bits, packed
    .byte $00
WORK0:                            ;; scratch
    .byte $00
WORK1:                            ;; scratch
    .byte $00, $00, $00
HDRCHECK:                         ;; the address field read: checksum
    .byte $00
HDRFORMAT:                        ;; format byte
    .byte $00
HDRSIDE:                          ;; side bits
    .byte $00
HDRSECTOR:                        ;; sector
    .byte $00
HDRTRACK:                         ;; track
    .byte $00
SCRATCH:                          ;; scratch
    .byte $00
BUFFERCODE:                       ;; the current buffer's code: its card address / $200
    .byte $00
CACHESLOT:                        ;; the current cache slot (0 = none)
    .byte $00
DRIVE:                            ;; the unit less one: 0-1 the 3.5 drives, more a bus device, $FF the controller
    .byte $00
WAITCOUNT:                        ;; WAITREADY's counter
    .byte $00, $00
FIRSTBUSUNIT:                     ;; the first SmartPort bus device's unit, or 0
    .byte $00
UNITCOUNT:                        ;; the units, 3.5 drives and bus devices
    .byte $00
DEVICEKIND:                       ;; each unit's device: 1 Apple 3.5, 3 FDHD, $80 a bus device, 0 none
    .byte $00, $00, $00, $00
SPANFIRST:                        ;; READSPAN's first sector
    .byte $00
SPANCYLINDER:                     ;; READSPAN's cylinder
    .byte $00
MEDIAMODE:                        ;; each drive's disk: $11 GCR, $32 MFM 720K, $52 MFM 1440K; bits 5-6 = MFM
    .byte $00, $00, $00, $00, $00
OLDSENSE:                         ;; the sense lines before the last READSENSE
    .byte $00
MEDIAKIND:                        ;; each drive's disk: 0 unknown, 2 400K, 4 800K, 6 800K (2:1), 8 720K, $0A 1440K
    .byte $00, $00
BLOCKSLO:                         ;; each drive's block count, low bytes
    .byte $00, $00
BLOCKSHI:                         ;; and high bytes
    .byte $00, $00
SENSE:                            ;; each drive's sense lines: 7 switched, 6 no disk, 5 protected, 4 one side only, 0 motor has had its full start
    .byte $00, $00
FORMATKIND:                       ;; each drive's format for the next FORMAT (0 = the default)
    .byte $00, $00
FORMATSKEW:                       ;; each drive's interleave for the next FORMAT
    .byte $00, $00
PACKET:                           ;; the bus command packet: command, parameter count, parameters
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
ERRORCODE:                        ;; the result the host reads
    .byte $00
DISKERRORS:                       ;; what went wrong on the disk or the bus
    .byte $00
RETRIES:                          ;; retries left; CTLPEEK's byte
    .byte $00
RESULTA:                          ;; CTLEXECUTE's A; also counts errors
    .byte $00
RESULTX:                          ;; CTLEXECUTE's X; also counts errors
    .byte $00
RESULTY:                          ;; CTLEXECUTE's Y; also a retry count
    .byte $00
RESULTP:                          ;; CTLEXECUTE's P; also a seek count
    .byte $00
SECTORTRIES:                      ;; address fields left to look at
    .byte $00
TAGERROR:                         ;; $21 when a tagged call meets an MFM disk
    .byte $00
CACHEOPTION:                      ;; control $0F's bit 7
    .byte $00
READOPTION:                       ;; a read's state: 7 the cache full, 6 the block handed over
    .byte $00
TAGCALL:                          ;; negative during READWRITE
    .byte $00
SKEW:                             ;; the interleave for FORMAT
    .byte $04
TWOSIDED:                         ;; bit 7 = FORMAT writes both sides
    .byte $80
USERPOINTER:                      ;; the address for the control calls
    .byte $00, $05
NIBBLEHIGH:                       ;; a GCR write's high bits
    .byte $00
NIBBLE0:                          ;; the bytes being nibblized
    .byte $00
NIBBLE1:
    .byte $00
NIBBLE2:
    .byte $00
SETUPCOPY:                        ;; the ISM setup register's value
    .byte $00
READING:                          ;; $80 while a read is in progress
    .byte $00
BUSCOUNT:                         ;; a bus packet's byte count
    .byte $00, $00
NIBBLESTART:                      ;; where PREPAREDATA starts
    .byte $00
EJECTDRIVE:                       ;; the drive being ejected; bit 7 = none
    .byte $80
VECTORLENGTH:                     ;; the vectors' length, for CTLRESETVECTORS
    .byte $1B, $00
;; the vectors, JMP instructions the control calls can change
VECTORS:
VECREADADDRESS:
    jmp READADDRESSGCR
VECREADDATA:
    jmp READDATAGCR
VECWRITEDATA:
    jmp WRITEDATAGCR
VECSEEK:
    jmp SEEKTRACK
VECFORMAT:
    jmp FORMATDISK
VECWRITETRACK:
    jmp WRITETRACKGCR
VECVERIFY:
    jmp VERIFYTRACKGCR
VECCOMMAND:
    jmp DOCOMMAND
VECINIT:
    jmp INITCARD
MARKS:                            ;; the GCR marks and sync bytes
    .byte $FF
DATAMARK:                         ;; the data field's mark, last byte first: D5 AA AD
    .byte $AD, $AA, $D5, $FF
SYNCBYTES:                        ;; a self-sync group, last byte first
    .byte $FC, $F3, $CF, $3F, $FF
EPILOGUE:                         ;; the fields' end, last byte first: DE AA
    .byte $FF, $AA, $DE, $FF, $FF, $FF, $FF, $FF
ADDRESSMARK:                      ;; the address field's mark, last byte first: D5 AA 96
    .byte $96, $AA, $D5, $FF
PACKETIN:                         ;; a received bus packet's header
    .byte $00
GROUPS:                           ;; a bus packet's 7-byte groups
    .byte $00
ODDBYTES:                         ;; and its other bytes
    .byte $00
BUSRESULT:                        ;; the bus device's result
    .byte $00, $00, $00, $00, $00
BUFPTR:                           ;; the first half of the buffer
    .byte $00, $00
WORKPTR:                          ;; a pointer, or a timer
    .byte $00, $00
BUFPTR2:                          ;; the second half of the buffer
    .byte $00, $00
SPANLOW:                          ;; the sectors wanted: first
    .byte $00
SPANHIGH:                         ;; and past the last
    .byte $00, $00
SWIMSTATE:                        ;; bit 7 = the disk is MFM, bit 6 = the SWIM is in ISM mode
    .byte $00
UNITHIGHBIT:                      ;; the unit with bit 7, for an extended unit-0-style status
    .byte $00
MFMGAP:                           ;; the MFM format's gap length
    .byte $00, $00, $00
TESTCALL:                         ;; negative when the self-test calls a command
    .byte $00
FORMATHOOK:                       ;; a routine FORMAT calls for an Apple 3.5 drive
    .byte $00, $00
SIGNATURE:                        ;; the warm-start signature
    .byte $4A, $CF, $41, $55, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00
LASTCOMMAND:                      ;; the last command: CARDSTATE, CARDCOMMAND, CARDUNIT, PARAMLO, PARAMMID
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
.logicalorg
