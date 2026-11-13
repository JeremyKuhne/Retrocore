// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Isa;

/// <summary>
///  What a decoded postbyte field refers to.
/// </summary>
public enum PostbyteReference : byte
{
    /// <summary>
    ///  No static address: registers, a register list, or an offset from a register.
    /// </summary>
    None,

    /// <summary>
    ///  An address computed from the program counter and used directly, such as the MC6809's <c>Table,PCR</c>.
    /// </summary>
    Target,

    /// <summary>
    ///  A pointer read from a static address, such as the MC6809's <c>[$FFFE]</c> or <c>[Table,PCR]</c>.
    /// </summary>
    Pointer
}
