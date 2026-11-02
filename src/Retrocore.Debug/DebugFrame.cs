// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  A CPU's registers at one moment: the current state, or a caller's at its call.
/// </summary>
/// <remarks>
///  <para>
///   Values are held by their index in the instruction set's register list, so one fixed-size value serves
///   every CPU without allocating as the debugger observes each instruction.
///  </para>
/// </remarks>
internal struct DebugFrame
{
    /// <summary>
    ///  Gets the most registers a frame holds.
    /// </summary>
    internal const int Capacity = 24;

    private DebugFrameValues _values;

    /// <summary>
    ///  Gets or sets the program counter.
    /// </summary>
    internal ushort ProgramCounter { readonly get; set; }

    /// <summary>
    ///  Gets or sets the stack pointer, which grows down.
    /// </summary>
    internal int StackPointer { readonly get; set; }

    /// <summary>
    ///  Gets or sets the register at an index of the instruction set's register list.
    /// </summary>
    /// <param name="index">The index.</param>
    internal ushort this[int index]
    {
        readonly get => _values[index];
        set => _values[index] = value;
    }
}
