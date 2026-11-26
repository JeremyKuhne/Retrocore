# The adventure sample

An interpreter for Scott Adams adventures, in native 6502 assembly, the first sample of the
[Retrocore SDK plan](../../docs/backlog/Sdk.md#the-first-sample-a-scott-adams-interpreter). It plays games in the
ScottFree `.dat` text format, once [`tools/packer.cs`](tools/packer.cs) has packed them into the engine's own
[format](PackedFormat.md). The interpreter is our own code, written from the format's documented behavior.

It runs on five machines as `bare` targets of its project file, [`retrocore.json`](retrocore.json): the Apple-1 with
32K, the Apple II Plus, the Apple III, the PET 4032 and the BBC Micro model B. Every target assembles the same core,
unchanged, with its machine's platform folder before it, and links Pirate Adventure in, packed by the project's
step. A sixth target, `apple2-test`, links the test game instead (`TEST_GAME`, in `src/linked-game.s`). The disk and
tape targets follow as the SDK's environments arrive.

```text
sample/adventure/
  retrocore.json              the project: the core's sources, the steps that pack the games, and the targets
  src/core/                   the engine, which uses no machine's addresses
  src/linked-game.s           the packed game, linked in as Game: Pirate Adventure, or the test game
  src/platform/<family>/      console.s, the machine's screen and keyboard, and bare.cfg, its linker configuration
  tools/packer.cs             .dat to the packed format, and the C# reference engine
  games/test.dat              a small test adventure of our own, MIT
  games/test-*.in, *.out      its transcripts: the commands, and what the screen shows
  games/pirate.dat            Pirate Adventure, by Scott and Alexis Adams (not ours: see games/README.md)
  games/pirate-*.in, *.out    its transcripts: one that wins, one that dies
  PackedFormat.md             the packed format, and the rules the engines play by
```

| Target | Machine | Console | Loads at |
| --- | --- | --- | --- |
| `apple1` | Apple-1, 32K | the Woz Monitor's ECHO, and the PIA's keyboard | `$0300` |
| `apple2` | Apple II Plus | the Monitor's COUT and GETLN1 | `$0800` |
| `apple2-test` | Apple II Plus, the test game | the Monitor's COUT and GETLN1 | `$0800` |
| `apple3` | Apple III | its own text page 1 and keyboard routines | `$2000` |
| `pet` | PET 4032 | the kernal's jump table | `$0400` |
| `bbc` | BBC Micro model B | the MOS's OSWRCH and OSWORD 0 | `$2000` |

Each console includes the SDK's `<machine.inc>` for its machine's names, and takes the screen's width from the
SDK's `RC_SCREEN_COLUMNS`. The Apple III's console is built but not yet played under the debugger: a bare program
there shows text once a character set is loaded, which SOS does as it boots.

## Building and running

From this folder, build every target:

```powershell
dotnet ../../artifacts/AnyCPU/Release/Retrocore.Debug/net11.0/Retrocore.Debug.dll build --all
```

The project's `steps` pack each game with the packer into `obj/` first, printing each part's size, and are skipped
while the packer and the games are unchanged. The build writes each target's binary, debug information and map to
`artifacts/<target>/`. To debug a target, launch it as a `project`:

```jsonc
{
    "type": "retrocore", "request": "launch", "name": "Adventure",
    "project": "${workspaceFolder}/sample/adventure",
    "target": "pet"
}
```

The editor analyzes each source through the target that assembles it, the active one when it does, so the core's
files open with their symbols and with the platform's names that target gives them.

## Testing

Once a build has packed the games, the reference engine plays a transcript and checks it against what the screen
should show:

```powershell
dotnet run tools/packer.cs -- play obj/test.bin games/test-win.in --echo --expect games/test-win.out
```

`play` without `--expect` writes the transcript instead, and without `--echo` leaves the commands out, as the
engine itself writes it. `--columns` sets the screen's width, 40 by default.

[`tools/Test-AdventureDap.mjs`](../../tools/Test-AdventureDap.mjs) plays both of Pirate Adventure's transcripts, the
win from start to finish and the death, on the Apple-1 with 32K, the PET 4032, the Apple II and the BBC Micro, and the
test game's three on `apple2-test` alone, under the debug adapter, through project launches, and checks that what the
6502 engine writes matches the transcript's `.out`, character for character. Give target names to play only those,
such as `node tools/Test-AdventureDap.mjs apple1 pet`.

## The platform layer

Everything machine-specific is in a platform folder's `console.s`, which the build assembles before the core, so its
constants are known where the core sizes its buffers. Each provides:

| Name | What it is |
| --- | --- |
| `SCREEN_COLUMNS` | The screen's width; the engine wraps its text a column short of it |
| `TextPointer`, `TablePointer`, `ActionPointer`, `WordPointer` | Four two-byte pointers in zero page |
| `Console::Start` | Sets up the screen and keyboard |
| `Console::Write` | Writes the character in A, `$0A` for a new line; keeps A, X and Y |
| `Console::ReadLine` | Reads a line into `InputLine`, in capitals, ending in 0, at most `INPUT_SIZE - 1` characters; the line typed is shown, and the screen's line ends after it |
| `Console::Clear` | Clears the screen |
| `Console::Pause` | Waits about two seconds |
| `Console::Finish` | Stops at the game's end; it need not return |

`src/linked-game.s` puts the packed game at `Game`, and the project's `entry` is `Engine::Start`. The engine's state
is in the `BSS` section, which it clears itself, so each target's linker configuration defines `__BSS_RUN__` and
`__BSS_SIZE__`. It clears the console's `BSS` too, just after `Console::Start` returns, so anything `Console::Start`
sets in `BSS` is cleared.

## Pirate Adventure

Pirate Adventure is Scott and Alexis Adams' game. Its file, `games/pirate.dat`, is in this repository, with
[games/README.md](games/README.md) recording where it is hosted and on what terms, and the reference engine plays it
(`games/pirate-win.in` wins). It is not built into any target yet: the targets that link or load it are to come.
