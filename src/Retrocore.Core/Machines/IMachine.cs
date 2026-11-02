// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu;

namespace Retrocore.Machines;

/// <summary>
///  What the debugger and front ends need from any emulated machine.
/// </summary>
/// <remarks>
///  <para>
///   Machines keep their concrete, specialized API for speed; this interface is the boundary the debugger
///   and the machine-neutral tools cross.
///  </para>
/// </remarks>
public interface IMachine
{
    /// <summary>
    ///  Gets the machine's identifier, as a launch configuration's <c>machine</c> names it, such as <c>apple2</c>.
    /// </summary>
    string Id { get; }

    /// <summary>
    ///  Gets the CPU.
    /// </summary>
    ICpuDebugView Cpu { get; }

    /// <summary>
    ///  Gets the video output, or null for a machine without one.
    /// </summary>
    IVideoSource? Video { get; }

    /// <summary>
    ///  Gets the names of the memory areas <see cref="MemoryArea"/> reports, indexed by area; area 0 is none.
    /// </summary>
    IReadOnlyList<string> MemoryAreas { get; }

    /// <summary>
    ///  Gets the devices installed in the machine, such as its floppy and tape drives, in the order the machine's
    ///  documentation lists them.
    /// </summary>
    IReadOnlyList<Devices.IDevice> Devices { get; }

    /// <summary>
    ///  Gets the CPU's bus activity in the last cycle, built on request.
    /// </summary>
    ProcessorCycle LastCycle { get; }

    /// <summary>
    ///  Advances the machine by one CPU cycle; <see cref="LastCycle"/> then describes it.
    /// </summary>
    void StepCycle();

    /// <summary>
    ///  Runs until the current or next instruction completes.
    /// </summary>
    /// <param name="maximumCycles">The most cycles to run.</param>
    /// <returns>The status and cycles run.</returns>
    ProcessorExecutionResult StepInstruction(int maximumCycles);

    /// <summary>
    ///  Reads what the CPU would see at an address, without side effects.
    /// </summary>
    /// <param name="address">The CPU address.</param>
    /// <returns>The value.</returns>
    byte Peek(ushort address);

    /// <summary>
    ///  Gets which memory area currently backs a CPU address, such as main RAM or a bank of ROM.
    /// </summary>
    /// <param name="address">The CPU address.</param>
    /// <returns>An index into <see cref="MemoryAreas"/>.</returns>
    int MemoryArea(ushort address);

    /// <summary>
    ///  Presses a key, in the machine's own character code.
    /// </summary>
    /// <param name="code">The code.</param>
    void QueueKey(byte code);
}
