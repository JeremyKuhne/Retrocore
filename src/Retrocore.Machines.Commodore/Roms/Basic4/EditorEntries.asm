;; PET BASIC 4 SCREEN EDITOR ENTRY POINTS, FOR THE KERNAL
;;
;; The editor's routines that the kernal uses, as equates at their addresses in the editor ROM. Both editors, for
;; the graphics and the business keyboards, keep them at the same addresses, so one kernal serves both. Editor4.asm
;; defines and documents each of them as a label, so it does not include this file; Kernal4.asm does, and each
;; definition here inherits the editor's documentation.

;; Inherit: <Editor4:CINT>
CINT = $E000

;; Inherit: <Editor4:LP2>
LP2 = $E0A7

;; Inherit: <Editor4:LOOP5>
LOOP5 = $E116

;; Inherit: <Editor4:PRT>
PRT = $E202

;; Inherit: <Editor4:PULS>
PULS = $E442

;; Inherit: <Editor4:KEY>
KEY = $E455

;; Inherit: <Editor4:PREND>
PREND = $E600
