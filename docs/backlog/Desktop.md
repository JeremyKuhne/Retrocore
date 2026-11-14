# Backlog: Retrocore Desktop, the standalone emulator

A desktop app that runs Retrocore's machines outside VS Code, with the same machine pane, drives and display
options, so the shared model in [machine files](MachineFiles.md) and [saving media](MediaPersistence.md) is proven
by a second host before it is built into both.

**Status:** proposed 2026-11-14; the [spike](#phase-0-the-spike) is built and passes on Windows, with 60 Hz pacing
still to check on a local display. "Retrocore Desktop" is a working name. The [decisions](#decisions-agreed-2026-11-14) were agreed on 2026-11-14.

## Why

The plans for machine files and media assume two hosts, VS Code and a standalone emulator, sharing machines,
settings, the recovery journal and the history. Today the standalone emulator is AppleSharp: an SDL window for the
Apple II alone, with its own settings and its own way of writing disks back. A second host that runs every machine,
and looks and works like the extension's views, tests those plans where they are weakest: two processes on one
history, machines opened outside VS Code, settings kept in step, and the UI's prompts without VS Code's dialogs.

## What there is

| Piece | What the desktop app can use |
| --- | --- |
| `IDebugTarget` ([IDebugTarget.cs](../../src/Retrocore.Debug/IDebugTarget.cs)) | Every machine behind one interface: `StepCycle`, `ClockHertz`, `RenderVideo` (RGBA pixels), `TakeAudio` (16-bit PCM), `Key`, `Reset`, `Screens` and `Screen`, `Hardware`, `Devices` and `DeviceAction`, and each machine's own requests (such as `apple2/sound`) |
| `OffMachine.Build` | Builds any machine from a launch configuration, as a launch does |
| `MachineConfiguration` | Captures and restores cards and media |
| The display panel ([display.ts](../../extension/src/display.ts)) | What the panel offers: speed, sound and volume, fast disk, scale, screen (monitor), beam overlay, each machine's keys (Ctrl, Reset, Esc, Open Apple and so on), paste, the BASIC program, and the key map per machine |
| The Machine and Drives views ([devices.ts](../../extension/src/devices.ts)) | The machine's row, its settings, its hardware slot by slot, and its drives with their media, head and activity |
| AppleSharp ([src/AppleSharp](../../src/AppleSharp)) | SDL3 audio, game controllers, frame clock and Native AOT publishing, for the Apple II |

`Retrocore.Debug` is an executable whose types are internal. The spike references it and sees its internals; the
first phase after the spike moves what both hosts need into a library, `Retrocore.Hosting`, so neither depends on
the other's internals.

## The technology

- **Avalonia 12** for the window, the panes, the trees and the status bar, with compiled bindings only, no XAML
  loaded at run time, and only Avalonia's own controls, as its [Native AOT
  guidance](https://docs.avaloniaui.net/docs/deployment/native-aot) asks.
- **The screen** is a control that draws the machine's latest frame with Skia on the GPU: the frame's pixels are
  copied into a bitmap the control owns, and drawn scaled, sharp (whole pixels) or fitted. Shaders for CRT and NTSC
  effects can come later as Skia runtime effects. If pacing or latency falls short, the fallback is Avalonia's
  `OpenGlControlBase`, which uses ANGLE over Direct3D on Windows.
- **SDL3** for audio and game controllers, as AppleSharp and the debug host already use it; Avalonia owns the window.
- **Native AOT** on win-x64, linux-x64 and osx-arm64. Windows is built and tested first; the others follow once the
  spike passes there.
- **AppleSharp stays**, as the minimal SDL emulator for the Apple II.

## The window

Like VS Code: an activity bar on the left, a side pane that collapses, the machine's screen filling the rest, and a
status bar across the whole bottom.

```text
┌───┬───────────────────────────────┬───────────────────────────────────────────────────────┐
│ 🖥 │ MACHINE                     ⇄ │                                                       │
│   │ ▾ 🖥 Apple IIe   Enhanced · run│                                                       │
│ ⚙ │   ▸ Settings                  │                                                       │
│   │   ▸ Slot 6  Disk II · 2 drives│                    machine's screen                   │
│   │ DRIVES                        │                                                       │
│   │ ▾ Slot 6 · Disk II            │                                                       │
│   │     ▣🔒 Drive 1  dos33.dsk     │                                                       │
│   │     ▫  Drive 2  empty          │                                                       │
│   │ DISPLAY AND SOUND             │                                                       │
│   │   Speed        1×           ▾ │                                                       │
│   │   Sound        Speaker      ▾ │                                                       │
│   │   Volume       ───●──         │                                                       │
│   │   Scale        Sharp        ▾ │                                                       │
│   │   Screen       Color        ▾ │                                                       │
│   │   Fast disk    ☑              │                                                       │
├───┴───────────────────────────────┴───────────────────────────────────────────────────────┤
│ ● Apple IIe · running · 1.02 MHz · 60 fps   Drive 1: track 17 reading      [Ctrl] [Reset] │
└───────────────────────────────────────────────────────────────────────────────────────────┘
```

- **The activity bar** has the machine icon, the same small computer as the extension's, which opens and closes
  the side pane, as VS Code's activity bar does; clicking it while the pane is open collapses it. A gear at the
  bottom opens the settings.
- **The side pane** has sections that each collapse, as VS Code's views do:
  - **Machine**: the machine's row with its state, **Switch Machine...**, its settings, and its hardware slot by slot,
    with cards added and removed as in the extension's Machine view;
  - **Drives**: each card with drives, and its drives with their media, lock, head and activity, as the extension's
    Drives view shows them, with the same insert, eject, lock and save actions;
  - **Display and Sound**: what the display panel offers: speed, sound, volume, scale, screen, fast disk and the beam
    overlay.

  The pane's width is dragged, and it remembers it.
- **The status bar** runs the whole width: the machine and its state, its speed and frame rate, the busy drive, and
  on the right the machine's own keys from the panel (Ctrl, Ctrl-Reset, Esc, Open and Closed Apple, Break, Clear),
  which change with the machine.
- **The screen** takes the keyboard when clicked or when the pane is closed, and gives it back with Ctrl+Shift+E (to
  the pane, as in VS Code) or a click in the pane. Paste types text into the machine, as the panel's Paste does.
- **Light and dark.** The window follows the system's light or dark mode by default, and changes with it while open.
  **Settings → Appearance → Theme** picks Follow System, Light or Dark. The colours are VS Code's Light Modern and
  Dark Modern, so the window reads as the editor beside it does; Avalonia's own controls follow the same variant.
- **Zoom.** The window's chrome (the activity bar, the pane and the status bar) zooms as VS Code's does, in steps of
  20%, from about 58% to 300%:
  - Ctrl+= (or Ctrl++) zooms in, Ctrl+- zooms out and Ctrl+0 goes back to 100%, whenever the screen does not have the
    keyboard: while it does, those keys go to the machine;
  - Ctrl with the mouse wheel always zooms, anywhere in the window and even while the screen has the keyboard, as no
    machine takes the wheel;
  - **Settings → Appearance → Zoom** has the same, with the level shown, and the status bar shows the level while it
    is not 100%, clicking it going back to 100%.

  The machine's screen is not zoomed: it already fills the space left to it, sharp or fitted.
- **Settings** are a view of their own: the gear at the bottom of the activity bar switches the side pane to them, as
  VS Code's activity bar switches views. The theme and zoom are kept in Retrocore's roaming `settings.json`
  ([machine files](MachineFiles.md#settings-and-locations)) under `desktop`, apart from VS Code's own theme and zoom.

## Phases

### Phase 0: the spike

A first build in `src/Retrocore.Desktop`, to prove the technology before the rest:
- the window with the activity bar, the collapsible pane with its three sections (read-only lists where the
  extension has actions) and the status bar;
- the screen, drawing frames from `RenderVideo` at the display's rate, sharp or fitted;
- keys typed into the machine through `Key`, with the display panel's key map;
- sound through SDL3 from `TakeAudio`;
- a machine built with `OffMachine.Build` from a launch configuration, or the Apple IIe by default;
- `--smoke-seconds n`, which runs for n seconds, prints frames drawn, frame-time spread, emulated speed and audio
  underruns, and exits.

It passes when, on Windows:
1. **AOT:** `dotnet publish -r win-x64 -p:PublishAot=true` succeeds with no trimming or AOT warnings, and the app
   starts; size and start time are recorded.
2. **Pacing:** at 60 Hz the app draws 60 frames a second with a 99th-percentile frame time under 20 ms, and the
   machine keeps its clock.
3. **Keys:** typing at the screen reaches the machine, and focus moves between the screen and the pane.
4. **Sound:** the speaker plays without underruns while frames draw.

#### Results, 2026-11-14, on Windows

The spike is in [src/Retrocore.Desktop](../../src/Retrocore.Desktop), and passes on Windows, with one check open:

| Check | Result |
| --- | --- |
| AOT | `dotnet publish -r win-x64` succeeds with no trimming or AOT warnings. The app is 24.9 MB, 47.6 MB with Skia, HarfBuzz, ANGLE and SDL3. Its first frame comes about 165 ms after start, against 1,130 ms for the JIT build. |
| Pacing | Frames keep to the display's rate, with a p99 frame time within 0.7 ms of the median over three ten-second runs, and the machine keeps its clock (1.000×). The PC tested drives a 32 Hz remote display, so **60 Hz is still to be checked** on a local display. Avalonia's default composition and its low-latency DXGI swap chain pace the same here (`--composition`). |
| Keys | `PRINT 6*7` typed through the same path as the keyboard prints `42` on the Apple IIe; the TRS-80's key map and 4 by 3 picture work too. |
| Sound | The Apple IIe's speaker plays through SDL3 with no underruns, once each stream starts with 40 ms of silence. |
| Theme | Light Modern and Dark Modern, from `Palette` resources that follow the application's theme variant; the Fluent controls follow it too. Settings → Appearance → Theme switches it while running. |
| Zoom | With the screen holding the keyboard, Ctrl and one wheel notch over the screen zoom the chrome to 120%, and Ctrl+= then goes to the machine, leaving the zoom alone. The pane's width zooms with its contents. |

Not yet tried: following the system's theme as it changes while the app is open, and the settings file being
written (smoke runs neither read nor write it, so they measure the same each time).

What the spike turned up:
- One line of the debug host ([DebugSession.BasicThread.cs](../../src/Retrocore.Debug/DebugSession.BasicThread.cs))
  used `JsonArray`'s generic `Add<T>` through a collection expression, which Native AOT cannot compile; it is fixed,
  which also matters for the debug host's own AOT build.
- An AOT app cannot reference the debug host's executable unless the SDK's self-contained check is turned off,
  which the spike does until phase 1's library.
- Linking needs `vswhere.exe` on the PATH (`C:\Program Files (x86)\Microsoft Visual Studio\Installer`), which a plain
  Git Bash does not have.
- The display panel's per-machine aspect (280 by 192 for the Apples, 4 by 3 for the others) is what the screen needs,
  not a rule from the picture's size.

### Phase 1: the shared host library

`Retrocore.Hosting`, holding what both hosts need: building and running a machine, its frames, audio and keys, its
devices and hardware actions, and the machine configuration. `Retrocore.Debug` and Retrocore Desktop both use it.
Done when the debug host's tests pass on it unchanged and the desktop app no longer sees `Retrocore.Debug`'s
internals.

### Phase 2: the views as the extension has them

The Machine, Drives and Display and Sound sections with their actions: switching machines, cards, inserting and
ejecting, locks, speed, sound, screen, and the status bar's keys. Done when everything the extension's views and
panel do while a machine runs can be done here.

### Phase 3: machine files and media

The app opens and writes `.machine.retrocore` files and shares settings, the recovery journal and the history, as
those plans' phases land. This is where the two hosts are tested against each other.

### Phase 4: Linux and macOS

Publishing and testing on linux-x64 and osx-arm64, with Wayland and the macOS menu bar.

## Decisions (agreed 2026-11-14)

- **Avalonia 12 with SDL3** for audio and controllers, and Avalonia's GPU-backed Skia for the screen, proven by a spike.
- **Windows, macOS and Linux**, with Windows tested first.
- **AppleSharp stays** as the minimal SDL emulator.
- **Retrocore Desktop** is the working name, for the window title, `src/Retrocore.Desktop` and `retrocore-desktop`.
