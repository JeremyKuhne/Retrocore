;; MBASIC 5.21: EQUATES
;;
;; The names MBASIC's modules share for CP/M: its page zero, the BDOS functions BASIC calls, and the layout of
;; the file data block (FDB) BASIC keeps for each open file. They define no bytes. Mbasic.asm includes this file
;; before the modules.
;;
;; BASIC calls the BDOS through CPMENT with the function in C and its argument, an FCB's or a buffer's address,
;; in DE. The console and printer don't go through the BDOS: INIT patches the BIOS's own entries into the calls in
;; Console.asm, found through BIOSWB.

; CP/M's page zero, below the program.
CPMWRM = $0000                      ;; the warm boot jump: SYSTEM leaves BASIC through it
BIOSWB = $0001                      ;; the warm boot jump's address, the BIOS's warm boot entry, from which INIT finds the BIOS's console entries
CPMENT = $0005                      ;; the BDOS jump: C = the function, DE = its argument
CPMMEM = $0006                      ;; the BDOS jump's address, the top of the TPA: MEMSIZ starts below it

; CP/M's BDOS functions, passed in C to CPMENT (Digital Research's names).
S_BDOSVER = 12                      ;; return the version in A: 0 before CP/M 2, else $2x
DRV_ALLRESET = 13                   ;; reset the disk system, logging every drive back in
DRV_SET = 14                        ;; select the drive in E (0 = A:)
F_OPEN = 15                         ;; open the file DE's FCB names; A = $FF if not found
F_CLOSE = 16                        ;; close the file, recording its extent in the directory
F_SFIRST = 17                       ;; search for the first directory entry matching DE's FCB; A = $FF if none
F_SNEXT = 18                        ;; search for the next matching entry; A = $FF if no more
F_DELETE = 19                       ;; delete the files DE's FCB matches
F_READ = 20                         ;; read the next record sequentially into the DMA buffer
F_WRITE = 21                        ;; write the DMA buffer as the next record
F_MAKE = 22                         ;; create the file DE's FCB names; A = $FF if the directory is full
F_RENAME = 23                       ;; rename the file DE's FCB names to the name 16 bytes on
DRV_GET = 25                        ;; return the current drive in A
F_DMAOFF = 26                       ;; set the DMA buffer to DE
F_READRAND = 33                     ;; read the record the FCB's random record field names (CP/M 2)
F_WRITERAND = 34                    ;; write the record the FCB's random record field names (CP/M 2)
F_SIZE = 35                         ;; set the FCB's random record field to the file's size in records (CP/M 2)
F_RANDREC = 36                      ;; set the FCB's random record field from its sequential position (CP/M 2)

; CP/M's default DMA buffer and records.
TBUFF = $0080                       ;; the default DMA buffer, where CP/M leaves the command line's length and text
DIRTMP = TBUFF                      ;; the same buffer, where directory searches return their entries
DATPSC = 128                        ;; the bytes in a CP/M record, and in a file's buffer

; The modes of a file, in its FDB's first byte (Microsoft's names).
MD_SQI = 1                          ;; sequential input
MD_SQO = 2                          ;; sequential output
MD_RND = 3                          ;; random

; The layout of a file data block.
FD_MODE = $00                       ;; the mode: 0 when closed, else MD_SQI, MD_SQO or MD_RND
FD_FCB = $01                        ;; CP/M's 36-byte file control block
FD_EXT = $0D                        ;; the FCB's extent number (byte 12)
FD_RC = $10                         ;; the FCB's count of records in the extent (byte 15), LOF's result
FD_CR = $21                         ;; the FCB's current record in the extent (byte 32)
FD_RR = $22                         ;; the FCB's random record number (bytes 33-35)
FD_REC = $25                        ;; a word: the records read or written so far, LOC's result for a sequential file
FD_BCNT = $27                       ;; the bytes in the buffer: those written, or DATPSC read (0 at the end of the file)
FD_BREM = $28                       ;; reading, the bytes left in the buffer; writing, the column printed to
FD_BUF = $29                        ;; the DATPSC-byte record buffer, CP/M's DMA buffer for the file
FD_RLEN = $A9                       ;; a random file's record length (OPEN's LEN, 128 by default); file 0's block ends here
FD_PREC = $AB                       ;; a random file's 128-byte record in the buffer, plus 1 (0 for none)
FD_LREC = $AD                       ;; a random file's current record, from 1, LOC's result
FD_FPOS = $B0                       ;; a random file's position in its record buffer, for PRINT# and INPUT#
FD_FIELD = $B2                      ;; a random file's record buffer, FD_RLEN bytes, which FIELD maps variables onto
