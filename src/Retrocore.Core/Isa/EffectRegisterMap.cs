// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Isa;

/// <summary>
///  The registers effects are kept on, as bits: the registers line's, in its order, then the parts a
///  <c>parts</c> line adds, such as the Z80's IXH. A register with parts, such as HL, has no bit of its own and
///  stands for its parts' bits.
/// </summary>
internal sealed class EffectRegisterMap
{
    private EffectRegisterMap()
    {
    }

    /// <summary>
    ///  Gets the register names by bit.
    /// </summary>
    internal List<string> Names { get; } = [];

    /// <summary>
    ///  Gets the bits each register name stands for.
    /// </summary>
    internal Dictionary<string, uint> Masks { get; } = [with(StringComparer.Ordinal)];

    /// <summary>
    ///  Gets the bit of the register that holds the flags, or -1.
    /// </summary>
    internal int FlagsRegister { get; private set; } = -1;

    /// <summary>
    ///  Gets every flag's bit in the flags register.
    /// </summary>
    internal byte AllFlags { get; private set; }

    /// <summary>
    ///  Gets or sets the bit of the stack register <c>push</c> and <c>pull</c> use unless they name another, or -1.
    /// </summary>
    internal int Stack { get; set; } = -1;

    /// <summary>
    ///  Gets or sets whether an effects line has used the map, after which parts may not change it.
    /// </summary>
    internal bool InUse { get; set; }

    /// <summary>
    ///  Builds the map of a registers line and its flags.
    /// </summary>
    /// <param name="registers">The registers.</param>
    /// <param name="flags">The flags, all bits of one 8-bit register.</param>
    /// <returns>The map, or null when the flags are not of one register of the line.</returns>
    internal static EffectRegisterMap? Create(List<IsaRegister> registers, List<IsaFlag> flags)
    {
        if (flags.Count == 0) { return null; }
        EffectRegisterMap map = new();
        foreach (IsaRegister register in registers) { map.Add(register.Name); }
        foreach (IsaFlag flag in flags)
        {
            int register = registers.FindIndex(known => known.Name == flag.Register);
            if (flag.Bit is < 0 or > 7 || register < 0 || (map.FlagsRegister >= 0 && register != map.FlagsRegister))
            {
                return null;
            }

            map.FlagsRegister = register;
            map.AllFlags |= (byte)(1 << flag.Bit);
        }

        return map;
    }

    /// <summary>
    ///  Gets the bits a register name stands for.
    /// </summary>
    /// <param name="name">The register's name.</param>
    /// <returns>The bits, or 0 when no register has the name.</returns>
    internal uint Mask(string name) => Masks.TryGetValue(name, out uint mask) ? mask : 0;

    /// <summary>
    ///  Gets the flags a register mask holds: every flag when it holds the flags register.
    /// </summary>
    /// <param name="mask">The register bits.</param>
    /// <returns>The flag bits.</returns>
    internal byte FlagsOf(uint mask) => FlagsRegister >= 0 && (mask & (1u << FlagsRegister)) != 0 ? AllFlags : (byte)0;

    /// <summary>
    ///  Makes a register stand for its parts, adding a bit for each part the registers line lacks.
    /// </summary>
    /// <param name="whole">The register, such as <c>HL</c>.</param>
    /// <param name="parts">Its parts, such as <c>H</c> and <c>L</c>.</param>
    /// <returns>Why it cannot, or null.</returns>
    internal string? AddParts(string whole, IReadOnlyList<string> parts)
    {
        if (!Masks.TryGetValue(whole, out uint own) || own != 1u << Names.IndexOf(whole))
        {
            return $"'{whole}' must be a register of the registers line, given its parts once.";
        }

        uint mask = 0;
        foreach (string part in parts)
        {
            if (part == whole || (Masks.TryGetValue(part, out uint bits) && bits != 1u << Names.IndexOf(part)))
            {
                return $"Part '{part}' of '{whole}' must be a single register.";
            }

            if (!Masks.ContainsKey(part) && !Add(part)) { return "Effects describe at most 32 registers and parts."; }
            mask |= Masks[part];
        }

        Masks[whole] = mask;
        return null;
    }

    private bool Add(string name)
    {
        if (Names.Count == 32) { return false; }
        Masks[name] = 1u << Names.Count;
        Names.Add(name);
        return true;
    }
}
