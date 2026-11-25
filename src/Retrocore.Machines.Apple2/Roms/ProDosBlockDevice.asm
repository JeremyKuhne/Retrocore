; retrocore: style=strict
; Copyright (c) 2025 Jeremy W Kuhne
; SPDX-License-Identifier: MIT
; See LICENSE file in the project root for full license information

;; THE PRODOS BLOCK-DEVICE INTERFACE
;;
;; What a ProDOS block device's card ROM shares with ProDOS: the mailbox in page zero that the caller fills before it
;; calls the card's driver, the commands, the errors the drivers return, and the bits of the capability byte at $CnFE.
;; The card ROMs that are ProDOS block devices include it: ProFile.rom.asm, Slot7.rom.asm and Disk35.rom.asm, and the
;; 3.5 controller's host code (Disk35/Disk35Host.asm). The names are the SDK's: ProDOS's manuals describe the mailbox
;; by address.
;;
;; A driver is called with JSR, the mailbox filled, and returns A = 0 with carry clear on success, or A = an error
;; with carry set. Its address is $Cn00 plus the byte at $CnFF.

.scope ProDos

; The mailbox, in page zero.

;; The command: <COMMAND_STATUS>, <COMMAND_READ>, <COMMAND_WRITE> or <COMMAND_FORMAT>.
Command = $42

;; The unit number: the drive in bit 7 (clear for drive 1) and the slot in bits 6-4; bits 3-0 are 0.
UnitNumber = $43

;; The address of the caller's 512-byte buffer, low byte; <BufferHigh> is the high byte.
Buffer = $44

;; The high byte of <Buffer>.
BufferHigh = $45

;; The block number, low byte; <BlockHigh> is the high byte.
Block = $46

;; The high byte of <Block>.
BlockHigh = $47

; The commands.

;; Returns the device's size in blocks, in X (low) and Y (high).
COMMAND_STATUS = 0

;; Reads a block into the buffer.
COMMAND_READ = 1

;; Writes the buffer to a block.
COMMAND_WRITE = 2

;; Formats the device.
COMMAND_FORMAT = 3

; The errors the drivers return.

;; An I/O error: the device could not read or write the block.
ERROR_IO = $27

;; No device connected.
ERROR_NO_DEVICE = $28

; The device-capability byte at $CnFE.

;; Removable media.
CAPABILITY_REMOVABLE = %10000000

;; Interrupts.
CAPABILITY_INTERRUPT = %01000000

;; Bits 5-4, the number of volumes less one: one volume.
ONE_VOLUME = %00000000

;; Bits 5-4, the number of volumes less one: four volumes.
FOUR_VOLUMES = %00110000

;; Formats.
CAPABILITY_FORMAT = %00001000

;; Writes.
CAPABILITY_WRITE = %00000100

;; Reads.
CAPABILITY_READ = %00000010

;; Returns its status.
CAPABILITY_STATUS = %00000001

;; Every command: format, write, read and status.
CAPABILITY_EVERY_COMMAND = CAPABILITY_FORMAT | CAPABILITY_WRITE | CAPABILITY_READ | CAPABILITY_STATUS

.endscope
