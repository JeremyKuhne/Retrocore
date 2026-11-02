;; APPLE DOS 3.2
;;
;; The disk operating system of the Apple II before DOS 3.3: the code on tracks 0 to 2 of a DOS 3.2 System
;; Master, for the 13-sector disks of the Disk II's first boot ROM (Boot13.asm). This file assembles all of it
;; from the modules below, in memory order. docs/Dos.md explains how DOS boots, what each part does and how a
;; disk is laid out; docs/DiskII.md explains the hardware underneath, and the 5-and-3 nibbles 13-sector disks
;; use.
;;
;; DOS has three layers, each built on the one below:
;;
;; - The command interpreter (DosInit to CommandTables) hooks the Monitor's character input and output, so
;;   that BASIC's PRINT and INPUT reach it, and carries out commands such as CATALOG, LOAD and OPEN.
;; - The file manager (FileManagerEntry to FileManagerData) keeps the files on a disk: the VTOC, the catalog
;;   and each file's track/sector list.
;; - RWTS, "read or write a track and sector" (BootLoader32 to Formatter32), drives the Disk II controller: it
;;   moves the head, turns 256-byte sectors into nibbles and back, and formats disks.
;;
;; The command interpreter and the file manager are DOS 3.3's, at the same addresses, as they were before DOS
;; 3.3's own patches, so this file shares their modules with DOS 3.3 (Dos33.asm):
;;
;; - Shared: Equates, Relocator, the command interpreter and file manager modules, RwtsEquates and DosPatches.
;;   They test DOS32, set to 1 here, where DOS 3.2 differs: the numbers that describe a 13-sector disk (the
;;   VTOC image, the free-sector maps, the catalog's first sector), the places DOS 3.3 patched (the end of
;;   APPEND, SAVE and BSAVE without the check DOS 3.3 added, DOSGO's handling of errors), RWTS's zero page and
;;   the relocator's code ranges. Apple's DOS 3.3 build options are set as DOS 3.2's code needs them: DOS33B =
;;   0, for instance, leaves LOCSEC without its CLC.
;; - DOS 3.2's own, whose names end in 32: BootLoader32, PreNibble32, WriteSector32, ReadSector32,
;;   ReadAddress32, PostNibble32, SeekMsWait32, NibbleBuffers32, Rwts32 and Formatter32, the boot loader, RWTS
;;   and formatter for 13-sector disks. RWTS is an earlier form of DOS 3.3's.
;;
;; Two builds come from this source, chosen by MASTER:
;;
;; - MASTER = 1 (the default), with the origin at $1B00, is the image on the System Master's tracks 0 to 2: a
;;   relocator at $1B00 and DOS at $1D00-$3FFF. The relocator moves DOS to the top of whatever memory the
;;   machine has, adjusting every address in it, so one master boots on any Apple II. It assembles byte for
;;   byte to the DOS on the master, track 0 sectors 10 to 12, tracks 1 and track 2 sectors 0 to 10, then
;;   track 0 sectors 0 to 9.
;; - MASTER = 0, with the origin at $9D00, is DOS where it runs on a machine with 48K or more: $9D00-$BFFF.
;;   This is the copy INIT writes to the disks it formats, and the one the debugger steps through.
;;
;; The names are Apple's, from its DOS 3.3 C source listing (July 1983), wherever DOS 3.2 has the same code;
;; the names of code only DOS 3.2 has are the SDK's, in the same style. Where DOS reserves storage, the master
;; holds whatever was in memory when it was written; the sources keep those bytes as data, marked "leftover"
;; or written with the LEFTOVER macro in the shared modules, so the image is exact.
;;
;; Maintained by hand.

.cpu Mos6502

;; 1: this root builds DOS 3.2. The shared modules test it where DOS 3.2 differs.
DOS32 = 1

;; 1 to build the System Master image (relocator at $1B00, DOS at $1D00); 0 to build DOS where it runs, at $9D00.
.ifndef MASTER
MASTER = 1
.endif

; Apple's DOS 3.3 build options, with the values that give DOS 3.2's code: no diagnostic RWTS, none of the 1982
; "revision B" patches and no lowercase-input patch.
DIAGMODE = 0                        ;; 1 builds a diagnostic RWTS without the formatter (Apple's)
DOS33B = 0                          ;; 1 includes DOS 3.3's 1982 "revision B" patches (Apple's)
ULC = 0                             ;; 1 builds the lowercase-input patch (Apple's)

.include "Equates.asm"

.if MASTER
ORIGIN = $1B00                      ;; where the master image starts: the relocator, then DOS two pages later
.include "Relocator.asm"
.else
; Without the relocator, the names DOS uses for it point into DOS itself, as they do after relocation.
BEGIN = START
DOSREL = DBINIT
.endif

; The command interpreter.
.include "DosInit.asm"
.include "DosHook.asm"
.include "CommandScan.asm"
.include "OpenClose.asm"
.include "LoadSave.asm"
.include "MiscCommands.asm"
.include "DosGoer.asm"
.include "BuildFileTables.asm"
.include "CommandTables.asm"

; The file manager.
.include "FileManagerEntry.asm"
.include "FileOpenCloseReadWrite.asm"
.include "FileDeleteCatalog.asm"
.include "FileManagerIo.asm"
.include "FileLocateNextByte.asm"
.include "FileLocateSector.asm"
.include "FileManagerData.asm"

; RWTS, starting with the boot loader's pages, $B600-$B7FF where DOS runs.
.include "BootLoader32.asm"
.include "RwtsEquates.asm"
.include "PreNibble32.asm"
.include "WriteSector32.asm"
.include "ReadSector32.asm"
.include "ReadAddress32.asm"
.include "PostNibble32.asm"
.include "SeekMsWait32.asm"
.include "NibbleBuffers32.asm"
.include "Rwts32.asm"
.include "Formatter32.asm"
.include "DosPatches.asm"
