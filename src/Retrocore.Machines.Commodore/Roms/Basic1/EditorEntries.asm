;; COMMODORE PET 2001 BASIC 1 SCREEN EDITOR ENTRY POINTS, FOR THE KERNAL
;;
;; The screen editor's routines that the kernal (Kernal1.asm) uses, as equates at their addresses in the editor.
;; Editor1.asm defines and documents each as a label, so it does not include this file; the kernal does, and each
;; definition here inherits the editor's documentation.
;;
;; Maintained by hand.

;; Inherit: <Editor1:CINT>
CINT = $E1E1

CINT_PAGE2 = $E1F0                  ;; <CINT> with X the bytes of page 2 to clear plus one, for the factory test

;; Inherit: <Editor1:LP2>
LP2 = $E27D

;; Inherit: <Editor1:LOOP5>
LOOP5 = $E2FA

;; Inherit: <Editor1:PRT>
PRT = $E3EA

;; Inherit: <Editor1:PULS>
PULS = $E66B

;; Inherit: <Editor1:PREND>
PREND = $E67E

;; Inherit: <Editor1:KEY>
KEY = $E685

;; Inherit: <Editor1:MSG>
MSG = $E7DE
