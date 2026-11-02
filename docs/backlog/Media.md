# Backlog: the media library and explorers

Status: **not started**. Today [`Retrocore.Media`](../../src/Retrocore.Media) holds only what the machines need to
run. This design turns it into a library for reading, writing and browsing retro media, with four ways to use
it.

## What exists

| Type | For |
| --- | --- |
| `IBlockDevice`, `MemoryBlockDevice` | The Apple II's slot-7 ProDOS block device. |
| `WozDisk`, `DiskTrack`, `DiskBitWriter`, `SectorDiskConverter` | Disk II bit-level tracks, from WOZ or from DOS-order, ProDOS-order and 13-sector (`.d13`) sector images. |
| `DosDisk`, `DosFile`, `DosFileType` | Building bootable DOS 3.3 and 3.2 disk images and files. |
| `FloppyDisk`, `FloppySector`, `Jv1Format`, `Jv3Format` | Model I floppies as sectors with their IDs, density and marks. |
| `CassetteImage` | Model I CAS tapes. |

The debugger reads unadorned ProDOS-order (`.po`) images itself, as their 512-byte blocks in order. CiderPress2
comes in with the adapter below, in its own assembly; nothing depends on it today.

## The model

Three layers, each usable without the ones above it:

1. **Images.** A format reads and writes a container: WOZ, 2MG, DSK/DO/PO, NIB, JV1, JV3, DMK, CAS, WAV.
   Formats are found by content first and extension second, report what they could not represent, and keep
   unknown chunks so a round trip loses nothing.
2. **Physical media.** What a drive sees:
   - flux or bit tracks (`DiskTrack`);
   - sectored tracks with IDs, density, deleted marks and errors (`FloppyDisk`);
   - blocks (`IBlockDevice`);
   - tape bit streams (`CassetteImage`).

   Converters move between them where that loses nothing, and say what is lost where it does.
3. **Filesystems.** A volume over physical media, with directories, files and file attributes. These come from
   CiderPress2 for Apple formats; TRSDOS, NEWDOS/80 and LDOS are ours. Writes go through the filesystem, so a
   change to a file updates the disk the machine sees.

A **media slot** connects a machine to media: a drive, a cassette deck, a slot device. A slot accepts the
physical kinds its hardware reads, notifies its machine of changes, and tracks whether the media is dirty so
the host can save it back. The debugger's `retro/media` request and the Model I's tape and disk commands become
its first clients, and the Apple II's Disk II and block device move onto it.

The [device model](../Devices.md) is the read side of this already: each machine lists its drives with their
media, head and activity, and whether the machine has changed the media. A slot adds the media library's
images behind those devices, so inserting takes any format the library reads and a changed disk can be saved
back to its image.

## The CiderPress2 adapter

CiderPress2 already reads and writes the Apple formats and filesystems: DOS 3.3, ProDOS, Pascal, CP/M and HFS,
and archives such as ShrinkIt and Binary II. We adapt rather than port it:

- `Retrocore.Media.CiderPress` wraps `DiskArc` behind our filesystem interfaces, so callers never see CiderPress2
  types;
- our physical layer stays the authority for timing-sensitive media (WOZ bit tracks), with CiderPress2 reading
  their decoded sectors;
- the adapter is an optional package, so the machines and the core library do not depend on it.

## Explorers

All four share one model and differ only in presentation:

- **API.** `MediaLibrary.Open(path)` returns the image, its physical media and its volume, with
  `Volume.Files`, `File.OpenRead()` and `File.Write(...)`.
- **CLI.** `retrocore media ls|cat|get|put|rm|mkdir|convert|info`, with paths such as
  `disk.dsk:/BASIC/HELLO`. `convert` changes the image format (for example JV1 to JV3, or DSK to WOZ) and
  reports anything the target cannot hold.
- **VS Code view.** A tree of mounted and workspace images beside the debugger. You can open a BASIC file as
  detokenized text, drag a file in or out, and mount an image into the running machine's slot.
- **Avalonia app.** A desktop browser for people who do not use VS Code: open, browse, extract, add and
  convert, sharing AppleSharp's packaging.

## Order of work

1. The three-layer interfaces, with what exists today moved behind them.
2. Media slots, with dirty tracking and save on eject; then the Model I's disk write-back.
3. TRSDOS and NEWDOS/80 directories, read-only first, then the CLI's `ls`, `get` and `info`.
4. The CiderPress2 adapter, and the Apple II's Disk II on media slots.
5. Writes, `put` and `convert`, and then the VS Code view and the Avalonia app.

## Testing

Format round trips are byte-exact, and the tests carry their own fixtures, built in code like the Model I's
JV1-to-JV3 boot test. Images we may not distribute stay external, like the ROM dumps. The NEWDOS/80 image
already serves for a directory listing, which must match what `DIR` prints on the emulated machine.
