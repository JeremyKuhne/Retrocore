# Backlog: choosing and starting a machine, next round

Status: **ideas, not agreed.** The first round is done: an entry per machine in the Run and Debug dropdown, and
**Retrocore: Start Machine…**, **Start Last Machine** and **Save Last Machine as Launch Configuration**, all built
on one machine catalog ([machines.ts](../../extension/src/machines.ts)). The extension README's
[Starting a machine](../../extension/README.md#starting-a-machine) describes them. These are the candidates for
the next round:

- **Better starter configurations and snippets**, generated from the catalog: one per machine, without this
  repository's paths, so a new launch.json is useful. Today's `initialConfigurations` point at
  `${workspaceFolder}\artifacts\...` and the `RETROCORE_IIE_ROMS` variable, and there is one snippet, for a BASIC
  file.
- **Choosing the machine from the file being debugged**: a Z80 source to the Model I, an AppleSoft or Integer BASIC
  file to a matching Apple II, a quick pick when it cannot tell.
- **A machine setup panel**: a webview form for the whole machine, sharing the catalog and the start flow
  ([startFlow.ts](../../extension/src/startFlow.ts)).
- **Named machine profiles**, chosen from the dropdown or a status bar item. Agreed below, as favorites.
- **Configuring from the Retro Devices view** before a session starts. Agreed below, as the powered-off machine.

## Agreed: the powered-off machine and favorites

Status: **agreed, not started.** The Retrocore activity bar's Machine and Drives views
([devices.ts](../../extension/src/devices.ts), described in [Devices.md](../Devices.md)) show only a running
session's machine. Changing hardware means starting a machine first, and a setup worth keeping lives only in the
workspace's saved machine for one launch configuration's name. This round lets a machine be set up while it is
off, and keeps setups as favorites.

### The powered-off machine

With no Retrocore session running, the Machine and Drives views show a machine marked as off: the last one
started (the setup **Start Last Machine** boots, `retrocore.lastSetup`), or the favorite last loaded. Its header
says `off` where a running one says `running` or `paused`, and its screen icon is dark. **Switch Machine…** in
the Machine view's title bar picks another: a launch configuration, a catalog machine or a favorite. With no
machine ever started, the views keep their welcome text, with **Switch Machine…** beside **Start Machine**.

While it is off:

- **Cards and media** change as they do while running: Add Card and Remove Card on the slots, insert, record,
  eject and write protection on the drives. A disk inserted while off is in its drive at power-on.
- **Settings** are rows of the machine: model, memory, the II's Monitor, the Model I's Expansion Interface and
  the rest of the machine's choices. They come from the same catalog as **Start Machine → Options…**
  ([machines.ts](../../extension/src/machines.ts)), so the two never disagree, and each opens a quick pick of its
  values. They change only while off; while running they show their values and say a change waits for the next
  start. A setting change keeps the cards and media that still fit, rather than discarding the saved machine as
  a changed launch option does today; what no longer fits is listed once, as the host's restore already does.
- **▶** on the header boots it, with what was changed.

When a session starts, the views show the live machine, as now. When it ends, they show it powered off with what
changed while it ran, instead of going empty.

**How the views get an off machine's hardware.** The language server, which is the same `Retrocore.Debug.dll` as
the debug host and runs whenever the extension is active, answers two new requests:

- `retrocore/machine/describe`: a launch configuration and its saved machine (the `machineState` the debug host
  restores) in; the hardware rows and devices out, in `retro/devices`'s shape. It builds the machine as a launch
  does, restores the saved machine and does not run it, so the rows are exactly a running session's. No ROM
  dumps are needed: without them every machine's ROMs are assembled from the SDK's sources. If building the
  machine for each change proves slow, the fallback is a description of the hardware that does not build it.
- `retrocore/machine/change`: the same in, plus a `retro/hardware` or `retro/device` action; the new saved
  machine and rows out.

The extension keeps the off machine's saved machine where it keeps a launch configuration's today
([savedMachine.ts](../../extension/src/savedMachine.ts)), so the next launch restores it the same way.

### Favorites

A favorite is a whole machine kept under a name, with a description: the catalog machine and its settings, what
it runs (a source, a program, a disk, a tape or nothing), and its cards and media (the saved machine).

- **Where.** In the `retrocore.favorites` setting, an array of `{ name, description, machine, options, run?,
  machineState }`. In user settings a favorite is there in every workspace (and on other computers through
  Settings Sync); in the workspace's `.vscode/settings.json` it is shared with the project through git. Paths
  inside the workspace are written as `${workspaceFolder}/…`, so a shared favorite works on another computer.
  Names are unique within each scope.
- **The Favorites view**, a third view in the Retrocore container: each favorite with its description beside its
  name and in full on hover, grouped under **User** and **Workspace** when both have some. Clicking a favorite
  loads it into the Machine and Drives views, powered off, to inspect or adjust; its inline **▶** boots it.
  Its menu has **Edit Description…**, **Rename…**, **Update from Machine** (overwrite it with what the Machine
  view shows), **Share with Workspace** or **Move to User**, and **Remove**.
- **Adding.** **Add to Favorites…** on the Machine view's header, running or off, asks for a name and a
  description and saves what the view shows. **Retrocore: Add Machine to Favorites…** does the same from the
  Command Palette.
- **Starting.** **Start Machine…** lists the favorites first, and a favorite boots like any setup, so
  **Start Last Machine** repeats it.

### Order

Each step is usable on its own:

1. **Done.** The language server's `describe` and `change` requests ([OffMachine.cs](../../src/Retrocore.Debug/OffMachine.cs),
   described in [Devices.md](../Devices.md#a-machine-that-is-off)), tested against the debug host's own rows by
   `tools/Test-OffMachine.mjs`. Building the machine for each request takes about 40 to 200 ms (the first, cold,
   about 500), so the fallback is not needed.
2. The powered-off views and **Switch Machine…**: cards and media while off, and what a session changed kept
   when it ends.
3. Settings as rows of the off machine, from the catalog, keeping the cards and media that still fit.
4. The `retrocore.favorites` setting and the Favorites view.
