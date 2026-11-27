// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines;

/// <summary>
///  What kind of memory backs each of a CPU's 65,536 addresses in one state of a machine, such as at reset, for static
///  analysis: whether a byte read is the ROM's, what a program stored, or a device's.
/// </summary>
public sealed class MemoryMap
{
    private readonly MemoryKind[] _kinds;

    private MemoryMap(MemoryKind[] kinds) => _kinds = kinds;

    /// <summary>
    ///  Gets a map with every address RAM, as a CP/M program's memory is: its I/O goes through ports.
    /// </summary>
    public static MemoryMap AllRam { get; } = Uniform(MemoryKind.Ram);

    /// <summary>
    ///  Gets the kind of memory at an address.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>The kind.</returns>
    public MemoryKind this[ushort address] => _kinds[address];

    /// <summary>
    ///  Captures the map of a machine as it is now, from the area its memory map reaches at each address.
    /// </summary>
    /// <param name="machine">The machine, in the state its programs run in, such as just after it was built.</param>
    /// <returns>The map.</returns>
    public static MemoryMap Capture(IMachine machine)
    {
        ArgumentNullException.ThrowIfNull(machine);
        MemoryKind[] kinds = new MemoryKind[0x10000];
        for (int address = 0; address < kinds.Length; address++)
        {
            kinds[address] = machine.AreaKind(machine.MemoryArea((ushort)address));
        }

        return new(kinds);
    }

    /// <summary>
    ///  Builds a map from ranges, inclusive; addresses no range covers are <see cref="MemoryKind.None"/>, and a later
    ///  range wins where two overlap.
    /// </summary>
    /// <param name="ranges">Each range's first and last address and kind.</param>
    /// <returns>The map.</returns>
    public static MemoryMap FromRanges(IEnumerable<(ushort First, ushort Last, MemoryKind Kind)> ranges)
    {
        ArgumentNullException.ThrowIfNull(ranges);
        MemoryKind[] kinds = new MemoryKind[0x10000];
        foreach ((ushort first, ushort last, MemoryKind kind) in ranges)
        {
            ArgumentOutOfRangeException.ThrowIfGreaterThan(first, last);
            kinds.AsSpan(first, last - first + 1).Fill(kind);
        }

        return new(kinds);
    }

    /// <summary>
    ///  Gets a map with every address of one kind.
    /// </summary>
    /// <param name="kind">The kind.</param>
    /// <returns>The map.</returns>
    public static MemoryMap Uniform(MemoryKind kind)
    {
        MemoryKind[] kinds = new MemoryKind[0x10000];
        Array.Fill(kinds, kind);
        return new(kinds);
    }

    /// <summary>
    ///  Gets the map as runs of addresses of one kind, in address order.
    /// </summary>
    /// <returns>Each run's first and last address and kind.</returns>
    public IEnumerable<(ushort First, ushort Last, MemoryKind Kind)> Ranges()
    {
        int start = 0;
        for (int address = 1; address <= _kinds.Length; address++)
        {
            if (address < _kinds.Length && _kinds[address] == _kinds[start]) { continue; }
            yield return ((ushort)start, (ushort)(address - 1), _kinds[start]);
            start = address;
        }
    }
}
