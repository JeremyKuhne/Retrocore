// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Isa;

/// <summary>
///  The registers a postbyte names, for an instruction's effects: registers as bits from
///  <see cref="IsaDescription.RegisterMask"/>.
/// </summary>
/// <remarks>
///  <para>
///   An effects line names them as its operand slots, as the MC6809's <c>effects TFR reads $1 writes $2</c> and
///   <c>effects PSHS reads $1 S writes S push $1</c>. The address registers of an indexed postbyte apply to every
///   instruction in an indexed form, as the index register of an address does.
///  </para>
/// </remarks>
public readonly record struct PostbyteEffects
{
    /// <summary>
    ///  Gets the registers in the field's first slot, <c>$1</c>: a register list's, or a pair's first.
    /// </summary>
    public uint First { get; init; }

    /// <summary>
    ///  Gets the register in the field's second slot, <c>$2</c>: a pair's second.
    /// </summary>
    public uint Second { get; init; }

    /// <summary>
    ///  Gets the bytes a register list moves through the stack, for <c>push $1</c> and <c>pull $1</c>.
    /// </summary>
    public byte Bytes { get; init; }

    /// <summary>
    ///  Gets the registers an address is formed from, as an index register and an accumulator offset.
    /// </summary>
    public uint AddressRead { get; init; }

    /// <summary>
    ///  Gets the registers forming the address changes, as an auto-incremented index register.
    /// </summary>
    public uint AddressWritten { get; init; }
}
