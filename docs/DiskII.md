# The Disk II controller

The Disk II is Apple's 5.25-inch floppy drive for the Apple II family, and the controller is the card it plugs
into, usually in slot 6. This guide explains what the controller's two ROMs do, for anyone reading or stepping
through the SDK's sources of them in [`Roms/DiskII`](../src/Retrocore.Machines.Apple2/Roms/DiskII). It
assumes you know some 6502 assembly but not the Apple II's internals.

| Source | Chip | What it is |
| --- | --- | --- |
| [`Boot16.asm`](../src/Retrocore.Machines.Apple2/Roms/DiskII/Boot16.asm) | P5, 341-0027 | The 16-sector card's boot ROM, which loads the first sector of a DOS 3.3 or ProDOS disk: sets `SECTORS = 16` and includes `Boot.asm`. |
| [`Sequencer16.asm`](../src/Retrocore.Machines.Apple2/Roms/DiskII/Sequencer16.asm) | P6, 341-0028 | The 16-sector card's logic state sequencer, the table that runs the card's hardware: its reading table, with `Sequencer.asm` for the rest. |
| [`Boot13.asm`](../src/Retrocore.Machines.Apple2/Roms/DiskII/Boot13.asm) | P5, 341-0009 | The 13-sector card's boot ROM, for DOS 3.1 to 3.2.1 disks: sets `SECTORS = 13` and includes `Boot.asm`. |
| [`Sequencer13.asm`](../src/Retrocore.Machines.Apple2/Roms/DiskII/Sequencer13.asm) | P6, 341-0010 | The 13-sector card's sequencer: its reading table, with `Sequencer.asm` for the rest. |
| [`Boot.asm`](../src/Retrocore.Machines.Apple2/Roms/DiskII/Boot.asm) | | The code both boot ROMs share, with `.if SECTORS = 13` around what differs: the nibble table, the address mark, decoding the data field, and how the ROM ends. |
| [`Sequencer.asm`](../src/Retrocore.Machines.Apple2/Roms/DiskII/Sequencer.asm) | | What both sequencers share: the commands, the table macros, the writing table, and the chip's wiring. |

`Boot16.asm`, `Boot13.asm`, `Sequencer16.asm` and `Sequencer13.asm` are the roots, one per chip; each assembles
byte for byte to its chip. `DiskIISourceTests` pins each one by SHA-256, and compares it
with the dumps in `RETROCORE_DISKII_ROMS` (default `%USERPROFILE%\Retrocore\disk2-roms`, or `disk2-roms` under
`RETROCORE_CACHE`) when they are there.

## The card in a slot

Every Apple II slot has two address ranges that belong to it, where n is the slot number:

- **$Cn00-$CnFF**, 256 bytes for a ROM on the card. The Disk II's boot ROM (P5) is here, so `PR#6`, or
  `C600G` in the Monitor, runs it. At power-on the Autostart Monitor (on the IIe, the II Plus, and an Apple II
  configured with it) scans the slots from 7 down for a ROM whose bytes at $Cn01, $Cn03 and $Cn05 are $20, $00
  and $03, and runs the first it finds: that is how a disk starts by itself.
- **$C080-$C08F plus n * 16**, sixteen addresses that work the card's switches. The code puts n * 16 in X and
  reads `$C080,X` and the like, so the same code works in any slot. This value is SLOTX16 in the sources.

The switches are eight on/off controls. Reading the even address of a pair turns its switch off, the odd one
turns it on; the value read back does not matter, except that every even address also returns the data latch,
the byte being read or written. Writes work too, but a program should not write to even addresses: the card
would drive the data bus at the same time as the 6502.

| Switch | Off | On | DOS's names |
| --- | --- | --- | --- |
| Q0-Q3 | $C080, $C082, $C084, $C086: stepper phase 0-3 off | $C081, $C083, $C085, $C087: phase 0-3 on | PHASEOFF, PHASEON (+ phase * 2) |
| Q4 | $C088: drive motor off | $C089: motor on | MOTOROFF, MOTORON |
| Q5 | $C08A: select drive 1 | $C08B: select drive 2 | DRV0EN, DRV1EN |
| Q6 | $C08C: shift (and read the latch) | $C08D: load | Q6L, Q6H |
| Q7 | $C08E: read | $C08F: write | Q7L, Q7H |

Q6 and Q7 together choose the mode: read (Q7 off, Q6 off), sense write protect (Q7 off, Q6 on), write (Q7 on,
Q6 off), and load the byte to write (Q7 on, Q6 on). The sources name the switches for what they do (`DRIVE1`,
`DATALATCH`, `READMODE`) and give DOS's names in comments.

## The drive

A disk has 35 tracks, rings from the outside (track 0) in. The head moves between them with a stepper motor
of four magnets, the phases. Turning on the phase next to the current one pulls the head half a track
toward it, so stepping through the phases in order moves it in (0, 1, 2, 3, 0, ...) or out (0, 3, 2, 1,
0, ...), and a whole track is two steps. Nothing tells the card where the head is. The boot ROMs find track 0
by stepping out 80 times, more than enough from anywhere; at track 0 the head hits a stop and stays.

The disk turns at 300 revolutions a minute, a fifth of a second a turn. The head writes and reads flux
transitions, changes in the magnetic field. The card divides the track into bit cells of 4 microseconds, four
6502 cycles: a transition within a cell is a 1, none is a 0. A track holds about 50,000 of them.

## Nibbles

The hardware puts two limits on what can be written:

- **The top bit of every byte is 1.** The card shifts bits into the data latch until its top bit becomes 1,
  so that is how the 6502 knows a byte is complete. It starts a byte at the first 1 it sees.
- **There are never too many 0 bits in a row.** With no transitions, the drive's amplifier (an MC3470) starts
  to see false ones. The 13-sector card allows no two 0 bits together; the 16-sector card allows two.

A byte that obeys these rules is a disk byte, usually called a nibble. Data is encoded into nibbles, so a
256-byte sector takes more than 256 of them:

- **4-and-4** (address fields): each byte becomes two nibbles, one holding its odd bits and one its even bits,
  with every other bit 1. The first nibble is `1 b7 1 b5 1 b3 1 b1`, the second `1 b6 1 b4 1 b2 1 b0`;
  `(first << 1 | 1) & second` gives the byte back.
- **5-and-3** (13 sectors, DOS 3.1 to 3.2.1): each nibble carries five bits. A sector is 256 nibbles of the
  bytes' top five bits and 154 of their three low bits, 410 in all.
- **6-and-2** (16 sectors, DOS 3.3 and ProDOS): each nibble carries six bits. A sector is 256 nibbles of the
  bytes' top six bits and 86 of their two low bits, three bytes' worth to a nibble, 342 in all.

A table maps the 32 or 64 valid nibbles to their values; each boot ROM builds its table before it reads. To
catch errors, each value is written exclusive-ored with the one before it, and a final checksum nibble
brings the total to zero.

Between fields are gaps of self-sync bytes: $FF written with two extra 0 bits after it (one on the 13-sector
format). However far into a gap the card starts reading, these bring it into step with the real byte
boundaries within a few bytes.

## A track

Each sector is two fields, each starting with a three-nibble prologue that cannot occur in data:

| Field | Prologue | Contents | Epilogue |
| --- | --- | --- | --- |
| Address | D5 AA 96 (D5 AA B5 on 13-sector disks) | volume, track, sector and their checksum, each 4-and-4 | DE AA EB |
| Data | D5 AA AD | the sector, 5-and-3 or 6-and-2, and a checksum | DE AA EB |

To read a sector, code reads nibbles until it finds an address field for the sector it wants, then reads the
data field that follows. The boot ROMs do exactly this, and check neither epilogue.

## Starting a disk

1. **BOOT 0**, the boot ROM. It builds its nibble table, finds its slot (it calls an RTS in the Monitor and
   reads its own address off the stack), turns on drive 1, steps to track 0 and reads sector 0.
   - The 16-sector ROM reads it into $0800 and jumps to $0801. The first byte at $0800 says how many sectors
     to read in all, one page each; DOS 3.3 and ProDOS say 1. The sector reader, `READ` at $Cn5C, is also a
     routine: BOOT 1 sets the sector (`$3D`) and page (`$27`) and jumps there for each sector it loads, and
     the ROM comes back to $0801.
   - The 13-sector ROM reads it into $0300, decodes only part of it, and jumps to $0301, where the sector's
     code finishes decoding itself.
2. **BOOT 1**, the boot sector, loads the rest of DOS's loader.
3. **BOOT 2** and DOS itself, with RWTS, its own sector reader and writer.

## The logic state sequencer

The card has no processor. Its timing comes from the logic state sequencer: a 256-byte PROM (P6) and a 4-bit
register for its state, clocked at 2 MHz, twice the 6502's rate. Each clock the PROM takes the current state
and the inputs and gives the next state and a command for the data latch (Sather calls it the data register).

The inputs:

| Input | Meaning |
| --- | --- |
| state | the register's 4 bits |
| Q7, Q6 | the mode the 6502 chose |
| QA | the latch's top bit |
| RP | the read pulse from the drive: 0 while a flux transition passes, 1 otherwise. Sather's tables call the two cases RP and NO RP. |

The commands, with Sather's mnemonics:

| Code | Name | Command |
| --- | --- | --- |
| $0-$7 | CLR | clear the latch |
| $8, $C | NOP | nothing |
| $9 | SL0 | shift left, bringing in a 0 |
| $D | SL1 | shift left, bringing in a 1 |
| $A, $E | SR | shift right, bringing in the write-protect sensor as bit 7 |
| $B, $F | LD | load the latch from the data bus |

Apple's tables use only the first code of each, so the sources write each entry as a command and the state to
go to, such as `SL1($2)`, and that gives back the exact byte. `READING` lists a state's entries in read and
sense write protect modes, `WRITING` in the two write modes. Both pass each entry to `ENTRY`, which names it
by its state and inputs, Q7 Q6 QA RP written as four binary digits such as `%0110`.

- **Reading.** The states time the gaps between read pulses: a pulse within a bit cell shifts in a 1, a cell
  with none a 0. Once QA is 1 the sequencer holds the byte for a while, long enough for a 6502 loop of 7
  cycles to see it, then clears the latch for the next. Sense write protect shifts the write-protect sensor
  in eight times, so the latch reads $FF or $00.
- **Writing.** The states count around a loop of eight, 4 microseconds, one bit cell. The state's top bit is
  the write signal to the drive, and each change of it is a flux transition: at the end of the loop it changes
  when QA is 1. Then the latch shifts left to put the next bit in QA, or, in load mode, takes the byte the
  6502 stores. A program must store each byte at the right moment, every 32 cycles.

### The chip's wiring

The PROM's pins are not in the order of the inputs: the board's designers assigned them to keep its traces
short. Address pins A7-A0 carry state bits 3 and 2, state bit 0, RP, Q7, Q6, QA and state bit 1; data pins
D7-D4 the next state and D3-D0 the command. The sources list the table in logical order, and `SEQUENCER` lays
it out by pin.

The known dump of the 13-sector sequencer, 341-0010, is not in the card's pin order. Its address lines A5 and
A7 are exchanged and its data lines D7-D4 reversed: exactly the difference Sather describes between the
sequencer's socket and the boot ROM's, where a sequencer can be read by the 6502. Read in the card's order,
the dump never completes a nibble; exchanged back, it is Sather's DOS 3.2 table entry for entry, and boots DOS
3.2. `Sequencer13.asm` assembles to the card's order, and `DiskIISourceTests` exchange the dump's lines back
to compare. To run the dump itself, launch with `sequencerLayout: "boot-socket"`. The 341-0028 dump is in
the card's order.

The card also shortens each read pulse to one sequencer clock. The 16-sector table reads correctly with
longer pulses, but the 13-sector table takes a second clock of pulse as another 1 bit.

## References

- Jim Sather, *Understanding the Apple II* (Quality Software, 1983), chapter 9, "The Disk Controller": the
  switches (Table 9.1), the sequencer's commands (Table 9.3), the read pulse (page 9-15), its wiring (page
  9-16), and the DOS 3.2 and DOS 3.3 sequencer tables (Figures 9.10 and 9.11);
  [scan](https://archive.org/details/Understanding_the_Apple_II_1983_Quality_Software).
- Don Worth and Pieter Lechner, *Beneath Apple DOS* (Quality Software, 1981), chapter 3 for the nibbles and
  the track, chapter 6 for the switches' names, chapter 8 for BOOT 0 and BOOT 1;
  [scan](https://archive.org/details/Beneath_Apple_DOS), [text](https://github.com/iKarith/beneath-apple-dos).
- Apple, *DOS 3.3 C source listing* (1983), for RWTS's names: `PHASEOFF`, `Q6L`, `NBUF1`, `NBUF2`, `DNIBL`;
  [PDF](https://elite.bbcelite.com/pdfs/apple2_SRC_DOS33C_1983.pdf).
- Don Worth and Pieter Lechner, *Beneath Apple ProDOS* (Quality Software, 1984), appendix D, the 16-sector
  sequencer's table; [scan](https://archive.org/details/Beneath_Apple_ProDOS_1985).
- Christer Ericson, notes on that table: the state 2 loop that discards sync bits and the state D hang copy
  protection uses; [notes](https://www.retro.co.za/ccc/apple2/christer/Apple/p6.notes.html).
- Andy McFadden, *Disk ][ controller card "BOOT0" code*, a commented disassembly of the 16-sector boot ROM;
  [text](https://www.applefritter.com/files/2023/07/17/disk_ii_prom.txt).
