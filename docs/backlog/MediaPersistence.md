# Backlog: saving media back to images

How disks, tapes and other media the machines change get back to image files, on every machine and in every format,
without losing what the machine wrote.

**Status:** proposed 2026-11-14 and revised the same day after two reviews. Phase 1 is built for the Disk II
([phases](#phases)); phase 2, every drive saving, is built: the Apple II's block drives and the TRS-80's and Color
Computer's floppies save. Phase 3, the UI, is built: the Drives view's rows, Save in each state, Revert and Discard
with Undo, the eject prompt, and the disks the machine ejects. The
[decisions](#decisions-agreed-2026-11-14) were agreed with the review's findings in mind. Where machines and their
unsaved disks are kept is [machine files, data folders and libraries](MachineFiles.md).

Today one drive saves: the Disk II's `save` ([Devices.md](../Devices.md#the-debug-protocol)), on the Apple II and
the Apple III. Every other disk keeps its changes in memory until the session ends, and then they are gone, and so
is a recording still in its recorder. This plan gives every medium one model, one way it leaves a drive, one safe way
to write it, and a recovery journal so a stop or a crash loses nothing, so later save actions are not added drive by
drive.

It takes over the second step of [the media library's order of work](Media.md#order-of-work) ("media slots, with
dirty tracking and save on eject; then the Model I's disk write-back"), and follows its layers: formats in
`Retrocore.Media`, the machines' drives above them, the hosts above both.

## What there is

| Machine | Device | Formats | Changes held as | Saves |
| --- | --- | --- | --- | --- |
| Apple II, Apple III | Disk II drives (`Apple2FloppyDrive`) | `.woz`; `.dsk`, `.do`, `.po`, `.d13` converted to WOZ (every `.dsk` as DOS order) | `WozDisk` bit tracks, with `IsDirty` and `Version`; `IsReadOnly` is a plain property, so a lock change is not counted | `save` to `.woz`, or `.dsk`/`.do`/`.po` decoded back to sectors; atomic, through a temporary file; asks first in the Drives view |
| Apple II | 3.5 drives (`Apple2Disk35Drive`) | `.po`, `.2mg`, `.hdv`, `.img`, 3.5-inch `.dsk` | `Disk35Disk` blocks, with `IsDirty` and `Version`; the 2MG header is dropped on load | no |
| Apple II, Apple III | ProFile (`ProFileDrive`) | `.po`, `.hdv` | a writable `MemoryBlockDevice`, a `_changed` flag | no |
| Apple II | Slot 7 block storage (`Apple2BlockStorage`) | `.po` | a `MemoryBlockDevice` that is read-only (its default), a `BlockWritten` flag; the ROM's write capability is set once, when the machine is built | no; its media is fixed |
| Model I, III, 4, II | Floppy drives (`Trs80FloppyDrive`) | JV1 (`.dsk`), JV3, DMK, IMD | `FloppySector` data changed in place by the controller; a per-drive `Changed` | no; JV1 and JV3 writers exist, DMK and IMD have none (before phase 2) |
| Model I, III, 4 | Cassette (`Trs80CassetteDrive`) | `.cas` | `CassetteImage` bytes, and bits buffered in the recorder until it stops | a recording is written on eject, after the tape is detached, with `File.WriteAllBytes`; stopping the session first loses it |
| CoCo | Cassette | `.cas` | `CassetteImage` | as the TRS-80's |
| CoCo | Floppy drives (`Trs80FloppyDrive` on `CocoDiskController`) | JVC only (`.dsk`, `.jvc`) | `FloppyDisk` | no; `JvcFormat.Write` writes only 18 sectors of 256 bytes (before phase 2) |
| CoCo | ROM pack (`cartridge`) | ROM image | ROM; not a device | never: read-only |
| Apple-1 | Cassette (`Apple1CassetteDrive`) | `.wav` | `Apple1Tape` half-cycle lengths | a recording is written on eject, as `ToWave()` at 44.1 kHz, which is not cycle-exact |
| Altair | Cassette (`AltairCassette`, the 88-ACR on an 88-SIO) | `.tap`, the bytes in order | the tape's bytes, grown as the 88-ACR records, and a `_changed` flag | a recording is written on eject, and when the session ends or relaunches, with `File.WriteAllBytes` |
| Altair | 8-inch floppy drives | SIMH `.dsk` when the 88-DCDD comes ([Altair8800.md](Altair8800.md)) | | |
| AppleSharp | Disk II (`FloppyMount`) | `.woz` writable when asked; sector images read only | `WozDisk` | writes a changed WOZ back whenever the drive's motor stops, atomically, refusing when the file's hash changed |
| AppleSharp | Slot 7 `FileBlockDevice` | `.po` | none: writes go straight to the file when opened writable | write-through |

What the hosts and views already do:

- `MediaState` has `Label`, `Format`, `WriteProtected` and `Changed` ("written since inserted"). The Disk II's
  `Saved(...)` resets it.
- `MachineConfiguration.Capture` keeps each drive's `path` and `writeProtected`, and leaves out media that cannot
  be inserted again: a disk a `dos` launch built, a tape being recorded. A launch restores the saved machine and
  then, for a `dos` source or program, builds a fresh disk in drive 1 over it.
- Media leaves a drive by several paths: `eject`, an `insert` over a disk (which ejects first), removing a card, the
  legacy `retro/media` request, a 3.5-inch drive's own eject (which drops the disk before setting its flag), and the
  session ending. None of them asks about changes.
- A failed request answers `success: false` and the exception's message, which the extension shows as text.
- Write protection differs by drive: a Disk II disk loads protected, a 3.5-inch disk writable unless a 2MG locks
  it, a ProFile writable, slot 7 read-only.

## The model

### A medium

The media layer, `Retrocore.Media`, gets one interface for a mutable medium, which `WozDisk`, `Disk35Disk`,
`FloppyDisk`, `MemoryBlockDevice`, `CassetteImage`, `Apple1Tape` and the Altair's tape implement:

```csharp
public interface IMedium
{
    long Version { get; }                    // changes on every write, and on a lock change
    bool IsWriteProtected { get; set; }      // the lock; setting it changes Version
    MediumSnapshot Snapshot();               // an immutable copy, cheap: only chunks changed since the last one
}
```

- **Every mutation counts.** `FloppySector` stops handing out its data to change in place; the controller writes
  through `FloppyDisk`, which counts the write. `WozDisk.WriteBit` marks its track changed without allocating. A
  lock change is a change, so a lock-only edit can be saved.
- **Formats are codecs** beside the media, in `Retrocore.Media`: each reads an image and writes a snapshot, and says
  exactly what it could not hold ([below](#what-each-format-keeps)). The machines know none of them.
- **A drive** implements `IMediumSlot` (in `Retrocore.Media`): its `IMedium?`, and a **mount generation** that
  changes each time a medium goes in or out. The machines' assemblies, which reference both `Retrocore.Core` and
  `Retrocore.Media`, implement it; `Retrocore.Core` stays free of media and files, and `MediaState` only gains the
  version and generation to show.

### Its identity and source

The host gives each mounted medium a **medium id**, a GUID kept across sessions in the recovery journal and the
machine's state, so two `work.woz` images, or two disks a program ejected from one drive, are never confused. Its
**source** is one of:
- an **image**: its library reference or path, format, and **baseline**, the revision of the file it matches: length,
  last write time and SHA-256;
- **built**: made by the launch, such as a `dos` disk;
- **blank**: made by `new`;
- **recovered**: taken from the journal after a stop or crash, with the source it belongs to.

### Changed, stale and saved

- **Changed**: the medium's version differs from its **saved version**, the version of the last snapshot that was
  saved to its source without loss, or loaded from it. A built medium starts unchanged: it needs no first save, and
  only counts as changed once the machine writes it. A blank medium starts changed.
- **Stale**: the file no longer matches the baseline. Each host watches the images it has open, and checks again
  just before any write.
- **A save** commits a snapshot. If the format held all of it, the baseline becomes the file just written and the
  saved version the snapshot's. A **lossy** save, which the user allowed, writes the file and moves the baseline to
  it, but leaves the medium changed against it, and its full copy stays in the journal: reloading the image could
  not give the disk back, so nothing marks it clean.
- **Revert to Image** reads the file as it is now and replaces the medium with it, so it means the same whether or
  not the file is stale.

### One way out of a drive

Every way a medium leaves a drive goes through one host step, **prepare to detach**: an explicit eject, an insert
over it, removing its card, the legacy `retro/media` request, a relaunch, an off-machine change, a revert, and the
machine's own eject. For one a person started:
1. A new image is read and checked first, so a bad file leaves the old disk where it was.
2. An unchanged medium detaches.
3. A changed one answers `changed`, and the client asks: save, save as, discard (with Undo) or cancel. After a save
   the step checks again that nothing changed meanwhile.

For the machine's own eject, nothing can ask: the drive snapshots the medium into the journal, synchronously, before
it lets go, and the host keeps each ejected medium as its own entry, however many there are.

## What each format keeps

Three guarantees, which every format states for itself:
- **byte-exact**: an unchanged medium saved to its own format gives back the file's bytes; an unchanged save writes
  the file it read, not a re-encoding;
- **guest-equivalent**: the machine reads back the same data, though the file's layout may differ;
- **physical**: every bit, ID, mark, error and track the medium holds survives.

A save never converts silently. Each codec checks that it can hold the snapshot (track count, quarter tracks, sector
IDs, sides, density, sizes, marks, CRC errors, header fields), and anything it cannot is listed; the user can save
as a format that holds it, save anyway, or cancel.

| Format | Holds | What it can lose, and what changes here |
| --- | --- | --- |
| **WOZ** | physical: tracks, lengths, the quarter-track map, unknown chunks, and the write-protect flag, now kept in step with the lock | a WOZ1 image is written as WOZ2, and the save says so |
| **`.dsk`, `.do`, `.po` (5.25)** | guest-equivalent while every track is standard | the reader grows to 35-40 tracks, as the converter reads; a quarter track, a track that no longer decodes as 16 sectors, and a DOS volume other than 254 are reported. On load, a `.dsk`'s order is found from its filesystem, not assumed, and saved back the same |
| **`.d13`** | reads only | no writer from WOZ yet: save as `.woz` |
| **2MG** | physical, once the header is kept: creator, version, comment, creator data, flags and unknown bytes | today `Disk35Disk` drops the header; it keeps it and rewraps on export. Its locked flag is the lock |
| **`.po`, `.hdv`, `.img`, 3.5 `.dsk`** | physical: raw blocks | nothing |
| **JV1** | guest-equivalent for one side, single density, sectors 0-9 of 256 bytes on every track, `$FA` marks on track 17 and `$FB` elsewhere, no CRC errors, IDs matching the track | the writer lists each of these it finds otherwise, and does not keep a track's sector order |
| **JV3** | physical for what `FloppyDisk` holds, but for a sector whose ID names another track or side than where it lies, which an entry cannot say, and double-density marks other than `$FB` and `$F8` | the writer puts each sector where it lies and lists those, and sectors past two tables; it packs the tables, so a changed save is guest-equivalent, not byte-exact |
| **JVC** | guest-equivalent for uniform geometry | the writer keeps the header it was read with, its sides grown to the disk's, takes a new disk's geometry from its first track, and lists what does not fit it, single density and marks other than `$FB` |
| **DMK** | physical, with gaps and CRCs | the floppies' snapshot, and their recovery format ([below](#the-recovery-journal)); the writer lays out IBM gaps, or none for a track too full for them. The CoCo loads it |
| **IMD** | reads, dropping some details | a writer comes later; a changed IMD disk saves as DMK or JV3 until then |
| **CAS** | the decoded bytes the machine wrote | timing and the analog signal. Generating a waveform from a CAS needs the machine and baud rate: the supported ones are the Model I's 500, the Model III's 500 and 1500, Level I's 250, and the CoCo's 1500 |
| **TAP** | exact: the Altair's tape is the bytes in order, as the 88-ACR sends and receives them | none; its writer is today's eject |
| **WAV** | the Apple-1's tape format | written at 44.1 kHz, a recording is guest-equivalent, not cycle-exact; the recovery journal keeps the half-cycles themselves |

## Write protection

Two things are kept apart:

- **The lock** says whether the machine can write the disk, as a real disk's write-protect tab does. It belongs to
  the medium: WOZ, 2MG and JV3 store it, saving writes it back, and changing it is a change to save. Formats without
  one forget it, though the machine's state keeps it.
- **A read-only image** is one the host cannot write: a read-only file or folder, an image under
  `RETROCORE_CACHE`, or one in a read-only library ([machine files](MachineFiles.md#libraries)). It saves only with
  save as.

**The default lock depends on the source.** A read-only image loads locked, and so does any disk from a library set
to load its disks locked, as one of master disks would be. Any other disk loads with the lock its image stores, and
otherwise unlocked. Unlocking a read-only image is allowed: the machine writes its copy, which saves as a new file.
The machine's state keeps each drive's choice, and it wins over the default. This replaces today's per-drive
defaults, including the Disk II's loading every disk locked, once the recovery journal is in place
([phase 4](#phases)).

**Hard disks**, which have no tab:
- A locked **ProFile** fails writes as the drive does when a write fails: the operation-failed bit in its status. That
  is `$27`, an I/O error, through the Apple II's ProFile ROM, and an I/O error through the Apple III's SOS driver;
  neither can report write protection, and the docs say so.
- **Slot 7** gets a writable block device. Its ROM announces whether it can write when the machine starts, and a
  running ProDOS has already read that, so its lock takes effect at the next power-on, and the drive says so until
  then.

## Saving

### A save, step by step

1. **Snapshot.** At one point under the session's lock, the host takes the medium's snapshot with its medium id,
   mount generation, version, lock, format and baseline. The snapshot is immutable; nothing else happens under the
   lock, so the guest does not wait on the disk.
2. **Encode.** The codec writes the image and its list of losses, off the machine's thread.
3. **Commit**, per destination one at a time: Retrocore's hosts on one PC share a lock per image file in local data.
   The host reads the file's revision again; if it is not the baseline the user authorized, the save stops with
   `conflict`. Otherwise it keeps the revision it just read as the backup and replaces the file.
4. **Complete**, only if the drive still holds the same medium id and generation: the baseline and saved version
   move as [above](#changed-stale-and-saved). A save that finishes after its disk was ejected marks nothing.

### Writing the file

- **Atomic where the file system allows.** The host writes `.name.<guid>.saving` beside the image, flushes it, and
  replaces the image: `File.Replace` on Windows, which keeps the file's attributes and ACLs and gives the backup, and
  a rename elsewhere. A failed write leaves the image as it was and removes the temporary file.
- **Links.** A symbolic link is followed and its target replaced, so a link into a repository stays a link.
- **Transient locks.** OneDrive and antivirus programs hold new files briefly. A sharing violation is retried for
  about two seconds before it is reported, and is never shown as a read-only file, which is told by the file's
  attribute or a denied ACL.
- **What is promised.** The check and the replace are as close together as the file system lets them be, and other
  Retrocore hosts take the same lock; a program outside Retrocore that writes the file in that instant can still be
  overwritten, and the backup then holds what Retrocore read. On a network share or a synced folder the replace is
  atomic only for that file, not across files. Save as creates a new file and never replaces one without the
  dialog's question.
- **One backup, always.** Every save keeps the revision it replaced: in the history when it is on, and otherwise as
  the one backup of that image in local data. Saving never claims a backup it did not make.

### When media is written

| When | What happens |
| --- | --- |
| **Save** | The medium is written to its source, in its format, keeping a backup. It asks only when something is off ([below](#saving-in-each-state)). |
| **Save as** | Written to a path and format the user picks; the medium then comes from it, with a fresh history. |
| **Eject**, by the user, and every other detach | [Prepare to detach](#one-way-out-of-a-drive): save, save as, discard (with Undo) or cancel. |
| **Eject**, by the machine | Snapshotted into the journal before it lets go, and kept under its drive. |
| **A recording** | A changed tape like any changed disk: written to its file on Save or eject, through the same writer, and kept in the journal at stop or a crash. A file that appeared at its path since the recording started is a conflict. |
| **Session end** | Nothing is written to images. The journal's last snapshots are the machine's unsaved state ([below](#the-recovery-journal)). |
| **Checkpoints** | Every 30 seconds while a medium changes, a snapshot goes to the journal, and to the history when it is on. Never to images. |
| **Write-through** | Later, and separately ([below](#write-through)). |

| Device | Save | Save as |
| --- | --- | --- |
| Disk II | `.woz`, `.dsk`, `.do`, `.po` | the same; `.d13` needs a writer first |
| 3.5 drive | its own format, 2MG rewrapped | `.po`, `.2mg`, `.hdv`, `.img` |
| ProFile, slot 7 | `.po`, `.hdv` | the same, and `.2mg` |
| TRS-80 floppies | JV1 when the disk fits, JV3, DMK | DMK always; JV3 and JV1 when the disk fits (the Model II: DMK and JV3) |
| CoCo floppies | JVC when the disk fits, DMK | DMK always; JVC when the disk fits |
| Cassettes | the recording | `.cas` (TRS-80, CoCo), `.tap` (Altair) or `.wav` (Apple-1, and generated for the CAS machines' supported baud rates) |
| CoCo ROM pack | never | never |

## The recovery journal

What the machine wrote and did not save is kept in a journal in local data, never in an image, a library or a
repository, and never only in memory.

### What it holds

`%LOCALAPPDATA%\Retrocore\Recovery\<machine id>\` ([the places](MachineFiles.md#the-places)):
- `session.json`: the machine file, the PC, the host's process id and start time, when the session started, and
  whether it ended cleanly;
- for each medium, by its medium id, numbered snapshots that are never rewritten, and `journal.json`, which names
  the latest committed snapshot of each medium with its source and baseline, and the machine's ejected media.

**Snapshots are lossless, and real images**, in the format that holds everything for the kind of medium, whatever
the source's format:

| Medium | Snapshot format |
| --- | --- |
| Disk II | WOZ2 |
| 3.5-inch disk, ProFile, slot 7 | 2MG, keeping the source's header when it had one |
| TRS-80 and CoCo floppies | DMK |
| TRS-80 and CoCo tapes | CAS, with a small record of the recorder's state: its buffered bits, copied without flushing the recorder |
| Apple-1 tapes | its half-cycle lengths, the one format of Retrocore's own, as no standard one is exact |
| Altair tapes | TAP, the bytes the 88-ACR wrote, which is all its tape holds |

### When it is written

- **Checkpoints**, every 30 seconds while a medium changed since the last, and only when its controller is idle: the
  Disk II not writing, the TRS-80's controller between commands, the ProFile between commands, a recorder between
  bytes. A checkpoint that cannot find an idle moment in five seconds is taken anyway and marked as caught
  mid-write.
- **The machine's own eject**, before the drive lets go.
- **Stop**: only a medium that changed since its last checkpoint is snapshotted, so stopping writes little; then
  `session.json` is marked clean. The journal is committed by writing the snapshot first and `journal.json` after
  it, replaced atomically, so a crash at any point leaves the previous state whole.
- 30 seconds is a target, not a promise: when writes fail, the disk is full or the work falls behind, the drive says
  so in its tooltip and the Drives view shows a warning.

### Starting again

- **After a clean stop**, starting the machine puts each recovered medium back in its drive, changed against its
  source. A source that changed since is a conflict the Machine view reports; a source that is gone does not stop
  the recovered copy from starting. Nothing in the journal is dropped without the user's choice.
- **After a crash**, the next Retrocore host to start finds sessions not marked clean whose process is gone (by its
  id and start time, so a reused id is not mistaken), and offers them ([the UI](#a-crash)). Recovering one adopts its
  latest snapshots as the machine's unsaved state.
- **Mirrored for backup.** After a clean stop, the language server or the standalone emulator, not the stopping
  session, copies the journal's latest snapshots and a small `unsaved.json` into the machine's `Unsaved\` folder, so
  a backup of the machine's folder has them ([machine files](MachineFiles.md#a-data-folder)). A machine inside a git
  repository is not mirrored, so a run never changes the repository; nor, by setting, is any machine. The machine
  file itself does not change: its unsaved state is the journal, or the mirror on a PC with no journal for it.

### Built disks

A `dos` or source launch builds its disk afresh every time, so F5 always runs the code just built. If the last run
changed its built disk, that disk is not put back: it stays in the history, and one notice says so, with **Save Disk
As...** ([the UI](#a-built-disk-the-last-run-changed)). At stop, a changed built disk is listed with the others, and
saving it means save as.

## History

Every medium keeps a history of versions, as Time Machine keeps a file's, and any of them can come back. It is
optional; the journal is not. It covers media only: a whole-machine snapshot (CPU, memory and devices) is a later
feature, which can name these versions rather than copy the disks.

### Versions

| A version is taken | Which keeps |
| --- | --- |
| on insert | the image as loaded |
| before and after each save | the revision the save replaces (the backup), and what it wrote |
| at each checkpoint that changed the medium | what the journal checkpointed |
| when the session stops | the disk as the session left it |
| before a revert, a restore or a discard | what those drop, which Undo restores |
| when the machine ejects a disk | the disk it ejected |
| when a launch rebuilds a built disk the last run changed | the last run's disk |

Each version records its time, what took it, the machine, its differences from the version before (by sector,
track or block, from the snapshots' changed chunks, not by decoding every track), and a pin and a label when the user
gives them. A history belongs to a medium id; Save as starts a new medium with a fresh history, and the chunks the
two share are stored once.

### Storage

In local data (`%LOCALAPPDATA%\Retrocore\History`), never in a data folder: its many small chunks would keep OneDrive
busy. Content is stored in chunks named by their SHA-256 (a Disk II track, a floppy track, 4 KB of a block image),
and a version is a small manifest of its chunks, so versions share what they have in common.

Several processes use it at once (the debug host, the language server, the standalone emulator), so:
- a version writes its chunks, then publishes its manifest atomically under a short store lock;
- thinning and clearing take the same lock, and delete only chunks that no manifest names **and** that are more than an
  hour old, so a version still being written keeps its chunks;
- a reader that finds a manifest whose chunks are gone reports it rather than failing;
- the off machine reads the history but never adds to it.

### Thinning

Every version from the last hour, the newest of each hour for the last day, of each day for the last month, and of
each week before that. Never thinned: pinned versions, each medium's newest, and the version matching each image's
baseline. The size setting, 1 GB, is a **target**: thinning drops the oldest versions it may, and when what must be
kept is larger, the history says it is over its target and by how much. **Clear History** empties one medium's
history or all of them, asking first. No machine needs the history to start: the journal holds its unsaved state.

### Using a version

- **Restore to Drive** makes the disk that version, changed against its image; the disk it replaces becomes a
  version first.
- **Restore to Image** writes the version over the image, as a save does.
- **Save As...** writes it to a new image.
- **Compare with Disk** and **Compare with Previous** list the differences: by sector, track or block now, and by
  file once the media library reads the disk's filesystem.
- **Pin**, **Label...** and **Delete**.

### On, off and settings

History is on by default, and can be turned off for all media or for one disk; a disk's own choice wins and is kept
in the machine's state. With history off a disk keeps no versions, but the journal still keeps its latest snapshot,
a save still keeps one backup, and Undo still works, from the journal, until the next change. Turning history off
asks whether to keep or clear the versions already there.

| Setting | Default | What |
| --- | --- | --- |
| `media.history.enabled` | `true` | Keep a history of versions for each disk and tape. |
| `media.checkpointInterval` | `30` | Seconds between checkpoints while a medium changes, for the journal and the history. |
| `media.history.size` | `1024` | Megabytes the history aims to stay within. |
| `media.onSessionEnd` | `keep` | `keep` changed media and ask, or `discard` it. |
| `media.mirrorUnsaved` | `true` | Copy unsaved media into the machine's folder after a clean stop (never inside a git repository). |

They live in Retrocore's roaming `settings.json` and show in VS Code as `retrocore.media.*`, kept in step as
[machine files](MachineFiles.md#settings-and-locations) describes. A change applies to a running machine at once.

## Write-through

Writing each block straight to its image, as AppleSharp's `FileBlockDevice` does, is a separate, later opt-in for
raw block images, after the rest is in use. Before it is offered, it needs:
- what happens to changes already in memory when it is turned on (saved first, or it is refused), and the new
  baseline when it is turned off;
- the file held for the drive alone, so the same image cannot be mounted elsewhere, and no stale warnings from the
  drive's own writes;
- a failed write shown to the guest as the drive's write error and to the user, with the saved version moved only
  after a write succeeds;
- what a checkpoint, a backup and a history version mean when the image is the medium.

AppleSharp's Disk II write-back on motor-off stays behind its explicit writable option until AppleSharp moves onto
machine files ([phase 6 there](MachineFiles.md#phases)); it then follows this plan, with write-through as the
opt-in.

## The debug protocol

### Answers, not errors

The outcomes a person decides on come back as successful answers, so every client gets them whole; DAP's
`success: false` carries only a message, which VS Code shows as text. A failure is kept for what nobody can act on.

```json
{ "outcome": "saved", "devices": { … } }
{ "outcome": "conflict", "medium": "m-3f9c…", "generation": 7,
  "baseline": { "length": 232960, "written": "2026-11-14T10:02:11Z", "sha256": "…" },
  "current":  { "length": 232960, "written": "2026-11-14T10:52:03Z", "sha256": "…" } }
{ "outcome": "losses", "format": "dsk", "losses": ["track 3 does not read as 16 sectors"] }
{ "outcome": "readOnly", "reason": "file" }
{ "outcome": "changed", "medium": "m-3f9c…", "differences": { "unit": "sector", "count": 14, "summary": "tracks 17-18" } }
```

Each answer names the medium id and generation it is about, and a retry names the revision it authorizes, so an
answer to an old question cannot apply to a new disk. The host says it speaks this in its `initialize` answer
(`supportsRetrocoreMedia: 1`); for an older client, a detach of changed media is refused with a message, as the safe
default. The language server's off-machine requests answer the same outcomes.

### `media` in `retro/devices`

```json
"media": { "label": "C:\\disks\\work.woz", "format": "WOZ", "writeProtected": false, "changed": true,
           "medium": "m-3f9c…", "generation": 7, "version": 1874, "savedVersion": 1200,
           "source": { "kind": "image", "path": "C:\\disks\\work.woz", "readOnly": null, "stale": false },
           "recovery": { "lastCheckpoint": "2026-11-14T10:52:30Z", "behind": false },
           "history": { "enabled": true, "own": false } }
```

`differences` and `saveFormats` come only when asked, on a drive's own request, as working them out is not free.

### `retro/device` actions

```json
{ "id": "disk35d1", "action": "save" }
{ "id": "disk35d1", "action": "save", "path": "copy.2mg", "format": "2mg" }
{ "id": "disk0", "action": "save", "acceptLosses": true }
{ "id": "disk0", "action": "save", "overwrite": { "sha256": "…" } }
{ "id": "disk0", "action": "eject", "discard": true }
{ "id": "disk0", "action": "revert" }
{ "id": "disk0", "action": "undo", "medium": "m-3f9c…" }
{ "id": "disk35d1", "action": "new", "format": "800K" }
{ "id": "disk2", "action": "restoreVersion", "version": "9b1e…" }
{ "id": "disk2", "action": "saveVersion", "version": "9b1e…", "path": "before-format.woz" }
{ "id": "disk2", "action": "pinVersion", "version": "9b1e…", "pinned": true, "label": "before FORMAT" }
{ "id": "disk2", "action": "history", "enabled": false }
```

- `overwrite` names the exact revision the user saw and agreed to replace.
- `eject`, `insert`, card removal and `retro/media` all answer `changed` for a changed medium until it is saved or
  `discard` is given.
- `undo` puts back what the last revert or discard dropped.
- `retro/mediaHistory` lists a drive's versions and compares two, as the History row needs; `retro/mediaEjected` tells
  the client a machine ejected a disk; `retro/mediaRecovery` lists and adopts crashed sessions for the language
  server.

On `disconnect` the host snapshots what changed since the last checkpoint, marks the session clean, and answers; it
writes no images, mirrors nothing and does not depend on a last event reaching the extension.

## The UI workflow

### What a drive shows

| State | Values | Shown as |
| --- | --- | --- |
| **Lock** | locked · unlocked | a small padlock, closed or open, in the corner of the drive's own icon, on every drive with a disk. The badge takes the activity's colour (reading, writing, seeking) |
| **Diff** | same · **changed** · **stale** · both, a conflict | at the row's end, as Git marks a changed file: `●` changed, `⚠` stale or a conflict |
| **Read-only image** | can be saved over · read-only file or folder · cache · read-only library | `read-only image` in the description, and Save As in place of Save |
| **Recovery** | up to date · behind | a warning in the tooltip and the decoration when checkpoints fall behind |

- **Icons.** Each kind of drive keeps its own picture (5.25-inch floppy, 3.5-inch floppy, hard disk, tape) and adds
  the padlock badge, drawn as custom icons for light and dark themes. Tapes have no badge: a playing tape cannot be
  written, and a recording can.
- **Inline buttons are icons**, with tooltips: VS Code shows no text there. They are `save` (or `save-as` for a
  read-only image), `eject`, and the lock toggle, which shows the disk's current state, closed or open, pressed while
  locked, so it always agrees with the badge. Its tooltip says what a click does: "Locked: click to let the machine
  write it".
- **Always visible.** Inline buttons show only while the pointer is on a row, so the icon, the description and the
  decoration carry the state.

The mockups below draw VS Code's views in text: `▣` is a 5.25-inch floppy, `◫` a 3.5-inch one, `⛁` a hard disk and
`▭` a tape, each followed by its badge `🔒` or `🔓`; `▫` is an empty drive. Inline buttons are written as their
icons' names in brackets, `[🔓]` being the lock toggle.

```text
DRIVES   History on                                                         [🕘] [⚙] [↻]   (3)
▾ Slot 4 · ProFile card · 1 drive
    ⛁🔓 ProFile        hard1.po · block 7 · reading                         [🔓] [eject]
▾ Slot 5 · 3.5 disk controller · 2 drives
    ◫🔓 3.5 drive 1    prodos.2mg · block 412 · writing                 ●   [🔓] [save] [eject]
    ◫🔓 3.5 drive 2    system.po · read-only image                      ●   [🔓] [save-as] [eject]
▾ Slot 6 · Disk II controller · 2 drives
    ▣🔓 Drive 1        work.woz · image changed on disk                 ⚠   [🔓] [save] [eject]
    ▣🔒 Drive 2        dos33.dsk · track 0                                  [🔒] [eject]
▾ Slot 7 · block storage
    ▫ Slot 7 disk      empty
```

- `(3)` is the badge: three media changed and not saved. Its tooltip names them.
- Drive 1's `save` will ask, as its image changed; its tooltip says so ("Save... (the image changed on disk)").
- Drive 2 loaded locked from a read-only library of master disks; a disk the same as its image has no `save`.

A changed drive's tooltip:

```text
┌──────────────────────────────────────────────────────────────┐
│ Drive 1: 5¼-inch floppy drive                                │
│                                                              │
│ work.woz (WOZ), C:\disks\work.woz                            │
│ Changed: 14 sectors on tracks 17-18, not saved to the image  │
│ Image changed on disk: 10:52 today; it was 10:02 when read   │
│ Unlocked: the machine can write it                           │
│ Last checkpoint: 10:52:30                                    │
│ Track 17, sector 4, writing                                  │
└──────────────────────────────────────────────────────────────┘
```

A drive's menu:

```text
┌──────────────────────────────────┐
│ Save                             │
│ Save As...                       │
│ Revert to Image                  │
│ Show History                     │
├──────────────────────────────────┤
│ Insert...                        │
│ Eject                            │
│ Lock (Unlock when locked)        │
└──────────────────────────────────┘
```

### Saving in each state

| State | Save |
| --- | --- |
| same | not offered |
| changed, fits, open | writes at once, keeping a backup |
| changed, lossy | asks, listing what would be lost: **Save as WOZ / DMK...**, **Save Anyway**, cancel |
| stale or a conflict | asks, with the differences: **Overwrite**, **Save As...**, **Revert to Image**, cancel |
| read-only image | save as only; says why, and offers **Make Writable** for a read-only file |

A quiet save says so in the status bar for five seconds:

```text
 ✓ Saved work.woz from Drive 1; the version it replaced is kept
```

A lossy format:

```text
┌──────────────────────────────────────────────────────────────────┐
│ ⚠ games.dsk can't hold the disk in Drive 1 as it is              │
│                                                                  │
│   Track 3 no longer reads as 16 sectors, so a .dsk would lose    │
│   it. A .woz keeps every track as it is. Saving anyway keeps     │
│   the whole disk in Retrocore, still marked changed.             │
│                                                                  │
│             [Save as WOZ...]   [Save Anyway]   [Cancel]          │
└──────────────────────────────────────────────────────────────────┘
```

A TRS-80 disk reads `newdos.dsk is JV1, which can't hold side 1 or track 0's double-density sectors. DMK keeps them.`
with **Save as DMK...**.

A stale image or a conflict:

```text
┌──────────────────────────────────────────────────────────────────┐
│ ⚠ work.woz changed on disk after Drive 1 read it                 │
│                                                                  │
│   The machine changed 14 sectors on tracks 17-18.                │
│   The file changed at 10:52 today; it was 10:02 when read.       │
│   Overwriting replaces the file's changes; they are kept as a    │
│   backup.                                                        │
│                                                                  │
│   [Overwrite]   [Save As...]   [Revert to Image]   [Cancel]      │
└──────────────────────────────────────────────────────────────────┘
```

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

An image in the cache or a read-only library says so, and offers only **Save As...** and **Cancel**.

### Revert, discard and Undo

**Revert to Image** reads the file as it is now. Neither it nor **Discard** asks; each shows a notification with
**Undo**, which puts the dropped disk back from the history, or from the journal when history is off:

```text
                         ┌─────────────────────────────────────────────────┐
                         │ ⓘ Reverted Drive 1 to work.woz; 14 changed       │
                         │   sectors were dropped.                         │
                         │                                         [Undo]  │
                         └─────────────────────────────────────────────────┘
```

### Eject

Ejecting a changed disk, and inserting over one or removing its card, ask:

```text
┌──────────────────────────────────────────────────────────────────┐
│ Save the changes to work.woz before ejecting it from Drive 1?    │
│                                                                  │
│   The machine changed 14 sectors on tracks 17-18.                │
│                                                                  │
│      [Save]   [Save As...]   [Discard]   [Cancel]                │
└──────────────────────────────────────────────────────────────────┘
```

**Save** goes through the same checks as the Save button. A disk the machine ejected itself stays under its drive,
one row for each:

```text
▾ Slot 5 · 3.5 disk controller · 2 drives
    ▫ 3.5 drive 1      empty                                                [add]
       ↳ ejected       prodos.2mg · 10:41 · ejected by the machine      ●   [save] [eject] [discard]
       ↳ ejected       scratch.po · 10:47 · ejected by the machine      ●   [save] [eject] [discard]
```

There, `eject` is "Insert Again".

### Stop

Stopping never waits. Afterwards one notification lists what changed:

```text
                         ┌─────────────────────────────────────────────────┐
                         │ ⓘ Apple IIe stopped with 2 disks not saved:      │
                         │   work.woz, prodos.2mg. They are kept.           │
                         │                                                 │
                         │               [Save All]   [Review]   [Discard] │
                         └─────────────────────────────────────────────────┘
```

**Save All** saves each in turn, and a disk that needs a prompt asks; **Discard** has Undo; dismissing keeps them.
A quick start adds **Save as Machine...** ([machine files](MachineFiles.md#the-hosts)).

### A built disk the last run changed

```text
                         ┌─────────────────────────────────────────────────┐
                         │ ⓘ Drive 1 has a fresh build of hello.s. The     │
                         │   last run's disk had changes; it is in History. │
                         │                                                 │
                         │                    [Save Disk As...]   [Show]   │
                         └─────────────────────────────────────────────────┘
```

### A crash

When a host starts and finds a session that did not stop cleanly:

```text
                         ┌─────────────────────────────────────────────────┐
                         │ ⚠ Apple IIe for Work did not stop cleanly at     │
                         │   10:52. 2 disks had changes, the last kept at   │
                         │   10:52:30.                                     │
                         │                                                 │
                         │                 [Recover]   [Review]   [Discard] │
                         └─────────────────────────────────────────────────┘
```

**Recover** makes them the machine's unsaved disks, shown on the machine while it is off; **Discard** asks once,
as no Undo can follow a choice made for a session that is gone.

### The off machine

```text
MACHINE
▾ 🖥 Apple IIe        Enhanced, 65C02 · off · 2 disks not saved
DRIVES                                                                                     (2)
▾ Slot 5 · 3.5 disk controller · 2 drives
    ◫🔓 3.5 drive 1    prodos.2mg · kept from the last run              ●   [🔓] [save] [eject]
    ▫ 3.5 drive 2      empty                                                [add]
▾ Slot 6 · Disk II controller · 2 drives
    ▣🔓 Drive 1        work.woz · kept from the last run                ●   [🔓] [save] [eject]
    ▣🔒 Drive 2        dos33.dsk                                            [🔒] [eject]
```

Starting it again boots with those disks as they were left, still changed.

### The History row

Each drive with a disk has a **History** row among its details:

```text
▾ ▣🔓 Drive 1       work.woz · track 17 · writing                    ●   [🔓] [save] [eject]
    Image            C:\disks\work.woz (WOZ 2)
    Changed          6 sectors on track 17, not saved
  ▾ 🕘 History       14 versions                                               [🕘] [⚙]
      ● now          not saved · 6 sectors on track 17
        10:52:30     checkpoint · 2 sectors on track 17                    [restore] [compare]
        10:52:00     checkpoint · 8 sectors on tracks 17-18
      📌 10:43        saved to work.woz · before FORMAT
        10:31        saved to work.woz
        09:58        inserted
      ▸ Yesterday    5 versions
```

A version's menu has **Restore to Drive**, **Restore to Image**, **Save As...**, **Compare with Disk**, **Compare with
Previous**, **Pin**, **Label...** and **Delete**. Compare opens a read-only document:

```text
work.woz: 10:31 (saved) against now (not saved)

Track 17   sectors 3, 4, 9            changed
Track 18   sectors 0, 1, 2            changed
Track 18   sector 11                  unreadable now
```

### Turning history on and off

A **clock**, lit while history is on and grayed while it is off, turns it on and off, and a **gear** opens its
settings: in the Drives view's title bar for all media, and on each History row for that disk. The row's own icon is
the clock too, so a disk's state shows without the pointer on it.

```text
DRIVES   History on                                                         [🕘] [⚙] [↻]
DRIVES   History off                                                        [🕘̸] [⚙] [↻]
```

```text
  ▾ 🕘 History       14 versions                                               [🕘] [⚙]
    🕘̸ History       off for this disk                                         [🕘̸] [⚙]
    🕘̸ History       off for all media                                         [🕘̸] [⚙]
```

- The clock is a toggle (VS Code's `toggled` state), and its tooltip says what a click does and how much the
  history holds: "Turn Off Media History (312 MB of 1 GB)". It writes the setting at the scope its value comes from,
  user or workspace.
- The title bar's gear opens the Settings editor filtered to `retrocore.media`. A row's gear opens a list for the
  disk:

```text
┌ History of work.woz ──────────────────────────────────────────────┐
│ 🕘 Turn Off History for This Disk                                  │
│ 🕘 Follow the Media Setting (on)                                   │
│ 🗑 Clear This Disk's History...       14 versions · 3.1 MB          │
│ ⚙ Media Settings...                  312 MB of 1 GB in all         │
└────────────────────────────────────────────────────────────────────┘
```

Turning history off asks once whether to keep or clear the versions already there. The Command Palette has **Turn On
Media History**, **Turn Off Media History**, **Media Settings** and **Clear Media History...**.

### The display panel

Its drive line shows the lock and `changed` for every drive, with no save controls; clicking a drive reveals it in
the Drives view. Its ended-session banner says how many disks were left changed.

```text
D1: track 17.00 · bit 2311/51024 · motor on · unlocked · changed | D2: track 0.00 · motor off · locked
```

## Costs

- **Memory.** A medium is held once, plus its snapshot's chunks while they are written; the baseline is a revision,
  not a copy, and Revert reads the file. Four 32 MB ProFiles cost about 128 MB, not twice that.
- **Pauses.** A snapshot copies only the chunks changed since the last one, under the session's lock; the target is
  under 5 ms for a 32 MB ProFile with a few hundred blocks changed. `WriteBit` and sector writes only mark a chunk.
- **Work.** Encoding, hashing and writing happen off the machine's thread, coalesced per medium; a medium never has
  more than one checkpoint queued, and falling behind shows in the drive.
- These are measured with several large drives and two sessions at once before the 30-second target is claimed.

## Decisions (agreed 2026-11-14)

The first round:
- **Stop keeps and asks**; nothing writes the user's images without them.
- **Save asks only when something is off**: a lossy format, a stale image or a read-only image.
- **A time-machine history of media**, optional, in local data, thinned as Time Machine thins, listed under each
  drive, with clocks and gears to turn it on and off for all media or one disk.
- **Every disk shows its lock**, and image flags are the lock; a read-only image is told in words.
- **Differences by sector now, by file later.** Open images are watched.
- **The display panel shows only the indicator.**

After the reviews:
- **Snapshots are lossless real images per kind of medium**: WOZ2, 2MG, DMK, CAS with the recorder's state, and the
  Apple-1's half-cycles, and the Altair's TAP. A save to the source's format checks what it can hold.
- **Unsaved state is a recovery journal in local data**, mirrored into the machine's `Unsaved\` after a clean stop for
  backup, except inside a git repository. The machine file stays a description of the machine.
- **Built disks are rebuilt every launch**; a changed one from the last run stays in the history, with a notice.
- **The default lock depends on the source**: read-only images and locked libraries load locked, others as their
  image says, else unlocked. It lands with the journal.
- **Lock icons are the drive's own icon with a padlock badge**, and the toggle shows the current state.
- **One Revert to Image**, which reads the file; Revert and Discard show Undo instead of asking.
- **Every save keeps one backup**, with history on or off.
- **A lossy save leaves the disk changed**, with its full copy kept.
- **History controls stay, trimmed**: the quota is in the clock's tooltip and the gear's list, and Save as starts a
  fresh history.
- **Settings are kept in step both ways with a merge base.**
- **Saves come first**, then the journal, then the history, then machine files; write-through is separate.
- **A recording is a changed tape**, saved like a disk and kept in the journal.

## Tests

| Area | Cases |
| --- | --- |
| Format fidelity | Unchanged WOZ2 byte-exact and WOZ1 upgraded; 35- and 40-track sector images, extra quarter tracks, a ProDOS-order `.dsk`, a volume other than 254; 2MG with comment, creator data and unknown bytes; JV1 with side 1, extra sectors and marks reported; JV3 with ID track and side differing from the physical ones; JVC with each header form; DMK round trips; CAS for each supported baud rate; Apple-1 WAV timing within its stated tolerance. Bytes where byte-exact is promised, the guest's reads otherwise. |
| Recovery format | For each mutable device, a medium no source format can hold (a half-formatted track, a reformatted JVC track), snapshotted, restarted and compared with what the machine sees. No recovery uses a lossy format. |
| Detach | A changed disk under insert-over, card removal, `retro/media`, relaunch, revert and two guest ejects; a failed insert leaves the old disk. Nothing leaves without a committed copy or a discard. |
| Built disks | A `dos` launch that writes its disk, stops and launches again runs the new build, and the old disk is in the history. |
| Crash and failure | The host killed at every chunk, snapshot, `journal.json`, image-replace and cleanup step, then started fresh: the previous committed state survives and is offered. Disk full, access denied, an offline folder, and a corrupt or missing snapshot are reported, never dropped. |
| Concurrent saves | Barriers around snapshot, confirmation, the revision check and the replace; two drives and two processes on one image; eject and reinsert during a save; completions out of order; an outside write. No unauthorized revision is overwritten, and no completion marks the wrong disk. |
| Baselines | Load A, save B, edit C, revert gives the file as it is; Save As then a later write stays changed; after a lossy save the disk stays changed and restarts whole. |
| Locks | A lock-only change saves and reloads in WOZ, 2MG and JV3; read-only files apart from locks; the ProFile's failure on the Apple II and the Apple III; slot 7's lock at the next power-on. |
| Tapes | Stop and crash mid-recording with bits buffered; a failed write keeps the recording; a file created at its path meanwhile is a conflict. |
| History | Two hosts adding, saving, thinning and clearing at once; interrupted chunk and manifest writes; pinned versions over the target; history off still journals and backs up. |
| Machines, by digest | DOS `SAVE`, ProDOS `SAVE`, TRSDOS `SAVE` and Disk BASIC write a file, the disk is saved and its SHA-256 pinned, and the machine boots it again and reads the file. |
| Protocol | Every outcome through real DAP and the language server, an older client, `retro/media`, and two sessions at once. |
| Costs | Pause, throughput, memory and checkpoint lag with four 32 MB ProFiles and two sessions. |

## Phases

1. **Foundations, and the Disk II on them.** `IMedium`, `IMediumSlot` and the codecs in `Retrocore.Media`; lock changes
   counted; the sector reader's 35-40 tracks, quarter tracks, volumes and `.dsk` order; the save steps with
   snapshots, ordered commits, revision checks, retries, links and one backup; prepare to detach on every path; the
   protocol's outcomes. Today's Disk II defaults stay. Done when the Disk II saves as it does now, plus conflicts, lossy
   saves that stay changed, and every detach path, with the tests above. It lands in two parts:
   - **The media layer (built).** `IMedium` (version, lock, snapshot), `MediumSnapshot`, `IMediumSlot` (medium and
     mount generation) and `IImageCodec` with `EncodedImage`'s losses and notes. `WozDisk` is a medium: its lock
     (`IsWriteProtected`, which was `IsReadOnly`) counts as a change and is written to the WOZ image's flag, and its
     snapshot is a WOZ2 image. `WozCodec` notes a WOZ1 image becoming WOZ2; `SectorImageCodec` writes 35 to 40
     tracks and lists a track that does not read, a quarter or half track of its own, and a volume other than 254.
     `DiskIIImage` loads each format with the codec that writes it back, finding a `.dsk`'s order from DOS 3.3's
     catalog, ProDOS's directory or Apple Pascal's volume header. The debug host's `save` uses them: a lossy save
     fails with its losses unless `acceptLosses` is given, and then leaves the disk changed. A WOZ disk has 160
     quarter tracks, so no track lies past the 40th. Tests: `DiskIIImageTests`.
   - **The host (built).** `MediaActions` in the debug host keeps each disk's source (medium id, image, codec and
     baseline revision), saves step by step (snapshot, encode, commit over the baseline or the revision `overwrite`
     names, and complete only for the same disk and mount generation), and holds back a changed disk that an
     `eject`, an `insert` over it or **Remove Card** would take out; an insert reads and checks its image before the
     disk in the drive comes out, so a bad image leaves that disk. `ImageWriter` writes the temporary file and
     replaces the image (`File.Replace` on Windows, a rename elsewhere), follows links, retries sharing violations
     for two seconds, takes each image's lock in local data, and keeps one backup there. The answers are `saved`,
     `changed`, `conflict`, `losses` and `readOnly`, to a client that sends `supportsRetrocoreMedia`; an older one
     is refused with a message. Each answer holds only for the mount it is about: a follow-up carries its
     `generation` or lists the mount in `discards`, so each of a card's changed disks is asked about, and a disk
     that went in while a question was open is never saved or let go by it. Save As replaces only the revision of
     the file the person chose, and an image deleted since is written again only once agreed. The extension's
     Drives view and Retrocore Desktop answer with modal prompts, and drop an answer for a session no longer
     active. The desktop also asks before Stop, Restart, switching machines, resetting and closing would lose a
     changed disk, holding the machine still from the first question, and asks again about a disk a lossy save
     left changed. A sector read from its second copy, after the first had a bad checksum, is a note. Tests:
     `MediaSaveTests`, and the Pascal debug adapter test's eject of its changed disk.
   - **Left for later phases.** Changing the lock alone does not yet count as a change to save: with every Disk II
     disk loading locked, unlocking one would mark it changed, so the lock joins `changed` with phase 4's default
     lock. A relaunch over a session and the session's end lose changed disks until phase 4's journal keeps them;
     saving runs on the request's thread, which is quick for a Disk II disk, until the costs are measured with the
     larger drives of phase 2. Staleness (`source.stale`) and `differences` come with phase 3's UI.
2. **Every drive saves.** The 3.5 drive with its 2MG header; the ProFile; slot 7 with a writable device and its
   lock at power-on; `FloppyDisk` writes counted; JV1, JV3 and JVC fixed; a DMK writer, and DMK on the CoCo. Done when
   each drive saves to each format it offers, reports losses, and boots again from the saved image, pinned by
   digest. It lands in two parts:
   - **The Apple II's block drives (built).** `Disk35Disk` and `MemoryBlockDevice` are media: their lock counts as a
     change to their version, and their snapshot is a 2MG of their blocks (`TwoImgContainer`), which keeps a 2MG's
     header, comment, creator data and any other bytes, so an unchanged disk wraps back to the file it read.
     `BlockImageCodec` writes bare blocks (`.po`, `.hdv`, `.img`, 3.5-inch `.dsk`) or the 2MG, with its locked flag
     as the lock, and notes a 2MG's comment and creator data dropped by a save to bare blocks. The 3.5 drive, the
     ProFile and slot 7 are `IMediumSlot`s with mount generations from `MountGenerations`, shared with the Disk II,
     and `Saved` is part of the slot; `MediaActions` saves any of them, choosing the codec from the drive's
     `SaveFormats`, which the device list gives as `saveFormats` for the clients' Save As. The ProFile and slot 7
     read 2MG too. A locked ProFile fails writes as the drive does, and slot 7 gets a writable device that loads
     locked, as today, whose ROM says it writes from the next reset after it is unlocked: the machine has no power
     cycle short of a new session. As for the Disk II, changing the lock alone is not yet a change to save.
     Tests: `BlockMediaSaveTests`, and `Test-BlockMediaDap.mjs`, where a boot block in slot 7 writes itself to a
     ProFile and to slot 7's device, which save and boot again, the image pinned by digest.
   - **The TRS-80 and CoCo floppies (built).** `FloppyDisk` is a medium: a controller changes it only through
     `Write` and `Format`, which count the change (`FloppySector`'s data is read-only), its lock counts in its
     version, and its snapshot is a DMK image, which holds every ID, mark, density, CRC error and sector order. A
     track holds what a DMK track can, at most 64 sectors in 16 KB with no gaps, more than any controller formats;
     an image with more is refused. `DmkFormat` writes IBM gaps, or none for a track too full for them. JV1 lists
     side 1, double density, sectors other than 0-9 of 256 bytes, marks other than its own, CRC errors and IDs naming
     another track; JV3 writes each sector where it lies and lists IDs naming another track or side, double-density
     marks other than `$FB` and `$F8` and sectors past two tables; JVC keeps the header it was read with (its sides
     grown to the disk's), takes a new disk's geometry from its first track, and lists what does not fit it.
     `FloppyImageCodec` writes them from the snapshot, `.dsk` as JVC on the Color Computer and JV1 on a TRS-80; IMD
     has no writer, so such a disk saves as another format. The drives are `IMediumSlot`s that save (the Model I,
     III and 4 as `.jv3`, `.dmk`, `.dsk` and `.jv1`, the Model II as `.dmk` and `.jv3`, the Color Computer as `.dsk`,
     `.jvc` and `.dmk`), and the Color Computer reads DMK. The legacy `retro/media` eject holds back a changed disk,
     as `retro/device`'s does. Tests: `FloppyMediaSaveTests`, where Disk BASIC's SAVE is saved as JVC and as DMK,
     pinned by digest, and loads and runs again in a new machine, and `Test-CocoDap.mjs`, which saves a disk through
     the protocol.
3. **The UI.** The badged icons, the states, the prompts, Revert with Undo, the eject prompt, host-side watching, and
   the off machine's saves. Done when every row of [saving in each state](#saving-in-each-state) works in the
   self-hosted extension. It lands in two parts:
   - **The drive rows and Save in each state (built).** The host watches each image a disk came from
     (`ImageWatcher`, a `FileSystemWatcher` per image and its link's target, kept whole by a sweep every two seconds,
     checked a moment after its events settle and off the machine's thread), and a drive's `source` gives `stale`,
     with the `baseline` revision and the `current` one, and
     `readOnly` (`format` or `file`); a change sends `retro/devices` even while the machine is stopped. In the Drives
     view ([drives.ts](../../extension/src/drives.ts)) each drive is its own picture (5.25-inch, 3.5-inch, hard disk,
     tape) with a padlock badge in its activity's colour, drawn as SVGs written to the extension's storage; the
     row's end carries `●` changed and `⚠` stale or a conflict, as decorations; the summary says `read-only image`,
     `image changed on disk` or `image deleted`; and the tooltip names the image, whether it changed, when the file
     changed and when it was read, the lock and the head. The inline buttons are icons: the lock toggle, which shows
     the lock as it is, **Save** (which says it will ask when the image changed), **Save As...** for a read-only image,
     and eject; the menu has Save, Save As..., Insert..., Eject, and Lock or Unlock. Save asks nothing for a changed
     disk whose image is as read, and says so in the status bar for five seconds; it asks, as the plan draws, for a
     lossy format (**Save as WOZ / DMK / 2MG...**, **Save Anyway**), a stale image or a conflict (**Overwrite** or
     **Save As...**; a deleted image, **Save There Again**), and a read-only file (**Save As...**, **Make Writable and
     Save**). The display panel's drive line says `locked` or `unlocked`. Tests: `MediaSaveTests`' watcher test,
     `drives.test.ts`, and the isolated VS Code suite's `drivesView.ts`, where a Color Computer's drive row shows its
     image changed on disk and read-only as the host sees them.
   - **Revert, discard and eject (built).** `IMedium` gains `IsDirty`, `MarkSaved` and `MarkChanged`, which every
     medium had, and `IMediumSlot` `Mount` and `Unmount`, so the host can put a disk back in its drive. `revert`
     reads the disk's image again through the machine's own insert, so a bad image leaves the disk, and a changed
     disk let go of, by Revert or by an eject or insert's discard, is kept for `undo` (the device list's `undo`, by
     its id), which puts it back, asking first about a changed disk there. A drive that the machine can eject from
     itself (`IEjectingSlot`, the 3.5 drive) hands the host each disk it ejected; a changed one is kept in the
     drive's `ejected` list until it is saved, put back (`insertAgain`) or let go (`discard`, with Undo), and a save
     works on a disk out of its drive. `differences` says what a disk changed against its image as the file is now,
     by the image's unit: sectors on tracks for a `.dsk`, JV1 or JVC, blocks for a block image or 2MG; WOZ, DMK and
     JV3 give none. In the Drives view, **Revert to Image** is in the drive's menu and in the stale prompt, and shows
     a notification with **Undo** ("Reverted Drive 1 to work.woz; 14 changed sectors were dropped."); the eject,
     insert and Undo prompts for a changed disk offer **Save**, **Save As...** and **Discard**, saying what changed,
     and a discard shows **Undo**; a changed disk's tooltip says what changed once the pointer is on it; and the
     machine's ejected disks are rows under their drive with **Save**, **Insert Again** and **Discard**, counted in
     the badge. A session that ends with disks not saved says which; until the journal keeps them past the session
     (phase 4, with **Save All**, **Review** and the off machine's kept disks), their changes are not kept. Tests:
     `MediaUndoTests`, `drives.test.ts`, `drivesView.ts`'s revert, and `Test-CocoDap.mjs`, where a disk Disk BASIC
     wrote says it changed sectors on tracks 16-17, reverts and is undone.
4. **The recovery journal.** Medium ids, checkpoints at idle moments, the machine's eject, clean stop, crash
   discovery and recovery, built disks rebuilt, recordings as changed tapes, the stop and crash notifications (with
   **Save All**, **Review** and **Discard**, and the off machine's saves of the disks kept), and then the
   source-aware default lock. Done when every case in *Crash and failure*, *Detach*, *Built disks* and *Tapes*
   passes in a fresh process.
5. **The history.** The chunk store with its lock and grace window, thinning to a target, the History rows, Compare,
   the clocks and gears. Done when the *History* tests pass and a disk restores to any version, running or off.
6. **Machine files.** The `Unsaved\` mirror and machine ids, with [machine files](MachineFiles.md#phases)' fourth
   phase.
7. **New media.** `new` for blank disks and tapes. Done when a blank 800K disk formatted under ProDOS saves as `.po`.
8. **Later.** Write-through, under [its conditions](#write-through); IMD and `.d13` writers; WAV to CAS; the Altair's
   disks, which follow this model from the start.

Each phase updates [Devices.md](../Devices.md) and the machines' docs as it lands.
