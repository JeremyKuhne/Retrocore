; retrocore: style=strict ignore=unlinked-name:RWTS -- the disk layer's name in prose
;; DOS 3.3 and 3.2: the patches at the top of DOS, and DOS's end
;;
;; Fixes added after the rest of DOS was written, in its last bytes (Apple's DOSPTCH module): in DOS 3.3, $BFC8-$BFFF
;; where DOS runs, the end of the boot sequence, which resets the screen and the language card, and three short
;; routines that existing code was changed to call; in DOS 3.2 only the three routines. <DosEnd>, just after them, is
;; where DOS ends: $C000 where it runs, $4000 in the master image. DOS 3.3 has more patches in spare space in the boot
;; loader's page (BootLoader.asm), and the 1983 DOS after <DiskII::Wait> (MsWait.asm).
;;
;; <ReportDiskFull> is the file manager's code, patched in here: it works on the file manager's state and leaves
;; through the file manager's error exit, so it reads as part of the file manager (FileLocateSector.asm), whose
;; names it uses.
;;
;; In DOS 3.3, `TopPatchCodeStart` to `TopPatchCodeLast` is one of the code ranges in the relocator's
;; <Relocator::CodeRanges>, so the addresses in these instructions move with DOS. DOS 3.2 has only the three
;; routines, in $BFDC-$BFFF. They are inside the range of RWTS and the formatter, its relocator's last code range,
;; which ends here at `RwtsCodeLast`.

.if DOS32 = 0
;; The start of the relocator's range of the patches at the top of DOS, which runs to <TopPatchCodeLast>.
;; Also: SDP1 (DOS33, DOS31)
TopPatchCodeStart:
.if REVISION_B

;; The end of `BOOT 2`, reached from <Boot::StartDos> once DOS is in memory: resets the hardware, then goes back to
;; <Boot::StartDos::AfterReset>.
;;
;; At $BFC8 where DOS runs. It points output at the screen and, on a machine with a language card, writes zero to
;; the card's RAM at $E000 while leaving the ROM selected for reading. Without a card the write goes nowhere. The
;; revision B DOS also turns off the IIe's 80-column display (<TurnOff80Columns>). Not in DOS 3.2.
;; Also: RCPATCH (DOS33)
.proc ResetScreenAndCard
.assert MASTER || * = $BFC8, "ResetScreenAndCard is at $BFC8 where DOS runs."
    jsr SetScreen
    lda LanguageCardRomWriteBank2   ; two reads in a row: read the ROM, write the card's RAM
    lda LanguageCardRomWriteBank2
    lda #0
    sta RomBasicId                  ; the card's $E000 can't pass for a BASIC's first byte (see Commands::FindBasic)
    jsr TurnOff80Columns
    jmp Boot::StartDos::AfterReset
.endproc
.else

;; The end of `BOOT 2`, reached from <Boot::StartDos> once DOS is in memory: resets the hardware, then goes back to
;; <Boot::StartDos::AfterReset>.
;;
;; At $BFC8 where DOS runs. It points output at the screen and, on a machine with a language card, writes zero to
;; the card's RAM at $E000 while leaving the ROM selected for reading. Without a card the write goes nowhere. The
;; 1980 DOS fills the space the revision B DOS uses to turn off the 80-column display with zeros. Not in DOS 3.2.
;; Also: RCPATCH (DOS33)
.proc ResetScreenAndCard
.assert MASTER || * = $BFC8, "ResetScreenAndCard is at $BFC8 where DOS runs."
    jsr SetScreen
    lda LanguageCardRomWriteBank2   ; two reads in a row: read the ROM, write the card's RAM
    lda LanguageCardRomWriteBank2
    lda #0
    sta RomBasicId                  ; the card's $E000 can't pass for a BASIC's first byte (see Commands::FindBasic)
    jmp Boot::StartDos::AfterReset
.endproc

    ; The three bytes revision B's JSR takes.
    .res 3,0
.endif
.endif

;; Clears <InterpreterScratch> and <KeywordByte>, the B option's value, while the command scanner resets a command's
;; options.
;;
;; At $BFDC where DOS runs. <Scanner::ReadOptions> calls it.
;; In: A = the value to store; its one caller passes 0
;; Keeps: A, X, Y
;; Also: CLRBYTE (DOS33)
.proc ClearByteOption
.assert MASTER || * = $BFDC, "ClearByteOption is at $BFDC where DOS runs."
    sta InterpreterScratch
    sta KeywordByte
    sta KeywordByte+1
    rts
.endproc

;; Clears the input and output states, as <ClearStates> does, and <RunPending> too; DOS's error handler calls it.
;; Out: Y = 0
;; Keeps: A, X
;; Also: CLRSTS1 (DOS33)
.proc ClearAllStates
    jsr ClearStates
    sty RunPending
    rts
.endproc

;; Reports DISK FULL, closing the open files first: the file manager's code, which its allocation reaches when no
;; sector is free.
;;
;; It saves the current file's control block back to its buffer (<FileManager::SaveWorkArea>), returns to the stack
;; level at which the file manager was entered, closes the files (<Commands::CloseAll>), and records the stack level
;; again, since <Commands::CloseAll> used the file manager itself. <FileManager::Fail>, the file manager's error exit,
;; then leaves the file manager with <ERROR_DISK_FULL>.
;; Also: ERROR9X (DOS33)
.proc ReportDiskFull
    jsr FileManager::SaveWorkArea
    ldx FileManager::EntryStack
    txs
    jsr Commands::CloseAll
    tsx
    stx FileManager::EntryStack
    lda #ERROR_DISK_FULL
    jmp FileManager::Fail
.endproc

.if DOS32
;; The last byte of DOS: the end of the relocator's last code range, RWTS, the formatter and these patches, which
;; leaves this byte out.
;; Also: AEC2 (DOS33, DOS31)
RwtsCodeLast = *-1
.else
;; The last byte of the patches: the end of the relocator's range from <TopPatchCodeStart>, which leaves this byte
;; out.
;; Also: EDP1 (DOS33, DOS31)
TopPatchCodeLast = *-1
.endif

;; The address just after DOS: $C000 where DOS runs, $4000 in the master image.
;; Also: ENDOFDOS (DOS33)
DosEnd:
.assert * - DosStart = $2300, "DOS is 35 pages long, $9D00-$BFFF where it runs."
