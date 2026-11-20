# Assembly style

How Retrocore's assembly sources are written: the SDK's ROM sources, the samples, and any source maintained by
hand. The goal is source a person can read, debug and change: structure that shows how the code works, names that
say what things are, and documentation the tools can check.

[NativeAssembly.md](NativeAssembly.md) is the dialect and [DocComments.md](DocComments.md) the `;;` format. This
guide is how to use them. Every `asm` example here assembles and passes the editor's lint (`NativeAssemblyDocsTests`
checks both).

## A routine, in full

```asm
.cpu Mos6502

; Characters.

;; The Apple II's carriage return, with its high bit set.
RETURN = $8D

;; What a nibble's digit is added to when it is 10 to 15: the letter before A, as a digit.
LETTER_OFFSET = 'A' - '9' - 1

;; Prints a character through the output hook.
;; In: A = the character, with its high bit set
;; Also: COUT (A2RM78)
CharacterOut = $FDED

.org $0300

;; Prints a byte as two hexadecimal digits, then a carriage return.
;; In: A = the byte
;; Keeps: X, Y
.proc PrintHexLine
    jsr PrintHex
    lda #RETURN
    jmp CharacterOut
.endproc

;; Prints a byte as two hexadecimal digits.
;; In: A = the byte
;; Keeps: X, Y
.proc PrintHex
    pha

    ; The high nibble first.
    lsr a
    lsr a
    lsr a
    lsr a
    jsr PrintDigit

    ; Then the low one.
    pla
    and #$0F
    ; Falls into PrintDigit.
.endproc

;; Prints a nibble as a hexadecimal digit.
;; In: A = the nibble, 0 to 15
;; Keeps: X, Y
.proc PrintDigit
    ora #'0' | $80
    cmp #('9' | $80) + 1
    bcc Print

    ; 10 to 15 are A to F.
    adc #LETTER_OFFSET - 1
Print:
    jmp CharacterOut
.endproc
```

The rest of this guide is the rules this follows.

## Files

- **One subject per file**, a few hundred lines at most: the disk driver's sector code, the console, the heap. A
  program's main file holds its file comment, `.cpu`, its sections and the includes, in address order.
- **Shared definitions** have files of their own: constants, zero page, hardware, system tables. Definitions one
  file uses go at its top.
- **The file comment** is a `;;` block at the top that says what the file is. A source rebuilt from a binary says
  so as "assembles byte-identically to ...", naming the original, and gives the command or test that checks it.

## Structure

- **Each routine is a `.proc`**, so its labels are its own. Code elsewhere reaches one as `Proc::Label`.
- **A family is a `.scope`**: routines that share a tail, or that are entered part way, such as the entries of a
  floating-point package or the handlers of one table. A `.proc` with labeled entries can serve too. Choose what
  shows how the code works.
- **Falling into the next routine** is said in a step comment (`; Falls into PrintDigit.`), as above.

```asm
.cpu Mos6502
.org $0300

;; The routines that move the cursor, which share the code that stores its new column.
.scope Cursor

;; The column the cursor is in.
Column = $24

;; Moves the cursor one column left, or not at all at the left edge.
.proc Left
    lda Column
    beq Done
    sec
    sbc #1
    jmp Store
Done:
    rts
.endproc

;; Moves the cursor to the left edge.
.proc Home
    lda #0
    ; Falls into Store.
.endproc

;; Stores the cursor's column.
;; In: A = the column
.proc Store
    sta Column
    rts
.endproc

.endscope
```

## Labels and names

- **Labels go on their own line**, at column 0.
- **Every label has a name for what happens there**: `Loop`, `NextRow`, `NotFound`, `WriteProtected`. Never
  `ROUTINE_1`, and never a name that is only an address (`L_F8C2`, `SUB_D253`). A label nothing refers to is
  dropped.
- **Case:** PascalCase for routines, labels, variables and tables; UPPER_SNAKE_CASE for constants. Macros are
  PascalCase.
- **Name things after what the code does**, not after a guess, and not after a manual unless the code shows
  the manual's name fits.
- **Historical names are kept.** A name from a manual or listing that the definition no longer has goes in its
  `Also:` section with the documents that give it, cited from the [bibliography](Bibliography.md). Code written
  with the old name still assembles, and the editor offers the new one ([DocComments.md](DocComments.md),
  section 2.4).
- **Shared bytes get scoped names.** Where a routine uses a shared zero-page byte for its own purpose, it names
  it inside its scope, from the global name (`Divisor = Work1`), never from a number, with a `;;` comment.

## Constants

- **Every value that means something gets a constant:** unit and device numbers, card types, field offsets,
  control codes, sizes, counts, masks, timing values, soft-switch offsets.
- **Trivial values stay numbers:** 0 for clearing, 1 and 2 for stepping a pointer, shift counts that are plain
  arithmetic.
- **Write a constant as what it is made from** when that is clearer than its value: `LETTER_OFFSET = 'A' - '9' - 1`,
  `RECORD_SIZE = 2 + NAME_LENGTH`.
- **Groups** have a plain `;` heading, and each constant its own `;;` above it.

## Documentation

- **A `;;` block above every definition:** each `.proc`, `.scope`, macro, constant, variable and table. Never a
  trailing `;;`: it does not fit beside most definitions, so none has one.
- **A `;;` block documents only the definition below it.** A heading over a group is a plain `;` comment.
- **Routines:** a one-sentence summary, then `In:`, `Out:` and `Keeps:` as they apply. Entries are
  `name = meaning`; flags are words (`carry = set on an error`), never `C` or `Z`.
- **`Keeps:`** lists only what the routine really preserves, worked out from its code and everything it calls.
  The debugger checks it when the routine returns. Leave it out when nothing is kept.
- **Macros** have `Parameters:`.
- **Link every documented definition a comment names:** `<CharacterOut>`, `<Cursor::Store>`, or
  `<text at Target>` when the text differs (`<UNITCLEAR at UnitIo::Clear>`). The names before `=` in `In:` and
  `Out:` entries are not links.
- **Say what the code does, accurately.** Check every claim against the code. Leave out comments that restate a
  name, describe a definition that is not there, or hedge without saying what is uncertain and why.
- **Plain ASCII**, and lines of at most 120 columns.

## Layout

- **Indentation:** directives that open and close blocks (`.proc`, `.scope`, `.macro`), definitions and labels
  are at column 0; instructions and data are four spaces in. The blocks show the nesting, so a `.proc` inside a
  `.scope` is not indented further. Inside a macro, a `.repeat` or `.if` body is one more level in.
- **Mnemonics and registers are lowercase.**
- **Steps:** inside a routine, each logical step starts with a blank line and a short `;` heading at the code's
  indentation, as in `PrintHex` above.
- **Comments are indented like the code they describe.** A trailing `;` comment explains one line, such as a skip
  over the next instruction.

## Data

- **Tables are written with macros**, so each entry reads as what it is, with an `.assert` where an entry's
  position matters.
- **Text is `.byte "TEXT"`**, and storage that starts empty is `.res`.

```asm
.cpu Mos6502
.org $0300

;; One entry of <Commands>: a command's key and the routine that runs it.
;; Parameters:
;;   key = the key, with its high bit set
;;   routine = the routine
.macro Command key, routine
    .byte key
    .word routine
.endmacro

;; The commands, ending with a 0.
Commands:
    Command 'L' | $80, List
    Command 'R' | $80, Run
    .byte 0
.assert * - Commands = 2 * 3 + 1, "Two commands of 3 bytes, then the end."

;; Lists the program.
.proc List
    rts
.endproc

;; Runs the program.
.proc Run
    rts
.endproc
```

## Sources rebuilt from a binary

- **The bytes never change.** A constant has the value the literal had, a macro emits exactly the bytes it
  replaces, and a `.word` equals the bytes it stands for.
- **Check after every change:** assemble and compare, or run the source's digest test. A change that keeps the
  bytes but breaks the lint is not done either.
- **What the source finds out goes where it happens:** a bug in the original, a dead stretch, a table read past
  its end, in the comment of the code concerned.
