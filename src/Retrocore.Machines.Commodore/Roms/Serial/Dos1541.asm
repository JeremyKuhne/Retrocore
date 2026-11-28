; retrocore: style=strict
;; COMMODORE 1541 AND 1540 DOS 2.6: ROMS 325302-01 AND 901229 (01, 02, 03, 05 AND 06) OR 325303-01
;;
;; The disk drives' DOS, 16 KB at $C000-$FFFF: 325302-01 at $C000, the same in every drive, and at $E000 the 1541's
;; 901229 or the 1540's 325303-01. The drive is a computer of its own, a 6502 with 2 KB of RAM and two VIAs: one for the
;; serial bus to the VIC-20 or 64 ($1800), one for the mechanism ($1C00). The DOS has two halves that share the job
;; queue at $0000-$0005. The controller, run by the 6522's timer interrupt every 14.848 ms (58 x 256 cycles at 1 MHz) or
;; more, does the jobs on the disk: seeking, reading and writing sectors in GCR, and formatting. The DOS, which the idle
;; loop runs, is the rest: the serial bus, the command channel and its commands, the directory, the block availability
;; map, the files and channels and the error channel.
;;
;; THE LAYOUT
;;
;; - $C000: the LEDs, the command parser and the commands (Dos1541.Commands.asm).
;; - $CE0E: channels, buffers, the job queue, OPEN and CLOSE (Dos1541.Files.asm).
;; - $DDF1: the side sectors and the relative files (Dos1541.Relative.asm).
;; - $E4FC: the error channel and the utility loader (Dos1541.Errors.asm).
;; - $E853: the serial bus (Dos1541.Serial.asm).
;; - $EA6E: start-up and the idle loop (Dos1541.Startup.asm).
;; - $EC9E: the directory listing, validate, new and the BAM (Dos1541.Directory.asm).
;; - $F259: the drive controller (Dos1541.Controller.asm).
;; - $FE85: the ROM's tables, the patches and the vectors (Dos1541.Tables.asm).
;;
;; THE NAMES
;;
;; The code is arranged in families, scopes spread through the ROM: `Controller`, `Jobs`, `Commands`, `Directory`,
;; `Bam`, `Files`, `Relative`, `Serial`, `Startup`, `Idle` and `Errors`. The VIAs, the job queue, the buffers, the
;; variables several families use and the ROM's tables are top level. Commodore's names from its listing of 901229-05
;; (D1541) are kept in each definition's `Also:`; docs/conversions/Dos1541Renames.md has every old name with its new
;; one, and Dos1541.md the decisions.
;;
;; Assembles byte-identically to 325302-01 and, by <REVISION>, to 901229-01, -02, -03, -05 or -06 (1, 2, 3, 5 or 6) or
;; the 1540's 325303-01 (40). Maintained by hand; Dos1541SourceTests pins each build by digest.

.cpu Mos6502

.ifndef REVISION
;; The ROM at $E000: 901229's revision, 1, 2, 3, 5 or 6 (901229-04 has no dump), or 40 for the 1540's 325303-01.
REVISION = 5
.endif

.assert (REVISION >= 1 && REVISION <= 6 && REVISION != 4) || REVISION = 40, "REVISION is 1, 2, 3, 5, 6 or 40."

;; 1 for the 1540's 325303-01: the VIC-20's bus timing alone, with no `Serial::SlowDown`, CLKDAT or `Startup::Nmi` (so
;; no UI+ and UI-, and the NMI vector at <Startup::Reinitialize>), its own power-on message, and a format that fills
;; each new block with zeros (a NOP where the 1541 has the INX before <Controller::WriteTrack::FillData>).
DRIVE_1540 = REVISION = 40

;; 1 for 901229-05 and -06: -05's patches, `Startup::ResetPatch` and `Serial::ReceiveBytePatch`, the boot loader
;; removed, the bus no longer released when the error channel's recovery frees a channel, and VIA 1's port B set before
;; its directions after message 73.
LATE_PATCHES = REVISION = 5 || REVISION = 6

;; 1 where a bit is taken with CLK and DATA in one read, from 901229-02 on; 901229-01 and the 1540 read them apart.
SINGLE_BIT_READ = REVISION != 1 && REVISION != 40

; The revisions differ in four more places, tested on REVISION where they are: <HEADER_GAP>, the upper ROM's checksum
; byte (<Startup::UpperRomChecksum>), -06's `Commands::FormatPatch`, and `RSR` in -02's and -03's fill at $FFE2.

.include "Dos1541.Equates.asm"

    .org $C000

.include "Dos1541.Commands.asm"
.include "Dos1541.Files.asm"
.include "Dos1541.Relative.asm"
.include "Dos1541.Errors.asm"
.include "Dos1541.Serial.asm"
.include "Dos1541.Startup.asm"
.include "Dos1541.Directory.asm"
.include "Dos1541.Controller.asm"
.include "Dos1541.Tables.asm"

.assert * = $10000, "The DOS ends at the processor's vectors."
