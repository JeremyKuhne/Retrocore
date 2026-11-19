;; PET BASIC 2 SCREEN EDITOR ENTRY POINTS, FOR THE KERNAL
;;
;; The editor's routines and tables that the kernal and its monitor use, as equates at their addresses in the editor
;; ROM. Editor2.asm defines and documents each of them as a label, so it does not include this file; Kernal2.asm does,
;; and each definition here inherits the editor's documentation.

;; Inherit: <Editor2:CINT>
CINT = $E1DE

;; Inherit: <Editor2:LP2>
LP2 = $E285

;; Inherit: <Editor2:LOOP5>
LOOP5 = $E2F4

;; Inherit: <Editor2:PRT>
PRT = $E3D8

;; Inherit: <Editor2:PULS>
PULS = $E61B

;; Inherit: <Editor2:KEY>
KEY = $E62E

;; Inherit: <Editor2:PREND>
PREND = $E6E4

;; Inherit: <Editor2:WROA>
WROA = $E76A

;; Inherit: <Editor2:WROB>
WROB = $E775

;; Inherit: <Editor2:WRTWO>
WRTWO = $E784

;; Inherit: <Editor2:T2T2>
T2T2 = $E797

;; Inherit: <Editor2:RDOA>
RDOA = $E7A7

;; Inherit: <Editor2:RDOB>
RDOB = $E7B6

;; Inherit: <Editor2:RDOC>
RDOC = $E7EB

;; Inherit: <Editor2:ERROPR>
ERROPR = $E7F7
