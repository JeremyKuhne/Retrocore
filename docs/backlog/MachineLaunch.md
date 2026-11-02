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
- **Named machine profiles**, chosen from the dropdown or a status bar item.
- **Configuring from the Retro Devices view** before a session starts.
