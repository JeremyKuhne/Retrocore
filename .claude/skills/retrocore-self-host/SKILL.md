---
name: retrocore-self-host
description: Self-host Retrocore's VS Code extension, opening the repository in a separate VS Code window that runs the in-repo extension, so its syntax highlighting, IntelliSense (completions, hovers, go to definition, symbols) and debugging can be seen and tried. Use when asked to self host, run or try the extension, see highlighting or IntelliSense, check a change to the grammar, the language server or the extension in a real editor, or install or update the extension in the user's VS Code.
license: MIT
compatibility: Windows with PowerShell, the .NET SDK, Node.js and VS Code's code command on PATH. IIe debugging also needs the IIe ROMs, which are never bundled.
metadata:
   portability: repository
   applicability: retrocore
   risk: local-write
   maturity: canary
   requires: none
---

# Self-host the Retrocore extension

Self-hosting opens a second VS Code window, an Extension Development Host, that runs the extension from
`extension/` in this repository rather than any installed copy. It has its own profile and extensions under
`artifacts/self-host`, so the user's VS Code settings, extensions and windows are left alone. One script does
everything; do not assemble the `code` command line yourself.

## Run it

From the repository root, in PowerShell:

```powershell
.\tools\Start-SelfHost.ps1
```

It compiles the extension (installing its npm packages the first time), builds the Release debug host, which
also runs the language server, and opens the repository with `sample\trs80\hello.asm`. It takes a minute or two
the first time and prints one line when the window opens.

| To | Add |
| --- | --- |
| Open other files, such as what the user is working on | `-File sample\iie\main.s, src\Retrocore.Machines.Trs80\Roms\Level2.asm` |
| Relaunch quickly when nothing needs building | `-SkipBuild` |
| Let the IIe launch configurations find the ROMs | `-RomDirectory <dir>`, or set `RETROCORE_IIE_ROMS` first |

Highlighting and IntelliSense need no ROMs. Only debugging the IIe needs them; the Model I's ROMs are assembled
from the SDK's sources, so its launch configurations work without any.

Running from inside VS Code, as Copilot does, is fine: the script makes `code` start the separate instance rather
than hand the request to the current window.

## After it opens

Tell the user the window is open and what to look at. In the new window:

- **Highlighting.** Assembly files open as `retrocore-asm`; the language mode in the status bar shows it.
- **IntelliSense.** Hover an instruction or label, press Ctrl+Space for completions, F12 to go to a definition,
  Ctrl+Shift+O for the file's symbols and Ctrl+T for the workspace's. These come from the language server, which
  starts a few seconds after the file opens. If they never appear, a "Retrocore: language features need
  Retrocore.Debug.dll" warning or the Output panel's **Retrocore Assembly** channel says why.
- **Debugging.** Run and Debug lists the workspace's launch configurations, such as "Model I: Z80 sample".

## After changing the extension

The development window runs the code it started with:

- **Grammar or extension TypeScript.** Run `npm --prefix .\extension run compile` (or the script without
  `-SkipBuild`), then run **Developer: Reload Window** in the development window.
- **Language server or debugger (C#).** Rebuild with `dotnet build .\src\Retrocore.Debug -c Release`, then reload
  the development window. The extension runs a shadow copy of the host, so building while the window is open
  works.

If a build says a project file it needs could not be loaded although the file exists, a stale MSBuild server is
the cause; the script shuts it down and retries once, and `dotnet build-server shutdown` fixes it by hand.

## Installing the extension instead

Self-hosting is for working on the extension. To update the copy installed in the user's everyday VS Code, for
example after a fix they want to keep, run `.\tools\Install-Extension.ps1`: it packages the extension with its
debug host as a VSIX and installs it; then tell the user to reload VS Code's windows. The installed copy runs its
packaged host in any folder; the self-hosted one runs the repository's build.

## Without an agent

The user can also press F5 on **Run Extension** in this repository's Run and Debug view. It builds the same
things and opens a development window on the same sample, with the debugger attached to the extension's
TypeScript; that window uses the user's own profile, settings and extensions rather than a separate one.
