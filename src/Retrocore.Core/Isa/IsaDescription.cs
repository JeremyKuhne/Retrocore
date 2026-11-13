// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Isa;

/// <summary>
///  What one description file says about a CPU family, shared by each of its instruction sets.
/// </summary>
public sealed class IsaDescription
{
    /// <summary>
    ///  Gets the byte order.
    /// </summary>
    public Endianness Endianness { get; init; }

    /// <summary>
    ///  Gets the width of an address, in bits.
    /// </summary>
    public int AddressBits { get; init; } = 16;

    /// <summary>
    ///  Gets the registers.
    /// </summary>
    public IReadOnlyList<IsaRegister> Registers { get; init; } = [];

    /// <summary>
    ///  Gets the flags.
    /// </summary>
    public IReadOnlyList<IsaFlag> Flags { get; init; } = [];

    /// <summary>
    ///  Gets the operand forms, indexed by ID; their order is the order operands are matched in.
    /// </summary>
    public IReadOnlyList<OperandForm> Forms { get; init; } = [];

    /// <summary>
    ///  Gets the addresses of the hardware vectors, pointers to code such as the 6502's reset vector, in the
    ///  order analysis follows them.
    /// </summary>
    public IReadOnlyList<ushort> Vectors { get; init; } = [];

    /// <summary>
    ///  Gets the fixed addresses where the hardware starts code, such as the Z80's reset, restarts and NMI.
    /// </summary>
    public IReadOnlyList<ushort> EntryPoints { get; init; } = [];

    /// <summary>
    ///  Gets whether leading <c>&lt;</c> and <c>&gt;</c> prefixes on address operands force narrow and wide modes.
    /// </summary>
    public bool AngleWidths { get; init; }

    /// <summary>
    ///  Gets the instruction sets the file defines, by name.
    /// </summary>
    public IReadOnlyDictionary<string, InstructionSet> InstructionSets { get; internal set; } =
        new Dictionary<string, InstructionSet>();

    /// <summary>
    ///  Finds a form by name.
    /// </summary>
    /// <param name="name">The name.</param>
    /// <returns>The form, or null.</returns>
    public OperandForm? Form(string name)
    {
        Dictionary<string, OperandForm>? byName = _byName;
        if (byName is null)
        {
            byName = new(StringComparer.Ordinal);
            foreach (OperandForm form in Forms)
            {
                if (!byName.ContainsKey(form.Name)) { byName.Add(form.Name, form); }
            }

            _byName = byName;
        }

        return byName.TryGetValue(name, out OperandForm? found) ? found : null;
    }

    private Dictionary<string, OperandForm>? _byName;
}
