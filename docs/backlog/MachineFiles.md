# Backlog: machine files, data folders and libraries

Where Retrocore keeps machines, their media and the user's images, as files Retrocore owns rather than VS Code
state, so VS Code and the standalone emulator open the same machines, and users can see, organize and back them up.

**Status:** proposed 2026-11-14 and revised the same day after two reviews; nothing here is built. The
[decisions](#decisions-agreed-2026-11-14) were agreed on 2026-11-14. [Saving media back to images](MediaPersistence.md)
builds on it.

## What there is

| What | Where it is kept now |
| --- | --- |
| A launch configuration's saved machine (its cards and media) | VS Code's workspace state, `retrocore.savedMachine:<configuration name>`, with a fingerprint of its hardware options ([savedMachine.ts](../../extension/src/savedMachine.ts)) |
| Start Machine's last setup, the machine shown while off | workspace state |
| Favorites: a setup (catalog machine, settings, what it runs), a name, a description and a saved machine | the `retrocore.favorites` setting, user or workspace ([favorite.ts](../../extension/src/favorite.ts)) |
| Which launch configuration is which favorite | workspace state |
| AppleSharp's settings | `%LOCALAPPDATA%\AppleSharp\settings.json` |
| Fetched ROM dumps and test images | `RETROCORE_CACHE`, by default `%USERPROFILE%\Retrocore` |

All of a machine's state is VS Code's, per workspace and invisible: the standalone emulator cannot open it, another
workspace cannot see it, and a user cannot back it up or copy it to another PC.

## The places

| Place | Windows | macOS | Linux | Holds | Backed up |
| --- | --- | --- | --- | --- | --- |
| **Roaming settings** | `%APPDATA%\Retrocore\settings.json` | `~/Library/Application Support/Retrocore/settings.json` | `~/.config/retrocore/settings.json` | preferences both hosts share: display, history, what stop does | roams with a roaming profile |
| **Local data** | `%LOCALAPPDATA%\Retrocore\` | `~/Library/Application Support/Retrocore/Local/` | `~/.local/share/retrocore/` | `locations.json`, the recovery journal, the history, backups, recent quick starts, caches | never |
| **Data folders** | `Documents\Retrocore\` by default; more can be added | `~/Documents/Retrocore/` | `~/Documents/Retrocore/`, or `~/Retrocore/` without a Documents folder | machines, their disks, the default library | yes, wherever the user's Documents are backed up |
| **Libraries** | each data folder's `Software\`, and any folder added | | | the user's disk and tape images, with metadata | as their folder is |

The .NET special folders give these on every system (`ApplicationData`, `LocalApplicationData`, `MyDocuments`), so
the debug host, the language server and the standalone emulator find them alike; the extension asks the language
server rather than working them out itself.

**Why Documents.** On Windows, OneDrive's folder backup (Known Folder Move), on by default for most new installs,
backs up Documents, Desktop and Pictures, and nothing under AppData or the user's profile folder itself. Documents is
also where people look. Local AppData holds what churns or belongs to one PC: the history's thousands of small
chunks would keep OneDrive uploading, and a list of folder paths means nothing on another PC.

**Roaming settings hold no paths**, as paths are one PC's: those are in `locations.json`.

`RETROCORE_CACHE` keeps working, but its default moves to `%LOCALAPPDATA%\Retrocore\Cache`, so a user does not see a
`Retrocore` folder in their profile beside the one in Documents; the old default is still read if it exists.

## A data folder

```text
Documents\Retrocore\
  Machines\
    Apple IIe for Work\
      Apple IIe for Work.machine.retrocore     the machine; open it in VS Code or the standalone emulator
      Disks\                                   disks the machine made: blanks, a dos launch's disk, Save As by default
      Tapes\                                   its recordings
      Unsaved\                                 a copy of its unsaved disks after a clean stop, for backup
      Snapshots\                               later: whole-machine snapshots
    TRS-80 Model I with NEWDOS\
      TRS-80 Model I with NEWDOS.machine.retrocore
      Disks\
  Software\                                    the data folder's library: its disks and tapes
    library.retrocore
    Apple II\
    TRS-80\
  ROMs\                                        its ROM library
    library.retrocore
```

- **Everything in a data folder is a file a person can open.** Machines are JSON; disks and tapes are ordinary
  `.woz`, `.po`, `.dsk`, `.cas` and `.wav` images. Stores no one browses (the history's chunks, indexes) are in local
  data only.
- **One folder per machine**, with the machine file inside, named as the folder is. Copying, zipping, backing up or
  sharing a machine is one folder, and renaming or moving it cannot part the file from its state. Renaming the machine
  in Retrocore renames both; a folder renamed by hand still opens, and the machine takes the folder's name.
- **Subfolders appear when used.** A new machine is its file alone; `Disks\` comes with its first disk.
- **`Unsaved\` is a mirror.** What a machine changed and did not save is kept in the recovery journal in local data
  ([the media plan](MediaPersistence.md#the-recovery-journal)); after a clean stop it is copied here with a small
  `unsaved.json`, so a backup of the machine's folder has it. A machine inside a git repository is not mirrored, so
  running it never changes the repository.
- A data folder is any folder with a `Machines\` or `Software\` folder in it. A project's repository can be one, so its
  machines are checked in with its code.

## The machine file

`*.machine.retrocore` is JSON that describes the machine, written atomically, and rewritten only when its
configuration changes (a card, a disk inserted, a lock or history choice), never by running it:

```json
{
  "format": 1,
  "id": "0b7f…",
  "name": "Apple IIe for Work",
  "description": "ProDOS 2.4 with the 3.5 drive and a Mockingboard",
  "machine": "apple2-iie",
  "options": { "model": "enhanced", "monitor": "color" },
  "run": null,
  "cards": { "4": "mockingboard", "5": "disk35", "6": "diskII16", "7": "empty" },
  "media": {
    "disk1":    { "library": "Software", "path": "Apple II/DOS 3.3/dos33.dsk", "sha256": "…", "locked": true },
    "disk2":    { "path": "Disks/Scratch.woz", "locked": false },
    "disk35d1": { "library": "Software", "path": "Apple II/ProDOS/work.2mg", "sha256": "…", "locked": false },
    "disk35d2": null
  },
  "history": { "disk2": false }
}
```

- `id` is the machine's own, made when it is created and kept through renames; a copied machine gets a new id the
  first time Retrocore sees both copies. The recovery journal and the history are keyed by it, not by path.
- `machine`, `options` and `run` are a favorite's setup: the catalog machine, its settings that differ from their
  defaults, and what it runs (a program, a source file, BASIC). The host translates the catalog machine to its own
  machine and model options, as Start Machine does now. `cards` and `media` are today's saved machine.
- **Media references** take three forms:
  - **in a library**: the library's name, the path inside it, and the image's SHA-256. Each PC's `locations.json`
    says where the library is, so the machine works on a PC whose library is on another drive. A path that no longer
    resolves is found again by its hash within the library, and the machine file is updated. Several images with one
    hash are offered, never chosen silently. A save updates the hash in the saving machine's file and in
    `library.retrocore`; other machines find the image by path first, so their older hash only matters when the path
    breaks;
  - **relative**: to the machine's folder, as its own `Disks/Scratch.woz`, or a repository's `../disks/build.dsk`;
  - **absolute**: anything else, which is one PC's, and reported when it is not there.
- **Unsaved changes are not in the machine file**: they are in the recovery journal, and in the `Unsaved\` mirror
  on a PC that has no journal for the machine. A missing recovered copy keeps its entry and asks, rather than
  inserting the original in its place.
- `locked` is the drive's lock choice, and `history` a disk's own choice of history, when it has one.
- `format` is the file's version. A newer Retrocore reads older files and writes the newest; an older one opens a newer
  file read-only and says so.
- The file holds no ROMs and no disk contents, so it stays small and readable.

**A machine in use** is recorded in local data (the journal's `session.json`, with the host's process id and start
time), not beside the machine, so starting and stopping writes nothing to a synced folder, and a crashed session is
told from a running one on the same PC. Two PCs sharing a machine through OneDrive cannot see each other's sessions:
the machine file changes rarely and conflicts show as OneDrive's conflict copies ([below](#safety-and-sync)), but
running one machine on two PCs at once is not guarded. Copying a machine's folder copies its description and its
mirrored unsaved disks, not the library images, ROMs and sources it refers to; another PC needs those too.

## Libraries

A library is a folder of images, organized however its owner likes, with one `library.retrocore` at its root:

```json
{
  "format": 1,
  "name": "Software",
  "id": "5d2c…",
  "items": {
    "Apple II/Games/Lode Runner.woz": {
      "sha256": "…",
      "title": "Lode Runner", "publisher": "Brøderbund", "year": 1983,
      "hardware": { "machines": ["apple2", "apple2-iiplus", "apple2-iie"], "memory": 48 },
      "boots": true,
      "tags": ["game"]
    }
  }
}
```

- **Metadata comes from the images first.** A WOZ's META chunk has the title, publisher, year and the machines it
  requires; a 2MG has a comment; a disk's catalog says its filesystem and volume. `library.retrocore` keeps only what
  the user adds or corrects. Retrocore never rewrites an image to hold metadata.
- **One file per library**, keyed by path and hash, not a file beside every image, so the library's folders stay as
  the user made them.
- **Finding images.** Inserting a disk offers the libraries' images the drive takes and the machine runs, by title,
  tag or folder, as well as the open dialog. The folders are not what decides it.
- **Reading little.** Retrocore indexes a library in local data, by each image's path, size and date, and reads an
  image only when it is new or changed. Browsing a library reads the index and `library.retrocore`, never the
  images, so OneDrive's files-on-demand placeholders stay in the cloud until a disk is inserted.
- **Read-only libraries**, such as a mirror of an archive, are marked so in `locations.json`; their images are
  read-only images, which load locked and save only as new files.
- **Locked libraries.** A library can be set to load its disks locked (`"loadLocked": true` in `library.retrocore`),
  for master disks; the machine can still unlock one.
- **Why `Software`.** It is what people put there (games, DOS masters, programs), and it does not read as pictures,
  as `Images` would beside screen pictures Retrocore saves. The folders inside it are the user's.
- **Names are unique.** A library's name is how machines refer to it; two libraries of one name are reported and the
  second is not used until one is renamed. Each data folder's `Software\` is named for its data folder when it is not the
  default one.
- **ROM libraries** are libraries of ROM dumps (`"kind": "roms"`), found by SHA-256. A machine needing a dump looks in
  them before `RETROCORE_CACHE`; a launch's explicit paths still win.

## Settings and locations

`settings.json`, roaming:

```json
{
  "media": { "history": { "enabled": true, "size": 1024 }, "checkpointInterval": 30, "onSessionEnd": "keep", "mirrorUnsaved": true },
  "display": { "monitor": "color" }
}
```

`locations.json`, local:

```json
{
  "dataFolders": [
    { "path": "C:\\Users\\pat\\Documents\\Retrocore", "default": true },
    { "path": "\\\\nas\\retro" }
  ],
  "libraries": [
    { "path": "D:\\Mirrors\\asimov", "readOnly": true }
  ]
}
```

Libraries in data folders are found by looking; `libraries` adds the others. New machines go in the default data
folder. Local data holds `Recovery\`, `History\`, `Backups\`, `Locks\`, `Recent\` and `Cache\` beside it.

In VS Code, the shared settings are also VS Code settings (`retrocore.media.*`), so the Settings editor, the gear
and the clock show and change them. The extension keeps the two in step at the user level, both ways, against a
**merge base**: the value both last agreed on, which it keeps for each setting.
- One side differs from the base: that side changed, and its value is written to the other.
- Both differ: the newer change wins, by the shared file's time and the time the extension saw VS Code's change;
  where VS Code's time is unknown, as after Settings Sync applied it at start, VS Code's value wins and the other is
  reported once.
- A value is written only when it differs, so neither write sets off the other again.
- A workspace value applies in that workspace only and is never written to the shared file. The clock and the gear
  change a setting at the scope its value comes from.

## The hosts

- **The debug host and the language server** read `settings.json` and `locations.json` themselves, and resolve media
  references, so the extension passes a machine file's path, not its contents. A launch's **`machineFile`** option
  names it; `machine` keeps its meaning, the debug host's machine id, so existing launch configurations are unchanged:

  ```json
  { "type": "retrocore", "request": "launch", "name": "Work", "machineFile": "${workspaceFolder}/Work/Work.machine.retrocore" }
  ```

  The machine file gives the hardware and media. The launch adds the debugger's own options (`stopOnEntry`, a
  `source` or `program`), and a hardware option it also sets wins for that launch only and is not written back. A
  launch with both `machineFile` and `machine` is an error unless they agree. The host writes the machine file as its
  configuration changes, which replaces the saved machine in workspace state.
- **The extension.** The Favorites view becomes the **Machines** view: the machines in every data folder and in the
  workspace, grouped by data folder, with the heart marking the ones starred. Starting one launches it; the Machine and
  Drives views show it, running or off, as they do now. **New Machine...** is Start Machine's setup saved as a machine
  file.
- **Quick starts.** Start Machine without saving still works, and keeps the machine in local data
  (`Recent\`), not in a data folder, so throwaway machines do not fill the folder people browse and back up. The
  Machines view lists the last 10 under **Recent**, each with **Save as Machine...**, which moves it, with its unsaved
  disks, into the default data folder. When a quick start stops with changed disks, the stop notification adds **Save
  as Machine...**, since local data is not backed up. Starting an eleventh drops the oldest, unless it holds unsaved
  disks; those wait until saved or discarded.
- **The standalone emulator** opens `.machine.retrocore` files, by file association and from its own list of the data
  folders' machines, and writes them as the debug host does. AppleSharp's own settings move into the shared
  `settings.json`.

## Moving to it

On the first start of a version with machine files, the extension, asking once:

- writes each favorite as a machine file in the default data folder, keeping its name, description, heart and
  whether it was a user or a workspace favorite;
- writes each launch configuration's saved machine as a machine file named for the configuration **and its
  workspace**, such as `Boot Disk (retro-games)`, numbered when that is taken too, so two workspaces' "Boot Disk"
  configurations stay apart; in a multi-root workspace, each folder's configurations separately;
- links each configuration to its machine in workspace state, so `launch.json` is not edited; adding `machineFile`
  makes the link explicit;
- keeps `${workspaceFolder}` and other variables in paths as they were written, and turns absolute media paths into
  library references where the image is in a library;
- records what it wrote, so running it again does nothing and **Undo Machine Migration** removes exactly those
  files;
- leaves `retrocore.favorites` and the workspace state as they were, so going back to an older version loses
  nothing, and says what it did.

## Safety and sync

- Machine files, `library.retrocore` and `locations.json` are written as images are: to a temporary file beside them,
  then moved over, so a failed write leaves them as they were.
- OneDrive's conflict copies (`name-PC.machine.retrocore`) are shown as machines of their own, marked as conflicts,
  so the user can pick one; a machine file that changed on disk while open is reloaded, or reported when the open
  machine also changed.
- A data folder that is missing (a NAS offline) is shown dimmed with its machines unavailable, not removed.
- A writable library gets no state of the hosts' own but `library.retrocore`: no journals, history, thumbnails or
  temporary files beyond a save's own. Its images are saved when the user saves them, as the
  [media persistence plan](MediaPersistence.md#saving) lets any writable source be, and the save updates the image's
  hash in `library.retrocore`. Nothing at all is written into a read-only library; its index is in local data.

## Tests

- **Places.** On a test file system with Windows, macOS and Linux special folders, each host resolves the same
  settings, local data and default data folder; `RETROCORE_CACHE` and its old default still work.
- **Machine files.** Read and write round trip by digest; a machine launched from its file lists the same hardware
  and devices as the launch configuration it came from (`tools/Test-OffMachine.mjs` covers this off and running); a
  newer `format` opens read-only.
- **References.** A library moved to another drive resolves through `locations.json`; an image moved within its
  library is found by hash and the file updated; a missing absolute path is reported.
- **Libraries.** Metadata from a WOZ META chunk and a 2MG comment; browsing reads no image bytes (a file system that
  counts reads); a read-only library's image is a read-only image.
- **Moving to it.** Favorites and saved machines from fixtures become machine files with nothing lost, and running it
  twice does nothing the second time.
- **In use.** A second session of a machine on one PC is told it is running; a crashed one, whose process is gone
  or whose process id was reused, is offered for recovery.
- **Settings in step.** A change on either side reaches the other once; both changed keeps the newer, and VS Code's
  when its time is unknown; Settings Sync applying a value at start is not overwritten; a workspace value stays out of
  the shared file.
- **Launches.** `machine` alone behaves as today; `machineFile` launches the file; both, disagreeing, are an error; a
  launch's hardware option overrides the file for that launch and is not written back.
- **Migration.** Two workspaces with a "Boot Disk" configuration get two machines; a multi-root workspace; user and
  workspace favorites; variables kept; Undo removes only what migration wrote.
- **Mirror.** A machine inside a git repository is not mirrored; one outside is mirrored after a clean stop and not
  after a crash.
- **Recent.** The eleventh quick start drops the oldest, but not one with unsaved disks; Save as Machine... moves its
  unsaved disks with it.

## Phases

1. **The places.** `settings.json`, `locations.json`, local data, the default data folder and the cache's new default,
   in a shared .NET library the hosts use. Done when every host resolves the same places on each system, with tests.
2. **The machine file.** Its schema, ids, reading and writing; the launch's `machineFile` option; `retrocore/machine/describe`
   and `change` on files; the host writing it as the machine changes. Done when a machine file launches as its launch
   configuration did, off and running.
3. **VS Code moves over.** The Machines view in place of Favorites, New Machine..., Recent quick starts and Save as
   Machine..., keeping the settings in step, linking launch configurations, and moving existing favorites and saved
   machines. Done when an existing user's favorites and saved machines open as
   machine files with nothing lost.
4. **References and the machine's own media.** Library, relative and absolute references, finding by hash, `Disks\`,
   `Tapes\`, and the `Unsaved\` mirror of the recovery journal. This is [the media plan's](MediaPersistence.md#phases)
   sixth phase, after its journal is in place.
5. **Libraries.** `library.retrocore`, the local index, metadata from images, read-only libraries, and inserting from
   a library. Done when a library of a few hundred images browses without reading them and inserting a disk finds it
   by title.
6. **The standalone emulator.** Opening and writing machine files, the file association, and the shared settings.
7. **ROM libraries.** Finding dumps by hash before `RETROCORE_CACHE`.

## Decisions (agreed 2026-11-14)

- **Machines are files Retrocore owns**, `.machine.retrocore`, which VS Code and the standalone emulator share; VS
  Code's saved machines and favorites become them.
- **The default data folder is `Documents\Retrocore`**, which OneDrive's folder backup covers; more can be added.
- **One folder per machine**, with its machine file and its `Disks`, `Tapes`, `Unsaved` and `Snapshots` inside.
- **The history stays in local data**, never in a data folder, so syncing does not churn.
- **Roaming settings hold preferences; local `locations.json` holds paths.**
- **Quick starts stay in local data**, the last 10 under **Recent**, until **Save as Machine...** makes them machine
  files; the stop notification offers it when one stopped with changed disks.
- **VS Code's settings and the shared `settings.json` are kept in step both ways** at the user level; workspace values
  stay VS Code's own.
- **A data folder's library is `Software\`**, beside `Machines\` and `ROMs\`.

After the reviews:
- **The machine file only describes the machine**, with a stable id; running it never writes it. Unsaved changes are in
  the recovery journal in local data, mirrored into `Unsaved\` after a clean stop, except inside a git repository.
- **A machine in use is recorded in local data**, with its process id, not as a file beside the machine.
- **A launch names a machine file with `machineFile`**; `machine` keeps its meaning.
- **Migration names machines by configuration and workspace**, keeps variables and scopes, and can be undone.
- **Settings are merged against a stored base**, and the clock writes at the scope its value comes from.
- **Read-only libraries load locked, and a library can load its disks locked.**
