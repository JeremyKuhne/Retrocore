;; COMMODORE PET 2001 BASIC 1 KERNAL ENTRY POINTS, FOR THE EDITOR
;;
;; The kernal's routines and tables that the screen editor (Editor1.asm) uses, as equates at their addresses in the
;; kernal. Kernal1.asm defines and documents each as a label, so it does not include this file; the editor does, and
;; each definition here inherits the kernal's documentation.
;;
;; Maintained by hand.

;; Inherit: <Kernal1:MSG1>
MSG1 = $F000

;; Inherit: <Kernal1:JUDTIM>
JUDTIM = $FFEA
