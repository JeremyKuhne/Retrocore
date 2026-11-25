; retrocore: style=strict
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
; This is our firmware, not an Apple ROM dump or the ProDOS operating system, so
; its names are its own.
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
; routine, Driver, starts at $C740. Numbers prefixed with $ are hexadecimal.
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
; in agreed memory locations, called a mailbox, then calls Driver. The routine
; reads the special address $C0F0. Unlike a normal RAM read, that access invokes
; Apple2Bus.DiskCommand in C#, which performs the transfer through IBlockDevice
; and returns an error code. A read copies a block into the caller's RAM buffer;
; a write copies the buffer's bytes to the corresponding disk block.
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
; The source generator assembles this file with Retrocore's own assembler when the
; machine library is built (docs/NativeAssembly.md describes the dialect; the .rom
; line names the generated C# type, its origin and its size). Slot7Rom.Bytes
; contains the complete image, including zero padding and the identification
; trailer, and .export makes Driver, DeviceInfo and CAPABILITY_WRITE constants of
; that type. At machine creation, C# copies that image into the card's ROM storage
; and adds the write-capability bit only if the mounted device permits writes. The
; CPU then executes these bytes normally; no assembler runs inside the emulator.
; The same firmware works with both original and enhanced IIe CPU configurations.
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
.export Driver, DeviceInfo, CAPABILITY_WRITE

; The ProDOS block-device mailbox in page zero, which the caller fills before calling <Driver>.

;; The ProDOS command: <COMMAND_STATUS>, <COMMAND_READ> or <COMMAND_WRITE>.
Command = $42

;; The ProDOS unit number: the drive in bit 7 (clear for drive 1) and the slot in bits 6-4.
UnitNumber = $43

;; The address of the caller's 512-byte buffer, low byte; <BufferHigh> is the high byte.
Buffer = $44

;; The high byte of <Buffer>.
BufferHigh = $45

;; The block number, low byte; <BlockHigh> is the high byte.
Block = $46

;; The high byte of <Block>.
BlockHigh = $47

; The ProDOS commands.

;; Returns the device's size in blocks.
COMMAND_STATUS = 0

;; Reads a block into the buffer.
COMMAND_READ = 1

;; Writes the buffer to a block.
COMMAND_WRITE = 2

;; The ProDOS unit number of slot 7, drive 1.
UNIT_SLOT_7_DRIVE_1 = $70

; Memory the boot uses.

;; Three bytes below the boot buffer where the boot writes a JMP to <Driver>: a trampoline into the driver in RAM for
;; the disk's bootstrap.
BootTrampoline = $07FD

;; The opcode of JMP absolute, for <BootTrampoline>.
OPCODE_JMP = $4C

;; The page block 0 is read to: $0800-$09FF.
BOOT_PAGE = $08

;; The page block 1 is read to: $0A00-$0BFF.
BOOT_SECOND_PAGE = $0A

;; Where the boot block's code starts, after its first byte.
BootEntry = $0801

; The emulator's ports.

;; Read: performs the mailbox's command and returns its ProDOS error code, 0 for success.
CommandPort = $C0F0

;; Read: the device's size in blocks, low byte; <BlockCountHigh> is the high byte.
BlockCount = $C0F1

;; Read: the high byte of <BlockCount>.
BlockCountHigh = $C0F2

; The ProDOS device-capability bits at $CnFE.

;; Removable media.
CAPABILITY_REMOVABLE = %10000000

;; Interrupts.
CAPABILITY_INTERRUPT = %01000000

;; Bits 5-4: the number of volumes less one (ProDOS Technical Note #21).
ONE_VOLUME = %00000000

;; Formats.
CAPABILITY_FORMAT = %00001000

;; The capability bit the C# card sets in <DeviceInfo> for a writable device.
CAPABILITY_WRITE = %00000100

;; Reads.
CAPABILITY_READ = %00000010

;; Returns its status.
CAPABILITY_STATUS = %00000001

; The four signature bytes the Monitor and ProDOS look for in a disk controller's page, which Boot's first
; instructions carry as their operands.

;; At $C701: a disk controller.
SIGNATURE_01 = $20

;; At $C703: a disk controller.
SIGNATURE_03 = $00

;; At $C705: a disk controller.
SIGNATURE_05 = $03

;; At $C707: $3C, not $00: a disk controller that is not a SmartPort, which the Autostart and original IIe Monitors
;; check.
SIGNATURE_07 = $3C

;; Boots the mounted disk: reads blocks 0 and 1 to $0800-$0BFF through <Driver>, then runs the disk's bootstrap at
;; $0801.
;;
;; It doesn't check the reads' carry: the host checks the image when it is mounted.
;; Out:   X = the unit number, as ProDOS's bootstrap expects
.proc Boot
    ; The signature: these loads are executed, but only their operands matter.
    lda #SIGNATURE_01
    lda #SIGNATURE_03
    lda #SIGNATURE_05
    lda #SIGNATURE_07

    ; JMP Driver at $07FD-$07FF, outside the boot buffer, for the disk's bootstrap.
    lda #OPCODE_JMP
    sta BootTrampoline
    lda #<Driver
    sta BootTrampoline + 1
    lda #>Driver
    sta BootTrampoline + 2

    ; Block 0 to $0800-$09FF. The unit number stays in the mailbox for the disk's bootstrap.
    lda #COMMAND_READ
    sta Command
    lda #UNIT_SLOT_7_DRIVE_1
    sta UnitNumber
    lda #0
    sta Buffer
    sta Block
    sta BlockHigh
    lda #BOOT_PAGE
    sta BufferHigh
    jsr Driver

    ; Block 1 to $0A00-$0BFF; Command is still COMMAND_READ.
    lda #BOOT_SECOND_PAGE
    sta BufferHigh
    inc Block
    jsr Driver

    ; The disk's bootstrap, with its unit number in X.
    ldx UnitNumber
    jmp BootEntry
.endproc

; Leave enough space for the existing $C740 driver entry. A backwards .org or a boot that grows into this entry is
; a compile-time error, not truncated data.
.org $C740

;; The ProDOS block-device entry: performs the command in the zero-page mailbox.
;;
;; At $C740; the low byte of its address is at $C7FF, where ProDOS finds it. Read and write keep X and Y. Status
;; reads <CommandPort> twice: once for the status and again through the read and write path, which earlier versions of
;; this driver also did; the second read is harmless.
;; In:    Command = <COMMAND_STATUS>, <COMMAND_READ> or <COMMAND_WRITE>; UnitNumber = drive and slot,
;;          Buffer/BufferHigh = the buffer, Block/BlockHigh = the block number
;; Out:   A = 0 or a ProDOS error code, carry = clear on success, set on error; X/Y = the block count, for status
;; See:   <DeviceInfo>
.proc Driver
    ; Status: the size from the emulator's ports.
    lda Command
    bne Perform
    lda CommandPort
    ldx BlockCount
    ldy BlockCountHigh
    ; Falls into Perform.

    ; Performs the command, and returns its error code with the carry set, or 0 with the carry clear.
Perform:
    lda CommandPort
    cmp #0                          ; zero for success
    beq Succeed
    sec
    rts
Succeed:
    clc
    rts
.endproc

; Unused bytes between the driver and the identification trailer are zero padded.
.org $C7FE

;; The ProDOS device-capability byte at $CnFE, followed by the low byte of <Driver> at $CnFF.
;;
;; One volume that reads and returns its status ($03), not removable and without interrupts; the C# card adds
;; <CAPABILITY_WRITE> only for a writable mounted device.
DeviceInfo:
    .byte ONE_VOLUME | CAPABILITY_READ | CAPABILITY_STATUS
    .byte <Driver
.assert * == $C800                  ; the image ends exactly after 256 bytes
