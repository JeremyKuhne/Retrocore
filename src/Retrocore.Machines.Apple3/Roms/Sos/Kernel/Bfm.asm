; SOS 1.3 kernel: the block file manager (BFM), SOS's file system for block devices.
;
; The BFM runs at ORGBFM ($BC00 on). It handles the file calls the file manager passes it, through BFMGR:
; CREATE, DESTROY, RENAME, SET_FILE_INFO, GET_FILE_INFO, VOLUME, SET_PREFIX, GET_PREFIX, OPEN, NEWLINE, READ,
; WRITE, CLOSE, FLUSH, SET_MARK, GET_MARK, SET_EOF and GET_EOF. Its source is a chain of files, each including
; the next at its end: BfmEquates (names and storage), Path (the call dispatcher and pathnames), Volume, Create,
; FndFil (finding files and logging in volumes), Alloc, PosnOpen, ReadWrite, CloseEof, Destroy and SwapOutIn.
; Labels follow Apple's SOS 1.3 listing.

ZZORG:                              ; the BFM's start, for the length check at the end of SwapOutIn.asm
    .include "BfmEquates.asm"
