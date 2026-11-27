// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;

namespace Retrocore.Debug;

/// <summary>
///  Verifies firmware sites against the SDK assemblies used for debug source maps.
/// </summary>
internal static class InputFirmware
{
    /// <summary>
    ///  Resolves an SDK symbol to a machine address.
    /// </summary>
    /// <param name="assembly">The verified firmware build.</param>
    /// <param name="name">The symbol's scoped name.</param>
    /// <returns>The address, or zero if it is absent.</returns>
    internal static ushort Symbol(AssemblyResult assembly, string name) =>
        assembly.Symbols.TryGetValue(name, out long address) ? checked((ushort)address) : (ushort)0;

    /// <summary>
    ///  Looks up a span of assembled bytes.
    /// </summary>
    /// <param name="assembly">The firmware build.</param>
    /// <param name="address">The starting address in a section.</param>
    /// <param name="length">How many consecutive bytes to take.</param>
    /// <returns>The span, or an empty span when the section does not hold it.</returns>
    internal static ReadOnlySpan<byte> Bytes(AssemblyResult assembly, int address, int length)
    {
        foreach (AssemblySection section in assembly.Sections)
        {
            int offset = address - section.Origin;
            if (offset >= 0 && length <= section.Bytes.Length - offset)
            {
                return section.Bytes.Span.Slice(offset, length);
            }
        }

        return [];
    }

    /// <summary>
    ///  Checks the active memory mapping without bus side effects.
    /// </summary>
    /// <param name="memory">The current mapped CPU memory.</param>
    /// <param name="address">The start of the signature.</param>
    /// <param name="bytes">The expected nonempty signature.</param>
    /// <returns>Whether mapped memory holds the signature.</returns>
    internal static bool Matches(IDebugMemory memory, int address, ReadOnlySpan<byte> bytes)
    {
        if (bytes.IsEmpty) { return false; }
        foreach (byte value in bytes)
        {
            if (memory.Peek((ushort)address++) != value) { return false; }
        }

        return true;
    }

    /// <summary>
    ///  Locates the continuation after a known instruction sequence.
    /// </summary>
    /// <param name="assembly">The firmware build.</param>
    /// <param name="start">The first address to search.</param>
    /// <param name="length">The number of bytes to search.</param>
    /// <param name="pattern">The instruction sequence.</param>
    /// <returns>The continuation, or zero if it is absent.</returns>
    internal static ushort After(AssemblyResult assembly, ushort start, int length, ReadOnlySpan<byte> pattern)
    {
        int index = Bytes(assembly, start, length).IndexOf(pattern);
        return index < 0 ? (ushort)0 : (ushort)(start + index + pattern.Length);
    }

    /// <summary>
    ///  Reads a little-endian vector without bus side effects.
    /// </summary>
    /// <param name="memory">The current mapped CPU memory.</param>
    /// <param name="address">The low byte's address.</param>
    /// <returns>The word.</returns>
    internal static ushort Word(IDebugMemory memory, ushort address) =>
        (ushort)(memory.Peek(address) | (memory.Peek((ushort)(address + 1)) << 8));

    /// <summary>
    ///  Reads the saved return address of a 6502 JSR, before the implicit increment done by RTS.
    /// </summary>
    /// <param name="target">The machine with a conventional page-one stack.</param>
    /// <returns>The saved return address.</returns>
    internal static ushort ReturnAddress(IDebugTarget target)
    {
        int stack = target.StackPointer;
        return (ushort)(target.Peek((ushort)(0x100 | ((stack + 1) & 0xFF)))
                | (target.Peek((ushort)(0x100 | ((stack + 2) & 0xFF))) << 8));
    }
}
