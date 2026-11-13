; SOS 1.3 kernel layout: where each module runs (ORG), how long it is (LEN), and where it sits in the SOS.KERNEL
; file (BLA). The BLA addresses count the file's first byte as $2000, the address Apple loaded the file at to build
; it; at boot the file loads at $1E00 instead, so the loader runs from the place it was loaded to.

; ---------------------------------------------------------------------------------------------------------------------
; Module origins: the address each module runs at once the loader has put it in place.
; ---------------------------------------------------------------------------------------------------------------------

ORGLODR = $1E00                     ;; the loader, SOSLDR, which runs where the boot loader reads the file
ORGINIT = $28F8                     ;; INIT, the managers' initialization, inside the space the loader keeps for it
ORGGLOB = $18FC                     ;; the global page, SYSGLOB, less its 4-byte address-and-count header
ORGBFMI = $B800                     ;; the block file manager's second initialization, whose space later holds bitmaps
ORGBFM = $BC00                      ;; the block file manager
ORGPATCH = $DE66                    ;; the patch area, which is empty in SOS 1.3 (it starts where OPRMSG does)
ORGOMSG = $DE66                     ;; the operator messages (asking for a volume)
ORGIPL = $DFC0                      ;; interrupts, events and the kernel's entry from BRK
ORGUMGR = $E48B                     ;; the utility manager
ORGDISK3 = $E899                    ;; the built-in Disk III driver
ORGSERR = $EE04                     ;; error returns and SYSDEATH
ORGDMGR = $EED9                     ;; the device manager
ORGSCMGR = $F05E                    ;; the system call manager
ORGFMGR = $F2F4                     ;; the file manager
ORGCFM = $F355                      ;; the character file manager
ORGBUFMG = $F552                    ;; the buffer manager
ORGMEMMG = $F86E                    ;; the memory manager
ORGEND = $FFBF                      ;; the end of the kernel, just below the I/O registers at $FFC0

; ---------------------------------------------------------------------------------------------------------------------
; Module lengths. Each module's source checks its own length against these with .assert.
; ---------------------------------------------------------------------------------------------------------------------

LENLODR = ORGINIT-ORGLODR           ;; the loader, up to the space it keeps for INIT
LENINIT = $01B2                     ;; INIT's code; the loader keeps $200 bytes for it
LENBFMI = ORGBFM-ORGBFMI
LENBFM = ORGPATCH-ORGBFM
LENPATCH = ORGOMSG-ORGPATCH         ;; 0: SOS 1.3 has no patch area
LENOMSG = ORGIPL-ORGOMSG
LENIPL = ORGUMGR-ORGIPL
LENUMGR = ORGDISK3-ORGUMGR
LENDISK3 = ORGSERR-ORGDISK3
LENSERR = ORGDMGR-ORGSERR
LENDMGR = ORGSCMGR-ORGDMGR
LENSCMGR = ORGFMGR-ORGSCMGR
LENFMGR = ORGCFM-ORGFMGR
LENCFM = ORGBUFMG-ORGCFM
LENBUFMG = ORGMEMMG-ORGBUFMG
LENMEMMG = ORGEND-ORGMEMMG

; ---------------------------------------------------------------------------------------------------------------------
; Module places in SOS.KERNEL, with the file's start at $2000. Modules from BFM on follow one another with no gap,
; so the kernel from $B800 to $FFBF is one block the loader moves in one piece.
; ---------------------------------------------------------------------------------------------------------------------

BLALODR = $2000                     ;; the loader: the file's first byte
BLAINIT = BLALODR+LENLODR           ;; INIT, at the end of the loader
BLAGLOB = $2CF8                     ;; the global page's header, after the loader and INIT's $200-byte space
BLABFMI = $2E00                     ;; the kernel's code ($B800 up), after its header at the end of the global page
BLABFM = $3200
BLAPATCH = BLABFM+LENBFM
BLAOMSG = BLAPATCH+LENPATCH
BLAIPL = BLAOMSG+LENOMSG
BLAUMGR = BLAIPL+LENIPL
BLADISK3 = BLAUMGR+LENUMGR
BLASERR = BLADISK3+LENDISK3
BLADMGR = BLASERR+LENSERR
BLASCMGR = BLADMGR+LENDMGR
BLAFMGR = BLASCMGR+LENSCMGR
BLACFM = BLAFMGR+LENFMGR
BLABUFMG = BLACFM+LENCFM
BLAMEMMG = BLABUFMG+LENBUFMG
