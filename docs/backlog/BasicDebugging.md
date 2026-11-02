# Backlog: debugging BASIC programs

Status: **two steps left: Level I and disk images.** AppleSoft, Integer BASIC and Level II are done: the library
([`Retrocore.Basic`](../../src/Retrocore.Basic)), the command line, the machine-program editor with import and
export, the language support, the BASIC thread, BASIC variables, and workspace files with labels and the `basic`
launch. The [extension README](../../extension/README.md) describes them. Each dialect is a class behind one
interface (`BasicDialect`), so the steps below add a dialect and a file source without changing the debugger or
the editor.

## Level I

Level I BASIC is the Model I's first ROM, Palo Alto Tiny BASIC, with an SDK source
([`Level1.asm`](../../src/Retrocore.Machines.Trs80/Roms/Level1.asm)). It keeps a program differently from the
Microsoft BASICs: lines are stored as text, with the abbreviations as typed (`P.` for `PRINT`), and the variables
are fixed (`A` to `Z`, `A$`, `B$` and one array). Today the `retrocore-level1` language id and the `.level1.bas`
extension exist, but a Level I document only says it is not supported yet.

What it takes:

- **The dialect:** reading and writing the program image (a line number and the line's text), the keywords and
  their abbreviations for highlighting and help, and the hooks (statement start, current line, GOSUB and FOR
  stacks, errors) named from `Level1.asm`.
- **The editor and files:** the machine-program editor, text import and export, and Level I's `CSAVE` tapes.
- **The BASIC thread and variables:** stops, steps and GOSUB frames as the other dialects have them; its scopes
  are the fixed variables, `A$`, `B$` and the array.
- **Language support:** a grammar, diagnostics, navigation, hover, completion and renumber, as Level II has.

## Disk images

Import and export of programs as files on disk images, once the media library has filesystems and writes
([Media.md](Media.md), steps 3 to 5):

| Machine | Files |
| --- | --- |
| Apple II family | AppleSoft and Integer BASIC files on DOS 3.3 and ProDOS disks |
| Model I | Disk BASIC files on TRSDOS and NEWDOS/80 disks |

The **Import** and **Export** commands gain a disk image as a source and a destination, beside text listings,
tokenized files and tapes.

## Later

Color BASIC, with the CoCo ([M6809-CoCo.md](M6809-CoCo.md)).
