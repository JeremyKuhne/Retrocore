// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Atari;

/// <summary>
///  The parts of the Atari 400 and 800's address space, for the debugger's memory views.
/// </summary>
public enum AtariMemoryArea
{
    /// <summary>
    ///  RAM.
    /// </summary>
    Ram,

    /// <summary>
    ///  The 800's right cartridge, <c>$8000-$9FFF</c>.
    /// </summary>
    RightCartridge,

    /// <summary>
    ///  The left cartridge: <c>$A000-$BFFF</c>, or <c>$8000-$BFFF</c> for 16 KB.
    /// </summary>
    LeftCartridge,

    /// <summary>
    ///  The chips' registers, <c>$D000-$D7FF</c>.
    /// </summary>
    Io,

    /// <summary>
    ///  The floating point package, <c>$D800-$DFFF</c>.
    /// </summary>
    FloatingPoint,

    /// <summary>
    ///  The operating system, <c>$E000-$FFFF</c>.
    /// </summary>
    OperatingSystem,

    /// <summary>
    ///  Nothing: reads <c>$00</c> at <c>$C000-$CFFF</c> and <c>$FF</c> elsewhere.
    /// </summary>
    Empty
}
