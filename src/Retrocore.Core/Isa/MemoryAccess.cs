// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Isa;

/// <summary>
///  How an instruction accesses its memory operand.
/// </summary>
public enum MemoryAccess : byte
{
    /// <summary>
    ///  It reads the operand.
    /// </summary>
    Read,

    /// <summary>
    ///  It writes the operand.
    /// </summary>
    Write,

    /// <summary>
    ///  It reads and then writes the operand.
    /// </summary>
    ReadWrite
}
