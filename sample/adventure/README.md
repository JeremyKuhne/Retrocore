# The adventure sample

An interpreter for Scott Adams adventures, in native 6502 assembly, the first sample of the
[Retrocore SDK plan](../../docs/backlog/Sdk.md#the-first-sample-a-scott-adams-interpreter). It plays games in the
ScottFree `.dat` text format, once [`tools/packer.cs`](tools/packer.cs) has packed them into the engine's own
[format](PackedFormat.md). The interpreter is our own code, written from the format's documented behavior.

This first part is the packer and the C# reference engine, which the 6502 engine's tests compare against, with a
small test game.

```text
sample/adventure/
  tools/packer.cs          .dat to the packed format, and the C# reference engine
  games/test.dat           a small test adventure of our own, MIT
  games/test-*.in, *.out   its transcripts: the commands, and what the screen shows
  PackedFormat.md          the packed format, and the rules the engines play by
```

## The packer and the reference engine

From this folder, pack the test game:

```powershell
dotnet run tools/packer.cs -- pack games/test.dat obj/test.bin
```

It prints each part's size. Then the reference engine plays a transcript, and checks it against what the screen
should show:

```powershell
dotnet run tools/packer.cs -- play obj/test.bin games/test-win.in --echo --expect games/test-win.out
```

`play` without `--expect` writes the transcript instead, and without `--echo` leaves the commands out, as the
engine itself writes it. `--columns` sets the screen's width, 40 by default.

## Pirate Adventure

Pirate Adventure is Scott and Alexis Adams' game, and is not in this repository yet: it comes with the targets that
load it from disk, with [games/README.md](games/README.md) recording where it is hosted and on what terms.
