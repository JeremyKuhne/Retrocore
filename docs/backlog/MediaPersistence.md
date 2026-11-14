# Backlog: saving media back to images

How disks, tapes and other media the machines change get back to image files, on every machine and in every format.

**Status:** proposed 2026-11-14, for review; nothing here is built. The [UI workflow](#the-ui-workflow) and the
[decisions](#decisions-agreed-2026-11-14) below it were agreed on 2026-11-14; the rest is still for review.

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
- **Its loaded bytes**: the image as it was read, kept beside the medium. A disk is small (a ProFile, the largest,
  is at most 32 MB), and the loaded bytes let the host say what changed against the image and what changed in the
  file since, and revert without reading the file again.
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
work in one place, `MediaFiles`, so atomic writes, stamps, conflicts and the history are written once. `Saved` takes the
version that was exported, so a write the machine makes while the file is being written leaves the medium changed.

## When media is written

| When | What happens | Default |
| --- | --- | --- |
| **Save** | The medium is written to its source image, in the source's format; the image it replaces is kept in the [history](#history). | asks only when something is off |
| **Save as** | Written to a path and format the user picks; the medium then comes from it. | the dialog asks about replacing a file |
| **Eject**, by the user | A changed disk: the user picks save, save as, discard or cancel. | asks |
| **Eject**, by the machine (a 3.5 drive's CONTROL eject) | Nothing can ask in time: the ejected disk is kept as a recovered medium, and the drive offers it until the session ends. | keeps |
| **Recording a tape** | Written to its path when ejected, or when the session ends, as now, but atomically and without replacing a file that was there before the recording started unless the user said so. | writes |
| **Session end** | Changed media is kept as a version in its history, never written to its image; the off machine shows it changed and offers to save it. | keeps |
| **Autosave** | Only to the history: while the machine runs, a changed disk gets a version every 30 seconds, so a crash loses little. Never to the user's images. | on |
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
| **2MG** | lossless once the header is kept: the creator, version, comment and creator-data chunks, and the flags | today `Disk35Disk` drops the header on load. It keeps the header and rewraps the blocks on export. The **locked** flag is the disk's lock ([below](#write-protection)): a locked image loads locked, and saving writes the drive's lock back as the flag |
| **`.po`, `.hdv`, `.img`, 3.5 `.dsk`** | lossless: raw blocks | nothing |
| **JV1** | lossless while the disk stays single-sided, single-density, ten 256-byte sectors on every track, with `$FA` marks only on track 17 | a double-density track, another sector size, a missing sector or a deleted mark elsewhere; save as JV3 |
| **JV3** | lossless for what `FloppyDisk` holds: IDs, density, sizes, data marks, sides, the write-protect byte, and its CRC-error flags | nothing `FloppyDisk` holds; `Jv3Format.Write` already writes its 2,901-entry tables and the protect byte |
| **DMK** | no writer yet | a writer is needed to save in place; it can hold everything `FloppyDisk` does, gaps included |
| **IMD** | no writer yet | a writer, keeping the comment header and the per-track mode bytes |
| **JVC** | lossless for uniform disks: one sector size and count on every track | a disk the machine reformatted unevenly; save as JV3 |
| **CAS** | the decoded bytes the machine wrote, which is all it reads back | timing, silences between blocks and the analog signal, which no CAS holds. A tape written at the Model III's 1500 baud is kept as bytes too |
| **WAV** | the Apple-1's only tape format: the signal as recorded | none from a recording. Saving a CAS tape as WAV is lossless for the machine (we generate the signal); reading a WAV as CAS needs a decoder and loses whatever does not decode, so that conversion waits for the media library |

## Write protection

Two things are kept apart:

- **The lock** says whether the machine can write the disk, as a real disk's write-protect tab does. Every disk
  has one, shown as a lock or an open lock on its drive ([below](#what-a-drive-shows)), and one click changes it.
  Some formats store it: a WOZ's INFO write-protected flag, a 2MG's locked flag, a JV3's write-protect byte. Saving
  writes it back into the image in those formats; formats without one forget it, though the saved machine keeps it.
  Hard disks have no tab, but the ProFile and slot 7 get the lock too: a locked one answers writes with ProDOS's
  write-protected error ($2B), as a protected block device does.
- **A read-only image** is one the host cannot write: the file is read-only, its folder cannot be written, or it is
  under `RETROCORE_CACHE`, which holds images we fetched and never change. It saves only with save as.

The two are independent. A read-only image can be unlocked, so the machine writes its copy in memory and the user
saves it elsewhere; a disk the machine changed before it was locked still saves, as the lock stops the machine, not
the save.

One rule for the lock on every disk: **a disk loads with the lock its image stores, and otherwise unlocked.** This
is safe because writing the disk changes only the copy in memory; nothing reaches the file until a save. A
read-only image loads with its lock as stored too. The Disk II changes from loading every disk locked, so a program
can write its own disk without first unlocking it. The saved machine keeps the user's choice per drive, as now, and
it wins over the default.

## Safety

- **Never silently.** Save writes without asking only when nothing is off: the disk fits the image's format, the
  file has not changed since it was read, and it is not read-only; a backup is kept. Anything else asks
  ([below](#saving-in-each-state)). Save as uses the save dialog's own replace question. A recording does not
  replace a file that existed when it started without asking.
- **Atomic.** `MediaFiles.Write` writes beside the image as `.name.<guid>.saving`, flushes it to disk, and moves it
  over the image, so a failed write leaves the image as it was. This is
  today's Disk II code, moved to one place, with the flush added. Tapes use it too.
- **Stale images and conflicts.** The extension watches each inserted image's file and tells the host when it
  changes (by another program, another session, or the same image saved from another drive); the host compares it
  with the loaded bytes and marks the medium **stale** when it differs. Before writing, the host also reads the
  image's stamp again, so a change the watcher missed is still caught. Saving a stale medium stops with a
  `conflict` error; the user can overwrite, save as, or reload the file and drop the machine's changes. The same
  image may be in two drives at once, but once one saves it, the other is stale.
- **Backups.** Each save over an image keeps the image it replaces as a version in its [history](#history), in the
  extension's storage, never beside the image, so workspaces and repositories stay clean.
- **Read-only images.** An image the host cannot write ([above](#write-protection), or a write that fails with
  access denied) offers save as only, and says why; a read-only file also offers **Make Writable**, which clears its attribute. The cache never
  does.
- **No open files.** The host reads an image whole and closes it, as now, so other programs can open it; only
  write-through keeps a file open, shared for reading.
- **Recovered copies** are versions in the history, so they are as safe as it is. Resetting a saved machine, or
  saving or discarding a medium, stops the saved machine naming its version; the history keeps it until it is
  thinned or cleared.

## History

Every medium keeps a history of versions, as Time Machine keeps a file's: what the disk held at each moment that
matters, and any of them can come back. It covers media only. A whole-machine snapshot (CPU, memory and devices) is
a separate, later feature, which can name the media versions here rather than copy the disks.

The history is also the plan's backups and recovered copies: a backup is the version taken before a save, and a
medium's **recovered copy** is its newest version not saved to its image. One store, one rule for keeping versions,
and one view do for all three.

### Versions

| A version is taken | Which keeps |
| --- | --- |
| on insert | the image as loaded |
| before and after each save | the image the save replaces (the backup), and what it wrote |
| every 30 seconds while the machine runs, when the disk changed since the last version | at most 30 seconds of work lost to a crash |
| when the session stops | the disk as the session left it |
| before a revert, a reload, a restore or a discard | what those drop |
| when the machine ejects a disk | the disk it ejected |

Each version records its time; what took it (`insert`, `save`, `checkpoint`, `stop`, `beforeRevert`, `eject` and so
on); the machine and its launch configuration; whether it is the image as last saved; the differences from the
version before, such as "6 sectors on track 17"; and a pin and a label when the user gives them. A tape's history
has a version on insert and one when a recording is ejected.

### Whose history

A history belongs to a medium: an image by its full path, or a built or blank medium by an id the host gives it,
which the saved machine keeps. The same image in two drives shares one history. Save as moves the medium to the new
path's history, which starts with a link to the old one, so the earlier versions still list.

### Storage

The history is kept in the extension's global storage (`context.globalStorageUri/history`), never in the
repository or beside the image. The host is given the folder at launch (`mediaHistoryDirectory`), and the language
server is too, for the off machine.

Content is stored in chunks named by their SHA-256: a Disk II track, a TRS-80 track's sectors, or 4 KB of a block
image. A version is a small JSON manifest of its chunks and the format to rebuild its image from them, so versions
share whatever they have in common, and a hundred versions of an 800K disk that differ by a few sectors cost little
more than one copy. A version is written as images are, atomically, and is complete once its manifest is. The host
copies the changed chunks on the machine's thread and writes them on another, so the machine never waits on the
disk.

### Thinning

As Time Machine thins: every version from the last hour, the newest of each hour for the last day, of each day for
the last month, and of each week before that. Never thinned: pinned versions, each medium's newest version, the
version that matches each image as last saved, and any version a saved machine names. A size cap
(`retrocore.media.historySize`, 1 GB) then drops the oldest versions that may be thinned, across all media.
Thinning runs when a version is taken and when the extension starts, not on a timer. **Clear History** empties one
medium's history or all of them, asking first, and keeps the versions saved machines name.

### Using a version

- **Restore to Drive** makes the disk that version, changed against its image. The disk it replaces becomes a
  version first, so nothing is lost and nothing asks.
- **Restore to Image** writes the version over the image, with Save's checks; the image it replaces becomes a version.
- **Save As...** writes it to a new image, in any format that holds it.
- **Compare with Disk** and **Compare with Previous** list the differences: by sector, track or block now, and by
  file once the media library reads the disk's filesystem.
- **Pin**, **Label...** and **Delete**.

### On, off and settings

History is on by default, for all media, and can be turned off for all of it or for one disk; both are a click
away ([below](#turning-history-on-and-off)). A disk's own choice wins over the global one and is kept in the saved
machine.

With history off, a disk keeps no checkpoints and no old versions, but still keeps **one** version, its newest,
when the session stops or the machine ejects it, so stopping never loses work. As nothing else is kept, Revert,
Reload and Discard ask first again, and a save keeps no backup. Turning history off asks whether to keep or clear the
versions already there.

The settings, all under `retrocore.media`:

| Setting | Default | What |
| --- | --- | --- |
| `history.enabled` | `true` | Keep a history of versions for each disk and tape. |
| `history.interval` | `30` | Seconds between checkpoints while a disk changes; `0` keeps only the versions events take. |
| `history.size` | `1024` | Megabytes the history may use, across all media, before the oldest versions go. |
| `onSessionEnd` | `keep` | `keep` changed media and ask, or `discard` it. |
| `watchImages` | `true` | Watch each image's file, so a stale image shows at once. |

They are ordinary VS Code settings, so they can be set per user or per workspace; the host is given them at launch,
and a change applies to a running machine at once.

## Saved machines

`machineState`'s media entries grow from `{ path, writeProtected }` to say which of three states the medium is in:

```json
{ "media": {
    "disk1": { "path": "C:\\disks\\games.dsk", "writeProtected": false },
    "disk2": { "path": "C:\\disks\\work.woz", "writeProtected": false,
               "unsaved": { "version": "9b1e…", "stamp": { "length": 232960, "written": "2026-11-14T10:02:11Z", "sha256": "…" } } },
    "disk35d1": { "medium": "m-a71e…", "format": "800K", "writeProtected": false, "unsaved": { "version": "c04d…" } }
} }
```

- **Saved**: a `path`, as now. Any drive may add `"history": false` or `true`, its own choice; without it, the disk
  follows the global setting.
- **Unsaved changes**: a `path` and `unsaved`, the version the session left it at and the stamp the image had when
  it was read. Restoring inserts that version, changed against that image. If the image changed since, the version still goes in, with
  a conflict the Machine view reports.
- **New**: no `path`, only the medium's id and `unsaved`; a built or blank disk that was changed, so a `dos` disk with a program saved
  on it survives the session. An unchanged built disk is still left out, as the launch builds it again.

A version the history no longer has (its storage was deleted by hand) is reported in `problems` and skipped, as a missing image is now. Favorites store
saved media only: making a favorite from a machine with unsaved media asks to save it first or leaves those drives
as their images are.

## The debug protocol

`media` in `retro/devices` gains:

```json
"media": { "label": "C:\\disks\\work.woz", "format": "WOZ", "writeProtected": false, "changed": true,
           "source": { "kind": "image", "path": "C:\\disks\\work.woz", "readOnly": null, "stale": false },
           "version": 1874, "savedVersion": 1200,
           "differences": { "unit": "sector", "count": 14, "summary": "tracks 17-18" },
           "saveFormats": [ { "format": "woz", "losses": [] },
                            { "format": "dsk", "losses": ["track 3 does not read as 16 sectors"] } ] }
```

`source.kind` is `image`, `built`, `blank` or `recovered`; `source.readOnly` says why the image cannot be saved over
(`file`, `folder` or `cache`), null when it can; `source.stale` says the file changed since it was read.
`differences` compares the medium with its loaded bytes, by the medium's own unit: sectors for TRS-80 and Disk II
sector images (and the sectors a WOZ's tracks decode to, or tracks when they do not), blocks for block images, bytes
for tapes. Once the media library reads the disk's filesystem it adds the files changed, added and removed.
`saveFormats` and `differences` are worked out only when asked (`retro/devices` with
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
{ "id": "disk2", "action": "restoreVersion", "version": "9b1e…" }
{ "id": "disk2", "action": "restoreVersion", "version": "9b1e…", "toImage": true }
{ "id": "disk2", "action": "saveVersion", "version": "9b1e…", "path": "before-format.woz" }
{ "id": "disk2", "action": "pinVersion", "version": "9b1e…", "pinned": true, "label": "before FORMAT" }
{ "id": "disk2", "action": "deleteVersion", "version": "9b1e…" }
{ "id": "disk2", "action": "history", "enabled": false }
{ "id": "disk2", "action": "history", "enabled": null }
```

`history` sets a disk's own choice, and `null` makes it follow the global setting. The global settings come in the
launch as `mediaHistory` (`{ "enabled": true, "interval": 30, "size": 1024 }`), and a `retro/mediaSettings` request
changes them in a running session. `media` in `retro/devices` adds `history`: `{ "enabled": true, "own": false,
"versions": 14, "size": 3250176 }`.

`retro/mediaHistory` lists a drive's versions, newest first, and compares two:

```json
{ "id": "disk2" }
{ "id": "disk2", "compare": ["9b1e…", "now"] }
```

```json
{ "versions": [
    { "version": "now", "time": "2026-11-14T10:52:41Z", "kind": "current", "saved": false,
      "differences": { "unit": "sector", "count": 6, "summary": "track 17" } },
    { "version": "9b1e…", "time": "2026-11-14T10:43:02Z", "kind": "save", "saved": true,
      "pinned": true, "label": "before FORMAT", "machine": "Apple IIe" } ],
  "size": 3250176 }
```

- `save` fails with an error whose `id` the extension acts on: `conflict` (the image changed on disk), `losses` (the
  format cannot hold the medium; the message lists what), `readOnly` (the image cannot be saved over) or `ioError`.
  `overwrite` and `acceptLosses` answer the first two.
- `revert` drops the machine's changes, back to the loaded bytes; `reload` reads the file again, for a stale image.
- `imageChanged` (`{ "id": "disk2", "action": "imageChanged" }`) is the extension's file watcher telling the host to
  check the image's stamp.
- `new` inserts a blank medium, which only save as can write.
- `writeProtect`, which the lock sends, is offered for every drive with a disk, the ProFile and slot 7 included;
  `writeProtected` in `media` is the lock.
- `eject` of a changed medium is refused with `changed` unless it says `"discard": true` or saved first, so a
  client that does not know about changed media cannot lose it. The extension asks and resends.
- A machine's own eject sends a `retro/mediaEjected` event naming the drive and the version it took.
- On `disconnect`, before it answers, the host takes the stop versions and sends a last `retro/devices` event
  whose `configuration` names them, so the extension keeps them in the saved machine.

`retrocore/machine/change` takes the same actions for an off machine, where `save` and `revert` act on the
recovered copies, and `retrocore/machine/history` answers as `retro/mediaHistory` does.

## The UI workflow

### What a drive shows

Each medium has four independent states, and the Drives view shows each:

| State | Values | Shown as |
| --- | --- | --- |
| **Lock** | locked (the machine cannot write the disk) · unlocked | the drive's icon, on every drive with a disk: a lock or an open lock, coloured by its activity as the icon is now (green reading, red writing, yellow seeking). Its first inline button, **Lock** or **Unlock**, changes it |
| **Diff** | same · **changed** (the machine wrote it) · **stale** (the file changed since it was read) · both, a conflict | at the row's end, as Git marks a changed file: `●` for changed, `⚠` for stale or a conflict |
| **Read-only image** | the image can be saved over · a read-only file or folder · in `RETROCORE_CACHE` | `read-only image` in the description, and **Save As...** in place of **Save** |
| **Fit** | fits its image's format · lossy | only when saving |

VS Code shows a row's inline buttons only while the pointer is on it or it is selected, so what must always show is
in the icon, the description and a file decoration (a `FileDecorationProvider` over a `retrocore-drive:` URI per
drive), which stay visible. An empty drive keeps today's dimmed drive icon. Tapes keep their tape icon and have no
lock: a playing tape cannot be written, and a recording can.

The description joins them, such as `work.woz · image changed on disk`. The tooltip adds the differences,
such as "changed: 14 sectors on tracks 17-18", and for a conflict the file's size and date then and now. The badge
counts changed media, recovered copies included.

The mockups below draw VS Code's views in text. `🔓` is an unlocked disk and `🔒` a locked one, `▫` an empty drive;
`●` at a row's end is changed and `⚠` stale or a conflict. Buttons in brackets are a row's inline buttons, shown as
their tooltips, which appear while the pointer is on the row.

The Drives view while an Apple IIe runs, with one drive in each state:

```text
DRIVES                                                                                  (3)
▾ Slot 4 · ProFile card · 1 drive
    🔓 ProFile        hard1.po · block 7 · reading                         [Lock] [Eject]
▾ Slot 5 · 3.5 disk controller · 2 drives
    🔓 3.5 drive 1    prodos.2mg · block 412 · writing                 ●   [Lock] [Save] [Eject]
    🔓 3.5 drive 2    system.po · read-only image                      ●   [Lock] [Save As...] [Eject]
▾ Slot 6 · Disk II controller · 2 drives
    🔓 Drive 1        work.woz · image changed on disk                 ⚠   [Lock] [Save...] [Eject]
    🔒 Drive 2        dos33.dsk · track 0                                  [Unlock] [Eject]
▾ Slot 7 · block storage
    ▫ Slot 7 disk     empty
```

- Every disk shows its lock, so a writable disk is plain at a glance, and locking one is a click on **Lock**.
- `(3)` is the badge: three media changed and not saved. Its tooltip names them.
- A disk the same as its image has no Save button, as the ProFile and Drive 2 show.
- **Save...** has an ellipsis when it will ask (stale, lossy); a read-only image's button is **Save As...**.
- Drive 2's icon is dimmed, as its motor is off; its lock is the one the saved machine kept for it.

On the Model I the same rows read, for example, `🔓 Drive 0    newdos.dsk (JV1) · track 17 sector 4 · reading`,
while the cassette keeps its tape icon: `▶ Cassette    adventure.cas · playing · 1,204 of 6,912 bytes`.

A changed drive's tooltip:

```text
┌──────────────────────────────────────────────────────────────┐
│ Drive 1: 5¼-inch floppy drive                                │
│                                                              │
│ work.woz (WOZ), C:\disks\work.woz                            │
│ Changed: 14 sectors on tracks 17-18, not saved to the image  │
│ Image changed on disk: 10:52 today; it was 10:02 when read   │
│ Unlocked: the machine can write it                           │
│ Track 17, sector 4, writing                                  │
└──────────────────────────────────────────────────────────────┘
```

Once the media library reads the disk's filesystem, the changed line names files: `Changed: HELLO, DATA (new);
14 sectors on tracks 17-18`.

A drive's menu (right-click, or **...** on the row):

```text
┌──────────────────────────────────┐
│ Save                             │
│ Save As...                       │
│ Revert to Image                  │
│ Reload from File                 │   only while stale
│ Show History                     │
├──────────────────────────────────┤
│ Insert...                        │
│ Eject                            │
│ Lock (Unlock when locked)        │
└──────────────────────────────────┘
```

### Saving in each state

**Save** (the inline button, today's **Save to Its Image**) asks only when something is off:

| State | Save |
| --- | --- |
| same | disabled |
| changed, fits, open | writes at once, keeping a backup |
| changed, lossy | asks, listing what would be lost: **Save as WOZ / JV3...**, **Save Anyway**, cancel |
| stale or a conflict | asks, with the differences: **Overwrite**, **Save As...**, **Reload from File** (drops the machine's changes), cancel |
| read-only image | save as only; says why, and offers **Make Writable** for a read-only file |

The drive's menu has **Save As...**, **Revert to Image**, **Reload from File** while stale, and **Show History**.
Revert and Reload ask nothing while the disk has history on, as the disk they drop becomes a version first; with
history off they ask.

A quiet save says so in the status bar for five seconds, and asks nothing:

```text
 ✓ Saved work.woz from Drive 1 (the previous version is kept)
```

The prompts are VS Code's modal dialogs. A lossy format, where the disk no longer fits its image's format:

```text
┌──────────────────────────────────────────────────────────────────┐
│ ⚠ games.dsk can't hold the disk in Drive 1 as it is              │
│                                                                  │
│   Track 3 no longer reads as 16 sectors, so a .dsk would lose    │
│   it. A .woz keeps every track as it is.                         │
│                                                                  │
│             [Save as WOZ...]   [Save Anyway]   [Cancel]          │
└──────────────────────────────────────────────────────────────────┘
```

A TRS-80 disk reads `newdos.dsk is JV1, which can't hold track 0's double-density sectors. JV3 keeps them.` with
**Save as JV3...**.

A stale image or a conflict:

```text
┌──────────────────────────────────────────────────────────────────┐
│ ⚠ work.woz changed on disk after Drive 1 read it                 │
│                                                                  │
│   The machine changed 14 sectors on tracks 17-18.                │
│   The file changed at 10:52 today; it was 10:02 when read.       │
│   Overwriting replaces the file's changes; its version is kept.  │
│                                                                  │
│   [Overwrite]   [Save As...]   [Reload from File]   [Cancel]     │
└──────────────────────────────────────────────────────────────────┘
```

**Reload from File** drops the machine's changes, which stay in the history.

A read-only image:

```text
┌──────────────────────────────────────────────────────────────────┐
│ ⚠ system.po is a read-only file                                  │
│                                                                  │
│   Save the disk in 3.5 drive 2 under another name, or make the   │
│   file writable and save over it.                                │
│                                                                  │
│        [Save As...]   [Make Writable and Save]   [Cancel]        │
└──────────────────────────────────────────────────────────────────┘
```

An image in the cache says `prodos.po is in Retrocore's image cache, which is never changed.` and offers only
**Save As...** and **Cancel**.

### The History row

Each drive with a disk has a **History** row among its details, which lists its versions, newest first, the older
ones grouped:

```text
▾ 🔓 Drive 1        work.woz · track 17 · writing                    ●   [Lock] [Save] [Eject]
    Image            C:\disks\work.woz (WOZ 2)
    Changed          6 sectors on track 17, not saved
  ▾ 🕘 History       14 versions · 3.1 MB                                      [🕘] [⚙]
      ● now          not saved · 6 sectors on track 17
        10:52:30     checkpoint · 2 sectors on track 17                    [Restore] [Compare]
        10:52:00     checkpoint · 8 sectors on tracks 17-18
      📌 10:43        saved to work.woz · before FORMAT
        10:31        saved to work.woz
        09:58        inserted
      ▸ Yesterday    5 versions
      ▸ Last week    2 versions
```

- `📌` marks a pinned version, and its label follows its kind.
- A version's inline buttons are **Restore** (to the drive) and **Compare** (with the disk). Its menu:

```text
┌──────────────────────────────────┐
│ Restore to Drive                 │
│ Restore to Image                 │
│ Save As...                       │
├──────────────────────────────────┤
│ Compare with Disk                │
│ Compare with Previous            │
├──────────────────────────────────┤
│ Pin  (Unpin when pinned)         │
│ Label...                         │
│ Delete                           │
└──────────────────────────────────┘
```

Compare opens a read-only document beside the editor:

```text
work.woz: 10:31 (saved) against now (not saved)

Track 17   sectors 3, 4, 9            changed
Track 18   sectors 0, 1, 2            changed
Track 18   sector 11                  unreadable now
```

Once the media library reads the disk's filesystem, a section above the sectors names the files:

```text
Files      HELLO                      changed, 3 sectors
           DATA                       new, 4 sectors
```

The History row of a medium kept from the last run is there on the off machine too, so a disk can be restored to
any version before the machine starts.

### Turning history on and off

Two icons do it everywhere: a **clock** turns history on and off, lit while it is on and grayed while it is off, and
a **gear** opens its settings. In the mockups `[🕘]` is the lit clock, `[🕘̸]` the grayed one and `[⚙]` the gear.

The Drives view's title bar has both, for all media, beside Refresh:

```text
DRIVES   History on · 312 MB of 1 GB                                     [🕘] [⚙] [↻]   (3)
```

```text
DRIVES   History off                                                     [🕘̸] [⚙] [↻]   (3)
```

- The clock is a toggle (VS Code's `toggled` menu state), so it also shows pressed while history is on. Its tooltip
  says what a click does: "Turn Off Media History" or "Turn On Media History".
- VS Code shows a view's title buttons only while the pointer is over the view, unless
  `workbench.view.alwaysShowHeaderActions` is set, so the state is also in the view's description ("History on ·
  312 MB of 1 GB"), which always shows. Clicking the description does nothing; the buttons do.
- The gear opens the Settings editor filtered to `retrocore.media`:

```text
┌ Settings ──────────────────────────────────────────── 🔎 retrocore.media ┐
│ Retrocore › Media › History: Enabled                                     │
│ [✓] Keep a history of versions for each disk and tape.                   │
│                                                                          │
│ Retrocore › Media › History: Interval                                    │
│ [ 30 ] Seconds between checkpoints while a disk changes; 0 keeps only    │
│        the versions events take.                                         │
│                                                                          │
│ Retrocore › Media › History: Size                                        │
│ [ 1024 ] Megabytes the history may use before the oldest versions go.    │
│                                                                          │
│ Retrocore › Media › On Session End                          [ keep  ▾ ]  │
│ Retrocore › Media › Watch Images                                   [✓]   │
└──────────────────────────────────────────────────────────────────────────┘
```

Each disk's History row carries the same two icons, for that disk. Its own icon is the clock, lit or grayed, so a
disk's state shows without the pointer on it:

```text
  ▾ 🕘 History       14 versions · 3.1 MB                                      [🕘] [⚙]
```

```text
    🕘̸ History       off for this disk · keeps its newest version only         [🕘̸] [⚙]
```

```text
    🕘̸ History       off for all media                                         [🕘̸] [⚙]
```

The last is a disk following the global setting; its clock turns history on for this disk alone. The row's gear opens
a quick pick for the disk:

```text
┌ History of work.woz ──────────────────────────────────────────────┐
│ 🕘 Turn Off History for This Disk                                  │
│ 🕘 Follow the Media Setting (on)                                   │
│ 🗑 Clear This Disk's History...       14 versions · 3.1 MB          │
│ ⚙ Media Settings...                                                │
└────────────────────────────────────────────────────────────────────┘
```

The Command Palette has the same: **Retrocore: Turn On Media History**, **Retrocore: Turn Off Media History**,
**Retrocore: Media Settings** and **Retrocore: Clear Media History...**.

Turning history off, from either clock, asks once:

```text
┌──────────────────────────────────────────────────────────────────┐
│ Turn off history for all media?                                  │
│                                                                  │
│   312 MB of versions are kept now. Changed disks will still keep │
│   their newest version when the machine stops.                   │
│                                                                  │
│   [Turn Off, Keep Versions]  [Turn Off and Clear]  [Cancel]     │
└──────────────────────────────────────────────────────────────────┘
```

### Eject, stop and the off machine

- **Eject** of a changed disk asks: **Save**, **Save As...**, **Discard** or cancel; a discarded disk stays in its
  history. A machine's own eject cannot ask; the disk is kept as a recovered copy and shown under its drive until it
  is saved or discarded.
- **Stop** never waits, as VS Code does not let a debug session hold off ending. The host keeps changed media as
  recovered copies, and one notification follows: "2 disks changed in *Apple IIe*: **Save All**, **Review**,
  **Discard**". Review reveals them in the Drives view, on the machine now off. `retrocore.media.onSessionEnd`
  (`keep`, the default, or `discard`) changes this.
- **The off machine** shows recovered media as changed, and saves, saves as, reverts and discards it.
- **The display panel** shows `changed` for every drive, not only the Disk II, with no save controls; clicking a
  drive reveals it in the Drives view. Its ended-session banner says how many media were left changed.

Ejecting a changed disk:

```text
┌──────────────────────────────────────────────────────────────────┐
│ Save the changes to work.woz before ejecting it from Drive 1?    │
│                                                                  │
│   The machine changed 14 sectors on tracks 17-18.                │
│                                                                  │
│      [Save]   [Save As...]   [Discard]   [Cancel]                │
└──────────────────────────────────────────────────────────────────┘
```

**Save** here goes through the same checks as the Save button, so a stale, lossy or read-only image asks as above
before the disk comes out.

A disk the machine ejected itself, kept under its drive:

```text
▾ Slot 5 · 3.5 disk controller · 2 drives
    ▫ 3.5 drive 1     empty                                                [Insert...]
       ↳ ejected      prodos.2mg · ejected by the machine              ●   [Save] [Insert Again] [Discard]
```

Stopping, with changed media, shows one notification in the corner:

```text
                         ┌─────────────────────────────────────────────────┐
                         │ ⓘ Apple IIe stopped with 2 disks not saved:      │
                         │   work.woz, prodos.2mg. They are kept.           │
                         │                                                 │
                         │               [Save All]   [Review]   [Discard] │
                         └─────────────────────────────────────────────────┘
```

**Save All** saves each in turn, and a disk that needs a prompt (stale, lossy, read-only) asks as above; **Discard**
asks nothing while history is on, as the versions stay in each disk's history, and asks once with it off. Dismissing the notification keeps them.

The machine, now off, with what it kept:

```text
MACHINE
▾ 🖥 Apple IIe        Enhanced, 65C02 · off · 2 disks not saved
DRIVES                                                                                  (2)
▾ Slot 5 · 3.5 disk controller · 2 drives
    🔓 3.5 drive 1    prodos.2mg · kept from the last run              ●   [Lock] [Save] [Eject]
    ▫ 3.5 drive 2     empty                                                [Insert...]
▾ Slot 6 · Disk II controller · 2 drives
    🔓 Drive 1        work.woz · kept from the last run                ●   [Lock] [Save] [Eject]
    🔒 Drive 2        dos33.dsk                                            [Unlock] [Eject]
```

Starting it again boots with those disks as they were left, still changed.

The display panel's drive line while it runs, and its banner after:

```text
D1: track 17.00 · bit 2311/51024 · motor on · unlocked · changed | D2: track 0.00 · motor off · locked
```

```text
Apple IIe ended. 2 disks were kept with unsaved changes; Review them in Drives.         [Restart]
```

"Review them in Drives" reveals the Drives view.

## Decisions (agreed 2026-11-14)

- **Stop keeps and asks.** Changed media becomes recovered copies and a notification offers to save it; the user's
  images are never written without them.
- **Save asks only when something is off**: a lossy format, a stale image or a read-only image. The history covers the quiet case.
- **A time-machine history of media.** Every medium keeps versions on insert, around each save, every 30 seconds
  while it changes, on stop, on the machine's eject, and before anything drops changes. They are thinned as Time
  Machine thins, kept within a 1 GB cap, and listed in a History row under each drive. Backups and recovered copies
  are versions in it. Whole-machine snapshots are not part of it.
- **The history is in the extension's storage**, never beside the image.
- **History is easy to turn on and off.** A clock, lit or grayed, toggles it for all media in the Drives view's
  title bar and for one disk on its History row, and a gear beside each opens its settings. The state also shows in
  the view's description and the row's own icon, which are always visible. With history off, a disk still keeps its
  newest version at stop.
- **Every disk shows a lock.** The drive's icon is a lock or an open lock, so a writable disk is plain at a glance,
  and its first inline button locks or unlocks it. The ProFile and slot 7 get the lock too.
- **Image flags are the disk's lock.** A WOZ's write-protected flag, a 2MG's locked flag and a JV3's protect byte are
  what the lock changes and saving writes back. A read-only file or folder, or the cache, makes a read-only image,
  which is shown in words, not with the lock.
- **Differences by sector now, by file later.** The host keeps the loaded bytes and reports changed sectors, tracks
  or blocks; file names come with the media library's filesystems.
- **Images are watched.** The extension watches each image's file, so a stale image shows as soon as it changes, and
  the stamp is checked again on save.
- **The display panel shows only the indicator.**

Still to confirm, both proposed: Revert, Reload and Discard ask nothing while history is on, now that the history keeps what they drop
(this replaces the earlier proposal that Revert always asks); and the Disk II's write-protection change lands with
phase 6, not before.

## Tests

- **Round trips, per format.** Load and export with no writes gives the same bytes: WOZ2 (and WOZ1 to the WOZ2 it
  becomes, pinned by SHA-256), DSK, DO, PO, 2MG with a comment and creator chunk, raw 3.5 images, JV1, JV3 with more
  than one header block, JVC, CAS and WAV. Fixtures are built in code; external images under `RETROCORE_CACHE` only
  add cases and skip when absent.
- **Losses.** A JV3 disk with a double-density track, saved as JV1, reports it; a WOZ with an unreadable track,
  saved as DSK, names the track; a locked 2MG loads locked and saves its lock back as the flag.
- **`MediaFiles`.** A write that fails partway (a stream that throws) leaves the image as it was and no temporary
  file; a changed stamp is a conflict; a read-only file and a cache path are read-only images; a save adds the image it replaced to the
  history.
- **History.** A version restores to the same bytes it was taken from, pinned by digest; versions share chunks, so
  a hundred checkpoints of an 800K disk with a few sectors changed stay under twice its size; a version cut off
  mid-write leaves the history as it was; thinning, on a test clock, keeps what the [rule](#thinning) says, pinned
  and saved-machine versions included; the size cap drops the oldest first. With history off, globally or for one
  disk, no checkpoints are taken but the stop version is, and a disk's own choice wins over the global one.
- **Machines, by digest.** As the Disk II save test does now, a machine writes a file (DOS `SAVE`, ProDOS
  `SAVE`, TRSDOS `SAVE`, Disk BASIC on the CoCo), the disk is saved, and the image's SHA-256 is pinned; loading it
  again and reading the file back gives what was written.
- **Differences.** A disk with known writes reports exactly the sectors, tracks or blocks written; reverting gives
  back the loaded bytes.
- **The protocol.** `save`, `revert`, `reload`, `imageChanged`, `new`, refused eject and the error ids, through the
  debug host's tests.
- **Saved machines.** Capture and restore with unsaved and new media, a missing copy, and a conflicting image;
  `tools/Test-OffMachine.mjs` covers the off machine.
- **The extension.** The stop notification, the eject prompt, the prompts for each state, a watched image going
  stale, the History rows and their actions, Compare, and the badge, in `extension/src/test`.

## Phases

1. **The model and the host's file writing.** `MediaSource`, versions and `ISavableMedia` in `Retrocore.Core`;
   the loaded bytes and differences; `MediaFiles` with atomic writes, stamps, conflicts and read-only images; the history's store, with versions on
   insert and around each save; the Disk II's save moved onto them,
   and tapes written through them. Done when the Disk II saves as it does now, plus conflicts, and the image a save
   replaced restores from the history, with tests.
2. **Every block device saves.** The 3.5 drive (keeping the 2MG header), the ProFile and slot 7. Done when each
   saves and saves as, with round trips and a ProDOS `SAVE` pinned by digest.
3. **TRS-80 and CoCo floppies save.** Versions on `FloppyDisk`, JV1, JV3 and JVC saving with losses checked, and
   save as JV3 for DMK and IMD. Done when a Model I, a Model III and a CoCo disk each save a file and boot again
   from the image.
4. **The protocol's errors and the UI's prompts.** Error ids, `revert`, `reload`, the refused eject, the file
   watcher, the Drives view's states and the prompts of the [UI workflow](#the-ui-workflow), and the History rows with
   restore and Compare. Done when every row of [saving in each state](#saving-in-each-state) works in the self-hosted extension.
5. **Session end and the full history.** Versions every 30 seconds, on stop and on the machine's eject; thinning
   and the size cap; `unsaved` in `machineState`; the stop notification, and the off machine's save and history;
   the clocks and gears, the settings and the history's commands. Done when a changed disk survives stopping, restarting VS Code and
   starting the machine again, and can be saved, or restored to an earlier version, from the off machine.
6. **The write-protection rule.** The lock as its image stores it, otherwise unlocked, on every drive, and saved
   back in the formats that store it; the ProFile's and slot 7's lock, answering writes with $2B. Done when every
   drive with a disk shows and changes its lock, each device follows the rule, and the docs say so.
7. **New media and write-through.** `new` for blank disks; write-through for raw block images. Done when a blank
   800K disk formatted under ProDOS saves as `.po`, and a write-through ProFile matches AppleSharp's.
8. **Later.** DMK and IMD writers, a 13-sector reader back from WOZ, WAV to CAS for the TRS-80 and the CoCo, and
   the Altair's disks, which follow this model from the start.

Each phase updates [Devices.md](../Devices.md) and the machines' docs as it lands.
