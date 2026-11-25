;; THE KEYBOARD HANDLER ($F6E2-$F778)
;;
;; The keyboard handler's (K:) get, which the screen editor also reads its keys with: it waits for the keyboard
;; interrupt's key code in CH, clicks, and turns the code into ATASCII through the keyboard definition table,
;; <KEYBOARD_DEFINITIONS>, applying caps lock and the Atari key's inverse video and handling the keys that change them.

; The keyboard definition table's special values, for keys that type nothing.


KEY_CONTROL_SHIFT = KEY_CONTROL | KEY_SHIFT ;; the key codes with CTRL and SHIFT both held, which type nothing
KEY_UNUSED = $03                    ;; a key code no key gives, whose table entry is KEYDEF_NONE

;; The keyboard handler's (K:) get: waits for a key and returns its ATASCII character.
;;
;; The keys that type nothing (the Atari key, CAPS/LOWR and the unused codes) take effect and are discarded, and
;; the next key is waited for. With caps lock on, an unshifted letter is looked up again as SHIFT or CTRL with it.
;; Characters other than the control codes are inverted while inverse video is on. A forced read (ICAX1Z bit 0)
;; returns EOL at once, without a key, which is how the screen editor reads the screen without waiting for RETURN.
;; In: ICAX1Z = the open mode
;; Out: A = ATACHR = the character, Y = the status, DSTAT = SUCCES
;; Errors: Y = BRKABT, A = EOL for BREAK; Y = EOFERR, A = EOL for CTRL+3
;; Uses: X, CH, HOLDCH, INVFLG, SHFLOK, BRKKEY
;; See: <KEYBOARD_IRQ>, <KEYBOARD_DEFINITIONS>
KEYBOARD_GET:
    lda ICAX1Z
    lsr A
    bcs KEYBOARD_GET_RETURN         ; a forced read
    lda #BRKABT
    ldx BRKKEY
    beq KEYBOARD_GET_ERROR
    lda CH
    cmp #KEY_NONE
    beq KEYBOARD_GET
    sta HOLDCH
    ldx #KEY_NONE
    stx CH
    jsr SCREEN_CLICK                      ; the click
KEYBOARD_GET_LOOKUP:
    tax
    cpx #KEY_CONTROL_SHIFT
    bcc KEYBOARD_GET_CODE
    ldx #KEY_UNUSED
KEYBOARD_GET_CODE:
    lda KEYBOARD_DEFINITIONS,x
    sta ATACHR
    cmp #KEYDEF_NONE
    beq KEYBOARD_GET_AGAIN
    cmp #KEYDEF_INVERSE
    bne KEYBOARD_GET_LOWER
    lda INVFLG
    eor #DISPLAY_INVERSE
    sta INVFLG
    jmp KEYBOARD_GET_AGAIN
KEYBOARD_GET_LOWER:
    cmp #KEYDEF_LOWER
    bne KEYBOARD_GET_UPPER
    lda #$00
    sta SHFLOK
    beq KEYBOARD_GET_AGAIN          ; always
KEYBOARD_GET_UPPER:
    cmp #KEYDEF_UPPER
    bne KEYBOARD_GET_CONTROL
    lda #KEY_SHIFT
    sta SHFLOK
    bne KEYBOARD_GET_AGAIN          ; always
KEYBOARD_GET_CONTROL:
    cmp #KEYDEF_CONTROL
    bne KEYBOARD_GET_EOF
    lda #KEY_CONTROL
    sta SHFLOK
    bne KEYBOARD_GET_AGAIN          ; always
KEYBOARD_GET_EOF:
    cmp #KEYDEF_END_OF_FILE
    bne KEYBOARD_GET_CAPS
    lda #EOFERR
KEYBOARD_GET_ERROR:
    sta DSTAT
    sta BRKKEY                      ; nonzero again: BREAK is taken; for CTRL+3 just nonzero
KEYBOARD_GET_RETURN:
    lda #EOL
    bne KEYBOARD_GET_STORE          ; always
KEYBOARD_GET_CAPS:
    lda HOLDCH
    cmp #KEY_SHIFT
    bcs KEYBOARD_GET_INVERSE        ; SHIFT or CTRL held
    lda ATACHR
    cmp #'a'
    bcc KEYBOARD_GET_INVERSE
    cmp #'z'+1
    bcs KEYBOARD_GET_INVERSE
    lda SHFLOK
    beq KEYBOARD_GET_INVERSE
    ora HOLDCH                      ; the key with SHIFT or CTRL
    jmp KEYBOARD_GET_LOOKUP
KEYBOARD_GET_INVERSE:
    jsr SCREEN_FIND_CONTROL_CODE
    beq KEYBOARD_GET_DONE           ; a control code
    lda ATACHR
    eor INVFLG
KEYBOARD_GET_STORE:
    sta ATACHR
KEYBOARD_GET_DONE:
    jmp DISPLAY_RETURN
