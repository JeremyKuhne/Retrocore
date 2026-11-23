; APPLESOFT FLOATING-POINT ENTRY NAMES
;
; Apple's names for shared floating-point entries, which resolve only in the AppleSoft builds that include this
; file. Each cites its documents by their keys in docs/Bibliography.md, as an Also: entry does. Microsoft's listing
; has no label at this entry within LINPRT. ASTIL's article 79, "Applesoft: Internals--Device I/O Routines":
; https://mirrors.apple2.org.za/Apple%20II%20Documentation%20Project/Companies/Apple/Documentation/Apple%20Technical%20Information%20Library/a2til228.txt

.cpu Mos6502

;; Prints <FAC> as a decimal number.
;;
;; Apple's name for <LINPRT_FOUT>: PRNTFAC (ASTIL), in ASTIL's article on device I/O routines (79).
PRNTFAC = LINPRT_FOUT
