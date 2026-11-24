; APPLESOFT INTERPRETER ENTRY NAMES
;
; Apple's names for shared interpreter entries, which resolve only in the AppleSoft builds that include this file.
; Each cites its documents by their keys in docs/Bibliography.md, as an Also: entry does. ASTIL's article 76,
; "Applesoft: Internals--Floating Point Math Package (3 of 3)":
; https://mirrors.apple2.org.za/Apple%20II%20Documentation%20Project/Companies/Apple/Documentation/Apple%20Technical%20Information%20Library/a2til231.txt

.cpu Mos6502

;; Requires a comma and reads a byte expression.
;;
;; Apple's name for <COMBYT>: COMBYTE (ASTIL, AS82), in ASTIL's article 76, on the floating-point math package.
COMBYTE = COMBYT
