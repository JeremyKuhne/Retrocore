# Backlog: the TRS-80 Model 100

Status: **phases 1, 2 and 3 built (2026-11-27)**, with WAV tapes but not yet byte tapes; [the
guide](../Trs80Model100.md) covers them. Phase 4, the serial port, the printer and the TPDD, is next.

## Why the Model 100

- **The 8085 has no machine.** Retrocore's 8085 core, with `SIM`/`RIM`, TRAP and RST 5.5, 6.5 and 7.5, is tested
  against exercisers and other emulators but runs nothing real. The Model 100 uses every one of those interrupts,
  and SOD and SID for the cassette.
- **It is one design with many badges.** Kyocera designed it; the Kyotronic 85, Olivetti M10, NEC PC-8201A and
  Tandy 102 and 200 are close relatives, so one machine model covers a family.
- **Its software is famous and well documented.** Its BASIC is among the last code Bill Gates wrote himself
  (Microsoft's blog calls the Model 100 his last major programming project there,
  [Mark Relph, MSDN](https://learn.microsoft.com/en-us/archive/blogs/mark_relph/vintage-the-trs-80-model-100);
  [Lunduke](https://lunduke.substack.com/p/the-last-programming-project-from); a 1993 Smithsonian oral history is
  the likely primary source, not yet checked). Its ROM has a published address-by-address map
  ([Covington's System Map](https://bitchin100.com/wiki/index.php?title=Model_100_System_Map_Part_0), 1985) and at
  least one disassembly said to reassemble byte for byte (below).
- **It sits beside Retrocore's other TRS-80s**, in name if not in design: the Model 100 shares nothing with the
  Model I, III or II but the badge.

## Sources

| Key | Source | Form |
| --- | --- | --- |
| **SM0** | Covington, *Model 100 System Map* Part 0, on [Bitchin100](https://bitchin100.com/wiki/index.php?title=Model_100_System_Map_Part_0) | Port map, file formats, keyboard matrix, `SIM`/`RIM` |
| **SM1** | [System Map Part 1 (0000-0CD9)](https://bitchin100.com/wiki/index.php?title=Model_100_System_Map_Part_1_(0000-0CD9)) | ROM entry points, interrupt vectors |
| **SM7** | [System Map Part 7 (F5F4-FFEC)](https://bitchin100.com/wiki/index.php?title=Model_100_System_Map_Part_7_(F5F4-FFEC)) | RAM variables, interrupt RAM vectors, clock copy |
| **LCD** | [Model 100 LCD Programming](https://bitchin100.com/wiki/index.php?title=Model_100_LCD_Programming) | LCD drivers, chip selects, control byte |
| **SER** | [Model 100 Serial Interface](https://bitchin100.com/wiki/index.php?title=Model_100_Serial_Interface) | IM6402, baud divisors, RS-232/modem select |
| **ROMS** | [Model and ROM information](https://bitchin100.com/wiki/index.php?title=Model_and_ROM_information) (S. Adolph, 2022) | ROM markings, checksums, regional variants |
| **OPT** | [OPTROM Switching](https://bitchin100.com/wiki/index.php?title=OPTROM_Switching), [M100 TS-DOS ROM OptROM Support](https://bitchin100.com/wiki/index.php?title=M100_TS-DOS_ROM_OptROM_Support) | Option-ROM switching and interrupt handling |
| **TPDD** | [TPDD](https://bitchin100.com/wiki/index.php?title=TPDD), [bkw777/pdd.sh](https://github.com/bkw777/pdd.sh), [bkw777/dlplus](https://github.com/bkw777/dlplus) | Disk drive protocol |
| **MAME** | MAME 0.264's `kyocera/kyocera.cpp`, through `mame -listxml` and `-listdevices` of the copy installed in the session; its source is KYO | ROM names and digests, chips, RAM options, clocks |
| **SMAN** | Model 100 Service Manual (26-3801/3802), [text on archive.org](https://archive.org/stream/m100service/m100service_djvu.txt), seen only through search excerpts | Circuit description |
| **T102** | Tandy 102 Service Manual (26-3803), seen only through search excerpts | Clock wiring, LCD drivers |
| **HD** | Hitachi, *MOS LSI Data Book: LCD Driver LSI* (1983), the HD44102CH's pages; [bitsavers on archive.org](https://archive.org/details/bitsavers_hitachidatSLSIDataBookLCDDriverLSI_15075758) | The LCD driver's instructions, counters and dummy read |
| **KYO** | MAME 0.264's `src/mame/kyocera/kyocera.cpp` and `kyocera.h` (Curt Coder, BSD-3-Clause), read, not copied (approved 2026-11-26) | Port decoding, RAM map by size, keyboard matrix, interrupt wiring |
| **TRM** | Tandy, *TRS-80 Model 100 Technical Reference Manual* (26-3810), [text on archive.org](https://archive.org/details/trs-80-model-100-technical-reference-manual) (fetched 2026-11-26) | I/O map, circuits, timing; chapter 10 reprints the 80C85, 81C55, uPD1990AC, IM6402, MC14412 and LCD drivers' data sheets |
| **MCS** | Intel, *MCS-80/85 Family User's Manual*, [on archive.org](https://archive.org/details/Mcs80_85FamilyUsersManual) (fetched 2026-11-26) | The 8155's data sheet: its timer modes, commands and count-by-twos |
| **Z88** | [z88dk techdocs `targets/m100`](https://github.com/z88dk/techdocs/tree/master/targets/m100): `m100.asm`, `sysvars.txt`, `tokens.txt` | Disassembly, RAM variables for each model |

Not yet read: the Model 100 service manual's text (downloaded for phase 1, approved 2026-11-26, not yet searched),
VirtualT's source and the disassemblies, which need the user's approval. The uPD1990AC's and 8155's data sheets
came with TRM and MCS.

## The hardware

| Part | What it is | Ports and addresses |
| --- | --- | --- |
| CPU | OKI MSM80C85 fed 4.9152 MHz, running at 2.4576 MHz (SER; MAME lists the 8085's input clock as 4,915,200 Hz) | |
| ROM | 32 KB: BASIC, TEXT, TELCOM, ADDRSS, SCHEDL | `$0000`-`$7FFF` |
| Option ROM | One socket; replaces the main ROM at `$0000`-`$7FFF` while port `$E0` bit 0 is set (SM0, OPT) | `$0000`-`$7FFF` |
| RAM | 8 KB standard, 8 KB modules to 32 KB (MAME: 8, 16, 24, 32 KB), filled down from `$FFFF` | `$8000`-`$FFFF` |
| 81C55 | CMOS 8155: 256 bytes of RAM (unused here), ports A, B and C, a 14-bit timer | `$B0`-`$BF` (`$B8`-`$BD` mirror `$B0`-`$B5`) |
| LCD | Ten HD44102 column drivers and two HD44103 common drivers; 240x64 dots, 40x8 characters | Data bus `$F0`-`$FF`; `$FE` command/status, `$FF` data |
| Keyboard | 9 columns x 8 rows; columns strobed by port A and port B bit 0, rows read at `$E0`-`$EF` | `$B9`, `$BA`, `$E8` |
| uPD1990AC | Serial real-time clock; TP output drives RST 7.5 | Port A bits 0-4, port C bit 0, `$E0` bit 2 |
| IM6402 | UART for RS-232 and the modem, clocked by the 81C55 timer | `$C0`-`$CF` data, `$D0`-`$DF` mode and status |
| Modem | MC14412 300-baud modem *(mailing list)* and phone relay | `$A0`-`$AF` |
| Cassette | FSK through SOD (out) and SID (in), motor on `$E0` bit 3 | `SIM`/`RIM` |
| Beeper | Port B bit 5, or the 81C55's timer output, chosen by port B bit 2 | `$BA` |
| Printer | Centronics parallel: data on port A, STROBE on `$E0` bit 1, BUSY on port C | `$B9`, `$E0`, `$BB` |
| Bar-code wand | Input on RST 5.5 and port C bit 3 | |

Address decoding is partial: each device answers all 16 ports of its block (SM0).

### Ports in detail (SM0 unless marked)

- **`$A0` modem control** (write): bit 0 the phone relay, bit 1 modem enable.
- **`$B0`/`$B8` 81C55 command** (write): bits 0-1 port A and B direction, 2-3 port C mode, 4-5 port A and B
  interrupt enables, 6-7 timer command (none, stop, stop after TC, start). **Status** (read): A and B interrupt
  request, buffer full and enable, bit 6 timer TC.
- **`$B1`/`$B9` port A** (write): printer data, keyboard columns 1-8, LCD chip selects 0-7; bits 0-4 are also the
  uPD1990's C0, C1, C2, CLK and DATA IN.
- **`$B2`/`$BA` port B** (write): bit 0 keyboard column 9 and LCD select 8, bit 1 LCD select 9, bit 2 beeper source
  (1 bit 5, 0 the timer), bit 3 UART to modem (1) or RS-232 (0), bit 4 power off, bit 5 beeper data, bits 6 and 7
  RS-232 DTR and RTS, active low. LCD says software must keep bits 2-7 when changing the chip selects.
- **`$B3`/`$BB` port C** (read): bit 0 the clock's DATA OUT, bit 1 printer BUSY (low), bit 2 printer BUSY, bit 3
  bar-code data, bits 4 and 5 RS-232 CTS and DSR, active low.
- **`$B4`/`$BC`, `$B5`/`$BD`** the timer count, low and high; the high byte's top two bits are the timer mode. The
  baud divisor is 153,600 / baud (`$BD` = divisor / 256 + 64, i.e. square-wave mode), committed by writing `$C3` to
  `$B8` (SER). The IM6402 takes 16x the baud rate.
- **`$C0`** UART data, both ways.
- **`$D0`** (write) the UART's word format: stop bits, parity, parity inhibit, length. (read) bit 0 modem carrier,
  1 overrun, 2 framing, 3 parity error, 4 transmit buffer empty, 5 ring, 7 low power (active low).
- **`$E0`** (write) bit 0 ROM select, bit 1 printer STROBE (low), bit 2 the clock's STB, bit 3 cassette motor;
  (read) the keyboard rows for the columns strobed low.
- **`$F0`-`$FF`** the LCD drivers selected by ports A and B: a command or status at `$FE`, data at `$FF`.

### Where the sources disagree

- **The UART's length bits.** SM0 gives bits 3-4 as `00` 5 bits, `10` 6, `01` 7, `11` 8; SER gives `01` 6, `10` 7,
  and its stop-bit wording (0 one stop bit, 1 two or 1.5) differs from SM0's (1 for 1.5, 0 for 2). The IM6402's
  data sheet settles both.
- **LCD select names.** SM0 calls port B bits 0 and 1 "CS 28" and "CS 29"; LCD numbers the ten drivers 0-9, port A
  bits 0-7 then port B bits 0-1. The latter is the layout the ROM uses.
- **RST 7.5's rate.** SM1 says "every 4 microseconds (255 times per second)"; SMAN *(excerpt)* says a key scan every
  4 ms, from the uPD1990's TP at 256 Hz. 4 ms, 256 Hz is what the clock chip can make; SM1's "microseconds" is a slip.
- **The cassette's rate.** SMAN *(excerpt)* says 1500 baud; other descriptions say 1200, with 1200 and 2400 Hz tones,
  unconfirmed. To be settled from the ROM's timing loops and MAME.
- **The keyboard table.** SM0 notes its matrix corrects the one in Tandy's *Technical Reference Manual*. Its arrows
  are wrong all the same: MAME puts left, right, up and down on column 6's rows 4-7, and the ROM agrees, giving
  `INKEY$` codes 29, 28, 30 and 31 for them (checked 2026-11-26).
- **The LCD's right-hand drivers.** LCD says drivers 4 and 9 drive 40x32 dots; one article says 40x42, a typo.
- **The 102's ROM.** One source calls it identical to the 100's but for `PEEK(1)` (51 against 167,
  [masswerk](https://masswerk.at/rc2016/01/10.html)); Club100 and ROMS list fixes: a different character set, a
  corrected ATN coefficient, "JUL" for "JLY".

### The LCD

Ten drivers in two rows of five, each top and bottom half 32 dots high; drivers 0-3 and 5-8 drive 50 columns, 4 and
9 drive 40, and their 10 unused columns are RAM (LCD). Several drivers can be selected at once. A command byte to
`$FE` gives the page (one text line of 8 dots) in bits 6-7 and the column (0-49) in bits 0-5; each byte to `$FF`
is one column of 8 dots and moves to the next. Status reads `BDER0000`, busy in bit 7 (Arduino forum,
[thread](https://forum.arduino.cc/t/talking-to-the-lcd-panel-from-a-trs-80-model-100-aka-tandy-m100-and-clones/569826)).
LCD believes bit 0 is the bottom dot; the HD44102 data sheet settles it. The ROM keeps a copy of the screen's
characters at `$FE00`-`$FF3F` (SM7). Since the key scan rewrites ports A and B, the ROM draws with interrupts off.

### The keyboard

The matrix (SM0), rows read at any port of `$E0`-`$EF` (the ROM uses `$E8`) with the column's strobe bit low:

| Row | Col 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 (`$BA` bit 0) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | Z | A | Q | O | 1 ! | 9 ( | Space | F1 | SHIFT |
| 1 | X | S | W | P | 2 @ | 0 ) | DEL | F2 | CTRL |
| 2 | C | D | E | [ ] | 3 # | - _ | TAB | F3 | GRPH |
| 3 | V | F | R | ; : | 4 $ | = + | ESC | F4 | CODE |
| 4 | B | G | T | ' " | 5 % | Down | PASTE | F5 | NUM |
| 5 | N | H | Y | , < | 6 ^ | Up | LABEL | F6 | CAPS |
| 6 | M | J | U | . > | 7 & | Left | PRINT | F7 | |
| 7 | L | K | I | / ? | 8 * | Right | ENTER | F8 | PAUSE/BREAK |

SM0's ASCII table shows the shifted characters; the unshifted ones here are from the key caps. Column 6's arrows are
SM0's; MAME's order, left, right, up, down, is the right one (see "Where the sources disagree").

### Interrupts

| Line | Vector | RAM hook | Use |
| --- | --- | --- | --- |
| TRAP | `$0024` | `$F602` (to `$1431`) | Power failing (SM1, SM7) |
| RST 5.5 | `$002C` | `$F5F9` | Bar-code wand data (SM1) |
| RST 6.5 | `$0034` | `$F5FC` | UART character received (SM1, SER) |
| RST 7.5 | `$003C` | `$F5FF` | The clock's 256 Hz TP: key scan, type-ahead, cursor blink, clock and power-off counters (SM1, SM7) |
| INTR | | | Not used, as far as the sources say |

SM7 shows the RST 7.5 handler counting: `$F92F` from 125 to 0 copies the time, `$F930` from 12 to 1 and `$F931`
counts down to power-off. The handler scans the keyboard every third interrupt (see Phase 1).

### The clock

The uPD1990AC takes a command on C0-C2 (port A bits 0-2) latched by STB (`$E0` bit 2), shifts 40 bits of BCD time
in on DATA IN with CLK (port A bits 4 and 3), and out on DATA OUT (port C bit 0). TP's rate is a command too, set
to 256 Hz by the ROM. The command set is NEC's data sheet's, which TRM reprints; the ROM keeps the time at `$F923`-`$F92E`
(SM7). MAME models it as a shared device (`upd1990a`), as Retrocore should.

### Memory and the option ROM

- **Map.** ROM `$0000`-`$7FFF`; RAM down from `$FFFF`, so an 8 KB machine has `$E000`-`$FFFF` and addresses below
  read `$FF`, as MAME has them unmapped and high. RAM survives power off, so the machine's state between sessions is a RAM image.
- **Option ROM.** Writing 1 to `$E0` bit 0 maps the option ROM over all of `$0000`-`$7FFF`, interrupt vectors
  included, so option ROMs carry their own vectors and call back into the main ROM through a RAM stub (OPT;
  `OUT $E0` from code at `$F605`, copied there at boot). At boot the main ROM looks for "TC" at option-ROM `$0040`
  and a name at `$0042`-`$0047` (SM0); `CALL 63012` (`$F624`) starts one from BASIC.
- **RAM files.** The directory is at `$F962` on the Model 100 and 102 (Z88, which also gives `$F961` on the KC85
  and M10, `$F252` on the 200 and `$F84F` on the PC-8201). Entries are 11 bytes: type, address and an 8-byte
  name *(to check; Z88's comment counts 9)*. BASIC text starts at `BASTXT` (`$F67C`), and `.DO` and `.CO` files
  follow at pointers `$FBAE` and `$FBB0`.

## ROM versions

From MAME 0.264 (`-listxml`) and ROMS:

| Model | MAME set | ROM file (32 KB) | CRC32 | SHA-1 | Notes |
| --- | --- | --- | --- | --- | --- |
| TRS-80 Model 100 (US) | `trsm100` | `m100rom.m12` | `730a3611` | `094dbc4a…bb25d` | Checksum A2D4; Y2K-patched A2CC (ROMS). Early boards a custom pinout, later 27C256 |
| Tandy 102 (US) | `tandy102` | `m102rom.m12` | `08e9f89c` | `b6ede773…0c36d11` | Fixes and a different character set |
| Kyotronic 85 (Japan) | `kc85` | `kc85rom.bin` | `8a9ddd6b` | `9d18cb52…6356c0` | The original; 16 KB default RAM in MAME |
| Olivetti M10 | `m10` (clone of `kc85`) | `m10rom.m12` | `f0e8447a` | `d5886727…7ce02e8a3af` | European, no modem |
| NEC PC-8201 / 8201A | `pc8201`, `pc8201a` | `pc8201rom.rom` (A) | `30555035` | `96f33ff2…37c596` | N82-BASIC, different tokens; up to 96 KB banked RAM, cassette cartridge |
| NEC PC-8300 | `npc8300` | `831000-438_…z01.bin` | `a3c15dcb` | | 1987 |
| Tandy 200 | `tandy200` | `t200rom.bin` (72 KB) | `e3358b38` | | "Bad dump" in MAME; 240x128 LCD (HD61830), 24-72 KB banked RAM, Multiplan built in |

ROMS also lists a UK Model 100 without a modem, closer to the KC85 (checksum EEA4, F0BF for another marking); an
EU Model 100 with a different modem (A8B7); a US 26-3802B whose ROM has the modem code but whose board lacks the
modem; a Norwegian Tele badge with a national keyboard; and EU and UK 102s (B20F). The MAME digests are what this
plan pins first; the others wait for dumps.

### The relatives, as they differ

- **Tandy 102** (1986): the same hardware in a thinner case, standard 8Kx8 RAM chips, the patched ROM. The same
  machine model with a different ROM.
- **Kyotronic 85 and Olivetti M10**: the same board; the M10's memory map differs from the Model 100's (Z88), and
  the European M10 has no modem.
- **NEC PC-8201A**: the same CPU and LCD family, but its own ROM, BASIC dialect, ports and RAM banking; a variant
  with real work.
- **Tandy 200** (1984): 72 KB of ROM in three banks, three 24 KB RAM banks, a 16-line HD61830 LCD, a flip-up
  screen. A different machine model sharing the chips.

## Software and files

Every program the Model 100 ran is copyrighted, so the user supplies it, as for the other machines.

- **The ROM** and option ROMs (Multiplan, Lucid, Ultimate ROM II, TS-DOS) as 32 KB images.
- **`.BA`** tokenized BASIC: lines of next-line address, line number, tokens and a null; three nulls end the
  program (SM0). The addresses are absolute, so the ROM fixes them on load; the 100, 102, 200, KC85 and M10 share
  the tokens ([hackerb9/tokenize](https://github.com/hackerb9/tokenize)).
- **`.DO`** text, CR LF lines, ended by `$1A` (SM0).
- **`.CO`** machine code with a 6-byte header: load address, length, entry address (SM0).
- **Cassette** blocks: a leader of `$55` bytes, a `$7F` sync, a header block (`$9C` DO, `$D0` CO, `$D3` BA, a
  six-character name, a checksum) and 256-byte data blocks (`$8D`, data, checksum)
  ([model-100-interface](https://github.com/Basicprogrammer10/model-100-interface/blob/main/formats/data_formats.md)).
  Tapes as WAV and as a byte-level `.cas`, if a standard exists (VirtualT's or MAME's).
- **RAM images**: the fitted RAM, from its first address to `$FFFF`, saved as a session ends and loaded before the
  power comes on, as battery-backed RAM; the CPU's state is not kept, as it is not when the power goes (built in phase
  2). VirtualT's and MAME's (`nvram`) formats to compare.
- **The TPDD and TPDD-2** on the serial port at 19,200 baud: requests are `ZZ`, a command, a length, up to 128 bytes
  and a checksum. Both have a file-access mode (6.2 names) and a sector-access mode; the TPDD-2 has two sides and a
  different sector protocol (TPDD). TS-DOS and Ultimate ROM II talk to it; `.pdd1` and `.pdd2` are dl2's images.

## Oracles

- **MAME** (`trsm100`, `tandy102` and the rest in `kyocera.cpp`, by Curt Coder): MAME 0.264 is already installed in
  this session by the environment's setup script, so it runs without a download, once the user supplies the ROM.
  Its keyboard, LCD and clock are emulated; its cycle accuracy is MAME's 8085's (which, per [the CPU
  backlog](I8080.md), does not model V and K). The driver is BSD-3-Clause (KYO).
- **VirtualT** (Ken Pettit; BSD per [SourceForge](https://sourceforge.net/projects/virtualt/); 1.7 released 2015,
  1.8 in source): Model 100, 102 and 200 (forks add the KC85, M10, PC-8201 and PC-8300), with a debugger, memory
  editor and TPDD server. Built from source, so a download to approve.
- **CloudT** (John Hogerhuis), a browser emulator; useful for spot checks.
- Real hardware: none here.

## Commented ROM disassemblies

| Disassembly | Author | Form | Licence | Byte-identical |
| --- | --- | --- | --- | --- |
| [z88dk techdocs `m100.asm`](https://github.com/z88dk/techdocs/tree/master/targets/m100) | Stefano Bodrato and others (2021-) | Assembler source, ~27,800 lines, conditionals for M100, M10 and KC85; cross-checked with MSX BASIC and MBASIC 5.22; with `sysvars.txt`, `tokens.txt` and fonts | Not stated on the pages read | Claimed for M100, M10 and KC85, not checked |
| Covington's *System Map* (SM0-SM7, and the *System ROM Map* parts) | Robert D. Covington, 1985, on Bitchin100 | An address map with descriptions, not source | Copyright 1985; Bitchin100 calls its copy "a derived work" | Not source |
| Ken Pettit's annotated listing | Ken Pettit (VirtualT) | Annotated listing; form unknown | Unknown | Unknown |
| LibROM's listing ([sarahkmarr.com](https://sarahkmarr.com/retromodel100.html)) | Sarah Marr, from Pettit's listing and Ron Wiesen's "Teeny" | A modified ROM's listing | Unknown | Of a modified ROM |
| [Kongduino/TRS80](https://github.com/Kongduino/TRS80) | | ROM call header | Unknown | Not source |

Microsoft has not released the source, as far as found. z88dk's is the only candidate that is assembler source and
claims to reassemble; its licence needs checking before Retrocore builds on it, and as the other ROM sources were,
it would be converted to Retrocore's style ([ConvertingSources.md](../ConvertingSources.md)), with z88dk's and
Covington's names kept as historical names. Covington's map is a second set of names to check against.

## The debug target

- **Launch id** `trs80-model100` (the TRS-80s are `trs80-model1`, `trs80-model3`, `trs80-model2`), with options for
  RAM (8-32 KB), the model (`100`, `102`), an option ROM, the clock's starting time (the host's by default), and a RAM
  image.
- **The LCD** as the machine's screen, 240x64 at a chosen scale, with the gray-green panel; **the keyboard** mapped
  from the host's, with F1-F8, PASTE, LABEL, PRINT, PAUSE and BREAK (GRPH, CODE and NUM are still to come).
- **Assembling `source`** and loading `program` binaries, as `.CO` files placed in RAM's directory, so they appear
  on the menu; loading `.BA` and `.DO` files the same way.
- **The call tracker** for `CALL`, `RST`, TRAP and RST 5.5-7.5; the register view with the 8085's flags and the
  interrupt masks from `RIM`; the ROM's source map once the ROM is an SDK source.
- **Battery-backed RAM** saved and restored through the media lifecycle (`retrocore-media-lifecycle`), with an
  explicit cold start.
- A DAP script, `tools/Test-Trs80Model100Dap.mjs`, like `tools/Test-AltairDap.mjs`.

## Phases

1. **The machine.** `Retrocore.Machines.Trs80Model100`: the 80C85 at
   2.4576 MHz, ROM and option ROM switching, RAM, and shared chips in `Retrocore.Core` for the 81C55, the HD44102
   and the uPD1990AC; the keyboard matrix, RST 7.5 from TP, power off. Tests boot the user's ROM to the menu and
   read its screen from the drivers' RAM.
2. **The debug target.** The launch, LCD display, keyboard, call tracker, `source` and `program` launches, RAM
   images, the extension and Desktop catalog entries, the DAP script, the guide and README rows.
3. **Files and BASIC.** `.BA`, `.DO` and `.CO` in and out of RAM's directory; the Model 100's BASIC as a dialect
   (CRUNCH and LIST from `tokens.txt`, checked against the ROM); the cassette through SOD and SID with WAV and byte
   tapes; the beeper.
4. **Serial.** The IM6402 with the 81C55's baud clock, RS-232 to a host file or pipe, the printer port, and a TPDD
   and TPDD-2 in file-access mode on `.pdd1` and `.pdd2` images, for TS-DOS.
5. **The ROM as an SDK source**, byte-identical and documented in the maintained style, so the debugger steps
   through BASIC by name.
6. **The relatives.** The Tandy 102 is built with phases 1 and 2; next the Kyotronic 85 and M10; the Tandy 200 and PC-8201A as
   machine models of their own.

## Testing

- The 81C55, HD44102 and uPD1990AC against their data sheets, as the 6850 was.
- Boot and keystroke tests against MAME's `trsm100`: the menu's text, bytes free, a BASIC program's output, the
  clock's display. Inconclusive, not passing, without the ROM in the external fixture root.
- The ROM's SDK source pinned by digest: CRC32 `730a3611`, SHA-1 `094dbc4a…bb25d` for the US Model 100.
- The 8085's interrupt timing exercised by the real key scan; the cassette against MAME's WAV output (checked by hand
  in phase 3: each machine's `CLOAD` read the other's `CSAVE`).
- The DAP script.

Every download (the ROM, option ROMs, software, manuals, MAME's and VirtualT's sources, disassemblies) is approved
by the user first, and stays out of the repository.

## Phase 1 (built 2026-11-26)

- **What is built.** `Retrocore.Machines.Trs80Model100`: the 80C85 at 2.4576 MHz, the main ROM and the option ROM's
  switch, 8-32 KB of RAM, ports as MAME's `kyocera.cpp` decodes them, the keyboard matrix with typed keys, the LCD
  as `IVideoSource`, the clock's TP on RST 7.5, and the power-off bit with a `PowerOn` switch. Three chips joined
  `Retrocore.Core`'s shared ones: `Pio8155` (the 8155 and 81C55), `Lcd44102` (the HD44102, from Hitachi's 1983 data
  book) and `Rtc1990` (the uPD1990AC).
- **Checked against MAME 0.264.** Both ROMs cold-start to the menu with the bytes free MAME shows at each RAM size
  (5062, 13254, 21446, 29638), checked at all four on the Model 100 and at 24 and 32 KB on the 102, the sizes MAME's
  `tandy102` offers; BASIC's banner (29382 free at 32 KB) and output; and the menu's LCD dots, which match MAME's
  screen exactly but for the seconds of the clock. `Trs80Model100RomTests` pins them; `Trs80Model100MachineTests`
  and `Model100ChipTests` need no ROM.
- **Found on the way.**
  - The LCD's byte has its top dot in bit 0, as the HD44102 data sheet draws it, not bit 7 as LCD guessed.
  - A cold start sets the clock to January 1 and shows "Jan 01,1900 Sun", in MAME as here.
  - The ROM scans the keyboard every third RST 7.5 (11.7 ms), takes a key seen on two scans and needs two scans with
    no key to take the same key again, so typed keys are held and released 50 ms each. MAME's keyboard needs about
    100 ms, as its notes say it is slow.
  - BASIC scrolls one line at a time, about 50 ms a line, so a screen read mid-scroll shows a line twice. A loop
    printing numbers runs within a line in three seconds of MAME's.
  - `POWER OFF` comes back to the menu at power-on; `POWER OFF,RESUME` comes back to BASIC with its variables.
- **Settled by TRM and MCS** (read after phase 1 was built, 2026-11-26):
  - The uPD1990AC latches its register commands (C2 low) and its TP commands (C2 high) separately, so setting TP
    keeps the register mode; the first build had a TP command end shift mode, now fixed and tested. TRM's "100" for
    register shift and "110" for time read list C0 first, so they are commands 1 and 3, as built.
  - The LCD's register select is A8, not A0; an `IN` or `OUT` puts the port on both halves of the address bus, so
    A8 is the port's bit 0, as built.
  - Port $E0's four bits are a 40H175 latch, cleared at reset; the cassette's input is SID and its output SOD.
  - The 8155's timer matches MCS (odd counts high one count longer, a single square wave stops at TC, reset stops
    the count) but for the count registers, which the chip reads back counting by twos; here they read the counts
    left.
  - TRM says one key scan each 4 ms TP period; the ROM's handler scans every third, as found above.
  - The buzzer: with port B bit 2 high, bit 5 drives it; with bit 2 low and bit 5 high, the timer's square wave
    does. The wand's signal goes inverted to port C bit 3 and RST 5.5.
- **Not yet.** The UART, modem, cassette, beeper, printer and wand are unconnected; TRAP never fires; the battery
  never runs low.

## Phase 2 (built 2026-11-26)

- **The debug target.** `trs80-model100` (`model` 100 or 102), with the ROM from `rom`, `romDirectory` or
  `RETROCORE_TRS80M100_ROMS` under MAME's or the fixtures' names; `ramKilobytes`, `optionRom` and `time`. The LCD is
  the display and the ROM's screen copy its text; the call stack follows the 8085's TRAP and RST 5.5-7.5, which push
  the program counter with no opcode fetch; programs load at `$E000` after 3 seconds of boot. Keys are ASCII with the
  ROM's arrow codes (28-31) and 128-140 for F1-F8, LABEL, PRINT, PASTE, PAUSE and BREAK (PAUSE/BREAK with
  SHIFT). Reset does what the power switch and the RESET button do.
- **The RAM image.** `ramImage` keeps the RAM between sessions, as the battery does: loaded before the power comes
  on, so the ROM resumes, and saved as the session ends or another launch replaces the machine, through a file beside
  it so a failed save leaves the old image and can be retried, as `IRecordingTarget` has it. `coldStart` starts
  empty.
- **The extension and Desktop** list the Model 100 and Tandy 102, with their RAM choices, keys, buttons and hints;
  the project catalog has `trs80-model100` and `tandy102`.
- **Tests.** `Trs80Model100DebugTargetTests` and `tools/Test-Trs80Model100Dap.mjs`, which CI runs; without the ROM
  the script checks the missing-ROM messages and reports the rest skipped.
- **Found on the way.** The ROM ignores the keyboard for its first second or so after a cold start (its scan
  counter at `$FF90` starts near 116 scans), though the menu is up by 0.8 s, so a key typed at once is lost, in MAME
  too. A cold start sets the clock to January 1 whatever the launch's `time`.

## Phase 3 findings (2026-11-26)

Read from the ROM, from RAM after the ROM saved files (in Retrocore's machine, whose menu and bytes free match MAME's),
and from a `CSAVE` MAME 0.264 recorded to WAV. No new downloads.

- **Tokens.** BASIC's keyword table is at `$0080`, each keyword's first letter with bit 7 set, `$80` (`END`) to
  `$FF` (`'`), one byte each; `$D0`-`$DE` are the operators `+ - * / ^ AND OR XOR EQV IMP MOD \ > = <`. Numbers and
  line numbers (after `GOTO` and `THEN` too) stay as ASCII digits. `'` is stored as `: REM '` (`3A 8E FF`), and
  `ELSE` with a `:` before it (`3A 91`), as in Microsoft's other BASICs.
- **The directory** at `$F962`: 11-byte entries of a type, the file's address, and a six-character name and
  two-character extension, padded with spaces. Types seen: `$B0` the ROM's own programs (BASIC, TEXT, TELCOM, ADDRSS,
  SCHEDL), `$80` `.BA`, `$C0` `.DO`, `$A0` `.CO`, and `$88`, `$C8` and `$48` for the three hidden entries, "Suzuki"
  (BASIC's unsaved program), "Hayashi" (the paste buffer) and "RickY". A new file takes the first free entry; the menu
  shows files in the directory's order.
- **The file area** from `$8000` (a `$00` before the first file): the `.BA` files, then Suzuki's program; the `.DO`
  files from the pointer at `$FBAE`, then Hayashi's `$1A`; the `.CO` files from `$FBB0`; BASIC's variables from
  `$FBB2`. A `.BA` file is linked lines ending in `00 00`; a `.DO` file is CR LF lines ending in `$1A`; a `.CO` file
  is its start, length and entry, two bytes each, then its bytes.
- **The cassette** (MAME's WAV at 44.1 kHz): a bit is one cycle, 1 at 2400 Hz and 0 at 1200 Hz, from SOD. A block is
  a leader of `$55` bytes sent least significant bit first, a `$7F`, then 9-bit frames, eight data bits most
  significant first and a ninth bit, with each frame's last cycle stretched by the ROM's per-byte work. `CSAVE`
  writes a header block (`$D3`, the name in six characters, `FF FF`, the program's length, six `FF`s and a checksum)
  and a data block (`$8D`, the program's bytes, a checksum).

## Phase 3, part 1 (built 2026-11-26)

- **BASIC.** `BasicDialect.Model100` (`model100`, `.model100.bas`): the ROM's tokens, and a tokenizer checked against
  the bytes the ROM stored for typed lines; listings, renumbering (with `RESTORE`'s line), the grammar, and the
  language server's diagnostics and completions. Hover help for its words is still to write; until then it has none,
  rather than another dialect's. BASIC's pointers: the open program at `$F67C`, the current
  line at `$F67A`, the stack top at `$F678`, the memory top at `$FB67`, the string bottom at `$FB8C`, `CONT`'s text at
  `$FBAC`, the variables, arrays and free memory at `$FBB2`-`$FBB6`, and the DATA pointer at `$FBB8`, each found by
  reading RAM after the ROM set them. After BASIC's `MENU`, before it draws the menu, the ROM fixes the
  directory's addresses and links every `.BA` file again; Retrocore does both as it moves the files. BASIC is at its
  prompt when the current line is `$FFFF` and the name of the program running, at `$FDD9`, is BASIC's or a `.BA`
  file's: the current line is `$FFFF` at the menu and in TEXT too.
- **Files.** `Model100Files` lists, reads, writes and removes `.BA`, `.DO` and `.CO` files in RAM's directory, with
  the region rules the ROM keeps. Files written at the menu match the ROM's own `SAVE`, `SAVEM` and `OPEN` byte for
  byte, and the ROM runs and reads them. A program written through the debugger replaces the one BASIC has open,
  moving the files after it. Removing the open program is refused, as the ROM's `KILL` refuses it (`?FC Error`);
  replacing a file puts the new one in its place, so BASIC keeps a program it has open.
- **The debugger.** The launch's `files` option; the Machine view's Files row; **Open BASIC Program** at BASIC's
  prompt; `.ba` files as listings; the `--model100` command on RAM images (`files`, `extract`, `add`, `delete`).
- **Not yet.** Stepping by BASIC's lines, BASIC's variables (its numbers are BCD, which the variables view does not
  read), the `basic` launch and BASIC's errors and call stack all follow the ROM's routines, and wait for the ROM as an
  SDK source (phase 5). Part 2 is the cassette and the beeper.

## Phase 3, part 2 (built 2026-11-27)

- **The cassette.** `Trs80Model100Tape` keeps a tape as its level changes in the 80C85's cycles, read from and written
  to WAV; `Trs80Model100Cassette` drives it from SOD and gives SID its level inverted, as MAME's driver does, while
  port `$E0` bit 3 runs the motor. The ROM's `CSAVE` and `CLOAD` round-trip; by hand, `CLOAD` read MAME 0.264's
  recording of a `CSAVE`, and MAME's `CLOAD` read Retrocore's. The recording decodes to MAME's blocks; the header's bytes after the
  name are RAM the ROM leaves unset, `$00` here and `$FF` in MAME, which fills RAM with `$FF`.
- **The buzzer.** Port B bit 5 while bit 2 is set; the 81C55's timer output while bit 2 is clear and bit 5 set (MAME's
  `i8155_pb_w` and `i8155_to_w`). `BEEP` sounds.
- **The debugger.** The `cassette`, `fastCassette` and `sound` launch options; the cassette in Retro Devices (Insert,
  Record and Eject), saved through a file beside the recording when it came out or the session ended, until recordings
  became changed tapes, saved like a disk ([MediaPersistence.md](MediaPersistence.md#phases), phase 4); the Machine
  view's Cassette and Sound rows; the display panel's sound.
- **Not yet.** A byte-level tape format (no common one for the Model 100 was found), and the cassette's tape in the
  recovery journal.

## Still open

- **The RAM image and the recovery journal.** The image is saved when the session ends cleanly; a host that crashes
  loses the session's changes since the last image, as the journal keeps disks but not this. Saving it from Retro
  Devices on demand, and journalling it, are still to do.
- **Speed against MAME.** A BASIC loop printing numbers runs within a line in three seconds of MAME's, a little
  slower; MAME's 8085 counts TRAP and the RST 5.5-7.5 entries as 11 states and this core as 12, and the 8155's
  count-by-twos and the LCD's busy times are not modelled. A longer timed comparison would settle it.
- **The UART's clock.** The 81C55's timer drives the buzzer; the UART's baud clock comes with the serial port.
- **The ROM's source map**, once the ROM is an SDK source (phase 5).
- **GRPH, CODE and NUM** have no key codes yet, so their characters cannot be typed from the debugger; the
  machine's keyboard has the keys.

## Decisions (agreed 2026-11-26)

- **Oracle.** MAME, the 0.264 the environment installs; VirtualT is not built.
- **Project and launch id.** A new `Retrocore.Machines.Trs80Model100`, launch id `trs80-model100`.
- **This round: phases 1 and 2**, the machine and its debug target, with the DAP script, the extension's and
  Desktop's catalog entries, the guide and the README rows.
- **Models.** The Model 100 and the Tandy 102 (a ROM option) now; the Kyotronic 85 and M10 in phase 6; the Tandy
  200 and PC-8201A stay in the backlog as machines of their own.
- **The ROM as an SDK source**, in phase 5, disassembled fresh with Retrocore's own tools, with names from
  Covington's *System Map*, rather than built on z88dk's `m100.asm`, whose licence is unstated.
- **Fixtures.** The ROMs are fetched from a source the user approves URL by URL, and kept in the external fixture
  root and the plans repository's assets, never in Retrocore. The US Model 100's and Tandy 102's came from the
  Bitchin100 wiki's [Model and ROM information](https://bitchin100.com/wiki/index.php?title=Model_and_ROM_information)
  page (`M100.ZIP`, `T102_rom.ZIP`, approved and fetched 2026-11-26), match MAME's digests, and are in the fixture
  root's `trs80m100-roms` folder as `m100.bin` and `t102.bin`.
- **Downloads approved** for reference, kept outside the repository: the 8155/81C55, HD44102, uPD1990AC and IM6402
  data sheets; Tandy's *Technical Reference Manual* and the Model 100 service manual; MAME's `kyocera.cpp`, read
  and not copied.
