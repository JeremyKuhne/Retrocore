// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Isa;

/// <summary>
///  The <c>[isa]</c> settings that shape each instruction set built from a description.
/// </summary>
internal sealed class IsaRules
{
    /// <summary>
    ///  Gets the instructions whose mnemonic ends in the bit number held in opcode bits 4-6.
    /// </summary>
    internal HashSet<string> BitSuffix { get; } = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>
    ///  Gets the opcodes that win over earlier encodings of their mnemonic and form.
    /// </summary>
    internal HashSet<uint> Preferred { get; } = [];

    /// <summary>
    ///  Gets the flow class of each instruction (<c>JSR</c>), or of one of its forms (<c>JMP:AbsoluteIndirect</c>).
    /// </summary>
    internal Dictionary<string, InstructionFlow> Flows { get; } = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>
    ///  Gets how each instruction (<c>STA</c>), or one of its forms (<c>LD:StoreA</c>), that does not only read
    ///  accesses its memory operand.
    /// </summary>
    internal Dictionary<string, MemoryAccess> Access { get; } = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>
    ///  Gets whether an opcode line may name a form the <c>[forms]</c> section does not declare, which then
    ///  is a literal form whose pattern is its name, such as <c>A,[HL]</c>.
    /// </summary>
    internal bool LiteralForms { get; set; }

    /// <summary>
    ///  Gets the addresses of the hardware vectors, pointers to code, in the order analysis follows them.
    /// </summary>
    internal List<ushort> Vectors { get; } = [];

    /// <summary>
    ///  Gets the fixed addresses where the hardware starts code, such as the Z80's restarts.
    /// </summary>
    internal List<ushort> EntryPoints { get; } = [];

    /// <summary>
    ///  Gets the instruction sets whose indirect pointers do not carry into the high byte's page.
    /// </summary>
    internal HashSet<string> IndirectPageWrap { get; } = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>
    ///  Gets whether leading <c>&lt;</c> and <c>&gt;</c> prefixes force narrow and wide addressing, as on Motorola CPUs.
    /// </summary>
    internal bool AngleWidths { get; set; }

    /// <summary>
    ///  Gets alternate mnemonic names mapped to their canonical mnemonic, such as <c>LSL</c> for <c>ASL</c>.
    /// </summary>
    internal Dictionary<string, string> Aliases { get; } = new(StringComparer.OrdinalIgnoreCase);
}
