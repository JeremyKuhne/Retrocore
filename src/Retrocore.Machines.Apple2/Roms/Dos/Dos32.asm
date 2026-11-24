; retrocore: style=strict
;; DOS 3.2: the root that assembles the whole of it from its modules
;;
;; The disk operating system of the Apple II before DOS 3.3: the code on tracks 0 to 2 of a DOS 3.2 System Master,
;; for the 13-sector disks of the Disk II's first boot ROM (Boot13.asm). This file assembles all of it from the
;; modules below, in memory order. docs/Dos.md explains how DOS boots, what each part does and how a disk is laid
;; out; docs/DiskII.md explains the hardware underneath, and the 5-and-3 nibbles 13-sector disks use.
;;
;; DOS has three layers, each built on the one below:
;;
;; - The command interpreter (DosInit to CommandTables) hooks the Monitor's character input and output, so that
;;   BASIC's PRINT and INPUT reach it, and carries out commands such as CATALOG, LOAD and OPEN.
;; - The file manager (FileManagerEntry to FileManagerData) keeps the files on a disk: the VTOC, the catalog and
;;   each file's track/sector list.
;; - RWTS, "read or write a track and sector" (BootLoader to Formatter), drives the Disk II controller: it
;;   moves the head, turns 256-byte sectors into nibbles and back, and formats disks.
;;
;; The command interpreter and the file manager are DOS 3.3's, at the same addresses, as they were before DOS
;; 3.3's own patches, and its boot loader, RWTS and formatter are an earlier form of DOS 3.3's, for 13-sector disks,
;; so this file shares its modules with DOS 3.3 (Dos33.asm):
;;
;; - Shared: every module but RWTS itself. They test <DOS32>, set to 1 here, where DOS 3.2 differs: the numbers that
;;   describe a 13-sector disk (the VTOC image, the free-sector maps, the catalog's first sector), the places DOS 3.3
;;   patched (the end of APPEND, SAVE and BSAVE without the check DOS 3.3 added, <RunFileRequest>'s handling of errors),
;;   RWTS's zero page and the relocator's code ranges. Apple's DOS 3.3 build options are set as DOS 3.2's code needs
;;   them: <REVISION_B> = 0, for instance, leaves <FileManager::SetPosition> without its CLC. In the boot loader, RWTS's
;;   low-level routines and the formatter, a routine both versions have is one definition, with `.if DOS32` where the
;;   two differ in places; one that differs throughout, such as `BOOT 1`, the prenibble and postnibble routines and the
;;   formatter, has a definition for each version, side by side in its module.
;; - DOS 3.2's own: Rwts32, RWTS itself, an earlier form of DOS 3.3's Rwts1 and Rwts2. DOS 3.3's address field
;;   writer, WriteAddress, is not part of it; its formatter includes the 4-and-4 writer (FourAndFour) itself.
;;
;; Two builds come from this source, chosen by <MASTER>:
;;
;; - MASTER = 1 (the default), with the origin at $1B00, is the image on the System Master's tracks 0 to 2: a
;;   relocator at $1B00 and DOS at $1D00-$3FFF. The relocator moves DOS to the top of whatever memory the machine
;;   has, adjusting every address in it, so one master boots on any Apple II. It assembles byte for byte to the
;;   DOS on the master, track 0 sectors 10 to 12, track 1 and track 2 sectors 0 to 10, then track 0 sectors 0 to
;;   9.
;; - MASTER = 0, with the origin at $9D00, is DOS where it runs on a machine with 48K or more: $9D00-$BFFF. This
;;   is the copy INIT writes to the disks it formats, and the one the debugger steps through.
;;
;; Where DOS 3.2 has the same code as DOS 3.3, each definition keeps the name of Apple's DOS 3.3 C source listing
;; (July 1983) in its historical names; the names of code only DOS 3.2 has are the SDK's, in the same style, and
;; have none. Where DOS reserves storage, the master holds whatever was in memory when it was written; the sources
;; keep those bytes as data, marked "leftover" or written with the <Leftover> macro in the shared modules, so the
;; image is exact.
;;
;; Maintained by hand.

.cpu Mos6502

; The SDK's build options, which the host may set.

;; 1: this root builds DOS 3.2. The shared modules test it where DOS 3.2 differs.
DOS32 = 1

;; 1 to build the System Master image (relocator at $1B00, DOS at $1D00); 0 to build DOS where it runs, at $9D00.
.ifndef MASTER
MASTER = 1
.endif

; Only the two builds DosSourceTests checks by digest. There is one DOS 3.2: the shared modules let YEAR choose
; only when DOS32 is 0, so YEAR selects nothing here, and the digests are checked with either year.
.assert MASTER = 0 || MASTER = 1, "MASTER is 1 for the System Master's image or 0 for DOS where it runs."

; Apple's DOS 3.3 build options, with the values that give DOS 3.2's code: no diagnostic RWTS, none of the 1982
; "revision B" patches and no lowercase-input patch.

;; 1 builds RWTS with an on-screen trace for diagnosing it, without the formatter; 0 for DOS 3.2.
;; Also: DIAGMODE (DOS33)
DIAGNOSTIC_RWTS = 0

;; 1 includes DOS 3.3's 1982 "revision B" patches; 0 for DOS 3.2, which came before them.
;; Also: DOS33B (DOS33)
REVISION_B = 0

;; 1 builds the patch that lets commands be typed in lowercase; 0 for DOS 3.2.
;; Also: ULC (DOS33)
LOWERCASE_INPUT = 0

.include "Equates.asm"

.if MASTER
;; Where the master image starts: the relocator, then DOS two pages later. The host sets the origin itself, so
;; this only checks it; the editor, which knows no origin, assembles the source at 0.
;; Also: ORIGIN (DOS33)
MASTER_ORIGIN = $1B00
.include "Relocator.asm"
.assert ImageStart = MASTER_ORIGIN || ImageStart = 0, "The master image starts with the relocator, at MASTER_ORIGIN."
.else
; Without the relocator, the names DOS uses for it point into DOS itself, as they do after relocation.

;; Where `BOOT 2` reads DOS to, and where INIT writes it from: without the relocator, DOS's first byte.
;; Also: BEGIN (DOS33, DOS31)
ImageStart = DosStart

;; Where `BOOT 2` ends: without the relocator, DOS's cold start, since this DOS is already where it runs.
;; Also: DOSREL (DOS33, DOS31)
RelocateDos = ColdStart
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
.include "BootLoader.asm"
.include "RwtsEquates.asm"
.include "PreNibble.asm"
.include "WriteSector.asm"
.include "ReadData.asm"
.include "ReadAddress.asm"
.include "PostNibble.asm"
.include "Seek.asm"
.include "MsWait.asm"
.include "Rwts32.asm"
.include "DriveTracks.asm"
.include "Formatter.asm"
.include "DosPatches.asm"
