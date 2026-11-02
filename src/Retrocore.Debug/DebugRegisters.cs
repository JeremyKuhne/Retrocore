// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Isa;

namespace Retrocore.Debug;

/// <summary>
///  Reads a frame's registers and flags by their instruction-set names.
/// </summary>
internal sealed class DebugRegisters
{
    private readonly Dictionary<string, int> _registers = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, (int Register, int Bit)> _flags = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<int, int> _flagMasks = [];

    /// <summary>
    ///  Creates the map for an instruction set's description.
    /// </summary>
    /// <param name="description">The description, whose registers index a <see cref="DebugFrame"/>.</param>
    internal DebugRegisters(IsaDescription description)
    {
        if (description.Registers.Count > DebugFrame.Capacity)
        {
            throw new ArgumentException("The instruction set has more registers than a debug frame holds.", nameof(description));
        }

        Listed = description.Registers;
        for (int index = 0; index < Listed.Count; index++) { _registers[Listed[index].Name] = index; }
        foreach (IsaFlag flag in description.Flags)
        {
            int register = _registers[flag.Register];
            _flagMasks[register] = _flagMasks.GetValueOrDefault(register) | (1 << flag.Bit);

            // Contracts name flags as documentation does, by word, so the Z80's carry is never its register C.
            foreach (string word in flag.Words) { _flags[word] = (register, flag.Bit); }
        }
    }

    /// <summary>
    ///  Gets the registers the variables view lists, in the description's order.
    /// </summary>
    internal IReadOnlyList<IsaRegister> Listed { get; }

    /// <summary>
    ///  Gets the words that name the flags, such as <c>carry</c>.
    /// </summary>
    internal IEnumerable<string> Flags => _flags.Keys;

    /// <summary>
    ///  Gets the index of a register in a frame.
    /// </summary>
    /// <param name="name">The register's name, in any case.</param>
    /// <returns>The index, or -1 when the CPU has no such register.</returns>
    internal int IndexOf(string name) => _registers.TryGetValue(name, out int index) ? index : -1;

    /// <summary>
    ///  Reads one register of a frame.
    /// </summary>
    /// <param name="frame">The frame.</param>
    /// <param name="name">The register's name, in any case.</param>
    /// <returns>The value, or null when the CPU has no such register.</returns>
    internal long? Value(in DebugFrame frame, string name) => _registers.TryGetValue(name, out int index) ? frame[index] : null;

    /// <summary>
    ///  Reads a register or flag as a routine's contract compares it: a flag register only by its flags.
    /// </summary>
    /// <param name="frame">The frame.</param>
    /// <param name="name">The register's name or the flag's word, in any case.</param>
    /// <returns>The value, or null when the CPU has neither.</returns>
    internal long? Kept(in DebugFrame frame, string name)
    {
        if (_registers.TryGetValue(name, out int index))
        {
            return _flagMasks.TryGetValue(index, out int mask) ? frame[index] & mask : frame[index];
        }

        return _flags.TryGetValue(name, out (int Register, int Bit) flag) ? frame[flag.Register] & (1 << flag.Bit) : null;
    }

    /// <summary>
    ///  Tests whether a name is a register or a flag.
    /// </summary>
    /// <param name="name">The register's name or the flag's word, in any case.</param>
    /// <returns>Whether the CPU has it.</returns>
    internal bool Knows(string name) => _registers.ContainsKey(name) || _flags.ContainsKey(name);
}
