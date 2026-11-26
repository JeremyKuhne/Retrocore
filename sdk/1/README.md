# The SDK's headers, major version 1

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
