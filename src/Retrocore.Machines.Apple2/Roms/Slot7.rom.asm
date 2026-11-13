; Copyright (c) 2025 Jeremy W Kuhne
; SPDX-License-Identifier: MIT
; See LICENSE file in the project root for full license information
;
; EMULATED SLOT-7 PRODOS BLOCK DEVICE FIRMWARE
;
; WHAT THIS FILE IS
;
; This is a small program that lets the emulated Apple IIe start an operating
; system from a disk image and subsequently access that disk. It belongs to an
; invented, emulated storage device, not a reproduction of a historical card.
; This is our firmware, not an Apple ROM dump or the ProDOS operating system.
;
; ProDOS is an Apple II operating system. Among other things, it understands
; files and directories and decides where their contents live on a disk. This
; firmware does not understand filenames: it only transfers numbered blocks.
; A block is a fixed-size chunk of 512 bytes. ProDOS turns file operations into
; requests to read or write those blocks.
;
; The mounted .po file is a disk image: a host-computer file whose contents are
; arranged in ProDOS block order. The emulator supplies its blocks through the
; IBlockDevice interface. Neither this assembly program nor the emulated CPU
; opens host files directly. The emulator's C# code reads the image.
;
; WHY "SLOT 7" AND "ROM"?
;
; A real Apple IIe has numbered expansion slots for peripheral cards. A storage
; card can provide a small ROM, containing instructions the Apple II can execute
; to identify the card, start reading its disk, and service later disk requests.
; We expose the same kind of interface in virtual slot 7, without requiring a
; physical card.
;
; ROM means read-only memory. The supplied Apple motherboard ROM starts the
; machine and searches for a bootable card. It recognizes our virtual card by
; particular bytes in its slot ROM, then executes the beginning of this program.
; Our 256-byte ROM appears at CPU memory addresses $C700-$C7FF; its disk-command
; routine starts at $C740. Numbers prefixed with $ are hexadecimal, not decimal.
;
; HOW BOOTING WORKS
;
; 1. The Apple motherboard firmware finds this card's identification bytes.
; 2. Boot, below, asks the emulated device to read disk blocks 0 and 1.
; 3. Those blocks are copied into ordinary Apple II RAM at $0800-$0BFF.
; 4. We jump to $0801 and execute the disk's own bootstrap program.
; 5. That bootstrap loads and starts ProDOS. Once running, ProDOS can call this
;    card's command routine to get disk capacity or read/write more blocks.
;
; There are therefore three separate programs involved: the supplied Apple
; motherboard firmware, our card firmware in this file, and the bootstrap/
; operating-system programs stored on the mounted disk image.
;
; HOW A DISK REQUEST CROSSES INTO C#
;
; The caller places the command, disk unit, RAM-buffer address, and block number
; in agreed memory locations, called a mailbox, then calls DriverEntry. The
; routine reads the special address $C0F0. Unlike a normal RAM read, that access
; invokes Apple2Bus.DiskCommand in C#, which performs the transfer through
; IBlockDevice and returns an error code. A read copies a block into the caller's
; RAM buffer; a write copies the buffer's bytes to the corresponding disk block.
;
; This is memory-mapped I/O: an address stands for a device operation rather than
; an ordinary stored byte. It is an intentional emulation shortcut for block
; storage. It does not model Disk II floppy hardware, magnetic tracks, nibble
; encoding, or the time needed for a physical drive to move and read a disk.
;
; The calling agreement is also called an ABI (application binary interface).
; A, X, and Y below are small CPU registers. The carry flag is a single status
; bit used here to distinguish success from failure. Mailbox addresses and
; register results must follow that agreement so ProDOS can use the device.
; A 16-bit address/block number occupies two bytes, with the low byte first;
; this ordering is called little endian.
;
; BUILDING AND MODIFYING THIS FIRMWARE
;
; The source generator uses the same Retrocore.Assembler implementation exposed by
; the retrocore library, linked into the build tool to avoid a dependency cycle.
; It extracts .rom metadata and passes the remaining source to that assembler,
; which uses the CPU's canonical opcode definitions. Slot7Rom.Bytes contains the
; complete image, including zero padding and the identification trailer. At
; machine creation, C# copies that image into the card's ROM storage and adds
; the write-capability bit only if the mounted device permits writes. The CPU
; then executes these bytes normally; no assembler runs inside the emulator.
; The same firmware works with both original and enhanced IIe CPU configurations.
;
; Assembler dialect:
;   .rom Namespace.Type, origin, size declares the generated constant byte span.
;   .cpu selects the canonical opcode map. Labels and constants are case-sensitive.
;   .org moves forward with zero padding; .res, .byte, .word and .assert are supported.
;   < and > extract low/high bytes. Branches are range checked; forward labels resolve
;   at build time. .export exposes addresses/constants to the C# device implementation.
;
; ProDOS mailbox ABI:
;   $42 command: 0=status, 1=read, 2=write.
;   $43 unit: drive bit 7 and slot bits 6..4 ($70 is slot seven, drive one). The
;   device is one volume, drive one; drive two answers $28, no device connected.
;   $44/$45 buffer address, $46/$47 block number, both little endian.
;   Reading $C0F0 performs the mailbox command and returns its error code.
;   $C0F1/$C0F2 report the device's 16-bit block count, at most 65535, ProDOS's limit.
;
; Driver return ABI:
;   A=0 and carry clear on success; A=error and carry set on failure.
;   Status returns block count in X/Y. Read/write preserve X/Y.
;   A, status flags and the mailbox/buffer contents are not preserved.
;   The host validates image mounts. This bootstrap preserves the existing behavior:
;   it reads the first two blocks and transfers to the disk bootstrap without checking
;   their returned carry flag. The command entry itself always reports errors.

.rom Retrocore.Machines.Apple2.Slot7Rom, $C700, $100
.cpu Mos6502
.export DriverEntry, DeviceInfo, WriteCapabilityMask

Command = $42
Unit = $43
BufferLow = $44
BufferHigh = $45
BlockLow = $46
BlockHigh = $47
BootTrampoline = $07FD
BootEntry = $0801
CommandPort = $C0F0
BlockCountLow = $C0F1
BlockCountHigh = $C0F2

; ProDOS device-capability bits at $CnFE.
RemovableMask = %10000000
InterruptibleMask = %01000000
OneVolume = %00000000                ; bits 5-4: the number of volumes less one (ProDOS Technical Note #21)
FormatCapabilityMask = %00001000
WriteCapabilityMask = %00000100      ;; The capability bit the C# card sets in <DeviceInfo> for a writable device.
ReadCapabilityMask = %00000010
StatusCapabilityMask = %00000001

;; Boots the mounted disk: reads blocks 0 and 1 to $0800-$0BFF through <DriverEntry>, then runs the
;; disk's bootstrap at $0801.
;; Out: X = the unit number, as ProDOS's bootstrap expects
Boot:
    lda #$20                 ; C701: first disk-card identification byte.
    lda #$00                 ; C703: second identification byte.
    lda #$03                 ; C705: third identification byte.
    lda #$3C                 ; C707: legacy disk device; original IIe ROM checks this.

    lda #$4C                 ; JMP opcode for the ProDOS bootstrap's RAM trampoline.
    sta BootTrampoline       ; Install it at 07FD, outside the 0800 boot buffer.
    lda #<DriverEntry        ; Resolve the low byte of the card's command entry.
    sta BootTrampoline + 1   ; Set the trampoline's destination low byte.
    lda #>DriverEntry        ; Resolve its high byte from the ROM load address.
    sta BootTrampoline + 2   ; Complete JMP C740 at 07FD-07FF.

    lda #1                   ; Boot starts with the ProDOS READ command.
    sta Command              ; The command entry reads the zero-page mailbox.
    lda #$70                 ; Slot seven, drive one, in ProDOS unit-number format.
    sta Unit                 ; Keep it available to the disk's bootstrap code.
    lda #0                   ; Buffer low byte and initial block number are zero.
    sta BufferLow            ; First buffer begins at 0800.
    sta BlockLow             ; Select block zero.
    sta BlockHigh            ; Select its zero high byte.
    lda #$08                 ; High byte of the first 512-byte buffer.
    sta BufferHigh           ; Destination is 0800-09FF.
    jsr DriverEntry          ; Read block zero through the emulator's block card.

    lda #$0A                 ; The second contiguous boot buffer starts at 0A00.
    sta BufferHigh           ; Destination is 0A00-0BFF.
    inc BlockLow             ; Advance from block zero to block one.
    jsr DriverEntry          ; Read the second boot block; Command remains READ.
    ldx Unit                 ; ProDOS's disk bootstrap expects its unit number in X.
    jmp BootEntry            ; Leave the card and execute the disk bootstrap at 0801.

; Leave enough space for the existing C740 driver entry. A backwards .org or a
; bootstrap that grows into this entry is a compile-time error, not truncated data.
.org $C740
;; The ProDOS block-device command entry: performs the command in the zero-page mailbox.
;; In:    Command = 0 for status, 1 to read, 2 to write; Unit = drive and slot, BufferLow/BufferHigh = the buffer,
;;          BlockLow/BlockHigh = the block number
;; Out:   A = 0 or a ProDOS error code; X/Y = the block count, for status, carry = clear on success, set on error
;; See:   <DeviceInfo>
DriverEntry:
    lda Command              ; Decide whether status must return capacity in X/Y.
    bne ExecuteCommand       ; READ/WRITE preserve the caller's X and Y registers.
    lda CommandPort          ; STATUS performs no buffer transfer; A receives status.
    ldx BlockCountLow        ; Return the low byte of device capacity.
    ldy BlockCountHigh       ; Return the high byte of device capacity.
; STATUS deliberately falls through for a second harmless status-port read,
; preserving the previous driver's instruction and bus-access sequence.
ExecuteCommand:
    lda CommandPort          ; Dispatch mailbox command and receive zero/error in A.
    cmp #0                   ; Test status without changing the returned A value.
    beq Success              ; Zero means success.
    sec                      ; Nonzero: report ProDOS error with carry set.
    rts                      ; Return to the caller; X/Y remain as required above.
Success:
    clc                      ; Zero: report success with carry clear.
    rts                      ; Return from the command entry.

; Unused bytes between the driver and identification trailer are zero padded.
; C7FE: one volume, readable, status supported; not removable or interruptible.
; The C# card adds WriteCapabilityMask only for a writable mounted device.
.org $C7FE
;; The ProDOS device-capability byte at $CnFE, followed by the low byte of <DriverEntry> at $CnFF.
DeviceInfo:
    .byte OneVolume | ReadCapabilityMask | StatusCapabilityMask ; Base read-only capabilities ($03).
    .byte <DriverEntry       ; C7FF: ProDOS command-entry offset within the slot ROM.
.assert * == $C800           ; Verify the complete image ends exactly after 256 bytes.
