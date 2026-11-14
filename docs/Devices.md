# Devices

Each machine lists the devices installed in it, such as its floppy and tape drives, with what they are and
what they are doing. The debugger sends that list to VS Code, whose **Machine** and **Drives** views show it while a
Retrocore session runs, and takes media actions from it.

## The object model

The model is in [`Retrocore.Core`](../src/Retrocore.Core/Machines/Devices), so every machine shares it.
`IMachine.Devices` lists a machine's devices in the order its documentation does. Every property reads state
without side effects, so a debugger can show it at any time, even mid-instruction.

| Type | What it is |
| --- | --- |
| `IDevice` | Any device: its `Id` (stable for the machine's configuration, such as `disk0`), `Kind`, `Info`, `Media` and `Activity`. |
| `DeviceInfo` | What the device is, which does not change while the machine runs: `Name`, `Description`, `Controller`, the image `Formats` the host can insert, the `Operations` it allows (insert, eject, record, write protect), and its `Tracks` and `Sides`. |
| `MediaState` | The media in it: the host's `Label` for it (such as the image's path), its `Format`, whether it is `WriteProtected`, and whether the machine has `Changed` it since it was inserted. |
| `DeviceActivity` | `Idle`, `Seeking`, `Reading` or `Writing`. |
| `IDiskDrive` | A floppy drive. Its `Head` gives the motor, whether the controller has selected it, the track (with a fraction for a drive that steps in quarter tracks), the side, and the sector the controller is working on. |
| `ITapeDrive` | A tape drive. Its `Transport` gives the motor, the mode (stopped, playing or recording), and the bytes played or recorded and the tape's length. |
| `IBlockStorage` | Storage addressed by block, with its `BlockCount` and the `LastBlock` the machine read or wrote. |

Inserting media belongs to the concrete devices, since the image formats are the machine's own:
`Trs80FloppyDrive.Insert(FloppyDisk, label, format)`, `Trs80CassetteDrive.Play` and `Record`, and
`Apple2FloppyDrive.Insert(WozDisk, label, format)`.

### The machines' devices

| Machine | Device | Id | Notes |
| --- | --- | --- | --- |
| Model I | Cassette | `cassette` | Plays and records CAS images. A playing tape shows as write-protected, and a recording as changed once it holds a byte. |
| Model I | Drive 0-3 | `disk0`-`disk3` | Present with the Expansion Interface's disk controller. JV1 and JV3 images; write protection can be changed. Drive 3 is single-sided, since its select line is the other drives' side select. The activity follows the FD1771's command: stepping and verifying seek, write sector and write track write, and the others read. |
| Apple II | Drive 1-2 | `disk1`, `disk2` (slot 6); `slotNdisk1`, `slotNdisk2` (other slots) | Present for each installed Disk II card: slot 6 from a floppy `diskImage`, `dos` or `diskController: "diskII"`, and any free slot via **Add Card**. Its ROMs are the SDK's 16- or 13-sector builds ([DiskII.md](DiskII.md)), or dumps given for slot 6 as `diskBootRom` and `diskSequencerRom`. Takes WOZ images, and DOS-order (`.dsk`, `.do`), ProDOS-order (`.po`) or 13-sector (`.d13`) sector images converted to WOZ. A disk loads write-protected; taking the protection off lets the machine write it, in memory. The head reads while the motor turns and writes in the card's write mode; the track counts quarter tracks. |
| Apple II | 3.5 drive 1-2 | `disk35d1`, `disk35d2` | Present while the 3.5 disk controller is in a slot (`disk35`, or **Add Card**). SuperDrives: 400K and 800K Apple disks and 720K and 1440K MFM disks, from `.po`, `.2mg`, `.hdv`, `.img` and 3.5-inch `.dsk` images; write protection can be changed. The head is where the last block was, its track, side and sector by the disk's layout; a block shows as reading or writing for a thirtieth of a second. A program's CONTROL eject takes the disk out. |
| Apple II, Apple III | ProFile (slot N) | `slotNprofile` | Apple's ProFile hard disk on a ProFile card (`proFiles`, or **Add Card**). Takes ProDOS-order images (`.po`, `.hdv`) of up to 65535 blocks, which the machine can write; inserting and ejecting are allowed. A block it reads or writes shows as reading or writing for a thirtieth of a second. |
| Apple II | Slot 7 disk | `slot7` | The ProDOS block device given at launch (a `.po` `diskImage`, unless `diskController: "diskII"` asks for the Disk II). Its media is fixed; a block command shows as reading or writing for a thirtieth of a second. |

## The debug protocol

`retro/devices` returns `{ devices: [...] }`, one object per device:

```json
{
  "id": "disk0", "kind": "floppyDrive", "name": "Drive 0",
  "description": "5¼-inch floppy drive",
  "controller": "FD1771 with a Percom doubler's WD1791, in the Expansion Interface",
  "formats": ["dsk", "jv1", "jv3"], "operations": ["insert", "eject", "writeProtect"],
  "tracks": 40, "sides": 2,
  "media": { "label": "C:\\disks\\newdos.dsk", "format": "JV1", "writeProtected": false, "changed": false },
  "activity": "reading",
  "head": { "motor": true, "selected": true, "track": 17, "side": 0, "sector": 4 }
}
```

A tape drive has `transport` (`motor`, `mode`, `position`, `length`) instead of `head`, and block storage has
`blocks` (`count`, `last`).

The body also has `hardware`, the machine's installed hardware in order: built-in parts, then each slot or
option, empty ones included. Each row names the devices on it, by id:

```json
{ "id": "slot6", "name": "Slot 6", "value": "Disk II controller",
  "description": "Two 5.25-inch drives. The launch installs it with diskController diskII, ...",
  "devices": ["disk1", "disk2"], "actions": ["removeCard"] }
```

| Machine | Rows |
| --- | --- |
| IIe | `model`, `memory`, `builtIn`, `gamePort` (the game controllers driving it), `auxiliary` (the extended 80-column card, always installed), `slot1` to `slot7` (4 the Mockingboard, 6 the Disk II and 7 block storage when the launch or Add Card installs them, and any of them the mouse card, a ProFile card, the 3.5 disk controller or the Z80 SoftCard) |
| II, II Plus | `model`, `memory`, `builtIn`, `gamePort`, `d0Socket` (the II only: Programmer's Aid #1 or empty, as the launch's `programmersAid` says), `slot0` (the language card, a firmware card with the other BASIC, or empty, as the launch's `slot0` says), `slot1` to `slot7` (as the IIe's, and slot 3 takes a card too) |
| Apple III | `model`, `memory`, `rom`, `disk` (the built-in controller with its four drives), `environment`, `slot1` to `slot4` (a ProFile card or empty) |
| Model I | `model`, `rom`, `memory`, `cassette`, `expansion`, `disk` (the controller and its doubler, with its drives), `lowercase` |

An empty slot's `value` is `empty`, and its `description` says what installs something there. A row's `actions`
say what `retro/hardware` can do to it: `addCard` on a free IIe slot (1, 2, 4 and 5, 6 without a Disk II, and 7
without block storage) or II and II Plus slot (those, 3, and an empty 0) or Apple III slot (1 to 4), `removeCard` on a Disk II card, the
Mockingboard, the mouse card, a ProFile card, the 3.5 disk controller, the Z80 SoftCard, or the language or firmware card in slot 0. A
ProFile card goes in any of them; the Apple III takes no other card yet.

```json
{ "id": "slot5", "action": "addDiskII", "sectors": 16 }
{ "id": "slot4", "action": "addMockingboard" }
{ "id": "slot2", "action": "addMouse" }
{ "id": "slot5", "action": "addDisk35" }
{ "id": "slot4", "action": "addProFile" }
{ "id": "slot5", "action": "addSoftCard" }
{ "id": "slot0", "action": "addLanguageCard" }
{ "id": "slot0", "action": "addFirmwareCard" }
{ "id": "slot5", "action": "removeCard" }
{ "id": "slot4", "action": "setSetting", "setting": "translation", "value": false }
```

A row may have `settings`, switches on its hardware, each with an `id`, a `label`, its `value` (on or off) and a
`description`. `setSetting` changes one. The Z80 SoftCard has two: `translation`, its address translation (DIP switch
S1-1 off, on by default), and `refresh`, the waiting 6502's read in each Z80 opcode fetch (on by default).

`retro/hardware` changes the machine at once, running or stopped, and returns the new `retro/devices` body. A Disk
II added to a slot answers at $C080 plus 16 times the slot and at its ROM page, $Cn00, with firmware built from the
SDK's sources (16- or 13-sector), so `PR#5` boots it, and the startup scan finds it after a reset. Its drives are
`slot5disk1` and `slot5disk2`; slot 6's keep `disk1` and `disk2`. The 3.5 disk controller, one per machine, answers the
same way with the SDK's own firmware (`Disk35.rom.asm`); its drives are `disk35d1` and `disk35d2` in whichever slot it
is. Removing a card ejects its disks. The changes last
for the session; the launch configuration is unchanged. The session sends the same body as a `retro/devices` event whenever any device's
state changes: on each stop, and with the running frames while the machine runs.

The body's `configuration` is what a later launch can restore: each slot's card (`languageCard` or `firmwareCard` in
slot 0 of a II or II Plus, `mockingboard`, `softCard`, `mouse`, `proFile`, `disk35`, `diskII16` or `diskII13`; `diskII` for one with the launch's ROM dumps, `blockStorage`, or
`empty`), and the media in each drive
that takes media, null when it is empty. Media the host cannot insert again, such as a disk a `dos` launch built or a
tape being recorded, is left out. Rows with switches add `settings`, each row's by its id, such as
`{ "slot4": { "translation": true, "refresh": false } }`, restored after the cards.

```json
{ "cards": { "1": "empty", "2": "empty", "4": "mockingboard", "5": "diskII16", "6": "empty", "7": "empty" },
  "media": { "slot5disk1": { "path": "C:\\disks\\games.dsk", "writeProtected": false }, "slot5disk2": null } }
```

The extension saves it for each launch configuration and gives it back as the launch's `machineState`, which the
host applies after building the machine from the other options: cards first, then media. A card that only the launch
can install (block storage, or a Disk II with ROM dumps) stays as the launch made it, and a disk image that no longer
exists is reported in the Debug Console and skipped.

`retro/device` acts on one device and returns the new list:

```json
{ "id": "disk0", "action": "insert", "path": "games.jv3" }
{ "id": "disk0", "action": "writeProtect", "writeProtected": true }
{ "id": "cassette", "action": "record", "path": "program.cas" }
{ "id": "cassette", "action": "eject" }
{ "id": "disk2", "action": "save" }
{ "id": "disk2", "action": "save", "path": "copy.woz" }
```

An action the device does not support is an error. A recording is saved to its path when its tape is ejected.
Disks the machine changes stay in memory, and `changed` shows that they differ from their images. An Apple drive's
`save` writes its disk to its own image, or to `path`: a `.woz` keeps the disk's tracks as they are, and a `.dsk`,
`.do` or `.po` reads them back as sectors, in DOS's or ProDOS's order. The disk then comes from that image. Other
drives don't save yet.

## A machine that is off

The language server, which is the same `Retrocore.Debug.dll`, answers two requests about a machine with no debug
session, built as a launch builds it and never run:

- `retrocore/machine/describe` takes `{ "configuration": { launch arguments }, "machineState": { saved } }`, the
  saved machine being the `configuration` above.
- `retrocore/machine/change` takes the same, plus `"request": "hardware"` or `"device"` and `"arguments"`, which are
  what `retro/hardware` or `retro/device` would take, such as `{ "id": "slot5", "action": "addDiskII", "sectors": 16 }`
  or `{ "id": "slot5disk1", "action": "insert", "path": "games.dsk" }`.

Both answer as `retro/devices` does, with the new saved machine as `configuration`, and add `problems`: what of the
saved machine could not be restored, such as a disk image that no longer exists. Nothing is kept between requests, so
the saved machine the editor holds is all of an off machine's state, and launching with it as `machineState` boots
the machine as it was described. Game controllers are not opened while off; the game port's row says they are read
while it runs. `tools/Test-OffMachine.mjs` checks that each machine lists the same hardware and devices off as
launched.

## The Machine and Drives views

Retrocore has its own icon in the activity bar, a small computer, which opens two views.

With no Retrocore session, the views show a machine that is off ([offMachine.ts](../extension/src/offMachine.ts)):
the one last started, or the one **Switch Machine…** (`⇄` in the Machine view's title bar) picks from Start
Machine's last setup, the workspace's launch configurations and the catalog's machines. The language server
describes it ([A machine that is off](#a-machine-that-is-off)) when either view comes into sight, so a closed
sidebar builds nothing. Its header says `off` with a dark screen, and its cards and media change as a running
machine's do, except that a tape cannot record and there is no changed disk to save.

Its **Settings**, the first rows under it, are the catalog's choices for the machine
([machines.ts](../extension/src/machines.ts)), the ones **Start Machine → Options…** offers; a launch.json entry
that leaves out its model is matched as the host reads it. While off, clicking one picks its value. The change goes
where the machine came from: Start Machine's setup (which **Start Last Machine** then starts), the launch.json
configuration (written there, its variables kept), or the configuration itself. Before it, the saved machine is cut
down to what differs from the machine its old settings give by themselves, so the new setting takes effect while
the cards and media someone added stay on top of it; what no longer fits is reported. While running, the settings
show the session's own values and do not change. Each change is saved as its
launch configuration's saved machine, which its next launch restores; its `▶` starts it as it came (Start Machine's
setup, the launch.json configuration, or the configuration itself). When a session ends, the views show its machine
off, with what changed while it ran. A saved disk that can no longer be restored is reported once, and a machine
that cannot be built says why at the top of the Machine view. Before any machine has started, the Machine view's
welcome text offers **Start Machine** and **Set Up a Machine**; its **...** menu always has **Start Machine…** and
**Start Last Machine**.

While a Retrocore session runs, the **Machine** view is headed by the machine itself, such as `Apple IIe` with
`Enhanced, 65C02 · running`: its screen icon is lit while it runs and dark while it is stopped in the debugger.
Under it is the installed hardware, slot by slot, empty slots dimmed and a slot with drives saying how many. Below
the machine is **BASIC program** when the machine has a supported BASIC (showing the active dialect and line
count, and opening **Retrocore: Open BASIC Program** when clicked). Hovering a row says what it does and which
launch option installs it.

The **Drives** view lists each card or option that has drives, with its drives under it: Slot 6's Disk II drives
under Slot 6, the Model I's drives under its disk controller. Each drive shows its media, its head or tape
position and what it is doing, such as `newdos.dsk · track 17 sector 4 · reading`; its icon is green while it
reads, red while it writes, yellow while it seeks and dimmed while it is empty. Expanding a drive lists its state
and metadata, and hovering it shows them all. The view's badge counts the disks changed and not yet saved to
their images.

A drive's inline buttons insert media (an open dialog filtered to its formats), record to a new tape, eject,
protect or unprotect a disk, and save a changed disk to its image (**Save to Its Image**, which asks first; **Save Disk
As...** in its menu saves to another), each as the drive allows. A slot's inline buttons in the Machine view add or
remove cards. The Machine view's title bar opens memory (**Retrocore: Open Memory...**) and refreshes both views,
and its **...** menu resets a launch configuration's saved cards and media (**Retrocore: Reset Saved
Machine...**). The views redraw at most ten times a second.

The **Favorites** view ([favorites.ts](../extension/src/favorites.ts), the favorite itself in
[favorite.ts](../extension/src/favorite.ts)) lists the `retrocore.favorites` setting: in user settings, and the
workspace's, grouped under **User** and **Workspace** when both have some. A favorite is a Start Machine setup (the
catalog machine, its settings that differ from their defaults, and what it runs) with a name, a description and the
saved machine; a launch.json machine is kept as the setup it amounts to, so launch options Start Machine cannot set
are not. Loading one sets it up off under its own name, which names its launch configuration and saved machine, with
its saved machine as that one's; starting one loads it and boots it through Start Machine, so **Start Last Machine**
repeats it. A name is one favorite across user and workspace settings, as it names the favorite's launch configuration and
saved machine; one with no saved machine loads as its launch gives it, dropping edits made to it since. Changes to an
off machine run one at a time, each from the saved machine the one before left. In user settings a favorite's paths
are kept as they are; in the workspace's, paths inside the workspace
are written as `${workspaceFolder}/...`, and moving a favorite between the two converts them.

The Machine view's heart, on the machine's row, says whether the machine shown is a favorite. The machine is one when
it was loaded from one (its name is the favorite's) or was saved as one (the extension links the launch
configuration's name to the favorite's). Its heart is empty when it is not one, and clicking it saves the machine at
once under its machine's name, numbered if taken, and links it. Filled, the favorite matches the machine as it is
now, and clicking it reveals the favorite in the Favorites view. Broken, it differs, in its settings, what it runs,
its cards, or its disks and tapes (`differences` in favorite.ts, which ignores empty slots and drives), and clicking
it updates the favorite. The machine's tooltip names the favorite and what differs.

VS Code opens Run and Debug as a session starts and when it breaks (its `debug.openDebug` setting). When that
takes the sidebar from the Retrocore views within a moment of a Retrocore session starting or stopping, the
extension reveals the Machine view again without focusing it, so the keyboard stays with the display panel or the
editor.
