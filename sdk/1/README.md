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

A bare Apple III program runs before SOS, in the power-on state: its zero page is physically the system bank's
`$FF00` page, whose `$FFCA-$FFCF` are the NMI and IRQ vectors, so the map leaves `$C0-$FF` to the machine. The
Apple-1's Woz Monitor points IRQ and BRK at `$0000` and NMI at `$0F00`, so a program that takes an interrupt puts its
handler there. The model B's free RAM starts at PAGE with its DFS fitted, `$1900`, as the emulator boots it (OSHWM at
`$0244` reads `$19` once the MOS has started).
