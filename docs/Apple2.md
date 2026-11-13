# The Apple II family

Retrocore's Apple II is [`Apple2Machine`](../src/Retrocore.Machines.Apple2/Apple2Machine.cs): one machine for the
Apple II, the II Plus and the IIe, original and enhanced, chosen by [`Apple2Model`](../src/Retrocore.Machines.Apple2/Apple2Model.cs).
This guide covers how the models differ, the cards they take, their ROMs and the SDK's sources of them, and how to
debug on each. [DiskII.md](DiskII.md) and [Dos.md](Dos.md) cover the disk controller and DOS.

## The models

| Model | `model` | CPU | ROM | Memory | Notes |
| --- | --- | --- | --- | --- | --- |
| Apple II (1977) | `ii` | 6502 | Integer BASIC and the original or Autostart Monitor, $E000-$FFFF | 16, 32 or 48 KB | `boardRevision` 0 for the first boards' colors |
| Apple II Plus | `iiplus` | 6502 | AppleSoft and the Autostart Monitor, $D000-$FFFF | 16, 32 or 48 KB, and a language card in slot 0 | |
| Apple IIe | `iie` | 6502 | AppleSoft, the Monitor and the internal firmware, $C100-$FFFF | 64 KB and the extended 80-column card's 64 KB | |
| Enhanced Apple IIe | `iie-enhanced` | 65C02 | As the IIe, enhanced, with MouseText | As the IIe | The default |

All four share the 6502 bus, the text, lo-res and hi-res video and its timing, the speaker, the game port and slots 1
to 7. A launch names the family with `"machine": "apple2"`; launch configurations written for the IIe alone, with
`"machine": "apple2e"` and `model` `enhanced` or `original`, still work.

**What only the IIe has.** The IIe adds soft switches at $C000-$C00F and $C011-$C01F, auxiliary memory, 80-column text
and double hi-res, MouseText on the enhanced IIe, lowercase, the Open Apple and Closed Apple keys, and the built-in
firmware at $C100-$CFFF, whose 80-column part answers in slot 3. On the II and II Plus, $C000-$C01F is all keyboard
(any access to $C010-$C01F clears the keyboard strobe), slot 3 takes a card like the others, the keyboard types only
capitals, and the game port's push buttons stand where the Apple keys are.

**The Monitor.** The II's original Monitor resets into the Monitor's `*` prompt; CONTROL-B starts Integer BASIC.
The Autostart Monitor of later IIs and the II Plus boots a disk at power-on, or starts BASIC when there is none, and
returns to BASIC on reset. The original Monitor also has STEP and TRACE and the multiply and divide routines the
Autostart Monitor dropped.

**Video.** The II and II Plus draw text from a 2 KB character generator (7341-0036) with 64 uppercase characters;
the board inverts codes below $40 and flashes those from $40 to $7F. A revision 0 board ignores bit 7 of a hi-res
byte, so it draws black, white, green and violet but not orange and blue (`"boardRevision": 0`). Its text's color
fringes are not modeled: text is drawn white, as on later boards.

**Memory.** The II and II Plus came with 16, 32 or 48 KB on the board (`ramKilobytes`). Past it, reads see the
floating bus and writes go nowhere, so BASIC finds the top of memory where the RAM ends.

## Slots and cards

| Slot | II and II Plus | IIe |
| --- | --- | --- |
| 0 | The language card or a firmware card, or empty (`slot0`) | Built in: the IIe's language card |
| 1, 2, 5 | Disk II controllers or the mouse card | Disk II controllers or the mouse card |
| 3 | A Disk II controller or the mouse card | The 80-column firmware |
| 4 | The Mockingboard, a Disk II controller or the mouse card | The Mockingboard, a Disk II controller or the mouse card |
| 6 | The Disk II (`diskImage`, `dos`) | The Disk II (`diskImage`, `dos`) |
| 7 | Block storage (a `.po` `diskImage`) or a Disk II | Block storage or a Disk II |

**The language card** is 16 KB of RAM at $D000-$FFFF, its first 4 KB in two banks, switched at $C080-$C08F. The II
Plus has one unless `slot0` says otherwise; DOS 3.3's System Master loads the other BASIC into it.

**A firmware card** holds the other model's BASIC and Monitor in 12 KB of ROM: AppleSoft and the Autostart Monitor on
a II, Integer BASIC and the original Monitor on a II Plus. Any access to $C080 selects the card's ROM and $C081 the
board's, as DOS 3.3's FP and INT do, and RESET selects what the card's switch says: up (the card) for the AppleSoft
card, down (the board) for the Integer card. The ROM is the other model's dumps (`firmwareCardRoms`, or
`RETROCORE_IIPLUS_ROMS` or `RETROCORE_II_ROMS`, or the other model's folder beside `romDirectory`), or else the
SDK's build of them.

DOS 3.3 ends its boot with two reads of $C081, to leave a language card reading ROM. On a firmware card the same reads
select the board's ROM, so a II with the AppleSoft card boots a DOS 3.3 disk into its own Integer BASIC, and FP selects
the card.

The Retro Devices view lists each model's slots, and **Add Card** puts a card in a free one; [Devices.md](Devices.md)
describes the view and its requests. Each launch configuration remembers the cards and disks it last ran with.

## ROMs

Without dumps, every model's ROMs are assembled from the SDK's sources, byte-identical to the chips. A launch can give
dumps instead, in `romDirectory` or the model's variable:

| Model | Variable | Chips |
| --- | --- | --- |
| II | `RETROCORE_II_ROMS` | Integer BASIC 341-0001 to 341-0003 and the original Monitor 341-0004; the 7341-0036 character generator and the Autostart Monitor 341-0020 come from an `APPLE II+` folder beside them when they are not there |
| II Plus | `RETROCORE_IIPLUS_ROMS` | AppleSoft 341-0011 to 341-0015, the Autostart Monitor 341-0020 and the 7341-0036 character generator |
| IIe | `RETROCORE_IIE_ROMS` | The CD and EF system ROMs and the video ROM, original or enhanced |

## The ROM sources

The sources are in [`Roms`](../src/Retrocore.Machines.Apple2/Roms). Each assembles byte-identically to its chips, and
the tests pin every build by digest.

| Source | Builds |
| --- | --- |
| [`Monitor.asm`](../src/Retrocore.Machines.Apple2/Roms/System/Monitor.asm) | `MONITOR` 0: the II's original Monitor (341-0004); 1: the Autostart Monitor (341-0020); 2, the default: the IIe's, with `ENHANCED` choosing the model |
| [`IntegerBasic.asm`](../src/Retrocore.Machines.Apple2/Roms/IntegerBasic/IntegerBasic.asm) | The II's Integer BASIC ROM, $E000-$F7FF (341-0001 to 341-0003), with the floating point, the Mini-Assembler and SWEET16; `FORFIX` 1 for the 1983 DOS 3.3 System Master's INTBASIC, which fixes FOR to shift both bytes of an enclosing loop's token address (the ROM shifts the low byte twice) |
| [`ProgrammersAid.asm`](../src/Retrocore.Machines.Apple2/Roms/ProgrammersAid/ProgrammersAid.asm) | Programmer's Aid #1, $D000-$D7FF (341-0016), the II's D0-socket ROM of Integer BASIC utilities: hi-res graphics, renumber and append, relocate, tape verify, a RAM test and music; `RAMTESTFIX` 1 for the 1983 DOS 3.3 System Master's INTBASIC, whose RAM test prints the bad byte where the chip jumps to $02CB |
| [`applesoft.mac`](../src/Retrocore.Machines.Apple2/Roms/AppleSoft) | AppleSoft II: `APLPLS` 1 for the II Plus (341-0011 to 341-0015), whose AppleSoft is the original IIe's but for its last byte; `ENHNCD` for the enhanced IIe |
| [`CharacterGenerator.asm`](../src/Retrocore.Machines.Apple2/Roms/System/CharacterGenerator.asm) | `IIBOARD` 1: the II and II Plus's 7341-0036; else the IIe's video ROM, with `ENHANCED` |
| [`Firmware.Original.asm`, `Firmware.Enhanced.asm`](../src/Retrocore.Machines.Apple2/Roms/System) | The IIe's internal firmware, $C100-$CFFF |
| [`Slot7.rom.asm`](../src/Retrocore.Machines.Apple2/Roms/Slot7.rom.asm) | The emulated slot-7 ProDOS block device's firmware, $C700-$C7FF |

Names follow Apple's listings where Apple published them: the Apple II Reference Manual of 1978
([archive.org](https://archive.org/details/Apple_II_Redbook)) for the original Monitor, the Mini-Assembler, SWEET16
and the floating point, and of 1979 ([archive.org](https://archive.org/details/Apple_II_Reference_Manual_1979_Apple))
for the Autostart Monitor. Apple did not publish Integer BASIC's; its names follow Paul R. Santa-Maria's. Programmer's
Aid's follow the listings in its manual of 1978 ([archive.org](https://archive.org/details/programmers-aid-1)).

The DOS 3.3 System Masters' FPBASIC and INTBASIC, the BASIC that HELLO loads into a language card, build from these
sources too: the 1980 masters' are the II Plus's and II's $D000-$FFFF with the Autostart Monitor, and the 1983
master's are $D000-$F7FF, with the IIe's AppleSoft and `FORFIX`'s Integer BASIC. The first 2 KB of INTBASIC
($D000-$D7FF) is Programmer's Aid #1, the chip's in 1980 and `RAMTESTFIX`'s in 1983, and $D800-$DFFF holds leftover
AppleSoft ROM bytes from the image Apple built it from. `SystemMasterBasicTests` compares them.

## Debugging

Each model is in the Run and Debug dropdown, and **Retrocore: Start Machine…** starts one with a program, a BASIC
file, a disk or a source on a fresh DOS disk, all without a launch.json; the extension README's
**The mouse card** goes in any free slot (`mouse`, or Add Card), one per machine. Its 256-byte firmware (`Mouse.rom.asm`)
is the SDK's own, not Apple's: it has the AppleMouse II's identification bytes ($38 at $Cn05, $18 at $Cn07, $01 and
$20 at $Cn0B-$Cn0C, $D6 at $CnFB) and its routines at the offsets in $Cn12-$Cn19 (SETMOUSE, SERVEMOUSE, READMOUSE,
CLEARMOUSE, POSMOUSE, CLAMPMOUSE, HOMEMOUSE and INITMOUSE), which use the slot's screen holes as Apple documents. Each
routine hands the call to the card through its ports at $C080 plus 16 times the slot, as slot 7's block storage does,
so it runs in any slot. Position starts clamped to 0-1023. Interrupts come as vertical blanking starts: every frame
with mode bit 3, and when the mouse moved or its button changed with bits 1 and 2. After `IN#n`, BASIC's `INPUT X,Y,B`
reads the position and the button (B 1 held, 2 pressed, 3 released, 4 up; negative when a key is waiting); after
`PR#n`, `PRINT CHR$(1)` turns it on and `CHR$(0)` off. In the debugger, a click on the display locks the pointer to it
until Escape, and a strip under the screen says which; in AppleSharp, where the card is in slot 2, a click on the screen
does, until a right-click, and the status line says which. AppleSharp's **Shift+F11** steps the monitor through color,
black and white, green and amber, and keeps the choice.

**Apple's mouse firmware** (341-0270-C) is an SDK source too, `Roms/Mouse/MouseInterface.asm`, which assembles
byte-identically to the EPROM (`MouseInterfaceSourceTests`). The emulator doesn't run it: it is eight 256-byte banks
switched through $Cn00 by the card's 6821 PIA, passing bytes to a 68705 microcontroller that does the work. It is the
reference the emulator's firmware follows:

| | Apple's card | The emulator's |
| --- | --- | --- |
| Finding the slot | The mouse routines use X = $Cn and Y = $n0 as given; SERVEMOUSE writes an RTS at $06 and calls it, so it works with the language card's RAM over the Monitor; BASIC's entries call the Monitor's IORTS | The same |
| BASIC input | Writes `+XXXXX,+YYYYY,+BB` into $0200 and returns a RETURN with X = $11, so nothing is echoed; with the mouse off, 0, 0 and B 1 | The same |
| BASIC output | A RETURN does nothing; any other character's low bit turns the mouse on or off, and mode bit 7 marks BASIC | The same |
| BASIC's registers | Keeps A, X and Y for output; input returns Y = $11; MSLOT is left at $Cn | Keeps Y for input too |
| READMOUSE with the mouse off | Changes nothing | The same |
| Pascal entries, $Cn1A-$Cn1F | Error 3; the factory's own commands (and the copyright message at $Cn1B) | Error 3; nothing, with carry set |
| Mouse routines' registers | X and Y as given; A not kept; SERVEMOUSE returns X = $Cn, Y = $n0 | A, X and Y kept |
| INITMOUSE | Waits for vertical blanking; on the II and II Plus clears hi-res page 1 and leaves the display in text, lo-res, page 1 | Returns at once and leaves memory and the display alone |
| Screen holes $0678+n and $06F8+n, and MOUMODE's bits 4-6 | Its own scratch space | Not used |
| Timing | Calls take hundreds of cycles, passing bytes to the microcontroller | About a hundred |

[Starting a machine](../extension/README.md#starting-a-machine) explains both. The launch options for the family, besides those every machine has (`source`, `program`, `basic`, `speed` and the
rest, in the [extension README](../extension/README.md)):

| Option | Models | What it does |
| --- | --- | --- |
| `model` | all | `ii`, `iiplus`, `iie` or `iie-enhanced` (the default) |
| `monitor` | II | `original` (the default) or `autostart` |
| `boardRevision` | II | 1 (the default) or 0, the first boards' four hi-res colors |
| `programmersAid` | II | `true` puts Programmer's Aid #1 in the D0 socket, from `romDirectory`'s dump or the SDK's build (`false` by default) |
| `ramKilobytes` | II, II Plus | 16, 32 or 48 (the default) |
| `slot0` | II, II Plus | `languageCard` (the II Plus's default), `firmwareCard` or `empty` (the II's default) |
| `firmwareCardRoms` | II, II Plus | The other model's dumps for the firmware card |
| `romDirectory` | all | The model's ROM dumps, in place of the SDK's builds |
| `mockingboard`, `sound` | all | The Mockingboard in slot 4 (defaulting on when `sound` is `mockingboard`), and what the panel plays (`speaker`, `mockingboard` or `off`; `speaker` by default) |
| `mouse` | all | The mouse card in that slot, 1 to 7 (none by default) |
| `screen` | all | The monitor: `color` (the default), or a monochrome `white` (black and white), `green` or `amber` one, which shows each of the 560 dots sharply; the panel's **Screen** menu changes it |
| `diskImage`, `diskController`, `diskSectors` | all | A disk in slot 6 (`diskII`) or slot 7 (`slot7`, the default for `.po`), and 16- or 13-sector Disk II firmware |
| `diskBootRom`, `diskSequencerRom`, `sequencerLayout` | all | Disk II P5/P6 ROM dumps in place of the SDK's ([DiskII.md](DiskII.md)) |
| `dos`, `dosYear` | all | Boot a program from a fresh DOS `3.3` (`1983` or `1980`) or `3.2` disk ([Dos.md](Dos.md)) |
| `fastDisk` | all | Run as fast as possible while any Disk II drive motor turns (`true` by default; toggled by **Fast disk** in the panel) |
| `controllers` | all | Game controllers on the game port (`true` by default), or `false` for none |

**Game controllers** drive the game port on every model, in the debugger and in AppleSharp. SDL reads Xbox,
PlayStation, Switch Pro and most other controllers, and the first one connected is the Apple joystick:

| Controller | Game port |
| --- | --- |
| Left stick or d-pad, left and right | Paddle 0 (the joystick's X), 0 at the left to 255 at the right |
| Left stick or d-pad, up and down | Paddle 1 (the joystick's Y), 0 at the top to 255 at the bottom |
| A (Cross) | Button 0, with Open Apple |
| B (Circle) | Button 1, with Closed Apple |
| X (Square) | Button 2 |
| A second controller's left stick | Paddles 2 and 3; its A presses button 2 |

The paddles are the game port's 558 timers: accessing $C070-$C07F starts all four, and $C064-$C067 read bit 7 high
until each times out, so the Monitor's PREAD and BASIC's `PDL` count the stick's position. A paddle with no controller
reads 255, as an unconnected one does. The debugger reads controllers whenever the machine runs, even with VS Code in
the background, and lists them in the Retro Devices view's **Game port** row; the launch option `controllers: false`
turns them off. AppleSharp reads them while its window has focus.

The debugger maps the SDK's sources onto whatever ROM is running, so stepping into the Monitor, AppleSoft or Integer
BASIC shows their source wherever the bytes match. The display panel follows the model: its title, and the key bar's
buttons, which are the Apple keys on the IIe and the game port's buttons 0 and 1 on the II and II Plus.

**AppleSoft** debugs on its own BASIC thread on every model that runs it: breakpoints and stepping by statement, GOSUBs
in the call stack, variables, arrays, `DEF FN` functions, `FOR` loops and AppleSoft expressions, under DOS 3.3 and
under ProDOS's BASIC.SYSTEM alike. The II Plus's AppleSoft is the original IIe's but for its last byte.

**Integer BASIC** runs on the II, a II Plus's firmware card, or a language card DOS 3.3's INT loaded, and debugs on
its own BASIC thread as AppleSoft does: breakpoints, stepping by statement, GOSUBs in the call stack, its variables,
arrays and strings, its FOR loops, and expressions in its 16-bit arithmetic. The debugger follows whichever BASIC is in
memory. A `basic` launch takes an Integer BASIC file (named `.integer.bas`, or with `REM retrocore integer` as its
first line), with labels if it likes. It is tokenized by the ROM's own matcher run over the ROM's syntax tables in C#
(`IntegerBasicSyntax`), so the program is what typing it would have stored, and a line the grammar refuses is a
`*** SYNTAX ERR` at the place it stopped. **Open as BASIC Listing** opens a CiderPress2 `#fa` file as text, and saving
tokenizes it the same way.

**Apple Pascal** 1.1 boots on a 64K II Plus (the language card holds its interpreter), and its programs debug on a
Pascal thread, with `pascal` breakpoints on their procedures: see [Pascal.md](Pascal.md).

## Testing

| Tests | What they check |
| --- | --- |
| `SystemSourceTests`, `AppleSoftTests`, `Apple2SourceTests` | Every Apple II, II Plus and IIe ROM source's digest, the ROMs built from them against the dumps, and each model starting BASIC |
| `Apple2MachineTests`, `Apple2PlusTests`, `Apple2IITests`, `Apple2SlotTests`, `Apple2GamePortTests` | The IIe's soft switches and auxiliary memory, the hardware the II and II Plus lack next to the IIe, slot 0 and peripheral cards, memory sizes, the keyboard, the game port, both Monitors, revision 0, and booting from dumps |
| `Apple2VideoTests`, `Apple2VideoOracleTests`, `Apple2AudioTests`, `Apple2MockingboardTests` | Text, lo-res, hi-res and double hi-res video (including against apple2ts), the speaker and the Mockingboard |
| `Apple2MouseTests`, `MouseInterfaceSourceTests` | The mouse card's firmware run on each CPU: its identification, routines, screen holes, clamping, interrupts and BASIC's `IN#`/`PR#`; Apple's mouse firmware's source against the EPROM (from `mouse-roms` under `RETROCORE_CACHE`, or `RETROCORE_MOUSE_ROMS`) and its identification against the emulator's |
| `Apple2DosTests`, `SystemMasterBasicTests` | DOS 3.3's System Master on the II and II Plus, switching BASIC with FP and INT through the language card and firmware cards, and the System Masters' `FPBASIC` and `INTBASIC` files |
| `IntegerBasicTests`, `IntegerBasicSyntaxTests` | Listing Integer BASIC, and tokenizing with `IntegerBasicSyntax` against the ROM and back |
| `SdkDocumentationTests` | The documentation lint over every source, each Monitor build linted on its own |
| `tools/Test-IIeDap.mjs`, `tools/Test-IIDap.mjs`, `tools/Test-IIPlusDap.mjs`, `tools/Test-IntegerBasicDap.mjs` | Each model and Integer BASIC through the debug adapter, from dumps and from the SDK's ROMs |
| `tools/Test-ProDosBasicDap.mjs` | AppleSoft's BASIC thread under ProDOS's BASIC.SYSTEM, which runs statements past `GONE`: breakpoints, stepping, Set Next Statement and errors, on the ProDOS 2.4.3 image from `Fetch-M1Dependencies.ps1` |

Dumps are looked for in `RETROCORE_IIE_ROMS`, `RETROCORE_IIPLUS_ROMS` and `RETROCORE_II_ROMS` (or `apple2-roms` under
`RETROCORE_CACHE`, default `%USERPROFILE%\Retrocore`, for the II and II Plus); without them dump-dependent tests are
inconclusive, and the SDK's builds are still checked by digest.
