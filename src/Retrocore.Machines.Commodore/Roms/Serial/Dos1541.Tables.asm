; retrocore: style=strict
; COMMODORE 1541 DOS: THE ROM'S TABLES, THE PATCHES AND THE VECTORS ($FE85-$FFFF)

;; 18: the directory's and the BAM's track.
;; Also: DIRTRK (D1541)
DirectoryTrack:
    .byte $12

;; 4: the BAM's bytes for each track.
;; Also: BAMSIZ (D1541)
BamEntrySize:
    .byte $04

;; 4: where the BAM starts in its sector; nothing reads it (Q4).
;; Also: MAPOFF (D1541)
BamOffset:
    .byte $04

;; $90: the disk name's offset in the BAM sector.
;; Also: DSKNAM (D1541)
DiskNameOffset:
    .byte $90

;; The commands' letters, VIDMBUP&CRSN; the parser's command number is the index.
;; Also: CMDTBL (D1541)
CommandLetters:
    .byte "VIDMBUP&CRSN"

;; Each command's routine, low bytes.
;; Also: CJUMPL (D1541)
CommandRoutinesLow:
    .byte <Directory::Validate, <Commands::Initialize, <Commands::Duplicate
    .byte <Commands::Memory, <Commands::Block, <Commands::User
    .byte <Relative::PositionCommand
    .byte <Commands::LoadUtility
    .byte <Commands::Copy
    .byte <Commands::Rename, <Commands::Scratch, <Commands::New

;; And high bytes.
;; Also: CJUMPH (D1541)
CommandRoutinesHigh:
    .byte >Directory::Validate, >Commands::Initialize, >Commands::Duplicate
    .byte >Commands::Memory, >Commands::Block, >Commands::User
    .byte >Relative::PositionCommand
    .byte >Commands::LoadUtility
    .byte >Commands::Copy
    .byte >Commands::Rename, >Commands::Scratch, >Commands::New

;; The patterns of the commands that take names: copy, rename, scratch and new, then LOAD's. Each byte holds the bits of
;; <Commands::Structure> that the command forbids, which the parser checks (<Commands::ParseNames>). The bits are: 7 a
;; pattern in the first names, 6 more than one first name, 5 first names given; 3 a pattern in the second names, 2 more
;; than one second name, 1 second names given; 0 no second names. No bit means a default drive; bit 4 is never set. The
;; table starts at `$FEAD`, and <PATTERN_ORIGIN> indexes it by the command's number.
CommandPatterns:
    .byte $51
    .byte $DD
    .byte $1C
    .byte $9E
    .byte $1C

;; Where <CommandPatterns> would start if it held a pattern for command 0: the table's address less 8, the number of its
;; first command (copy), so that the command's number indexes the table (LOAD's is <Commands::LOAD_STRUCTURE>, 12). The
;; listing's STRUCT is this address, which is not a table's: its bytes are the end of <CommandRoutinesHigh> (`$FEA1` to
;; `$FEAC`).
;; Also: STRUCT (D1541)
PATTERN_ORIGIN = CommandPatterns - 8

;; OPEN's modes: R, W, A, M.
;; Also: MODLST (D1541)
FileModes:
    .byte "RWAM"

;; The types OPEN takes: D, S, P, U, L.
;; Also: TPLST (D1541)
OpenTypeLetters:
    .byte "DSPUL"

;; The types' names' first letters, DSPUR (DEL, SEQ, PRG, USR, REL)...
;; Also: TYPLST (D1541)
TypeFirstLetters:
    .byte "DSPUR"

;; ...second, EERSE...
;; Also: TP1LST (D1541)
TypeSecondLetters:
    .byte "EERSE"

;; ...and third, LQGRL.
;; Also: TP2LST (D1541)
TypeThirdLetters:
    .byte "LQGRL"

;; Each drive's LED bit: LED0, LED1.
;; Also: LEDMSK (D1541)
LedMasks:
    .byte LED_DRIVE0, LED_DRIVE1

;; 0: BIT clears N and V and sets Z.
;; Also: ER00 (D1541)
BitZero:
    .byte $00

;; $3F: BIT clears N and V.
;; Also: ER0 (D1541)
BitNeither:
    .byte $3F

;; $7F: V set, N clear.
;; Also: ER1 (D1541)
BitOverflow:
    .byte $7F

;; $BF: N set, V clear.
;; Also: ER2 (D1541)
BitNegative:
    .byte $BF

;; $FF: N and V set.
;; Also: ER3 (D1541)
BitBoth:
    .byte $FF

;; Each zone's sectors: 17 for tracks 31-35, 18 for 25-30, 19 for 18-24, 21 for 1-17.
;; Also: NUMSEC (D1541)
SectorsPerTrack:
    .byte $11, $12, $13, $15

;; FM4040, A: the format NEW writes and a disk's header must have.
;; Also: VERNUM (D1541)
FormatType:
    .byte FORMAT_VERSION

;; 4 zones.
;; Also: NZONES (D1541)
ZoneCount:
    .byte $04

;; 36: one past the last track; <ZoneLimits>' first byte (Q2).
;; Also: MAXTRK (D1541)
TrackLimit:

;; Each zone's first track past it: 36, 31, 25, 18, searched down to find a track's zone.
;; Also: TRKNUM (D1541)
ZoneLimits:
    .byte $24, $1F, $19, $12
.assert TrackLimit = ZoneLimits, "TrackLimit and ZoneLimits are one table's two jobs: its first byte is both."

;; The head's steps for a job's retries, 1, -1, -1, 1, ended by 0.
;; Also: OFFSET (D1541)
RecoveryOffsets:
    .byte $01, $FF, $FF, $01, $00

;; Each buffer's page, $03-$07, by its number (a sixth byte repeats $07).
;; Also: BUFIND (D1541)
BufferPages:
    .byte $03, $04, $05, $06, $07, $07
; The tables' start-up part: the ROM's checksum byte, the NMI entry and the power-on patch.
.scope Startup continued

;; The byte that makes the `$E000` ROM's checksum come out at `$E0`; each revision has its own.
;; Also: ECHKSM (D1541)
UpperRomChecksum:
.if REVISION = 1
    .byte $FD
.elseif REVISION = 2
    .byte $10
.elseif REVISION = 3
    .byte $0E
.elseif REVISION = 5
    .byte $3E
.elseif REVISION = 6
    .byte $EC
.else
    .byte $60
.endif

;; Jumps through <NmiVector>, which holds <Reset::Initialize>, so a plain `UI` command re-initializes the drive without
;; the self-test. The 1540's NMI vector points here. It never returns.
;; Also: NMI (D1541)
.proc Reinitialize
    jmp (NmiVector)
.endproc

;; The power-on patch, the same in every build: lights the LEDs and sets VIA 2's port B direction, so the LED is an
;; output before the controller's start-up has run, then jumps back to <BlinkFault::LedsLit>.
;; Also: PEA7A (D1541)
.proc BlinkFaultPatch
    sta DriveControl
    sta Via2DirectionB
    jmp BlinkFault::LedsLit
.endproc
.endscope
.if DRIVE_1540
    ; The 1540 has no SlowDown, CLKDAT or NNMI: their 29 bytes are fill.
    .res 29, $AA
.else
; The serial bus's two routines in the patch area, which TALK calls.
.scope Serial continued

;; Delays about 40 microseconds more for each bit sent, at the VIC-20's speed.
;; Uses: A
;; Keeps: X
;; Also: SLOWD (D1541)
.proc SlowDown
    txa
    ldx #$05

;; Five counts.
;; Also: SLOWE (D1541)
Wait:
    dex
    bne Wait
    tax
    rts
.endproc

;; Ends a bit: pulls the clock with <PullClock>, then jumps to <ReleaseData>, which returns.
;; Also: CLKDAT (D1541)
.proc PullClockAndReleaseData
    jsr PullClock
    jmp ReleaseData
.endproc
.endscope
; The NMI vector's target, for the 1541's builds.
.scope Startup continued

;; The NMI vector's target, which the `UI` command reaches through the user table: `UI-` sets <SerialNoDelay> nonzero
;; (the 64's speed), `UI+` zero (the VIC-20's), and `UI` alone goes to <Reinitialize>.
;; Also: NNMI (D1541)
.proc Nmi
    lda CommandBuffer+2
    cmp #'-'
    beq SetSpeed
    sec
    sbc #'+'
    bne Reinitialize

;; <SerialNoDelay> = A.
;; Also: NNMI10 (D1541)
SetSpeed:
    sta SerialNoDelay
    rts
.endproc
.endscope
.endif

.if LATE_PATCHES
; -05's two patches, which -06 keeps: code moved out of start-up and the bus's receive routine into the patch area.
.scope Startup continued

;; -05's fix: sets VIA 1's port A direction (X is $FF, all outputs), then port B = `$02` and its directions, so CLK is
;; released and DATA pulled during the self-test (the listing's comment says the clock). It jumps back to
;; <Reset::SelfTest>.
;; Also: PATCH5 (D1541)
.proc ResetPatch
    stx Via1DirectionA
    lda #$02
    sta Via1PortB
    lda #$1A
    sta Via1DirectionB
    jmp Reset::SelfTest
.endproc
.endscope
.scope Serial continued

;; -05's fix to EOI's timing: waits until DATA reads released, every listener ready, before starting the 256
;; microseconds timer, then jumps back to <ReceiveByte::WaitForClock>.
;; Also: PATCH6 (D1541)
.proc ReceiveBytePatch
    lda Via1PortB
    and #$01
    bne ReceiveBytePatch
    lda #$01
    sta Via1Timer1High
    jmp ReceiveByte::WaitForClock
.endproc
.endscope
.else
    ; Before -05, and in the 1540, the patches' 31 bytes are fill.
    .res 31, $AA
.endif
.if REVISION = 6
; -06's patch.
.scope Commands continued

;; -06's fix: sets <Controller::FormatTrack> to $FF, no format under way, then jumps to <Format>, which NEW calls
;; through it.
.proc FormatPatch
    lda #$FF
    sta Controller::FormatTrack
    jmp Format
.endproc
.endscope
.endif
    ; The fill up to the vectors.
    .res $FFE2 - *, $AA
.if REVISION = 2 || REVISION = 3
    ; -02 and -03 have RSR in three bytes of the fill.
    .byte "RSR"
.else
    .res 3, $AA
.endif
    .byte $AA

; The vectors, at the ROM's end.

;; The format routine's address, for programs that format through the ROM.
FormatVector:
    .word Commands::Format

;; The motor timeout routine's address.
MotorOffVector:
    .word Controller::MotorTimeout

;; The user commands' addresses, U1 and U2 (UBLKRD, UBLKWT), U3-U8 into buffer 2; U9 to U; read on into the processor's
;; vectors (Q5).
;; Also: UBLOCK (D1541)
UserCommandVectors:
    .word Commands::UserRead
    .word Commands::UserWrite
    ; U3 to U8 jump into buffer 2.
    .word $0500
    .word $0503
    .word $0506
    .word $0509
    .word $050C
    .word $050F
.if DRIVE_1540
    .word Startup::Reinitialize
.else
    .word Startup::Nmi
.endif
    ; The 6502's own vectors: NMI (above), RESET and IRQ.
    .word Startup::Reset
    .word Controller::Interrupt
