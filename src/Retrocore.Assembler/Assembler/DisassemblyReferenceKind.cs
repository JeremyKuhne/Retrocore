// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  The statically known meaning of an encoded address reference.
/// </summary>
public enum DisassemblyReferenceKind : byte
{
    /// <summary>
    ///  A conditional branch target.
    /// </summary>
    Branch,

    /// <summary>
    ///  A direct jump target.
    /// </summary>
    Jump,

    /// <summary>
    ///  A subroutine entry point.
    /// </summary>
    Call,

    /// <summary>
    ///  A read address or indexed read base.
    /// </summary>
    Read,

    /// <summary>
    ///  A write address or indexed write base.
    /// </summary>
    Write,

    /// <summary>
    ///  A read-modify-write address or indexed base.
    /// </summary>
    ReadWrite,

    /// <summary>
    ///  An indirect-jump pointer, not a dereferenced code target.
    /// </summary>
    IndirectJump,

    /// <summary>
    ///  A code target stored in a hardware vector or an indirect-jump pointer inside the image.
    /// </summary>
    /// <remarks>The reference's source is the vector's address, not an instruction.</remarks>
    Vector
}
