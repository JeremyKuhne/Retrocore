# SOS sources

SOS is the Apple III's operating system. The SDK has its sources: the SOS 1.3 kernel, the bootstrap loader that
starts it, and Apple's drivers. Each assembles byte-identically to the files on Apple's disks, so the debugger
shows SOS's source wherever SOS runs. They are in the Apple III's ROM sources, under `Sos`:

| Path | What it builds |
| --- | --- |
| `Sos/SosKernel.asm` | SOS 1.3's `SOS.KERNEL`, 22,016 bytes. |
| `Sos/SosBoot.asm` | Block 0 of a SOS disk: Apple's bootstrap loader 1.1, which the boot ROM reads to `$A000`. `SYSTEM_DEMO = 1` builds the System Demo disk's copy, and `ON_THREE = 1` On Three's revision. |
| `Sos/Drivers/<Name>/<Name>.asm` | One driver, as `SOS.DRIVER` holds it. |

[`Apple3.md`](Apple3.md) covers the machine.

## The kernel

`SOS.KERNEL` is a series of modules. Each is assembled for the address it runs from and placed in the file at
the address it loads to. `SosOrg.asm` lists both for every module, and `SosKernel.asm` lays the file out. The
loader, the first module, moves the rest into place when SOS boots:

| Module | Runs at | What it does |
| --- | --- | --- |
| SOSLDR (`SosLdr*.asm`) | `$1E00` | The loader: moves the kernel, reads `SOS.INTERP` and `SOS.DRIVER`, relocates and starts the drivers, shows the welcome screen and starts the interpreter. |
| INIT (`Init.asm`) | `$28F8` | Initializes the managers, from space the loader keeps for it. |
| SYSGLOB (`SysGlob.asm`) | `$18FC` | Global data, and the jump table drivers call SOS through. |
| BFM.INIT2 (`BfmInit2.asm`) | `$B800` | The file manager's second initialization; the space then holds the volume bitmaps. |
| BFM (`Bfm.asm` and its includes) | `$BC00` | The block file manager: SOS's file system. |
| OPRMSG (`OprMsg.asm`) | `$DE66` | Asks for a volume to be put in a drive. |
| IPL (`Ipl.asm`, `Ipl2.asm`) | `$DFC0` | Interrupts, events, NMI, and the entry from `BRK` that every SOS call takes. |
| UMGR (`UMgr.asm`) | `$E48B` | The fence, the clock and the joystick calls. |
| DISK3 (`Disk3*.asm`) | `$E899` | The Disk III driver for `.D1`-`.D4`. |
| SYSERR (`SysErr.asm`) | `$EE04` | Error returns, and the message for a fatal error. |
| DEVMGR (`DevMgr.asm`) | `$EED9` | The device manager and its system device table. |
| SCMGR (`ScMgr.asm`) | `$F05E` | Checks each SOS call and passes it on. |
| FMGR, CFMGR (`FMgr.asm`, `CfMgr.asm`) | `$F2F4` | Route file calls; files on character devices. |
| BUFMGR (`BufMgr.asm`) | `$F552` | The kernel's buffers in banked memory. |
| MEMMGR (`MemMgr*.asm`) | `$F86E` | Segments and the memory calls. |

Each module is a scope of its own, as Apple assembled each on its own; the names other modules use are defined at
the end of `SosKernel.asm`. Labels follow Apple's SOS 1.3 listing, and the comments are our own. Some reserved
storage in the file holds whatever was in memory when Apple built it; the sources spell those bytes out.

## Drivers

A driver's source builds its code for address 0, as `SOS.DRIVER` stores it; SOS relocates it when it loads it. The
drivers on Apple's disks, by version:

| Driver | Folder | Builds |
| --- | --- | --- |
| `.CONSOLE` | `Console` | 1.31 (System Utilities), and 1.30 (Business BASIC 1.23) with `RELEASE_130 = 1` |
| `.RS232` | `Rs232` | 1.30 |
| `.PRINTER` | `Printer` | The serial printer driver, 1.10 |
| `.PROFILE` | `Profile` | 1.30 |
| `.FMTD1` | `Fmtd1` | The Disk III formatter, 1.30 |
| `.GRAFIX` | `Grafix` | 1.30 |
| `.AUDIO` | `Audio` | Release $1000 |
| `.SILENTYPE` | `Silentype` | Release $1040 |
| `.RAM` | `Ram` | D A DataSystems' RAM disk for Titan's III+IIe card (System Utilities) |
| `.RAM` | `TitanRam` | Harmony Systems' 280-block RAM disk for Titan's III+IIe card, 1.00 (Titan's startup disk) |

Labels follow Apple's driver listings where there are listings (the console, RS-232, serial printer, ProFile and
formatter drivers); for `.GRAFIX`, `.AUDIO`, `.SILENTYPE` and the two `.RAM` drivers the names are ours.

The `.RAM` drivers are not Apple's; both keep a RAM disk in the memory of Titan's III+IIe card. Titan's own, by
Harmony Systems, is a whole 280-block disk: 24 blocks inside the driver, which hold a formatted volume each time
SOS loads it, and the rest in the card's 128K. Titan's startup disk carries it in `RAMDISK.DRIVER`, a driver file
for the System Configuration Program. The System Utilities disk's, by D A DataSystems, is built from it with all
its blocks on the card. The debugger tells the two apart by their bytes. The printer driver on the disks is
the 1.10 that Apple's 1.30 listing revised; its source explains each difference where it is.

A driver with a comment, as SCP shows it, starts with its comment record: `$FFFF`, the comment's length and its
text. `SOS.DRIVER` keeps the comment apart from the code, so the code's addresses count from the driver's first DIB.

## The bootstrap loader

The boot ROM reads a SOS disk's block 0 to `$A000` and runs it. The loader finds `SOS.KERNEL` in the volume
directory, reads it to `$1E00` in the highest bank, checks for `SOS KRNL` and jumps to the kernel's loader.
`SosBoot.asm` builds Apple's 1.1 by default, the System Demo's copy with `SYSTEM_DEMO = 1`, and with
`ON_THREE = 1` On Three's 1985 revision, 2.2, which the SOS 1.3 System Utilities disk carries and which looks for
more than 256K.

## Debugging

- **The kernel** maps wherever memory holds its bytes: the loader and INIT while they run, and the rest in the
  system bank once the loader has moved it. A breakpoint in `ScMgr.asm` stops at every SOS call.
- **The bootstrap loader** maps at `$A000` while it runs.
- **Drivers** map as SOS loads them. The debugger reads the device manager's table, assembles each driver's source
  for the address and bank SOS put it in, and maps it there. A breakpoint set in a driver's source before SOS boots
  binds once the driver is loaded.
- `sos` function breakpoints and log messages trace SOS calls ([Breakpoints.md](Breakpoints.md#sos-call-breakpoints)).

## Testing

- `SosSourceTests` pins the kernel and the bootstrap loader by digest, and with Apple's disks
  (`RETROCORE_APPLE3_DISKS`) compares them with `SOS.KERNEL` and block 0.
- `SosDriverSourceTests` pins each driver build's code, and with the disks compares its code, relocation table and
  comment with the driver in that disk's `SOS.DRIVER`.
- `SosVolumeTests` reads SOS volumes and driver files.
- `node tools/Test-Apple3Dap.mjs` stops at a breakpoint in the kernel's source while the System Utilities boot,
  and binds one in the formatter driver's source once SOS has loaded it.
