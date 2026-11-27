# {{name}}

A {{cpu}} program built with [Retrocore](https://github.com/JeremyKuhne/Retrocore) for these targets:

| Target | Machine | Environment | What it builds |
| --- | --- | --- | --- |
{{targets}}

## Building

The `retrocore` tool is pinned in `.config/dotnet-tools.json`, so everyone, CI included, builds with the same tool
and the same SDK headers. It needs the .NET 11 SDK.

```text
dotnet tool restore
dotnet retrocore build --all{{projectOption}}
```

These run at the repository's root. Each target's program, debug information and disk or tape image go in
`artifacts/<target>/` beside `retrocore.json`, and intermediate files in `obj/`.
`dotnet retrocore build --target {{firstTarget}}{{projectOption}}` builds one target.

`retrocore` is not published yet. Until it is, restore it from a folder that holds its package, made by
`dotnet pack src/Retrocore.Debug -c Release -o <folder>` in a clone of Retrocore; the workflow's restore fails until
then, or until it is given such a source:

```text
dotnet tool restore --add-source <folder>
```

## Debugging

Open the repository in VS Code with the Retrocore extension, which its `.vscode/extensions.json` recommends. Pick a
target in the status bar and press F5: it builds the target, starts its machine and stops at the program's entry. No
launch.json is needed.

## How it is laid out

- `retrocore.json` is the project: its sources, its defines and its targets.
- `src/main.s` is the program, the same for every target.
- `src/platform/<family>/` is each machine family's console, which `main.s` writes with, and
  `src/platform/<environment>/` is how a program ends in each environment, and the console too where the
  environment owns the screen, as `sos` does. A target assembles its family's folder,
  then its model's (`src/platform/apple2-iie/`, say), then its environment's, before `src/`'s own files; a later
  folder's file replaces an earlier one's of the same name.
- `LOWERCASE` is a build switch: the project gives every target 0, and a target whose machine shows lowercase sets it
  to 1 in its `defines`.
- `{{workflow}}`, at the repository's root, builds every target on each push to main, each pull request and by
  hand, and keeps what they built, once `dotnet tool restore` can find the tool (see [Building](#building)).

## Adding a target

Add an entry to `targets` in `retrocore.json`, naming a machine as the extension's Start Machine lists it and an
environment:

```jsonc
"apple2-bare": { "machine": "apple2-iie-enhanced", "environment": "bare", "defines": { "LOWERCASE": 1 } }
```

A machine family or environment with no platform folder yet needs one, with the same routines as the others.
