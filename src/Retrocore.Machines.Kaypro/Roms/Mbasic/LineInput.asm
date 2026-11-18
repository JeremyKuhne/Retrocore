;; MBASIC 5.21: THE LINE EDITOR (INLIN)
;;
;; Reads a line typed at the console into the input buffer, BUF, for direct mode, INPUT, LINE INPUT and EDIT's
;; first line. It is MBASIC's own CP/M code, which GW-BASIC replaced with its screen editor, so most of its names
;; are descriptive; QINLIN, INLIN, SINLIN, SCNSEM and FININL are Microsoft's. In order:
;;
;; - QINLIN prints "? " and reads a line, for INPUT; INLIN reads one; SINLIN is INPUT's entry, which keeps the
;;   cursor on the line after INPUT; (SCNSEM notes the semicolon).
;; - The keys: a rubout echoes the characters it deletes between backslashes, backspace erases one, Control-U
;;   and Control-X cancel the line, Control-R retypes it, Control-A at the start of a line edits the previous
;;   line with EDIT's commands (INLED, Console.asm), and Control-C ends the line with carry set. A line feed is
;;   stored and starts a new screen line. Past 255 characters the bell rings, or, loading a program from a file,
;;   Line buffer overflow is the error.
;;
;; Runs at $4B0D-$4C57. The characters come from INCHR and are echoed through OUTDO (Console.asm).

;; Prints "? " and reads a line from the console.
;;
;; Out:   HL = the input buffer, less one, carry = set if Control-C was typed
;; See:   <INLIN>
QINLIN:
    LD A,$3F
    CALL OUTDO
    LD A,$20
    CALL OUTDO
    JP INLIN

;; Reads the next character of the line INLIN is reading and handles it.
;;
;; A Control-A ends the line and edits it, as EDIT does a program line; anything else goes to INLCHR.
;;
;; In:    HL = the next place in the buffer, B = the count of characters in it, plus one
INLINC:
    CALL INCHR
    CP $01                          ; Control-A
    JP NZ,INLCHR
    LD [HL],$00                     ; end the line, to edit it
    JP INLEDT
INLIN_1:
    LD [HL],B                       ; rubbed out to the start: B = 0 ends the line, and it starts again

;; Reads a line from the console into the input buffer, ending it with a zero.
;;
;; Remarks: the characters are echoed as typed. A rubout echoes the characters it deletes between
;; backslashes; backspace erases one; Control-U and Control-X cancel the line; Control-R retypes it;
;; Control-A at the start edits the previous line; Control-C ends with carry set. A line feed is stored and
;; starts a new screen line. Past 255 characters it rings the bell, or, loading a program from a file, gives
;; Line buffer overflow for that line.
;;
;; Out:   HL = the input buffer, less one, carry = set if Control-C was typed
;; Errors: Line buffer overflow (23)
;; Entry: SINLIN = INPUT's, keeping SCNSEM's flag to leave the cursor after the line
INLIN:
    XOR A
    LD [CHARC],A                    ; no typed-ahead character
    XOR A
    LD [TEMPA],A                    ; echo the carriage return
SINLIN:
    CALL INCHR
    CP $01                          ; Control-A: edit the buffer's line
    JP NZ,INLNEW
INLEDT:
    CALL CRDO
    LD HL,$FFFF                     ; a direct line, shown with "!"
    JP INLED                        ; edit the buffer, as EDIT
RUBOUT:
    LD A,[RUBSW]                    ; already echoing rubouts?
    OR A
    LD A,$5C                        ; the backslash that opens them
    LD [RUBSW],A
    JP NZ,RUBOUT_1
    DEC B
    JP Z,INLIN_1                    ; an empty line
    CALL OUTDO
    INC B
RUBOUT_1:
    DEC B
    DEC HL
    JP Z,INLCAN                     ; rubbed out to the start
    LD A,[HL]                       ; echo the deleted character
    CALL OUTDO
    JP INLINC
    DEC B                           ; never reached
ECHOBS:
    DEC HL                          ; the backspace's character is gone
    CALL OUTDO
    JP NZ,INLINC
INLCAN:
    CALL OUTDO                      ; the cancel's mark
    CALL CRDO
INLNEW:
    LD HL,BUF                       ; an empty buffer
    LD B,$01
    PUSH AF
    XOR A
    LD [RUBSW],A                    ; not echoing rubouts
    POP AF

;; Handles a character typed into the line INLIN is reading.
;;
;; In:    A = the character, HL = the next place in the buffer, B = the count of characters in it, plus one
INLCHR:
    LD C,A
    CP $7F                          ; rubout
    JP Z,RUBOUT
    LD A,[RUBSW]
    OR A
    JP Z,INLIN_2
    LD A,$5C                        ; close the rubouts' echo
    CALL OUTDO
    XOR A
    LD [RUBSW],A
INLIN_2:
    LD A,C
    CP $07                          ; bell: stored
    JP Z,GOODCH
    CP $03                          ; Control-C: echo "^C", return carry
    CALL Z,CTRLPT
    SCF
    RET Z
    CP $0D                          ; Return: the end
    JP Z,INLEND
    CP $09                          ; tab: stored
    JP Z,GOODCH
    CP $0A                          ; line feed
    JP NZ,INLIN_3
    DEC B
    JP Z,INLIN                      ; ignored first
    INC B
    JP GOODCH
INLIN_3:
    CP $15                          ; Control-U: echo "^U" and start again
    CALL Z,CTRLPT
    JP Z,INLIN
    CP $08                          ; backspace
    JP NZ,INLIN_4
    DEC B
    JP Z,SINLIN                     ; nothing to erase
    CALL OUTDO                      ; back, a space, and back
    LD A,$20
    CALL OUTDO
    LD A,$08
    JP ECHOBS
INLIN_4:
    CP $18                          ; Control-X: "#" and start again
    JP NZ,INLIN_5
    LD A,$23
    JP INLCAN
INLIN_5:
    CP $12                          ; Control-R: retype the line
    JP NZ,INLIN_6
    PUSH BC
    PUSH DE
    PUSH HL
    LD [HL],$00
    CALL CRDO
    LD HL,BUF
    CALL LISPRT                     ; print the line
    POP HL
    POP DE
    POP BC
    JP INLINC
INLIN_6:
    CP $20                          ; other control characters are ignored
    JP C,INLINC

;; Stores and echoes a character of the line INLIN is reading, or rings the bell if the buffer is full.
;;
;; In:    C = the character, HL = the next place in the buffer, B = the count of characters in it, plus one
;; Errors: Line buffer overflow (23), when the line comes from a file
GOODCH:
    LD A,B
    OR A
    JP NZ,GOODCH_1                  ; room
    PUSH HL
    LD HL,[PTRFIL]                  ; reading a file?
    LD A,H
    OR L
    POP HL
    LD A,$07                        ; no: ring the bell
    JP Z,GOODCH_2
    LD HL,BUF
    CALL LINGET                     ; DE = the line's number
    EX DE,HL
    LD [CURLIN],HL                  ; for the error message
    JP LBOERR                       ; Line buffer overflow
GOODCH_1:
    LD A,C
    LD [HL],C
    INC HL
    INC B
GOODCH_2:
    CALL OUTDO
    SUB $0A                         ; a line feed?
    JP NZ,INLINC
    LD [TTYPOS],A                   ; the column is 0
    LD A,$0D                        ; and a carriage return to go with it
    CALL OUTDO
GOODCH_3:
    CALL INCHR                      ; skip nulls
    OR A
    JP Z,GOODCH_3
    CP $0D                          ; and the Return that follows the line feed
    JP Z,INLINC
    JP INLCHR

;; Ends the line INLIN is reading, at a Return.
;;
;; Out:   HL = the input buffer, less one, carry = clear
INLEND:
    LD A,[TEMPA]                    ; INPUT;?
    OR A
    JP Z,FININL                     ; end it and echo the Return
    XOR A
    LD [HL],A
    LD HL,BUF-1
    RET

;; Notes a semicolon after INPUT or LINE INPUT, which leaves the cursor after the typed line.
;;
;; In:    A = the character at HL, HL = the text
;; Out:   TEMPA = ';' after a semicolon, else 0; HL = after the semicolon, A = the character there
SCNSEM:
    PUSH AF
    LD A,$00
    LD [TEMPA],A
    POP AF
    CP $3B
    RET NZ
    LD [TEMPA],A
    JP CHRGTR
