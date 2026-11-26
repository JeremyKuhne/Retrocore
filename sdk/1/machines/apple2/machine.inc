; retrocore: style=strict
;; The Apple II's locations and its Monitor's entry points, for programs on every Apple II
;;
;; A project includes it as <machine.inc> on the Apple II, II Plus, IIe and Enhanced IIe. It includes the SDK's
;; IIeEquates.asm, the page-zero locations, vectors, buffers, soft switches and characters, and MonitorEntries.asm,
;; the Monitor's entry points that the other ROM sources call, then adds the Monitor's routines a program most often
;; calls that MonitorEntries.asm leaves out. Each entry inherits the Monitor's own documentation and keeps Apple's
;; names, so `jsr COUT` assembles as `jsr CharacterOut` does.
;;
;; The names are the IIe's. The II and II Plus lack the IIe's soft switches for 80 columns, auxiliary memory and the
;; alternate character set, and its Open Apple and Solid Apple keys: a program for them leaves those alone, or tests
;; RC_MODEL_APPLE2_IIE and RC_MODEL_APPLE2_IIE_ENHANCED first. The Monitor's entry points here are at the same
;; addresses in every Apple II's Monitor.

.assert .defined(RC_MACHINE_APPLE2), "machine.inc for the Apple II is for targets whose machine is an Apple II."

.include <Roms/System/IIeEquates.asm>
.include <Roms/System/MonitorEntries.asm>

; The Monitor's routines a program calls, which MonitorEntries.asm leaves out.

;; Inherit: <Monitor:ReadKey>
;; Also: RDKEY (A2RM78, A2RM79, IIEROM82, IIETRM85)
ReadKey = $FD0C

;; Inherit: <Monitor:GetLineAfterReturn>
;; Also: GETLNZ (A2RM78, A2RM79, IIEROM82, IIETRM85)
GetLineAfterReturn = $FD67

;; Inherit: <Monitor:GetLine>
;; Also: GETLN (A2RM78, A2RM79, IIEROM82, IIETRM85)
GetLine = $FD6A

;; Inherit: <Monitor:GetLine::NoPrompt>
;; Also: GETLN1 (A2RM79, IIETRM85)
GetLineNoPrompt = $FD6F

;; Inherit: <Monitor:PrintHexByte>
;; Also: PRBYTE (A2RM78, A2RM79, IIEROM82, IIETRM85)
PrintHexByte = $FDDA

;; Inherit: <Monitor:CharacterOut>
;; Also: COUT (A2RM78, A2RM79, IIEROM82, IIETRM85)
CharacterOut = $FDED

;; Inherit: <Monitor:SetInverse>
;; Also: SETINV (A2RM78, A2RM79, IIEROM82, IIETRM85)
SetInverse = $FE80

;; Inherit: <Monitor:SetNormal>
;; Also: SETNORM (A2RM78, A2RM79, IIEROM82, IIETRM85)
SetNormal = $FE84

;; Inherit: <Monitor:Beep>
;; Also: BELL (A2RM78, A2RM79, IIEROM82, IIETRM85)
Beep = $FF3A
