// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

// A second CPU on the machine's bus, such as the Z80 SoftCard's: its own thread beside the machine's CPU.
//
// Only the CPU that has the bus runs, so the run checks breakpoints, steps and observes calls on that CPU's view, and
// a stop is that CPU's thread's. Each thread keeps its own frames, registers and disassembly; the coprocessor's
// memory references name its address space as a bank, such as z80:0x0100.
internal sealed partial class DebugSession
{
    private const int SoftCardThread = 3;

    // The coprocessor thread's frame ids start after this; the machine CPU's are 1 up to it.
    private const int SoftCardFrameBase = 1000;

    // The thread of the last stop, whose top frame hides the macro levels the stop hides.
    private int _stoppedThread = 1;

    /// <summary>
    ///  Gets the view of the CPU that has the bus: the coprocessor's while it has it, else the machine's.
    /// </summary>
    private IDebugTarget Cpu => _target is { CoprocessorActive: true, Coprocessor: { } coprocessor }
        ? coprocessor
        : Target;

    // Whether a view is the machine's own CPU rather than a coprocessor.
    private bool IsMachineCpu(IDebugTarget view) => ReferenceEquals(view, _target);

    // The thread a CPU's view runs as.
    private int ThreadOf(IDebugTarget view) => IsMachineCpu(view) ? 1 : SoftCardThread;

    // The view a thread shows: the coprocessor's for its thread while it is installed, else the machine's CPU.
    private IDebugTarget ThreadTarget(int thread) =>
        thread == SoftCardThread && _target?.Coprocessor is { } coprocessor ? coprocessor : Target;

    // The bank that names a thread's addresses in memory references: none for the machine's CPU.
    private DebugMemoryBank? ThreadBank(int thread) =>
        thread == SoftCardThread && ThreadTarget(thread) is SoftCardDebugTarget softCard ? softCard.Bank : null;

    // A frame id's thread and its index in that thread's frames.
    private static (int Thread, int Index) FrameIndex(int frameId) =>
        frameId > SoftCardFrameBase && frameId < BanksScope / 2
            ? (SoftCardThread, frameId - SoftCardFrameBase - 1)
            : (1, frameId - 1);

    // The view whose registers and memory a frame shows.
    private IDebugTarget FrameTarget(int frameId) => ThreadTarget(FrameIndex(frameId).Thread);
}
