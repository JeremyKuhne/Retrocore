// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.M6809;

/// <summary>
///  Parsed structure of an MC6809 indexed operand.
/// </summary>
internal readonly struct M6809IndexedOperand
{
    /// <summary>
    ///  Gets the indexed addressing subkind.
    /// </summary>
    public M6809IndexedKind Kind { get; init; }

    /// <summary>
    ///  Gets whether the operand is indirect (<c>[...]</c>).
    /// </summary>
    public bool Indirect { get; init; }

    /// <summary>
    ///  Gets the two-bit index register code (<c>0=X, 1=Y, 2=U, 3=S</c>), or fixed postbyte for <see cref="M6809IndexedKind.Fixed"/>.
    /// </summary>
    public byte Code { get; init; }

    /// <summary>
    ///  Gets any explicit offset width prefix.
    /// </summary>
    public M6809OffsetWidth Width { get; init; }

    /// <summary>
    ///  Gets the offset, target or pointer expression slice when <see cref="Kind"/> is not <see cref="M6809IndexedKind.Fixed"/>.
    /// </summary>
    public ReadOnlyMemory<char> Expression { get; init; }
}
