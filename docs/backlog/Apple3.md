# Backlog: the Apple III

The Apple III is built and reviewed: the machine, video, disks and SOS, the debugger and extension, the boot ROM's
source and Apple II emulation. [Apple3.md](../Apple3.md) describes them and how they were checked against MAME and
the Service Reference Manual. What is left:

## Not checked or not done

- SOS and mode-test frames, and frames in Apple II mode, compared with MAME pixel by pixel.
- The Emulation disk's configuration menu (its slot 5 and 7 serial cards), and the paddles in emulation.
- Host game controllers wired to the joysticks.
- SOS's documented entry points in `Apple3Equates.asm`, which names only the hardware.
- Breakpoints and disassembly qualified by bank (`bank2:$2000`), and the call stack across a bank switch: built, but
  no test covers them.
- The extension's editor test (`npm run test:editor`) past the machine menu, which needs the IIe ROM dumps.
- Beam breakpoints, which need the Apple III's debug target to report `HasBeam`.

## Later

- The Apple III Plus (interlaced video, its keyboard, 256K standard), once the III is solid.
- Business BASIC: 1.1 and 1.3 builds, invokable modules and DEF FN in the debugger ([BusinessBasic.md](BusinessBasic.md)).
- SOS volumes in the media library, through CiderPress2's ProDOS support ([media](Media.md)).
