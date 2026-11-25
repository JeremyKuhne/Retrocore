; retrocore: style=strict
;; Integer BASIC: the cold start, Control-C, HIMEM:, LOMEM:, LOAD, SAVE, POP and TRACE
;;
;; The cold start, which finds the top of RAM; the check for Control-C and TRACE before each line; HIMEM: and LOMEM:,
;; which move the ends of BASIC's memory; LOAD and SAVE, which move a program to and from the cassette through the
;; Monitor; and POP, TRACE and NOTRACE. It follows Statements.asm, at $F000.
;;
;; A program on cassette is two records, each written by the Monitor's <WriteCassette> with its own header tone and
;; checksum: first the program's length (2 bytes, from <Accumulator>), then the program itself, which LOAD reads into
;; the top of memory, ending at HIMEM.
;;
;; Part of IntegerBasic.asm.

;; The length of the header tone before the program's record, in 256 half cycles; the Monitor's <WriteCassette> writes
;; $40 before the length's.
PROGRAM_HEADER_LENGTH = $1A

;; What a running program shows as it runs: each line's number in TRACE mode, and each assignment to a variable marked
;; with DSP.
.scope Display

;; The TRACE flag: bit 7 is set in TRACE mode, when each line's number is printed as it runs.
;;
;; It is the first byte of the noun stack's high bytes of numbers (<NounStackNumberHigh>), the noun stack's entry 0,
;; which only an expression that fills the noun stack reaches. <Statements::Trace> sets it, and <Statements::NoTrace>
;; and the cold start clear it.
Tracing = NounStackNumberHigh

.endscope

;; The cold start: turns TRACE off, sets LOMEM to $0800, finds the top of RAM for HIMEM, and erases the program
;; (<NEW>).
;;
;; It tests each page from $0900 up by inverting its first byte and inverting it back; the first page where a byte
;; does not read back as written is past the end of RAM.
;; See: <BASIC>
;; Also: COLD (IBSM)
.proc ColdStart
    ldy #0
    sty Display::Tracing
    sty LowMemory
    sty HighMemory
    lda #VARIABLES_PAGE
    sta LowMemory+1
    sta HighMemory+1

    ; Try the next page: invert its first byte, then restore it, checking each.
NextPage:
    inc HighMemory+1
    lda (HighMemory),y
    eor #$FF
    sta (HighMemory),y
    cmp (HighMemory),y
    bne ToNew
    eor #$FF
    sta (HighMemory),y
    cmp (HighMemory),y
    beq NextPage

ToNew:
    jmp NEW
.endproc

;; Control-C, which stops a running program before its next line, and the place CON continues from.
.scope Break

;; Where Control-C stopped the program, for CON: the address of the token to run next, low byte.
;;
;; This and the three bytes below are the noun stack's entries 0 and 1, which only a statement that nearly fills the
;; noun stack reaches.
StoppedToken = NounStackLow

;; The address of the token to run next, high byte.
StoppedTokenHigh = NounStackLow + 1

;; The address of the line Control-C stopped, low byte: the noun stack's first high byte.
StoppedLine = NounStackHigh

;; The address of the line Control-C stopped, high byte.
StoppedLineHigh = NounStackHigh + 1

;; Not Control-C: goes on to print the line number in TRACE mode (<Display::TraceLine>).
.proc ToTraceLine
    jmp Display::TraceLine
.endproc

;; Checks for Control-C with the place to stop in X (low) and A (high), then runs from that token (<GETNEXTXA>);
;; nothing in the ROM reaches it.
;; In: X = the token address, low byte, A = its high byte
;; Also: CHKBRKRUN (UNKN)
.proc CheckThenRun
    jsr Check::FromToken
    jmp GETNEXTXA
.endproc

;; Before each line: stops the program if Control-C was typed, otherwise prints the line number in TRACE mode
;; (<Display::TraceLine>).
;;
;; Stopping takes the key, saves the token address in <StoppedToken> and the line's (<CurrentLine>) in
;; <StoppedLine>, for CON (<Statements::Con>), and prints STOPPED AT and the line's number (<STOPPED_AT>).
;; Entry:
;;   FromToken = with the token address in X (low) and A (high) instead of <TokenPointer>
;; Also: CHKBREAK (UNKN)
.proc Check
    ldx TokenPointer
    lda TokenPointer+1

;; With the token address in X (low) and A (high) instead of <TokenPointer>.
;; Also: CHKBREAKAT (UNKN)
FromToken:
    ldy Keyboard
    cpy #CONTROL_C | $80
    bne ToTraceLine

    ; Take the key and keep the place, then stop.
    bit KeyboardStrobe
    stx StoppedToken
    sta StoppedTokenHigh
    lda CurrentLine
    sta StoppedLine
    lda CurrentLine+1
    sta StoppedLineHigh
    jmp STOPPED_AT
.endproc

    ; Unused bytes.
    .res 2, $FF

.endscope

; HIMEM: and LOMEM:.
.scope Statements continued

;; HIMEM: (token $10): moves the top of BASIC's memory, and the program with it.
;;
;; <Auxiliary> is the distance from the old HIMEM down to the new one. When the new HIMEM is lower, the program moves
;; down, from its first byte up, and must stay above the variables. Whether the new HIMEM is RAM is not checked.
;;
;; When the new HIMEM is higher, the program is to move up, from its last byte down (CopyUp), but the test after each
;; step is the wrong way round: it copies only while the source is below <ProgramStart>. With a program in memory it
;; stops after at most one byte, and the program is lost: <ProgramStart> moves up by the distance, over bytes that
;; were never moved. With no program (<ProgramStart> = HIMEM) it copies everything from $0000 to the old HIMEM up by
;; the distance, over the screen and the variables.
;; In: X = the noun stack, its top entry the new HIMEM
;; Out: X = the noun stack, popped
;; Errors: MEM FULL if the program would reach the variables
;; Entry:
;;   ToMemoryFullError = the MEM FULL error; <LoMem> and <Load> branch here
;; Also: VHIMEM (IBSM)
.proc HiMem
    ; Pointer2 = the new HIMEM, and Auxiliary = the old HIMEM less the new one. X = $FE, then $FF: the low bytes,
    ; then the high.
    jsr GET16BIT
    stx SavedX
    ldx #$FE
    sec
Distance:
    lda Accumulator+2,x
    sta Pointer2+2,x
    lda HighMemory+2,x
    sbc Accumulator+2,x
    sta Auxiliary+2,x
    inx
    bne Distance
    bcc Step

    ; Lower: Pointer3 = the program's start, and Pointer2 = its new start. X = $FF, then 0.
    dex
NewStart:
    lda ProgramStart+1,x
    sta Pointer3+1,x
    sbc Auxiliary+1,x
    sta Pointer2+1,x
    inx
    beq NewStart

    ; The new start must stay above the variables.
    bcc ToMemoryFullError
    lda VariablesEnd
    cmp Pointer2
    lda VariablesEnd+1
    sbc Pointer2+1
    bcc CheckCopyDown

;; The MEM FULL error.
;; Also: JmpMEMFULL (IBSM)
ToMemoryFullError:
    jmp MEMFULL

    ; Move the program down: copy from Pointer3, the old start, to Pointer2, the new one.
CopyDown:
    lda (Pointer3),y
    sta (Pointer2),y
    inc Pointer2
    bne StepSource
    inc Pointer2+1
StepSource:
    inc Pointer3
    bne CheckCopyDown
    inc Pointer3+1

    ; Until Pointer3 reaches the old HIMEM.
CheckCopyDown:
    lda Pointer3
    cmp HighMemory
    lda Pointer3+1
    sbc HighMemory+1
    bcc CopyDown

;; Sets <HighMemory> to <Pointer2>, the new HIMEM, and <ProgramStart> to its old value less <Auxiliary>, the
;; distance moved.
;; Also: SETNEWHIMEM (UNKN)
SetEnds:
    ldx #$FE
SetNextByte:
    lda Pointer2+2,x
    sta HighMemory+2,x
    lda ProgramStart+2,x
    sbc Auxiliary+2,x
    sta ProgramStart+2,x
    inx
    bne SetNextByte
    ldx SavedX
    rts

;; Moves the program up, a byte at a time from <HighMemory> to <Accumulator>, both stepping down from the old and the
;; new HIMEM (<Step> steps first), while HIMEM is below <ProgramStart>: the test that should end the copy.
;;
;; The test's low byte is <HighMemory>'s before the step, its high byte the one after.
;; Also: SHIFTPROGUP (UNKN)
CopyUp:
    lda (HighMemory),y
    sta (Accumulator),y

;; Steps both pointers down, then tests.
;; Also: SHIFTUPSTEP (UNKN)
Step:
    lda Accumulator
    bne StepTarget
    dec Accumulator+1
StepTarget:
    dec Accumulator
    lda HighMemory
    bne StepHighMemory
    dec HighMemory+1
StepHighMemory:
    dec HighMemory
    cmp ProgramStart
    lda HighMemory+1
    sbc ProgramStart+1
    bcc CopyUp
    bcs SetEnds                     ; always
.endproc

;; LOMEM: (token $11): moves the bottom of the variables, and discards them (<CLR>).
;;
;; The new LOMEM must be below the program. The low byte is compared with $CA, the address of <ProgramStart>, rather
;; than with its low byte, so only the high bytes count reliably. Nothing keeps the new LOMEM out of page zero or
;; the screen.
;; In: X = the noun stack, its top entry the new LOMEM
;; Errors: MEM FULL if it is not below the program
;; Entry:
;;   MemoryFullIfCarry = the MEM FULL error if the carry is set; <Load> branches here
;; Also: VLOMEM (IBSM)
.proc LoMem
    jsr GET16BIT
    ldy Accumulator
    cpy #ProgramStart               ; the constant $CA, not the contents of ProgramStart
    lda Accumulator+1
    sbc ProgramStart+1

;; The MEM FULL error if the carry is set.
;; Also: BcsJmpMEMFULL (IBSM)
MemoryFullIfCarry:
    bcs HiMem::ToMemoryFullError
    sty LowMemory
    lda Accumulator+1
    sta LowMemory+1
    jmp CLR
.endproc

;; LOAD (token $04): reads a program from the cassette into the top of memory, below HIMEM.
;;
;; At $F0DF, which Programmer's Aid calls.
;;
;; The first record is the program's length. If it would not fit above the variables it is a MEM FULL error; if it
;; is 0 LOAD only beeps. Otherwise <ProgramStart> moves down to make room and the second record is read into the
;; program's place. The variables are kept.
;; Keeps: X
;; Errors: MEM FULL
;; See: <Save>, <ReadCassette>
;; Also: LOAD (IBSM)
.proc Load
.assert * = $F0DF, "Statements::Load must stay at $F0DF, where Programmer's Aid calls it."
    stx SavedX
    jsr Cassette::PointAtLength
    jsr ReadCassette

    ; Auxiliary = HIMEM less the length: the new start. X = $FF, then 0, and 1 after.
    ldx #$FF
    sec
NewStart:
    lda HighMemory+1,x
    sbc Accumulator+1,x
    sta Auxiliary+1,x
    inx
    beq NewStart
    bcc HiMem::ToMemoryFullError

    ; It must stay above the variables.
    lda VariablesEnd
    cmp Auxiliary
    lda VariablesEnd+1
    sbc Auxiliary+1
    bcs LoMem::MemoryFullIfCarry

    ; A length of 0 only beeps.
    lda Accumulator
    bne ReadProgram
    lda Accumulator+1
    beq Empty

    ; Read the program into its place, from the new start to HIMEM.
ReadProgram:
    lda Auxiliary
    sta ProgramStart
    lda Auxiliary+1
    sta ProgramStart+1
    jsr Cassette::PointAtProgram
    jsr ReadCassette

Done:
    ldx SavedX
    rts

Empty:
    jsr Beep
    jmp Done
.endproc

.endscope

;; The routines that point the Monitor's cassette routines at what LOAD and SAVE read and write.
.scope Cassette

;; Points the cassette routines at <Accumulator>: <Address1> = $00CE and <Address2> = $00CF, the program's length.
;; Out: Y = 0
;; Keeps: A, X
;; Also: SETHDR (IBSM)
.proc PointAtLength
    ldy #<Accumulator
    sty Address1
    iny
    sty Address2
    ldy #0
    sty Address1High
    sty Address2High
    rts
.endproc

;; Points the cassette routines at the program: <Address1> = <ProgramStart> and <Address2> = <HighMemory> - 1.
;; In: X = 1
;; Out: X = $FF
;; Uses: A, Y
;; Also: SETPRG (IBSM)
.proc PointAtProgram
    lda ProgramStart,x
    sta Address1,x
    ldy HighMemory,x
    sty Address2,x
    dex
    bpl PointAtProgram
    lda Address2
    bne StepLow
    dec Address2High

StepLow:
    dec Address2
    rts
.endproc

;; Saves X in <SavedX>, then falls into SAVE (<Statements::Save>); nothing in the ROM reaches it.
;; Also: SAVEKEEPX (UNKN)
.proc SaveKeepingX
    stx SavedX
    ; Falls into Statements::Save.
.endproc

.endscope

; SAVE.
.scope Statements continued

;; SAVE (token $05): writes the program to the cassette: its length, then its bytes.
;;
;; Santa-Maria's listing calls it SAVE. The program's record gets a shorter header tone than the length's: $1A
;; against the Monitor's usual $40. SAVE ends by loading X from <SavedX>, which only <Cassette::SaveKeepingX>
;; sets, so it returns with whatever X a routine before it saved there.
;; See: <Load>, <WriteCassette>, <WriteCassetteWithHeader>
;; Also: VSAVE (UNKN)
.proc Save
    ; Accumulator = HIMEM - ProgramStart, the length. X = $FF, then 0.
    sec
    ldx #$FF
Length:
    lda HighMemory+1,x
    sbc ProgramStart+1,x
    sta Accumulator+1,x
    inx
    beq Length

    ; Write the length, then the program.
    jsr Cassette::PointAtLength
    jsr WriteCassette
    ldx #1
    jsr Cassette::PointAtProgram
    lda #PROGRAM_HEADER_LENGTH
    jsr WriteCassetteWithHeader
    ldx SavedX
    rts
.endproc

.endscope

;; Prints the message at offset Y, then sounds the bell.
;; In: Y = the message's offset from <ErrMsg00>
;; Also: PRTERR (IBSM)
.proc PrintMessageThenBeep
    jsr ERRORMESS
    jmp Beep
.endproc

; POP, TRACE and NOTRACE.
.scope Statements continued

;; POP (token $77): forgets the last GOSUB, so its RETURN will not come back to it.
;;
;; With no GOSUB active it goes to RETURN, for the BAD RETURN error.
;; Errors: BAD RETURN
;; See: <GOSUB>, <RETURN>
;; Also: POP (IBSM)
.proc Pop
    lda GoSubIndex
    bne Drop
    jmp RETURN

Drop:
    dec GoSubIndex
    rts
.endproc

;; TRACE (token $7D): turns TRACE mode on: the run loop prints each line's number as it runs it.
;; Out: Display::Tracing = $FF
;; See: <Display::TraceLine>
;; Also: TRACE (IBSM)
.proc Trace
    lda #$FF
    sta Display::Tracing
    rts
.endproc

;; NOTRACE (token $7A): turns TRACE mode off.
;; Out: Display::Tracing = bit 7 clear
;; Also: NOTRACE (IBSM)
.proc NoTrace
    lsr Display::Tracing
    rts
.endproc

.endscope

; TRACE's line numbers.
.scope Display continued

;; In TRACE mode, prints # and the number of the line at <CurrentLine>, then a blank.
;; Uses: A, X, Y
;; Entry:
;;   PrintLineNumber = prints them whatever the mode
;; Also: TRACELINE (UNKN)
.proc TraceLine
    bit Tracing
    bpl GetLineAddress::Return

;; Prints # and the line's number, then a blank, whatever the mode.
;; Also: PRLINENUM (UNKN)
PrintLineNumber:
    lda #'#'
    jsr CharacterOut
    ldy #1
    lda (CurrentLine),y
    tax
    iny
    lda (CurrentLine),y
    jsr PRDEC
    lda #BLANK | $80
    jmp CharacterOut
.endproc

;; Loads the address of the line running, <CurrentLine>, into A (low) and Y (high); nothing in the ROM reaches it.
;; Out: A = the line's address, low byte, Y = its high byte
;; Keeps: X
;; Entry:
;;   Return = returns; <TraceLine> branches here when TRACE is off
;; Also: GETLINEADR (UNKN)
.proc GetLineAddress
    lda CurrentLine
    ldy CurrentLine+1

Return:
    rts
.endproc

.endscope
