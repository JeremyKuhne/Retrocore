# The games

- **`test.dat`** is a small adventure of our own, written for the engine's tests: a beach, a lighthouse's two rooms
  and a sea cave, two treasures, a lamp that runs out, a tide that rises, and a chest. It exercises the conditions,
  the actions, the light, the inventory and the score. It is part of Retrocore, under the repository's
  [MIT license](../../../LICENSE).
- **`test-win.in`**, **`test-fall.in`** and **`test-drown.in`** are its transcripts' commands: one that wins, one
  that tries what doesn't work and ends in a fall in the dark, and one that waits in the cave for the tide. Each
  `.out` is what the screen shows, from the reference engine, with each command after its prompt.

The commands and the `.out` files change together: after changing the game or the engines' rules, write each `.out`
again with the packer's `play` and read the difference. Windows PowerShell 5 redirects in UTF-16, so use PowerShell 7,
which writes UTF-8.

```powershell
dotnet run ../tools/packer.cs -- play ../obj/test.bin test-win.in --echo > test-win.out
```

## Where each game comes from

| File | Game | Authors | Source | Terms |
| --- | --- | --- | --- | --- |
| `test.dat` | the sample's own test adventure | Retrocore | this repository | [MIT](../../../LICENSE) |
| `pirate.dat` | Pirate Adventure (Adventure number 2) | Scott and Alexis Adams | `adv02.dat` in [AdamsGames.zip](https://ifarchive.org/if-archive/scott-adams/games/scottfree/AdamsGames.zip), in the [IF Archive's Scott Adams collection](https://ifarchive.org/indexes/if-archive/scott-adams/games/scottfree); the ScottFree conversion is by Paul David Doherty | Copyright Scott Adams, not public domain; shareware |

`pirate.dat` is the file from the archive, unchanged (16,325 bytes, SHA-256
`e8f5099105147503be7d2dd663f3782573957eb5c8fee390722e17ca634728ce`). The archive's
[copyright notice](https://ifarchive.org/if-archive/scott-adams/SA-Copyright.txt) (24 November 1997) says: "These Scott
Adams original text Adventure games are still copyrighted by Scott Adams and are not Public Domain. They may be freely
downloaded and enjoyed though. They are shareware but the contribution is strictly voluntary and the amount left to
your own discretion." The repository's MIT license does **not** cover this file. If you enjoy the game, the notice
asks for a voluntary contribution to Scott Adams.

The `pirate-*.in` and `pirate-*.out` files are transcripts of the reference engine playing it, made the same way as
the test game's.
