# Devices

Each machine lists the devices installed in it, such as its floppy and tape drives, with what they are and
what they are doing. The debugger sends that list to VS Code, whose **Retro Devices** view shows it while a
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
| IIe | `model`, `memory`, `builtIn`, `gamePort` (the game controllers driving it), `auxiliary` (the extended 80-column card, always installed), `slot1` to `slot7` (4 the Mockingboard, 6 the Disk II and 7 block storage when the launch or Add Card installs them, and any of them the mouse card, a ProFile card or the 3.5 disk controller) |
| II, II Plus | `model`, `memory`, `builtIn`, `gamePort`, `d0Socket` (the II only: Programmer's Aid #1 or empty, as the launch's `programmersAid` says), `slot0` (the language card, a firmware card with the other BASIC, or empty, as the launch's `slot0` says), `slot1` to `slot7` (as the IIe's, and slot 3 takes a card too) |
| Apple III | `model`, `memory`, `rom`, `disk` (the built-in controller with its four drives), `environment`, `slot1` to `slot4` (a ProFile card or empty) |
| Model I | `model`, `rom`, `memory`, `cassette`, `expansion`, `disk` (the controller and its doubler, with its drives), `lowercase` |

An empty slot's `value` is `empty`, and its `description` says what installs something there. A row's `actions`
say what `retro/hardware` can do to it: `addCard` on a free IIe slot (1, 2, 4 and 5, 6 without a Disk II, and 7
without block storage) or II and II Plus slot (those, 3, and an empty 0) or Apple III slot (1 to 4), `removeCard` on a Disk II card, the
Mockingboard, the mouse card, a ProFile card, the 3.5 disk controller, or the language or firmware card in slot 0. A ProFile card goes in any
of them; the Apple III takes no other card.

```json
{ "id": "slot5", "action": "addDiskII", "sectors": 16 }
{ "id": "slot4", "action": "addMockingboard" }
{ "id": "slot2", "action": "addMouse" }
{ "id": "slot5", "action": "addDisk35" }
{ "id": "slot4", "action": "addProFile" }
{ "id": "slot0", "action": "addLanguageCard" }
{ "id": "slot0", "action": "addFirmwareCard" }
{ "id": "slot5", "action": "removeCard" }
```

`retro/hardware` changes the machine at once, running or stopped, and returns the new `retro/devices` body. A Disk
II added to a slot answers at $C080 plus 16 times the slot and at its ROM page, $Cn00, with firmware built from the
SDK's sources (16- or 13-sector), so `PR#5` boots it, and the startup scan finds it after a reset. Its drives are
`slot5disk1` and `slot5disk2`; slot 6's keep `disk1` and `disk2`. The 3.5 disk controller, one per machine, answers the
same way with the SDK's own firmware (`Disk35.rom.asm`); its drives are `disk35d1` and `disk35d2` in whichever slot it
is. Removing a card ejects its disks. The changes last
for the session; the launch configuration is unchanged. The session sends the same body as a `retro/devices` event whenever any device's
state changes: on each stop, and with the running frames while the machine runs.

The body's `configuration` is what a later launch can restore: each slot's card (`languageCard` or `firmwareCard` in
slot 0 of a II or II Plus, `mockingboard`, `mouse`, `proFile`, `disk35`, `diskII16` or `diskII13`; `diskII` for one with the launch's ROM dumps, `blockStorage`, or
`empty`), and the media in each drive
that takes media, null when it is empty. Media the host cannot insert again, such as a disk a `dos` launch built or a
tape being recorded, is left out.

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
```

An action the device does not support is an error. A recording is saved to its path when its tape is ejected.
Disks the machine changes are not yet written back to their image files; `changed` shows that they differ.

## The Retro Devices view

The view is in the **Run and Debug** sidebar whenever no other debugger runs. Before a session starts, its
welcome text and title-bar **Start Machine** (`▶`) button start a machine without a `launch.json`.

While a Retrocore session runs, the view lists **BASIC program** first when the machine has a supported BASIC
(showing the active dialect and line count, and opening **Retrocore: Open BASIC Program** when clicked), then
the machine's installed hardware slot by slot, with each device under the card or option it sits on: Slot 6's
Disk II drives under Slot 6, the Model I's drives under its disk controller. Hovering a row says what it does
and which launch option installs it. Each device shows its media, its
head or tape position and what it is doing, such as `newdos.dsk · track 17 sector 4 · reading`; its icon is
green while it reads, red while it writes and yellow while it seeks. Expanding a device lists its state and
metadata, and hovering it shows them all.

A device's inline buttons insert media (an open dialog filtered to its formats), record to a new tape, eject,
and protect or unprotect a disk, each as the device allows. A hardware row's inline buttons add or remove cards,
and the view's title bar refreshes the list or resets a launch configuration's saved cards and media
(**Retrocore: Reset Saved Machine...**). The view redraws at most ten times a second.
