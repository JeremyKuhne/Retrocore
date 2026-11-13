; DISK3, continued: the driver's variables, its tables of each drive's state, and the boot ROM routines it calls.

;; The unit of the last read, write or status request, which a repeat request must name.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.KERNEL; the init request sets it.
;; See: <PREVCMD>, <MAIN>
PREVUNIT:
    .res 1, $A0
;; The last request's code, which a repeat request does again if it was a read or a write.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.KERNEL; the first request sets it.
;; See: <PREVUNIT>, <MAIN>
PREVCMD:
    .res 1, $99
;; The caller's environment register, without the screen bit, restored by <EXIT>.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.KERNEL; <MAIN> sets it.
ESAVE:
    .res 1, $CE
;; The system VIA's vertical-blanking interrupt enable bits, saved while a seek or a sector transfer has them off.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.KERNEL; SOS sets it at run time.
;; See: <SECTORIO>, <MYSEEK>
VBLSAVE:
    .res 1, $A0
;; Negative once the init request has set the driver up.
;; See: <INIT>
INITFLAG:
    .byte 0
    .if REV0ROM
;; Which boot ROM is present, found by the init request: 0 for the first revision, nonzero for the later one.
ROMREV:
    .res 1
    .endif
T50MS = $02                             ;; 50 milliseconds, in units of the motor-on count's high byte (about 25 ms)
T200MS = $08                            ;; 200 milliseconds, in the same units
T1SEC = $27                             ;; a second, in the same units
;; How long the motor must have been on for each request: a read, a write and status.
;;
;; Writes need the motor fully up to speed; reads can start sooner.
;; See: <UNITSEL>
MTIMES:
    .byte T200MS, T1SEC, T50MS
;; For each drive .D1-.D4, nonzero when it is the selected one, whose motor may be turning.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.KERNEL; the init request clears it.
;; See: <UNITSEL>, <EXTDESEL>, <ADDTIME>
DRIVESEL:
    .byte $A0, $C3, $A0, $CC
;; For each drive .D1-.D4, how long its motor has been on, in units of about 25 ms, up to just over a second.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.KERNEL; the init request clears it.
;; See: <ADDTIME>, <UNITSEL>, <MTIMES>
UPTIME:
    .byte $A0, $A0, $91, $A0
;; For each drive .D1-.D4, the track its head is on.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.KERNEL; the init request sets it.
;; See: <MYSEEK>, <RECAL>, <INIT>
DRVTRACK:
    .byte $E0, $99, $A0, $AC
    .if REV0ROM
;; The jump table to the boot ROM's disk routines, which the init request fills from <REV0> or <REV1>.
;;
;; A build for the first ROM revision calls the ROM through here, since the two revisions put some routines at
;; different addresses.
;; See: <INIT>
JMPTAB:
RDADR:
    jmp *
READ:
    jmp *
WRITE:
    jmp *
SEEK:
    jmp *
MSWAIT:
    jmp *
PRENIB:
    jmp *
POSTNIB:
    jmp *
;; The first boot ROM revision's addresses for <JMPTAB>, in its order.
REV0:
    jmp $F1BD
    jmp $F148
    jmp $F219
    jmp $F400
    jmp $F456
    jmp $F2C6
    jmp $F311
VSIZE = * - REV0                        ;; the jump table's size in bytes
;; The later boot ROM revision's addresses for <JMPTAB>, in its order.
REV1:
    jmp $F1B9
    jmp $F148
    jmp $F216
    jmp $F400
    jmp $F456
    jmp $F2C4
    jmp $F30F
    .else
; The later boot ROM's disk routines, called directly; each one's name in BootRom.asm follows in parentheses.
RDADR = $F1B9                           ;; reads the next address field into CSSTV (RDADR16)
READ = $F148                            ;; reads a sector's data field, still encoded (READ16)
WRITE = $F216                           ;; writes a sector's data field, already encoded (WRITE16)
SEEK = $F400                            ;; moves the head to a half-track, counting the motor time (SEEK)
MSWAIT = $F456                          ;; waits A times 100 microseconds, counting the motor time; keeps Y (MSWAIT)
PRENIB = $F2C4                          ;; encodes the 256 bytes at BUF for writing (PRENIB16)
POSTNIB = $F30F                         ;; decodes a sector just read into the 256 bytes at BUF (POSTNIB16)
    .endif
ZZEND:                                  ;; the end of the module
ZZLEN = * - ZZORG                       ;; the module's length, which must match LENDISK3 in SosOrg.asm
    .assert ZZLEN == LENDISK3, "SOSORG gives the module another length"
