// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.M6809;

/// <summary>
///  Width overrides for an MC6809 indexed offset.
/// </summary>
internal enum M6809OffsetWidth : byte
{
    /// <summary>
    ///  Choose the narrowest encoding that fits the resolved offset.
    /// </summary>
    Automatic,

    /// <summary>
    ///  Force a 5-bit signed offset (<c>&lt;&lt;</c>).
    /// </summary>
    FiveBit,

    /// <summary>
    ///  Force an 8-bit signed offset (<c>&lt;</c>).
    /// </summary>
    EightBit,

    /// <summary>
    ///  Force a 16-bit offset (<c>&gt;</c>).
    /// </summary>
    SixteenBit
}
