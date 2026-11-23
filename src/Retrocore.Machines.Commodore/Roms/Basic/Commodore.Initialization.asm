; COMMODORE BASIC: COLD START AND RAM DISCOVERY

;; Emits the workspace setup at the start of cold initialization.
;; Parameters: markDirect = 1 to mark the current line as direct,
;;             lineWidth = 1 to initialize the terminal width and comma zones,
;;             delayedSize = 1 to set descriptor size after clearing the flags,
;;             localPosition = 1 to initialize BASIC's terminal position,
;;             bufferPage = zero for a page-zero buffer, or the nonzero buffer page,
;;             diskStatus = 1 to initialize the disk-status descriptor instead of the output-wait flag,
;;             earlyBufferSetup = 1 to restore the page-zero buffer's comma and print a carriage return
.macro COMMODORE_INITIALIZE markDirect, lineWidth, delayedSize, localPosition, bufferPage, diskStatus, earlyBufferSetup
    .assert markDirect = 0 || markDirect = 1, "markDirect is 0 or 1."
    .assert lineWidth = 0 || lineWidth = 1, "lineWidth is 0 or 1."
    .assert delayedSize = 0 || delayedSize = 1, "delayedSize is 0 or 1."
    .assert localPosition = 0 || localPosition = 1, "localPosition is 0 or 1."
    .assert bufferPage >= 0 && bufferPage <= 255, "bufferPage must fit in a byte."
    .assert diskStatus = 0 || diskStatus = 1, "diskStatus is 0 or 1."
    .assert earlyBufferSetup = 0 || earlyBufferSetup = 1, "earlyBufferSetup is 0 or 1."

;; Cold-starts BASIC, sets up its RAM vectors and copies the character-reader template.
;;
;; The early ROM uses the whole stack and marks the line number as direct. The later ROMs load their
;; configured stack top. The following memory probe establishes BASIC's limit.
INIT:
    ldx #<(STACK_END-$100)
.if markDirect
    stx CURLIN+1
.endif
    txs
    lda #$4C
    sta JMPER
    sta USRPOK
    lda #<FCERR
    ldy #>FCERR
    sta USRPOK+1
    sty USRPOK+2
.if lineWidth
    lda #LINLEN
    sta LINWID
    lda #NCMPOS
    sta NCMWID
.endif
    ldx #<(RNDX+4-CHRGET)
MOVCHG:
    lda INITAT-1,x
    sta CHRGET-1,x
    dex
    bne MOVCHG
.if .not delayedSize
    lda #STRSIZ
    sta FOUR6
.endif
    txa
    sta BITS
    sta CHANNL
    sta LASTPT+1
.if NULL_COMMAND
    sta NULCNT
.endif
.if localPosition
    sta TRMPOS
.endif
.if diskStatus
    sta DSDESC
    pha
.else
    pha
    sta CNTWFL
.endif
.if delayedSize
    lda #STRSIZ
    sta FOUR6
.endif
.if earlyBufferSetup
    lda #','
    sta LINNUM+1
    jsr CRDO
.endif
.if bufferPage
    inx
    stx BUF-3
    stx BUF-4
.endif
    ldx #TEMPST
    stx TEMPPT
.endmacro

;; Emits the RAM probe and saves the discovered upper memory limit.
;; Parameters: explicitZero = 1 to load zero before setting the initial RAM address,
;;             explicitIndex = 1 to load zero into Y instead of copying A,
;;             saveProgramStart = 1 to initialize <TXTTAB> before probing,
;;             diskFallback = 1 to retain BASIC 4's unreachable ROM-location fallback,
;;             screenStop = 1 for the early screen-boundary check,
;;             probeByte = first value written when testing RAM
.macro COMMODORE_MEMORY_PROBE explicitZero, explicitIndex, saveProgramStart, diskFallback, screenStop, probeByte
    .assert explicitZero = 0 || explicitZero = 1, "explicitZero is 0 or 1."
    .assert explicitIndex = 0 || explicitIndex = 1, "explicitIndex is 0 or 1."
    .assert saveProgramStart = 0 || saveProgramStart = 1, "saveProgramStart is 0 or 1."
    .assert diskFallback = 0 || diskFallback = 1, "diskFallback is 0 or 1."
    .assert screenStop = 0 || screenStop = 1, "screenStop is 0 or 1."
    .assert probeByte >= 0 && probeByte <= 255, "probeByte must fit in a byte."

.if explicitZero
    lda #$00
.endif
    ldy #>RAMLOC
.if saveProgramStart
    sta TXTTAB
    sty TXTTAB+1
.endif
    sta LINNUM
    sty LINNUM+1
.if explicitIndex
    ldy #$00
.else
    tay
.endif
.if diskFallback
    lda #$80
    bne LOOPMM
    lda #<ROMLOC
    ldy #>ROMLOC
    jmp USEDEF
.endif

;; Probes successive RAM addresses until a write fails or the screen boundary is reached.
LOOPMM:
    inc LINNUM
    bne LOOPM1
    inc LINNUM+1
.if screenStop
    lda LINNUM+1
    cmp #$80
    beq USEDEC
.else
    bmi USEDEC
.endif
LOOPM1:
    lda #probeByte
    sta (LINNUM),y
    cmp (LINNUM),y
    bne USEDEC
    asl a
    sta (LINNUM),y
    cmp (LINNUM),y
    beq LOOPMM
USEDEC:
    lda LINNUM
    ldy LINNUM+1
USEDEF:
    sta MEMSIZ
    sty MEMSIZ+1
    sta FRETOP
    sty FRETOP+1
.endmacro

;; Emits program initialization and the sign-on.
;; Parameters: reloadProgramStart = 1 to load the initial program address again,
;;             carryProgramStart = 1 to carry an increment into its high byte,
;;             checkRoom = 1 to call <CheckFreeMemory>,
;;             carriageFirst = 1 to print a carriage return instead of a separate sign-on,
;;             banner = sign-on string when carriageFirst is 0
.macro COMMODORE_START_PROGRAM reloadProgramStart, carryProgramStart, checkRoom, carriageFirst, banner
    .assert reloadProgramStart = 0 || reloadProgramStart = 1, "reloadProgramStart is 0 or 1."
    .assert carryProgramStart = 0 || carryProgramStart = 1, "carryProgramStart is 0 or 1."
    .assert checkRoom = 0 || checkRoom = 1, "checkRoom is 0 or 1."
    .assert carriageFirst = 0 || carriageFirst = 1, "carriageFirst is 0 or 1."
    .assert carryProgramStart = 0 || checkRoom = 1, "The carry branch needs the room-check entry."

TTYW:
ASKAGN:
.if reloadProgramStart
    ldx #<RAMLOC
    ldy #>RAMLOC
    stx TXTTAB
    sty TXTTAB+1
.endif
    ldy #$00
    tya
    sta (TXTTAB),y
    inc TXTTAB
.if carryProgramStart
    bne QROOM
    inc TXTTAB+1
.endif
.if checkRoom
QROOM:
    lda TXTTAB
    ldy TXTTAB+1
    jsr REASON
.endif
.if carriageFirst
    jsr CRDO
.else
    lda #<banner
    ldy #>banner
    jsr STROUT
.endif
    lda MEMSIZ
    sec
    sbc TXTTAB
    tax
    lda MEMSIZ+1
    sbc TXTTAB+1
    jsr LINPRT
    lda #<WORDS
    ldy #>WORDS
    jsr STROUT
    jsr SCRTCH
    jmp READY
.endmacro

;; Emits the startup messages after initialization.
;; Parameters: earlyBanner = 1 for BASIC 1's home-and-cursor-down sign-on
.macro COMMODORE_START_MESSAGES earlyBanner
    .assert earlyBanner = 0 || earlyBanner = 1, "earlyBanner is 0 or 1."

;; Free-memory suffix and, in the early ROM, the sign-on following it.
WORDS:
    .byte " BYTES FREE"
.if earlyBanner
    .byte $13, "*** COMMODORE BASIC ***", $11, $11, $11, $00
.else
    .byte $0D, $00

;; Sign-on printed before the free-memory count.
FREMES:
    .byte "### COMMODORE BASIC ###", $0D, $0D, $00
.endif
.endmacro
