;; MOS 1.20 ENTRY POINTS, FOR THE SOURCES THAT CALL THE MOS
;;
;; The operating system calls a paged ROM such as BASIC or the DFS makes, and the extended vector entries a filing
;; system points the vectors at, as equates at their documented addresses at the top of the MOS ROM. Mos.asm defines
;; and documents each of them as a label, so it does not include this file; the others do, and each definition here
;; inherits the MOS's documentation. The MOS's workspace, vectors and hardware registers are in MosEquates.asm, which
;; those sources include too.

;; Inherit: <Mos:EXTENDED_VECTOR_ENTRIES>
EXTENDED_VECTOR_ENTRIES = $FF00

;; Inherit: <Mos:OSRDRM>
OSRDRM = $FFB9

;; Inherit: <Mos:VDUCHR>
VDUCHR = $FFBC

;; Inherit: <Mos:OSEVEN>
OSEVEN = $FFBF

;; Inherit: <Mos:GSINIT>
GSINIT = $FFC2

;; Inherit: <Mos:GSREAD>
GSREAD = $FFC5

;; Inherit: <Mos:NVRDCH>
NVRDCH = $FFC8

;; Inherit: <Mos:NVWRCH>
NVWRCH = $FFCB

;; Inherit: <Mos:OSFIND>
OSFIND = $FFCE

;; Inherit: <Mos:OSGBPB>
OSGBPB = $FFD1

;; Inherit: <Mos:OSBPUT>
OSBPUT = $FFD4

;; Inherit: <Mos:OSBGET>
OSBGET = $FFD7

;; Inherit: <Mos:OSARGS>
OSARGS = $FFDA

;; Inherit: <Mos:OSFILE>
OSFILE = $FFDD

;; Inherit: <Mos:OSRDCH>
OSRDCH = $FFE0

;; Inherit: <Mos:OSASCI>
OSASCI = $FFE3

;; Inherit: <Mos:OSNEWL>
OSNEWL = $FFE7

;; Inherit: <Mos:OSWRCR>
OSWRCR = $FFEC

;; Inherit: <Mos:OSWRCH>
OSWRCH = $FFEE

;; Inherit: <Mos:OSWORD>
OSWORD = $FFF1

;; Inherit: <Mos:OSBYTE>
OSBYTE = $FFF4

;; Inherit: <Mos:OSCLI>
OSCLI = $FFF7
