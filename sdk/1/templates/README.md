# Project templates

`retrocore new` and `retrocore init` start a project from one of these folders, which ship with the tool, beside the
host in `Sdk/1/templates/`. The extension's *Retrocore: New Project* is meant to run `retrocore new`, so that both
make the same files.

```text
dotnet retrocore new 6502 adventure --machines apple1,apple2,apple3,pet,bbc
dotnet retrocore init 6502 --machines apple2,bbc          # in a folder of a repository that is already there
dotnet retrocore new --list                               # the templates and their machines (--json for tools)
```

## A template

A folder named for the CPU family it is for, such as `6502/`, holding a `template.json` and the files the project
starts with:

```jsonc
{
  "description": "6502 assembly: a hello world for ...",
  "cpu": "6502",                          // the project's cpu
  "sources": ["src/*.s"],                 // the project's sources
  "entry": "Main",                        // the project's entry, if it gives one
  "defines": { "LOWERCASE": 0 },          // the project's defines: build switches every target gets
  "families": {                           // the machine families it builds for, in order
    "apple2": { "machine": "apple2-iiplus", "environment": "dos33", "suffix": "dos" }
  },
  "machineDefines": {                     // what a machine's targets add, by catalog id
    "apple2-iie": { "LOWERCASE": 1 }
  }
}
```

- Each machine asked for (`--machines`, a family's name or a catalog id of one of its machines; every family when it
  is left out) becomes a target with its family's environment. The target is named `<family>-<suffix>` for the
  family's own machine (`apple2-dos`), and `<catalog id>-<suffix>` for another (`apple2-iie-dos`).
- Every file but `template.json` is copied, except that of `src/platform/`'s folders only those the targets use go:
  each target's family's, its model's (its catalog id) and its environment's, and always `bare/`, so a bare target can
  be added by hand for a family with a console of its own (not the Apple III, whose console is SOS's). This is the
  build's own [platform folder](../README.md) order: family, model, environment.
- The 6502 template's convention, which a new template follows: a family's folder holds the machine's console
  (`Console::Start`, `Console::Write`, `Console::NewLine`), and an environment's folder holds how a program ends
  there (`Exit`): back to the Woz Monitor, to BASIC through DOS's warm start, to `SYS`'s or `*RUN`'s caller, or a wait
  under SOS and on a bare machine. Where the environment owns the screen, as SOS does, the console is the
  environment's, and the family has no folder. `LOWERCASE` is a build switch in the style of the adventure's
  `GAME_LINKED`: the project gives it 0, a target whose machine shows lowercase sets it to 1, and `main.s` asserts it is
  one or the other.
- A template's sources pass the editor's lint (`SdkDocumentationTests`), and every machine of every family builds
  (`ProjectScaffoldTests`). Under the debugger, `tools/Test-NewProjectDap.mjs` runs one machine of each family, and
  the enhanced IIe and the business PET for the `LOWERCASE` switch, to its greeting and back to its environment (under
  SOS, where the program waits, to its greeting).

## The repository's files

`common/` holds the files every project gets. A leading `_` in a name stands for a `.` (`_gitignore` is
`.gitignore`), so that no file in the tool's package has a name that starts with a dot, which packing can leave out.
These placeholders in the text files are filled in: `{{name}}`, `{{cpu}}`, `{{version}}` (the tool's), `{{targets}}`
(the README's rows), `{{firstTarget}}`, `{{workflow}}` (the workflow's path in the repository), `{{projectOption}}`
(` --project <folder>` when the project is below the repository's root) and `{{projectFolder}}` (that folder and a
`/`).

| File | `retrocore new` | `retrocore init` |
| --- | --- | --- |
| `retrocore.json`, `src/...` | written | written in the folder; an error if any is there |
| `README.md` | written | written beside the project unless one is there |
| `.gitignore` | written | written beside the project, or given the lines it lacks |
| `.config/dotnet-tools.json` | written, pinning the tool's own version | at the repository's root: written, or given `retrocore` unless it has an entry for it already, which is kept as it is |
| `.vscode/extensions.json` | written, recommending `retrocore.retrocore` | at the root: written, or given the recommendation |
| `.github/workflows/build.yml` | written | at the root: `build.yml` for a project at the root when the repository has none, otherwise `retrocore-<name>.yml` at the root and `retrocore-<folder>.yml` below it (the project's folder, `/` as `-`); never replaced |
| the root's `retrocore.json` | | a root file that lists `projects` is given the new folder |

For `init`, the repository's root is the nearest folder with a `.git` at or above the project's, or the project's
folder when there is none; `retrocore new` makes a repository of its own, so its root is the project's folder. A JSON
file with comments is never rewritten, as that would lose them: the command says what to add.

The workflow restores the pinned tool and runs `dotnet retrocore build --all`, then keeps `artifacts/`. Until the tool
is published to a feed, `dotnet tool restore` needs `--add-source` with a folder holding its package.
