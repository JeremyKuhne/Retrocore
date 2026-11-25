;; OS ENTRY POINTS, FOR THE SOURCES THAT CALL THE OS
;;
;; The OS's jump vectors at $E450-$E47F, which the OS User's Manual documents as the fixed ways into the OS, as
;; equates. Os.asm defines and documents each of them as a label, so it does not include this file; the sources
;; that call the OS do, and each definition here inherits the OS's documentation. The OS's database variables and
;; hardware registers are in OsEquates.asm, which those sources include too.

;; Inherit: <Os:DISKIV>
DISKIV = $E450

;; Inherit: <Os:DSKINV>
DSKINV = $E453

;; Inherit: <Os:CIOV>
CIOV = $E456

;; Inherit: <Os:SIOV>
SIOV = $E459

;; Inherit: <Os:SETVBV>
SETVBV = $E45C

;; Inherit: <Os:SYSVBV>
SYSVBV = $E45F

;; Inherit: <Os:XITVBV>
XITVBV = $E462

;; Inherit: <Os:SIOINV>
SIOINV = $E465

;; Inherit: <Os:SENDEV>
SENDEV = $E468

;; Inherit: <Os:INTINV>
INTINV = $E46B

;; Inherit: <Os:CIOINV>
CIOINV = $E46E

;; Inherit: <Os:BLKBDV>
BLKBDV = $E471

;; Inherit: <Os:WARMSV>
WARMSV = $E474

;; Inherit: <Os:COLDSV>
COLDSV = $E477

;; Inherit: <Os:RBLOKV>
RBLOKV = $E47A

;; Inherit: <Os:CSOPIV>
CSOPIV = $E47D
