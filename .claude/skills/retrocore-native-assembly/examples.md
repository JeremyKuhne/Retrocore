# Native assembly idioms

Each `asm` block assembles on its own and passes the documentation lint (`NativeAssemblyDocsTests` checks both),
on a 6502 unless it selects another CPU. They follow [the style guide](../../../docs/AssemblyStyle.md).

## A documented Z80 routine calling the Model I ROM

```asm
.cpu Z80

;; Shows the character in A at the cursor, through the Model I ROM.
;; In: A = the character
DisplayCharacter = $0033

.org $7000

;; Prints a zero-terminated string through the ROM.
;; In: HL = the string
;; Out: HL = just past its zero
;; Uses: A
.proc PrintString
Loop:
    ld a,[hl]
    inc hl
    or a
    ret z
    call DisplayCharacter
    jr Loop
.endproc
```

## Indexed Z80 structures

```asm
.cpu Z80

;; A sprite on the screen.
;; Members:
;;   Column = its column
;;   Row = its row
;;   Image = the address of its image
.struct Sprite
    Column .byte
    Row .byte
    Image .word
.endstruct

;; Moves the sprite at IX one column right, and loads its row and image.
;; In: IX = the sprite
;; Out: A = its row, DE = its image
;; Keeps: HL
.proc MoveRight
    inc [ix+Sprite::Column]
    ld a,[ix+Sprite::Row]
    ld e,[ix+Sprite::Image]
    ld d,[ix+Sprite::Image+1]
    ret
.endproc
```

## A 6502 routine with local labels and a page-aligned table

```asm
.cpu Mos6502
.org $0800

;; Clears a page, by changing the page of its own store instruction.
;; In: A = the page's high byte
;; Keeps: Y
.proc ClearPage
    sta Store + 2
    ldx #0
    lda #0
Store:
    sta $FF00,x
    inx
    bne Store
    rts
.endproc

.align 256

;; Each byte's value times 3, modulo 256.
Triples:
.repeat 256, value
    .byte (value * 3) & $FF
.endrepeat
.assert <Triples = 0, "Triples starts a page."
```

## Tables built by macros

```asm
.cpu Z80

;; One entry of <Commands>: a command's key and the routine that runs it.
;; Parameters:
;;   key = the key
;;   routine = the routine
.macro Command key, routine
    .byte key
    .word routine
.endmacro

;; The commands, ending with a 0.
Commands:
    Command 'L', List
    Command 'R', Run
    .byte 0

;; Lists the program.
.proc List
    ret
.endproc

;; Runs the program.
.proc Run
    ret
.endproc
```

## Variants under a host-set symbol

```asm
.ifndef REVISION
;; The ROM revision to build, 1 or 2; the host may set it.
REVISION = 2
.endif
.assert (REVISION = 1) | (REVISION = 2), "REVISION is 1 or 2."

.if REVISION = 2
;; The banner shown at startup.
Banner:
    .byte "VERSION 2", 0
.else
;; The banner shown at startup.
Banner:
    .byte "VERSION 1", 0
.endif
```

## Text with bit 7 set (Apple II)

```asm
.repeat 128, character
.charmap character, character | $80
.endrepeat

;; The prompt, in the Apple II's high-bit text, ending with a return and a 0.
Message:
    .byte "READY", $8D, 0

;; A second prompt, written with .hiascii.
Ok:
    .hiascii "OK"
```

## A historical name

```asm
.cpu Mos6502
.org $0300

;; Prints a character through the output hook.
;; In: A = the character, with its high bit set
;; Also: COUT (A2RM78)
CharacterOut = $FDED

;; Prints a carriage return. A listing that calls <COUT> still assembles.
.proc PrintReturn
    lda #$8D
    jmp COUT
.endproc
```
