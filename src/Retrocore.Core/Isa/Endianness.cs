// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Isa;

/// <summary>
///  The byte order of a CPU's multi-byte values.
/// </summary>
public enum Endianness : byte
{
    /// <summary>
    ///  Low byte first, as on the 6502 and Z80.
    /// </summary>
    Little,

    /// <summary>
    ///  High byte first, as on the 6800 and 6809.
    /// </summary>
    Big
}
