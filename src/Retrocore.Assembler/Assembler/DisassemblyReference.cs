// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  A statically known code or data address reference.
/// </summary>
public readonly struct DisassemblyReference
{
    /// <summary>
    ///  Creates an address reference.
    /// </summary>
    /// <param name="source">The referring instruction address.</param>
    /// <param name="target">The encoded address or resolved relative target.</param>
    /// <param name="kind">The reference semantics.</param>
    public DisassemblyReference(ushort source, ushort target, DisassemblyReferenceKind kind)
    {
        if (!Enum.IsDefined(kind)) { throw new ArgumentOutOfRangeException(nameof(kind)); }
        Source = source;
        Target = target;
        Kind = kind;
    }

    /// <summary>
    ///  Gets the referring instruction address.
    /// </summary>
    public ushort Source { get; }

    /// <summary>
    ///  Gets the referenced address; indexed references name the encoded base, not an effective address.
    /// </summary>
    public ushort Target { get; }

    /// <summary>
    ///  Gets the reference semantics.
    /// </summary>
    public DisassemblyReferenceKind Kind { get; }
}
