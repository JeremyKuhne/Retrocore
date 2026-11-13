// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Isa;

/// <summary>
///  A postbyte operand parsed by a <see cref="PostbyteCodec"/>, ready for layout and encoding.
/// </summary>
public readonly struct PostbyteOperand
{
    /// <summary>
    ///  Gets the field kind it was parsed as.
    /// </summary>
    public OperandFieldKind Kind { get; init; }

    /// <summary>
    ///  Gets a codec-defined code, such as the whole postbyte of a mode with no expression.
    /// </summary>
    public byte Code { get; init; }

    /// <summary>
    ///  Gets codec-defined details, such as the mode and a forced offset width.
    /// </summary>
    public byte Detail { get; init; }

    /// <summary>
    ///  Gets the one expression the assembler evaluates for the field, or empty when there is none.
    /// </summary>
    public ReadOnlyMemory<char> Expression { get; init; }
}
