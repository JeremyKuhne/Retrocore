// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Isa;

namespace Retrocore.Cpu;

/// <summary>
///  What a debugger sees of any CPU: its registers by their instruction-set names, and where execution is.
/// </summary>
/// <remarks>
///  <para>
///   Cores implement this explicitly beside their concrete, struct-bus API, so only the debugger pays for
///   interface calls.
///  </para>
/// </remarks>
public interface ICpuDebugView
{
    /// <summary>
    ///  Gets the instruction set the CPU decodes with.
    /// </summary>
    InstructionSet InstructionSet { get; }

    /// <summary>
    ///  Gets the number of elapsed CPU cycles.
    /// </summary>
    ulong CycleCount { get; }

    /// <summary>
    ///  Gets whether no instruction, reset or interrupt sequence is in flight.
    /// </summary>
    bool IsInstructionBoundary { get; }

    /// <summary>
    ///  Gets the execution or halt status.
    /// </summary>
    ProcessorExecutionStatus Status { get; }

    /// <summary>
    ///  Gets the address of the next instruction.
    /// </summary>
    ushort ProgramCounter { get; }

    /// <summary>
    ///  Gets the address the stack pointer refers to, such as <c>$0100 + S</c> on the 6502.
    /// </summary>
    ushort StackAddress { get; }

    /// <summary>
    ///  Reads a register by its instruction-set name, such as <c>A</c> or <c>PC</c>.
    /// </summary>
    /// <param name="name">The name, in any case.</param>
    /// <param name="value">The value.</param>
    /// <returns>Whether the CPU has the register.</returns>
    bool TryGetRegister(string name, out int value);

    /// <summary>
    ///  Writes a register by its instruction-set name at an instruction boundary.
    /// </summary>
    /// <param name="name">The name, in any case.</param>
    /// <param name="value">The value, which must fit the register.</param>
    /// <returns>Whether the CPU has the register.</returns>
    /// <exception cref="InvalidOperationException">Execution is not at a running instruction boundary.</exception>
    /// <exception cref="ArgumentOutOfRangeException">The value does not fit the register.</exception>
    bool TrySetRegister(string name, int value);
}
