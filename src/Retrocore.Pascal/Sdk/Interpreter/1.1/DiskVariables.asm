; retrocore: style=strict
;; The Disk II driver's variables at the end of bank 2.

;; <WriteSector>'s slot times 16, for reloading X in its loop over <ScratchBuffer>.
WriteSlot:
    .res 1

;; The arm's half-track while <StepArm> moves it; <SeekTrack> then halves it to the track that address fields should
;; show.
ArmPosition:
    .res 1

;; Unused.
UnusedVariable:
    .res 1

;; The wrong-track address fields <TransferTrack> still takes, seeking again after each, before it recalibrates.
SeekRetries:
    .res 1

;; The address fields <TransferTrack> still reads in this round looking for its sectors.
AddressTries:
    .res 1

;; The rounds <TransferTrack> has left before it gives up with <DISK_ERROR_NOT_FOUND>.
Recalibrations:
    .res 1
    .assert * = $E000, "The Disk II driver's variables end bank 2."
