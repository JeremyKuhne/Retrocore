; SOSLDR, the SOS loader: the first part of SOS.KERNEL, which the boot loader reads into memory from $1E00 up and
; starts at SOSLDR. It puts the global page and the kernel in place, initializes the kernel, shows the welcome
; screen, reads SOS.INTERP and SOS.DRIVER from .D1, relocates the drivers and links them into the device table,
; initializes them, and jumps to the interpreter.
;
; This file includes the rest of the loader, each part including the next: SosLdrC.asm (the kernel file's header
; and the loader's names), SosLdrD.asm (the main program, MOVE and the device table), SosLdrE.asm (file and driver
; walking), and SosLdrF.asm (driver placement, relocation, memory segments, error and welcome messages, SOS call
; parameters, and the space INIT is assembled into). Names follow Apple's SOS 1.3 listing.

ZZORG:                              ; the loader's first byte, the start of the kernel file
    .include "SosLdrC.asm"
