# Backlog: saving media back to images

How disks, tapes and other media the machines change get back to image files, on every machine and in every format.

**Status:** proposed 2026-11-14, for review; nothing here is approved or built. The [UI workflow](#the-ui-workflow)
is a first proposal to settle together before the rest.

Today one drive saves: the Disk II's `save` ([Devices.md](../Devices.md#the-debug-protocol)), on the Apple II and
the Apple III. Every other disk keeps its changes in memory until the session ends, and then they are gone. Tapes
being recorded are written when they are ejected. This plan gives every medium one model, one set of rules for
when and how it is written, and one safe way to write it, so later save actions are not added drive by drive.

It takes over the second step of [the media library's order of work](Media.md#order-of-work) ("media slots, with
dirty tracking and save on eject; then the Model I's disk write-back"). The media library's image layer, when it
comes, plugs into the same interface.

## What there is

| Machine | Device | Formats | Changes held as | Saves |
| --- | --- | --- | --- | --- |
| Apple II, Apple III | Disk II drives (`Apple2FloppyDrive`) | `.woz`; `.dsk`, `.do`, `.po`, `.d13` converted to WOZ | `WozDisk` bit tracks, with `IsDirty` and `Version` | `save` to `.woz` (tracks as they are) or `.dsk`/`.do`/`.po` (decoded back to sectors); atomic, through a temporary file; asks first in the Drives view |
| Apple II | 3.5 drives (`Apple2Disk35Drive`) | `.po`, `.2mg`, `.hdv`, `.img`, 3.5-inch `.dsk` | `Disk35Disk` blocks, with `IsDirty` and `Version`; the drive's own `Changed`; `ToImage()` gives the raw blocks | no |
| Apple II, Apple III | ProFile (`ProFileDrive`) | `.po`, `.hdv` | `MemoryBlockDevice`, a `_changed` flag | no |
| Apple II | Slot 7 block storage (`Apple2BlockStorage`) | `.po` | `MemoryBlockDevice`; `BlockWritten` on the bus | no; its media is fixed |
| Model I, III, 4, II | Floppy drives (`Trs80FloppyDrive`) | JV1 (`.dsk`), JV3, DMK, IMD | `FloppyDisk` sectors; a per-drive `Changed` in the controller | no; `Jv1Format.Write` and `Jv3Format.Write` exist, DMK and IMD have no writer |
| Model I, III, 4 | Cassette (`Trs80CassetteDrive`) | `.cas` | `CassetteImage` bytes | a recording is written on eject (`File.WriteAllBytes`, not atomic) |
| CoCo | Cassette | `.cas` | `CassetteImage` | as the TRS-80's |
| CoCo | Floppy drives (`Trs80FloppyDrive` on `CocoDiskController`) | `.dsk`, `.jvc` | `FloppyDisk` | no; `JvcFormat.Write` exists |
| CoCo | ROM pack (`cartridge`) | ROM image | ROM; not a device | never: read-only |
| Apple-1 | Cassette (`Apple1CassetteDrive`) | `.wav` | `Apple1Tape` | a recording is written on eject, as `ToWave()` |
| Altair | none yet | SIMH 8-inch `.dsk` when the 88-DCDD comes ([Altair8800.md](Altair8800.md)) | | |
| AppleSharp | Slot 7 `FileBlockDevice` | `.po` | none: writes go straight to the file when opened writable | write-through |

What the saved machine and the views already do:

- `MediaState` has `Label`, `Format`, `WriteProtected` and `Changed`. `Changed` means "written since inserted",
  and `Saved(...)` on the Disk II resets it.
- `MachineConfiguration.Capture` keeps each drive's `path` and `writeProtected`, and leaves out media that cannot
  be inserted again: a disk a `dos` launch built, a tape being recorded. Changes are not kept.
- The Drives view shows `changed`, its badge counts changed disks that can be saved, and **Save to Its Image**
  (which asks) and **Save Disk As...** send `save`. The display panel's Disk II line shows `changed`. When a session
  ends, nothing asks about changed disks.
- Write protection differs: a Disk II disk loads protected (a WOZ also by its INFO flag), a 3.5-inch disk loads
  writable unless a 2MG locks it, a ProFile loads writable.

## The model of a changed medium

Every medium in a drive has three things, which the machines' types share through `Retrocore.Core`:

- **Its source**: where it came from. One of
  - an **image**: its full path, its format, and the file's stamp when it was read (length, last write time and
    SHA-256 of the bytes read, which are in memory anyway);
  - **built**: made by the host, such as a `dos` launch's disk, with no file;
  - **blank**: a new disk or tape, with no file;
  - **recovered**: an unsaved copy the host kept at the end of a session (below), with the image it belongs to, if
    any.
- **Its version**: a count that changes on every write, as `WozDisk.Version` and `Disk35Disk.Version` do now.
  Media whose writes are not counted yet (`FloppyDisk`, `MemoryBlockDevice`, the ProFile) get one.
- **Its saved version**: the version last written to its source, or loaded from it. The medium is **changed** when
  the two differ, which replaces today's "written since inserted": saving clears it, and a write after a save sets
  it again. A built or blank medium is changed from the start, as nothing holds it yet.

A device that can save says so with `MediaOperations.Save` and implements one interface in `Retrocore.Core`:

```csharp
public interface ISavableMedia
{
    MediaSource? Source { get; }
    long Version { get; }
    long SavedVersion { get; }
    IReadOnlyList<SaveFormat> SaveFormats { get; }      // what it can be saved as, and what each loses
    MediaImage Export(string format);                    // the file's bytes and anything the format cannot hold
    void Saved(MediaSource source, long version);        // the medium now comes from this image
}
```

The machines never touch files. They export bytes and say what is lost; the host (`Retrocore.Debug`) does all file
work in one place, `MediaFiles`, so atomic writes, stamps, conflicts and backups are written once. `Saved` takes the
version that was exported, so a write the machine makes while the file is being written leaves the medium changed.

## When media is written

| When | What happens | Default |
| --- | --- | --- |
| **Save** | The medium is written to its source image, in the source's format. | asks first |
| **Save as** | Written to a path and format the user picks; the medium then comes from it. | the dialog asks about replacing a file |
| **Eject**, by the user | A changed disk: the user picks save, save as, discard or cancel. | asks |
| **Eject**, by the machine (a 3.5 drive's CONTROL eject) | Nothing can ask in time: the ejected disk is kept as a recovered medium, and the drive offers it until the session ends. | keeps |
| **Recording a tape** | Written to its path when ejected, or when the session ends, as now, but atomically and without replacing a file that was there before the recording started unless the user said so. | writes |
| **Session end** | Changed media is kept as recovered copies, never written to its images; the off machine shows it changed and offers to save it. | keeps |
| **Autosave** | Only to recovered copies: while the machine runs, changed media is copied there every 30 seconds, so a crash loses little. Never to the user's images. | on |
| **Write-through** | Each write goes straight to the file, as AppleSharp's `FileBlockDevice` does. Only for raw block images (`.po`, `.hdv`, `.img`, ProFile, slot 7), only when asked per drive, and the file stays open. | off |

What each device allows:

| Device | Save | Save as | Write-through |
| --- | --- | --- | --- |
| Disk II | `.woz`, `.dsk`, `.do`, `.po` | the same; `.d13` needs a 13-sector reader first | no |
| 3.5 drive | its own format, 2MG rewrapped | `.po`, `.2mg`, `.hdv`, `.img` | raw images only |
| ProFile, slot 7 | `.po`, `.hdv` | the same, and `.2mg` | yes |
| TRS-80 and CoCo floppies | JV1 if it still fits, JV3, JVC; DMK and IMD once they have writers | JV3 always; JV1, JVC, DMK and IMD when the disk fits | no |
| Cassettes | the recording | `.cas` or `.wav` | no |
| CoCo ROM pack | never | never | no |
| Altair 8-inch disk (later) | SIMH `.dsk` | the same | possible: its sectors are raw |

## What each format keeps

A save never converts silently. Saving to a format that cannot hold the medium as it is is an error that names what
would be lost, and the user can save anyway, save as a format that holds it, or cancel. Saving an unchanged medium
to its own format gives back the same bytes, and the tests check that for every format.

| Format | Round trip | What can be lost |
| --- | --- | --- |
| **WOZ** | lossless: `Export` keeps the tracks, their lengths, quarter-track map and unknown chunks | a WOZ1 image is written as WOZ2; the plan keeps that and says so on save, as WOZ1 writers are rare |
| **`.dsk`, `.do`, `.po` (5.25)** | lossless while every track decodes as 16 standard sectors | a track that no longer decodes (a copy-protected track, a half-finished format, a track written by a nibble copier) fails the save, naming the tracks; save as `.woz` keeps them. Sector images carry no volume number, so a DOS volume other than 254 is lost; that is reported too |
| **`.d13`** | reads only | no 13-sector reader back from WOZ yet; save as `.woz` until there is one |
| **2MG** | lossless once the header is kept: the creator, version, comment and creator-data chunks, and the flags | today `Disk35Disk` drops the header on load. It keeps the header and rewraps the blocks on export. The **locked** flag is the image's own write protection: a locked image loads protected, unprotecting it in the drive does not unlock the file, and saving to it is refused (save as, or unlock it on purpose with a separate `unlock` save option) |
| **`.po`, `.hdv`, `.img`, 3.5 `.dsk`** | lossless: raw blocks | nothing |
| **JV1** | lossless while the disk stays single-sided, single-density, ten 256-byte sectors on every track, with `$FA` marks only on track 17 | a double-density track, another sector size, a missing sector or a deleted mark elsewhere; save as JV3 |
| **JV3** | lossless for what `FloppyDisk` holds: IDs, density, sizes, data marks, sides, the write-protect byte, and its CRC-error flags | nothing `FloppyDisk` holds; `Jv3Format.Write` already writes its 2,901-entry tables and the protect byte |
| **DMK** | no writer yet | a writer is needed to save in place; it can hold everything `FloppyDisk` does, gaps included |
| **IMD** | no writer yet | a writer, keeping the comment header and the per-track mode bytes |
| **JVC** | lossless for uniform disks: one sector size and count on every track | a disk the machine reformatted unevenly; save as JV3 |
| **CAS** | the decoded bytes the machine wrote, which is all it reads back | timing, silences between blocks and the analog signal, which no CAS holds. A tape written at the Model III's 1500 baud is kept as bytes too |
| **WAV** | the Apple-1's only tape format: the signal as recorded | none from a recording. Saving a CAS tape as WAV is lossless for the machine (we generate the signal); reading a WAV as CAS needs a decoder and loses whatever does not decode, so that conversion waits for the media library |

## Write protection

One rule for every disk: **a disk loads with the protection its image gives it, and otherwise writable.** The image
gives it protection when:
- its format says so: a WOZ's INFO write-protected flag, a locked 2MG, a JV3's write-protect byte;
- its file is read-only, or its folder cannot be written;
- it is under `RETROCORE_CACHE`, which holds images we fetched and never change.

This is safe because writing the disk changes only the copy in memory; nothing reaches the file until a save.
The Disk II changes from loading every disk protected, so a program can write its own disk without first taking
the tab off. The saved machine keeps the user's choice per drive, as now, and it wins over the default.

Protection the image gives cannot be saved over: such media saves only with save as, and its tab can still be taken
off in the drive so the machine can write the copy in memory.

## Safety

- **Never silently.** Save asks first, unless the user turns that off. Save as uses the save dialog's own replace
  question. A recording does not replace a file that existed when it started without asking.
- **Atomic.** `MediaFiles.Write` writes beside the image as `.name.<guid>.saving`, flushes it to disk, and moves it
  over the image (`File.Replace` where a backup is kept), so a failed write leaves the image as it was. This is
  today's Disk II code, moved to one place, with the flush added. Tapes use it too.
- **Conflicts.** Before writing, the host reads the image's stamp again. If the file changed since it was read (by
  another program, another session, or the same image in two drives), the save stops with a `conflict` error; the
  user can overwrite, save as, or reload the file and drop the machine's changes. The same image may be in two
  drives at once, but only one of them can save it without a conflict.
- **Backups.** The first save over an image in a session keeps the image it replaces as `name.ext.bak` beside it;
  later saves in that session replace the image only. A setting turns this off.
- **Read only.** An image the host cannot write (protection above, or a write that fails with access denied) offers
  save as only, and says why.
- **No open files.** The host reads an image whole and closes it, as now, so other programs can open it; only
  write-through keeps a file open, shared for reading.
- **Recovered copies** live in the extension's global storage (`context.globalStorageUri/media`), never in the
  repository or beside the image, one file per medium in its own format with a small JSON record of its source and
  stamp. The host is given the folder at launch (`mediaRecoveryDirectory`). Resetting a saved machine, or saving or
  discarding a medium, deletes its copy.

## Saved machines

`machineState`'s media entries grow from `{ path, writeProtected }` to say which of three states the medium is in:

```json
{ "media": {
    "disk1": { "path": "C:\\disks\\games.dsk", "writeProtected": false },
    "disk2": { "path": "C:\\disks\\work.woz", "writeProtected": false,
               "unsaved": { "copy": "…/media/3f9c….woz", "stamp": { "length": 232960, "written": "2026-11-14T10:02:11Z", "sha256": "…" } } },
    "disk35d1": { "format": "800K", "writeProtected": false, "unsaved": { "copy": "…/media/a71e….po" } }
} }
```

- **Saved**: a `path`, as now.
- **Unsaved changes**: a `path` and `unsaved`, the recovered copy and the stamp the image had when it was read.
  Restoring inserts the copy, changed against that image. If the image changed since, the copy still goes in, with
  a conflict the Machine view reports.
- **New**: no `path`, only `unsaved`; a built or blank disk that was changed, so a `dos` disk with a program saved
  on it survives the session. An unchanged built disk is still left out, as the launch builds it again.

A recovered copy whose file is gone is reported in `problems` and skipped, as a missing image is now. Favorites store
saved media only: making a favorite from a machine with unsaved media asks to save it first or leaves those drives
as their images are.

## The debug protocol

`media` in `retro/devices` gains:

```json
"media": { "label": "C:\\disks\\work.woz", "format": "WOZ", "writeProtected": false, "changed": true,
           "source": { "kind": "image", "path": "C:\\disks\\work.woz", "protected": false },
           "version": 1874, "savedVersion": 1200,
           "saveFormats": [ { "format": "woz", "losses": [] },
                            { "format": "dsk", "losses": ["track 3 does not read as 16 sectors"] } ] }
```

`source.kind` is `image`, `built`, `blank` or `recovered`; `source.protected` says the image cannot be saved over,
and why (`readOnly`, `locked`, `cache`). `saveFormats` is worked out only when asked (`retro/devices` with
`"saveFormats": true`, or on the drive's own request), since decoding a WOZ's tracks is not free.

`retro/device` actions:

```json
{ "id": "disk35d1", "action": "save" }
{ "id": "disk35d1", "action": "save", "path": "copy.2mg", "format": "2mg" }
{ "id": "disk0", "action": "save", "path": "work.jv1", "acceptLosses": true }
{ "id": "disk0", "action": "save", "overwrite": true }
{ "id": "disk0", "action": "revert" }
{ "id": "disk35d1", "action": "new", "format": "800K" }
{ "id": "slot7", "action": "writeThrough", "enabled": true }
```

- `save` fails with an error whose `id` the extension acts on: `conflict` (the image changed on disk), `losses` (the
  format cannot hold the medium; the message lists what), `protected` (the image cannot be saved over) or `ioError`.
  `overwrite` and `acceptLosses` answer the first two.
- `revert` reads the image again and drops the machine's changes.
- `new` inserts a blank medium, which only save as can write.
- `eject` of a changed medium is refused with `changed` unless it says `"discard": true` or saved first, so a
  client that does not know about changed media cannot lose it. The extension asks and resends.
- A machine's own eject sends a `retro/mediaEjected` event naming the drive and its recovered copy.
- On `disconnect`, before it answers, the host writes the recovered copies and sends a last `retro/devices` event
  whose `configuration` names them, so the extension keeps them in the saved machine.

`retrocore/machine/change` takes the same actions for an off machine, where `save` and `revert` act on the
recovered copies.

## The UI workflow

The pieces, to settle together before building:

- **The Drives view.** A changed drive's description says `changed`, and its icon gets a dot, as an unsaved editor
  tab does. Its inline button is **Save** (today's **Save to Its Image**); its menu has **Save As...**, **Revert to
  Image** and, for a conflict, **Compare** (sizes and dates; there is no diff of disks). The badge keeps counting
  changed media, now including recovered copies.
- **Save prompts.** Saving to its image asks once per medium per session, with "don't ask again" as a setting
  (`retrocore.media.confirmSave`). A lossy format, a conflict or a protected image asks with what is wrong and the
  ways out: save anyway, save as, cancel.
- **Eject.** Ejecting a changed disk asks: **Save**, **Save As...**, **Discard** or cancel.
- **Stopping.** VS Code cannot hold a debug session open to ask, so stopping never waits. The host keeps the
  changed media as recovered copies, and the extension then shows one notification: "2 disks changed in *Apple
  IIe*: **Save All**, **Review**, **Discard**". Review reveals them in the Drives view, where the off machine shows
  them changed. A setting (`retrocore.media.onSessionEnd`: `keep`, `save`, `discard`) changes this.
- **The display panel.** Its drive line keeps `changed`, now for every drive and not only the Disk II, and a changed
  drive's name is a link that saves it. Its ended-session banner says how many media were left changed.
- **The off machine.** Recovered media shows changed, and Save, Save As, Revert and Discard work while the machine is
  off.

Open questions:
1. Is keep-and-ask on stop right, or should stop save automatically (with backups) by default?
2. Should Save ask every time, once per session, or never, given the backup?
3. Is a `.bak` beside the image welcome, or should backups go to global storage too?
4. Should Revert ask?
5. Does the display panel want save controls at all, or only the indicator?
6. Should the write-protection change for the Disk II land now, or wait until every drive saves?

## Tests

- **Round trips, per format.** Load and export with no writes gives the same bytes: WOZ2 (and WOZ1 to the WOZ2 it
  becomes, pinned by SHA-256), DSK, DO, PO, 2MG with a comment and creator chunk, raw 3.5 images, JV1, JV3 with more
  than one header block, JVC, CAS and WAV. Fixtures are built in code; external images under `RETROCORE_CACHE` only
  add cases and skip when absent.
- **Losses.** A JV3 disk with a double-density track, saved as JV1, reports it; a WOZ with an unreadable track,
  saved as DSK, names the track; a 2MG that is locked refuses.
- **`MediaFiles`.** A write that fails partway (a stream that throws) leaves the image as it was and no temporary
  file; a changed stamp is a conflict; a read-only file and a cache path are protected; the backup is made once.
- **Machines, by digest.** As the Disk II save test does now, a machine writes a file (DOS `SAVE`, ProDOS
  `SAVE`, TRSDOS `SAVE`, Disk BASIC on the CoCo), the disk is saved, and the image's SHA-256 is pinned; loading it
  again and reading the file back gives what was written.
- **The protocol.** `save`, `revert`, `new`, refused eject and the error ids, through the debug host's tests.
- **Saved machines.** Capture and restore with unsaved and new media, a missing copy, and a conflicting image;
  `tools/Test-OffMachine.mjs` covers the off machine.
- **The extension.** The stop notification, the eject prompt and the badge, in `extension/src/test`.

## Phases

1. **The model and the host's file writing.** `MediaSource`, versions and `ISavableMedia` in `Retrocore.Core`;
   `MediaFiles` with atomic writes, stamps, conflicts, backups and protection; the Disk II's save moved onto them,
   and tapes written through them. Done when the Disk II saves as it does now, plus conflicts and backups, with
   tests.
2. **Every block device saves.** The 3.5 drive (keeping the 2MG header), the ProFile and slot 7. Done when each
   saves and saves as, with round trips and a ProDOS `SAVE` pinned by digest.
3. **TRS-80 and CoCo floppies save.** Versions on `FloppyDisk`, JV1, JV3 and JVC saving with losses checked, and
   save as JV3 for DMK and IMD. Done when a Model I, a Model III and a CoCo disk each save a file and boot again
   from the image.
4. **The protocol's errors and the UI's prompts.** Error ids, `revert`, the refused eject, the Drives view's
   changes and the prompts, after the [UI workflow](#the-ui-workflow) is agreed. Done when every path in it works
   in the self-hosted extension.
5. **Session end and recovery.** Recovered copies, autosave to them, `unsaved` in `machineState`, the stop
   notification and the off machine's save. Done when a changed disk survives stopping, restarting VS Code and
   starting the machine again, and can be saved from the off machine.
6. **The write-protection rule.** Applied to every drive, with the image's own protection. Done when the table
   above holds for each device and the docs say so.
7. **New media and write-through.** `new` for blank disks; write-through for raw block images. Done when a blank
   800K disk formatted under ProDOS saves as `.po`, and a write-through ProFile matches AppleSharp's.
8. **Later.** DMK and IMD writers, a 13-sector reader back from WOZ, WAV to CAS for the TRS-80 and the CoCo, and
   the Altair's disks, which follow this model from the start.

Each phase updates [Devices.md](../Devices.md) and the machines' docs as it lands.
