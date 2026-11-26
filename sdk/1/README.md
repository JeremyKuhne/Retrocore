# The SDK's headers and memory maps, major version 1

A project's sources include three headers, which each target's build finds in its own folders:

```asm
.include <cpu.inc>          ; the CPU family's names
.include <machine.inc>      ; the machine's hardware and ROM entry points
.include <environment.inc>  ; the environment's calls and conventions
```

They ship beside the debug host and in the `retrocore` tool as `Sdk/1/`. The [SDK plan](../../docs/backlog/Sdk.md#headers-and-defines)
gives the design; this file is the contract as it stands.

## Where an include is found

A target's angle-bracket includes search, in order:

1. `machines/<machine>/`, the catalog id's own folder, such as `machines/apple2-iie-enhanced/`, when there is one;
2. `machines/<family>/`, such as `machines/apple2/`;
3. `environments/<environment>/`, such as `environments/bare/`;
4. `cpus/<cpu>/`, then `cpus/<family's cpu>/`: `cpus/6502/` for every 65C02;
5. `Sdk/1/`, so a model's header reaches its family's as `<machines/apple2/machine.inc>`;
6. `Sdk/`, the ROM sources and their entries files, such as `<Roms/System/MonitorEntries.asm>`.

A `source` launch and `--assemble` search only `Sdk/`.

## The headers

| Header | Targets | What it gives |
| --- | --- | --- |
| `cpus/6502/cpu.inc` | every 6502 and 65C02 target | the stack's page and the three vectors |
| `environments/bare/environment.inc` | `bare` | nothing yet: a bare program calls its ROM |
| `environments/wozmon/environment.inc` | `wozmon` | nothing yet: the program calls the Woz Monitor, as the Apple-1's `<machine.inc>` names it |
| `environments/basic/environment.inc` | `basic` | `BASIC_START`, where the PRG loads, and `SYS_TOKEN`, the token of its BASIC line's `SYS` |
| `environments/dfs/environment.inc` | `dfs` | OSFILE's loads and saves, the layout of its control block, and the Return that ends a file name |
| `environments/dos33/environment.inc` | `dos33` | DOS 3.3's page-3 vector from `$03D0`, from DosInit.asm, and `DOS_COMMAND`, the Ctrl-D that starts a command a program writes |
| `machines/apple1/machine.inc` | `apple1` | the PIA, and the Woz Monitor's ECHO, PRBYTE, PRHEX and GETLINE, written here |
| `machines/apple2/machine.inc` | every Apple II | `IIeEquates.asm`, `MonitorEntries.asm`, and nine more Monitor entries |
| `machines/apple3/machine.inc` | `apple3` | `Apple3Equates.asm`, and text page 1 |
| `machines/pet/machine.inc` | every PET | `PetEquates.asm`, and the kernal's character in, character out and get |
| `machines/bbc/machine.inc` | `bbca`, `bbcb` | `MosEquates.asm` and `MosEntries.asm` |

Each header asserts the define of the targets it is for, so a header included for another target fails at once
with a message that names what it is for. Each entry a header writes itself inherits the documentation of the ROM
source's label (`;; Inherit:`) and keeps the old names (`;; Also:`); a test checks that each is at its label's
address.

## The defines

Every target's build defines these, as the build, the `project` launch and the language server all do:

| Define | Value | Example |
| --- | --- | --- |
| `RC_SDK` | the SDK's major version | `RC_SDK = 1` |
| `RC_CPU_<cpu>` | 1 for the target's CPU and each CPU whose code it runs | `RC_CPU_6502`, `RC_CPU_65C02` |
| `RC_MACHINE_<family>` | 1 for the machine's family | `RC_MACHINE_APPLE2`, `RC_MACHINE_PET`, `RC_MACHINE_BBC` |
| `RC_MODEL_<machine>` | 1 for the machine, by its catalog id | `RC_MODEL_APPLE2_IIE_ENHANCED`, `RC_MODEL_PET4032` |
| `RC_ENV_<environment>` | 1 for the environment | `RC_ENV_BARE` |
| `RC_RAM_KB` | the RAM: the target's `ramKilobytes`, or the launch's default | `RC_RAM_KB = 32` |
| `RC_SCREEN_COLUMNS`, `RC_SCREEN_ROWS` | the text screen the ROM starts in | 40 and 24 on the Apple II |
| `RC_TARGET` | the target's name, a textual definition of a quoted string | `.byte RC_TARGET` |

A name's letters are capitals, and a `-` or `.` in it is `_`. A project's `defines` and its sources may not define a
name starting with `RC_`, in any case: the SDK keeps them, and the `rc_` macros to come.

## Memory maps

Each machine and environment has a map of the memory a program may use, with a file for each RAM size:
`environments/<environment>/<name>.map.json`, where the name is the first of `<catalog id>-<RAM>k`, `<catalog id>`,
`<family>-<RAM>k` and `<family>` that exists, and the RAM is the target's `RC_RAM_KB`. A machine with no map builds as
before, at its launch's load address with nothing checked; a machine whose family has maps, but none for its RAM, is
an error.

```jsonc
// environments/bare/apple2-48k.map.json, shortened
{
  "description": "The Apple II, II Plus and IIe with 48K, bare: ...",
  "load": "$6000",
  "free": [{ "start": "$0300", "end": "$03CF" }, { "start": "$0800", "end": "$BFFF" }],
  "zeroPage": ["$06-$09", "$FA-$FD"],
  "reserved": [{ "start": "$0100", "end": "$01FF", "why": "the stack" }, ...]
}
```

- **`load`** is where the program loads, in free RAM: the launch's own load address at a machine's default RAM, so a
  bare build loads where a `source` launch would.
- **`free`** and **`reserved`** account for every address from `$0100` once. Each reserved area says why, as a phrase
  that follows "overlaps".
- **`zeroPage`** gives the bytes a program may use, at least one; the rest of the zero page is the machine's. Runs
  that touch count as one.

**The build.** With no `linkerConfiguration`, a target links by one made from its map, which `retrocore build` and a
`project` launch write to `obj/<target>/memory.cfg` before they assemble, so it is there when the assembly or the
map's check fails. It places `CODE`, `RODATA`, `DATA` and `BSS` in that order from `load` (`BSS` defines
`__BSS_RUN__` and `__BSS_SIZE__`), and `ZEROPAGE` in the largest run of free zero-page bytes. Code in no section goes
in `CODE`.
With a configuration or without, every section is checked against the map. One in zero page the map doesn't give, or
overlapping a reserved area, fails the build:

```text
<project>/retrocore.json: target t: apple1-4k.map.json:
section CODE ($0300-$1396) overlaps addresses with no RAM, as the machine has 4K from $0000 ($1000-$BFFF) on target t.
section RODATA ($1397-$2A9C) overlaps addresses with no RAM, as the machine has 4K from $0000 ($1000-$BFFF) on target t.
section BSS ($2A9D-$2CA1) overlaps addresses with no RAM, as the machine has 4K from $0000 ($1000-$BFFF) on target t.
The program does not fit: from $0300 its sections take 10658 bytes (CODE 4247, RODATA 5894, BSS 517), and the free RAM there ends at $0FFF, 3328 bytes, so it is 7330 bytes over.
```

**A target's `memoryMap`** changes its map: its `free` areas leave the reserved areas they overlap (a game that draws
on hi-res page 1 frees it this way), its `reserved` areas leave free RAM, and its `load` and `zeroPage` replace the
map's.

The bare maps, from the ROM sources and the emulator (a test checks names from each `<machine.inc>` against them):

| Map | Loads at | Free RAM | Zero page |
| --- | --- | --- | --- |
| `apple2-48k`, `-32k`, `-16k` | `$6000`; `$0800` at 16K | `$0300-$03CF`, `$0800` to the top of RAM | `$06-$09`, `$FA-$FD` |
| `apple1-4k` to `-32k` | `$0300` | `$0280` to the top of RAM | all but the Woz Monitor's `$24-$2B` |
| `apple3` | `$2000` | `$0200-$03FF`, `$0C00-$BFFF` | `$00-$BF` |
| `pet-4k` to `-32k` | `$0800` | `$0400` to the top of RAM | `$00-$8C`, BASIC's, while it isn't running |
| `bbc-32k` (model B), `bbc-16k` (model A) | `$2000` | from PAGE (`$1900` with the DFS, `$0E00`) to MODE 7's screen | `$70-$8F` |

The `wozmon` maps, `apple1-4k` to `-32k`, are the bare Apple-1's but for their descriptions (a test checks it): a
program typed in as hex, or read from the cassette interface's tape, loads where a bare one does, and runs with the
Woz Monitor as a bare one does.

The `dos33` maps, `apple2-48k` and the Apple II's `apple2-ii-48k`, are the bare one's with DOS 3.3 reserved from
`$9600` (its three file buffers, then DOS itself from `$9D00`), as the SDK builds DOS for a 48K machine: a target with
less RAM has no map. They also reserve HELLO, which BASIC is still running as the program loads: AppleSoft's at
`$0801` with its variables to `$08FF`, and on the II, Integer BASIC's variables there and its program below HIMEM,
`$9500-$95FF`. They load at `$6000` and have the bare map's zero page, which neither the Monitor nor DOS 3.3 uses.

The `dfs` maps, `bbc-32k` (the model B) and `bbc-16k` (a model A, with the disk interface its launch fits), load at
PAGE, `$1900`, where `*RUN` puts the program. The model B's is its bare map with that load address; the model A's
also reserves the DFS's workspace below PAGE, `$0E00-$18FF`, which a bare model A, with no DFS, has free.

The `basic` maps, `pet-4k` to `-32k`, are the bare ones with the PRG's BASIC line reserved, `$0400-$040F` (the zero
before BASIC's program, then `10 SYS` and the entry), and load at `$0410`, where the program follows the line.

A bare Apple III program runs before SOS, in the power-on state: its zero page is physically the system bank's
`$FF00` page, whose `$FFCA-$FFCF` are the NMI and IRQ vectors, so the map leaves `$C0-$FF` to the machine. The
Apple-1's Woz Monitor points IRQ and BRK at `$0000` and NMI at `$0F00`, so a program that takes an interrupt puts its
handler there. The model B's free RAM starts at PAGE with its DFS fitted, `$1900`, as the emulator boots it (OSHWM at
`$0244` reads `$19` once the MOS has started).

## Environments

A target's environment decides how its program is loaded and started, and the file and image it is built as. The
build assembles every environment's program the same way, at its map's `load`, into one block, and writes
`artifacts/<target>/<name>.bin` with its debug information and map; the environment writes its own file and its
image beside them. `retrocore build` prints a line for each, and `obj/<target>/build.json` gives them as `file` and
`image`.

| Environment | Its file | Its image | A launch |
| --- | --- | --- | --- |
| `bare` | the binary | none | loads the binary into RAM and starts at its entry |
| `wozmon` | `<name>.hex`, the Woz Monitor's hex: lines that store the bytes from `load`, then `<entry>R` | `<name>.wav`, an ACI tape of the bytes, which `C100R` and then `start.endR` read | loads the binary as if its hex had been typed, and starts at its entry as `R` would |
| `dos33` | the binary, as the B file it is on the disk | `<name>.dsk`, a DOS 3.3 disk (DOS order) with DOS, `HELLO`, the program as a B file named for the project in capitals, and the target's `files` | boots the disk from slot 6, and `HELLO` starts the program: `BRUN` when its entry is its first byte, else `BLOAD` and `CALL` |
| `basic` | `<name>.prg`, loading at `$0401`: the line `10 SYS<entry>`, zeros to `$0410`, then the program | `<name>.tap`, a TAP tape of the PRG, and `<name>.d64`, a 4040 disk (CBM DOS 2) with it as a program file, each under the project's name in capitals | puts the tape in cassette 1 with PLAY down, types `LOAD` at BASIC's prompt and `RUN` once the program is in; with `"image": { "boot": "disk" }`, boots the disk in unit 8 with `LOAD"<NAME>",8` instead, which needs the 4040's ROMs (below) |
| `dfs` | `<name>.uef`, a UEF tape of the same files, for `*TAPE` and `*RUN` | `<name>.ssd`, a DFS disk (80 tracks, one side) titled for the project, with the program as `$.<NAME>` (the project's name in capitals, cut to 7), the target's `files`, and `$.!BOOT`, `*RUN <NAME>`, with the boot option set to `*EXEC` it | boots the disk from drive 0, holding SHIFT from power-on as SHIFT-BREAK does, and `!BOOT` runs the program |

A launch that boots an image builds it as `retrocore build` does, puts it in its drive after a saved machine's media
and the recovery journal's disks have gone in, so the program debugged is the one just built (a changed disk it
replaces is kept, as one the machine ejects is), and runs the machine with nothing tracked until an instruction starts
at the program's entry with its bytes in memory. There it stops, or runs on, as a `bare` launch does from its entry.
The image goes in from memory, so what the program writes to it never reaches the build's output. A target with
`"image": false` builds, but cannot launch. On the Apple II, a `dos33` launch gives the machine the Autostart ROM,
which boots the disk at power-on, and its target cannot give the Disk II's options. A `dfs` launch fits the disk
interface and holds SHIFT, and its target cannot give `disks`, `boot` or `diskInterface`. No launch that boots an
image takes `bootSeconds`: the machine boots the image from power-on.

A target's fields for its media, which an environment that has no use for one refuses, naming it:

- **`files`**: data files put beside the program on its disk, each a path (relative to the project's folder, with
  `${obj}` for its `obj/`, so a step's output can go on the disk) or `{ "path", "name", "address" }`, giving its name
  on the disk and the load address the disk records. Neither `bare` nor `wozmon` has a disk. On a `dos33` disk each
  is a B file, named by `name` or its file name in capitals, at `address` or `$0000`, which a program loads where it
  wants with `BLOAD` and `,A`. On a `dfs` disk each is `D.NAME`, in directory `D`, or `NAME` in `$`, by `name` as given,
  or its file name without its extension in capitals, at `address` or `&0000`, which a program loads where it wants
  with OSFILE. On its tape the name is `D.NAME` too, and the bare `NAME` for `$`, so OSFILE finds it under `*TAPE` by
  that name.
- **`image`**: `false` leaves the image out (the `wozmon` tape), and `{ "template": "<disk>" }` starts it from a
  disk where the environment can.
- **`image.boot`**: which image a launch boots, where an environment builds more than one: `basic`'s `tape` (the
  default) or `disk`.
- **`bootImage`**: the folder of boot media or device dumps that are not SDK sources, for an environment that needs
  some: a `basic` target's 4040 ROMs.

**Boot media.** [`boot-media.json`](boot-media.json) lists the dumps the SDK cannot build, each file with the SHA-1 its
usual source publishes. Today that is the 4040's ROMs, MAME's `c4040` set (DOS 2.0 revision 2, the controller's
901466-04 and the GCR PROM 901467), which only booting a `basic` target's disk needs; its tape plays from the SDK's
sources alone. A launch finds a set's files by size and hash, whatever their names, in the target's `bootImage`, the
launch's `romDirectory`, the machine's ROM folder variable (`RETROCORE_PET_ROMS`) and `RETROCORE_CACHE` (by default `%USERPROFILE%\Retrocore`),
each with its subfolders, and copies them under their usual names to `obj/<target>/media/c4040/` for the machine to load. When
one is missing, the launch fails naming each file, its hash, where it looked and where to put them. There is no
download for them: they are the user's own dumps.

Each target also assembles its environment's platform folder, `src/platform/<environment>/`, after its family's and
its model's: a file there takes the place of theirs of the same name, so an environment can give its own console or
the code that loads a program's data from its disk.
