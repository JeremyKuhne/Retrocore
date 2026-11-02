# Native assembly idioms

Each `asm` block assembles on its own (`NativeAssemblyDocsTests` checks them), on a 6502 unless it selects
another CPU.

## A documented Z80 routine calling the Model I ROM

```asm
.cpu Z80

DISPLAY_CHAR = $0033                ;; shows the character in A at the cursor

.org $7000

;; Prints a zero-terminated string through the ROM.
;; In: HL = the string
;; Out: HL = just past its zero
;; Uses: A
PRINT:
        ld a,[hl]
        inc hl
        or a
        ret z
        call DISPLAY_CHAR
        jr PRINT
```

## Indexed Z80 structures

```asm
.cpu Z80

.struct Sprite
        column .byte
        row .byte
        image .word
.endstruct

;; Moves the sprite at IX one column right.
;; In: IX = the sprite
;; Keeps: HL
RIGHT:
        inc [ix+Sprite::column]
        ld a,[ix+Sprite::row]
        ld e,[ix+Sprite::image]
        ld d,[ix+Sprite::image+1]
        ret
```

## A 6502 routine with cheap locals and a page-aligned table

```asm
.cpu Mos6502

        .org $0800

;; Clears a page.
;; In: A = the page's high byte
;; Keeps: Y
CLEAR:
        sta @pointer+1
        ldx #0
        lda #0
@loop:  sta $FF00,x
@pointer = @loop + 1
        inx
        bne @loop
        rts

        .align 256
TABLE:
.repeat 256, I
        .byte (I * 3) & $FF
.endrepeat
        .assert <TABLE = 0, "TABLE starts a page."
```

## Tables built by macros

```asm
.cpu Z80

;; A command: its key and its handler.
.macro COMMAND key, handler
        .byte key
        .word handler
.endmacro

COMMANDS:
        COMMAND 'L', LIST
        COMMAND 'R', RUN
        .byte 0                     ; the end of the table

LIST:   ret
RUN:    ret
```

## Variants under a host-set symbol

```asm
.ifndef REVISION
REVISION = 2
.endif
.assert (REVISION = 1) | (REVISION = 2), "REVISION is 1 or 2."

.if REVISION = 2
BANNER: .byte "VERSION 2", 0
.else
BANNER: .byte "VERSION 1", 0
.endif
```

## Text with bit 7 set (Apple II)

```asm
.repeat 128, character
.charmap character, character | $80
.endrepeat

MESSAGE: .byte "READY", $8D, 0
         .hiascii "OK"
```
