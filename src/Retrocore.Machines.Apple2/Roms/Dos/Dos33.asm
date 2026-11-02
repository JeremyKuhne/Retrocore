;; APPLE DOS 3.3 (1980 AND 1983)
;;
;; The disk operating system of the Apple II from 1980 until ProDOS: the code on tracks 0 to 2 of every DOS 3.3
;; disk. This file assembles all of it from the modules below, in Apple's order. docs/Dos.md explains how DOS
;; boots, what each part does and how a disk is laid out; docs/DiskII.md explains the hardware underneath.
;;
;; DOS has three layers, each built on the one below:
;;
;; - The command interpreter (DosInit to CommandTables) hooks the Monitor's character input and output, so
;;   that BASIC's PRINT and INPUT reach it, and carries out commands such as CATALOG, LOAD and OPEN.
;; - The file manager (FileManagerEntry to FileManagerData) keeps the files on a disk: the VTOC, the catalog
;;   and each file's track/sector list.
;; - RWTS, "read or write a track and sector" (BootLoader to Formatter), drives the Disk II controller: it
;;   moves the head, turns 256-byte sectors into nibbles and back, and formats disks.
;;
;; YEAR chooses the DOS: 1983 (the default) is the one on the 680-0210-A System Master, and 1980 the one on
;; the 680-0051 masters. They differ in Apple's 1982 "revision B" patches (DOS33B), which the 1980 DOS lacks,
;; and in their leftover bytes. Two builds of each come from this source, chosen by MASTER:
;;
;; - MASTER = 1 (the default), with the origin at $1B00, is the image on a System Master's tracks 0 to 2: a
;;   relocator at $1B00 and DOS at $1D00-$3FFF. The relocator moves DOS to the top of whatever memory the
;;   machine has, adjusting every address in it, so one master boots on any Apple II. It assembles byte for
;;   byte to the DOS on that year's master.
;; - MASTER = 0, with the origin at $9D00, is DOS where it runs on a machine with 48K or more: $9D00-$BFFF.
;;   This is the copy INIT writes to the disks it formats, and the one the debugger steps through.
;;
;; The names are Apple's, from its DOS 3.3 C source listing (July 1983), and so is the order of the modules.
;; The 680-0210-A master differs from that listing in one patch, FIXIT2: it is shorter, and it sits in the
;; patch area after MSWAIT ($BA84 where DOS runs) rather than in the boot loader's page. Where DOS reserves
;; storage, the master holds whatever was in memory when it was written; the sources keep those bytes as data,
;; marked "leftover" or written with the LEFTOVER macro where the masters differ, so each image is exact.
;;
;; The modules are shared with DOS 3.2 (Dos32.asm), which has the same command interpreter and file manager:
;;
;; - Shared: Equates, Relocator, the command interpreter and file manager modules, RwtsEquates and DosPatches.
;;   They test DOS32, set to 0 here, where DOS 3.2 differs, and LEFTOVER picks each master's leftover byte.
;; - DOS 3.3's own: BootLoader, PreNibble, WriteSector, PostNibbleRead, ReadAddressSeek, MsWait,
;;   WriteAddress, Rwts1, Rwts2 and Formatter, its 16-sector boot loader, RWTS and formatter. DOS 3.2's
;;   counterparts are the modules whose names end in 32.
;;
;; Maintained by hand; DosSourceTests pin each build by digest.

.cpu Mos6502

;; 0: this root builds DOS 3.3. The shared modules test it where DOS 3.2 differs.
DOS32 = 0

;; 1 to build the System Master image (relocator at $1B00, DOS at $1D00); 0 to build DOS where it runs, at $9D00.
.ifndef MASTER
MASTER = 1
.endif

;; Which DOS 3.3 to build: 1983, the 680-0210-A master's, or 1980, the 680-0051 masters'.
.ifndef YEAR
YEAR = 1983
.endif

; Apple's build options. The 1980 DOS is the one without the revision B patches.
DIAGMODE = 0                        ;; 1 builds a diagnostic RWTS without the formatter (Apple's)
DOS33B = YEAR >= 1983               ;; 1 includes the 1982 "revision B" patches (Apple's)
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
.include "BootLoader.asm"
.include "RwtsEquates.asm"
.include "PreNibble.asm"
.include "WriteSector.asm"
.include "PostNibbleRead.asm"
.include "ReadAddressSeek.asm"
.include "MsWait.asm"
.include "WriteAddress.asm"
.include "Rwts1.asm"
.include "Rwts2.asm"
.include "Formatter.asm"
.include "DosPatches.asm"
