# The adventure sample

An interpreter for Scott Adams adventures, in native 6502 assembly, the first sample of the
[Retrocore SDK plan](../../docs/backlog/Sdk.md#the-first-sample-a-scott-adams-interpreter). It plays games in the
ScottFree `.dat` text format, once [`tools/packer.cs`](tools/packer.cs) has packed them into the engine's own
[format](PackedFormat.md). The interpreter is our own code, written from the format's documented behavior.

It runs on a bare Apple II today. The plan's other targets (the Apple-1, the Apple III, the PET and the BBC Micro)
each add a platform folder, as the project file, headers and media writers they need arrive.

```text
sample/adventure/
  src/core/                   the engine, which uses no machine's addresses
  src/platform/apple2/        console.s: the Monitor's COUT and GETLN
  src/platform/apple2-bare.s  the bare Apple II's program, with the test game linked in, and its .cfg
  tools/packer.cs             .dat to the packed format, and the C# reference engine
  games/test.dat              a small test adventure of our own, MIT
  games/test-*.in, *.out      its transcripts: the commands, and what the screen shows
  PackedFormat.md             the packed format, and the rules the engines play by
```

## Building and running

From this folder, pack the test game, then assemble the bare Apple II's program:

```powershell
dotnet run tools/packer.cs -- pack games/test.dat obj/test.bin
```

```powershell
dotnet ../../artifacts/AnyCPU/Release/Retrocore.Debug/net11.0/Retrocore.Debug.dll --assemble src/platform/apple2-bare.s obj/apple2-bare.bin --config src/platform/apple2-bare.cfg
```

`pack` prints each part's size. The program loads at `$0800` and starts there. To debug it, launch
`src/platform/apple2-bare.s` as a `source` on the Apple II with its `linkerConfiguration`:

```jsonc
{
    "type": "retrocore", "request": "launch", "name": "Adventure: bare Apple II",
    "machine": "apple2", "model": "iiplus",
    "source": "${workspaceFolder}/sample/adventure/src/platform/apple2-bare.s",
    "linkerConfiguration": "${workspaceFolder}/sample/adventure/src/platform/apple2-bare.cfg"
}
```

The bare program's root sits directly in `src/platform/`, where the editor finds it from the core's files and the
platform's alike, so each opens with its symbols. Once a project file lists a target's sources, it can go.

## Testing

The reference engine plays a transcript and checks it against what the screen should show:

```powershell
dotnet run tools/packer.cs -- play obj/test.bin games/test-win.in --echo --expect games/test-win.out
```

`play` without `--expect` writes the transcript instead, and without `--echo` leaves the commands out, as the
engine itself writes it. `--columns` sets the screen's width, 40 by default.

[`tools/Test-AdventureDap.mjs`](../../tools/Test-AdventureDap.mjs) plays each transcript on a bare Apple II Plus under
the debug adapter and checks that what the 6502 engine writes matches the transcript's `.out`, character for
character.

## The platform layer

Everything machine-specific is in a platform's `console.s`. Each provides:

| Name | What it is |
| --- | --- |
| `SCREEN_COLUMNS` | The screen's width, which the engine wraps its text to |
| `TextPointer`, `TablePointer`, `ActionPointer`, `WordPointer` | Four two-byte pointers in zero page |
| `Console::Start` | Sets up the screen and keyboard |
| `Console::Write` | Writes the character in A, `$0A` for a new line; keeps A, X and Y |
| `Console::ReadLine` | Reads a line into `InputLine`, in capitals, ending in 0, at most `INPUT_SIZE - 1` characters; the line typed is shown, and the screen's line ends after it |
| `Console::Clear` | Clears the screen |
| `Console::Pause` | Waits about two seconds |
| `Console::Finish` | Stops at the game's end; it need not return |

The program's root puts the packed game at `Game` and starts at `Engine::Start`. The engine's state is in the `BSS`
section, which it clears itself.

## Pirate Adventure

Pirate Adventure is Scott and Alexis Adams' game, and is not in this repository yet: it comes with the targets that
load it from disk, with [games/README.md](games/README.md) recording where it is hosted and on what terms.
