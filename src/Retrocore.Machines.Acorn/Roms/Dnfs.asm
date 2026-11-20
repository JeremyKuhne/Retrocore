;; BBC MICRO DNFS 1.20 ($8000-$BFFF)
;;
;; Acorn's DNFS: two filing systems in one 16K paged ROM, the Econet Network Filing System and the Disc Filing
;; System 1.20 for the 8271 controller, with the Tube host code that lets a second processor use them. The MOS calls
;; it through its service entry; it answers the service calls, claims workspace, and selects one filing system or
;; the other through the filing system vectors. The ROM is in parts, each in its own file in Dnfs, in the order they
;; sit in the ROM:
;;
;; - NetService.asm ($8000-$8840): the paged ROM header, the service call handler and dispatch table, starting the
;;   NFS and the Tube, and the NFS's start-up messages and boot.
;; - NetCommands.asm ($8841-$8FEF): the NFS's * commands and its catalogue display.
;; - NetCalls.asm ($8FF0-$9320): the NFS's filing system calls and NETV.
;; - Tube.asm ($9321-$962F): the Tube host code, which the NFS copies to zero page and pages four to six.
;; - Econet.asm ($9630-$9F9C): transmitting and receiving on the Econet, its NMI handlers and the code it copies to
;;   page &0D.
;; - DfsCommands.asm ($9F9D-$A7FE): the DFS's errors and messages, its * command tables and commands.
;; - DfsCatalogue.asm ($A7FF-$B009): the catalogue, the 8271 driver and the NMI code it copies to page &0D.
;; - DfsFiles.asm ($B00A-$B803): the DFS's filing system calls: OSFILE, OSARGS, OSBGET, OSBPUT, OSGBPB, OSFIND and
;;   OSFSC, and its service calls.
;; - DfsUtilities.asm ($B804-$BFFF): *COMPACT, *COPY, *BACKUP and the other utilities, and the help and syntax text.
;;
;; Names follow Acorn's documentation where it gives them: the Advanced User Guide and the DFS user guides name the
;; calls, service calls, commands and errors. Other labels are named after what the code does.
;;
;; Maintained by hand. BbcDnfsSourceTests check that it assembles byte-identically to DNFS 1.20.

.cpu Mos6502

.include "MosEquates.asm"
.include "MosEntries.asm"
.include "DnfsEquates.asm"

.org $8000

.include "Dnfs/NetService.asm"
.include "Dnfs/NetCommands.asm"
.include "Dnfs/NetCalls.asm"
.include "Dnfs/Tube.asm"
.include "Dnfs/Econet.asm"
.include "Dnfs/DfsCommands.asm"
.include "Dnfs/DfsCatalogue.asm"
.include "Dnfs/DfsFiles.asm"
.include "Dnfs/DfsUtilities.asm"
