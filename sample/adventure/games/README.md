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

Pirate Adventure is to be added here as `pirate.dat`, with where it is hosted and the terms given there.
