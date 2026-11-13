// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Apple3;

/// <summary>
///  What backs a CPU address on the Apple III.
/// </summary>
/// <remarks>
///  <para>
///   Each switchable bank is its own area, so a debugger can tell which one is mapped: bank 0 is 128K's and 256K's
///   first, through bank 14 with 512K.
///  </para>
/// </remarks>
public enum Apple3MemoryArea
{
    /// <summary>
    ///  Nothing answers: an empty slot.
    /// </summary>
    None,

    /// <summary>
    ///  The system bank, the last 32K of RAM, seen at <c>$0000-$1FFF</c> and <c>$A000-$FFFF</c>.
    /// </summary>
    SystemBank,

    /// <summary>
    ///  The 4K boot ROM.
    /// </summary>
    Rom,

    /// <summary>
    ///  The I/O page, <c>$C000-$C0FF</c>.
    /// </summary>
    Io,

    /// <summary>
    ///  The two system VIAs, <c>$FFD0-$FFEF</c>.
    /// </summary>
    Vias,

    /// <summary>
    ///  Switchable bank 0, which also holds the graphics pages.
    /// </summary>
    Bank0,

    /// <summary>
    ///  Switchable bank 1.
    /// </summary>
    Bank1,

    /// <summary>
    ///  Switchable bank 2.
    /// </summary>
    Bank2,

    /// <summary>
    ///  Switchable bank 3.
    /// </summary>
    Bank3,

    /// <summary>
    ///  Switchable bank 4.
    /// </summary>
    Bank4,

    /// <summary>
    ///  Switchable bank 5.
    /// </summary>
    Bank5,

    /// <summary>
    ///  Switchable bank 6.
    /// </summary>
    Bank6,

    /// <summary>
    ///  Switchable bank 7, with 512K.
    /// </summary>
    Bank7,

    /// <summary>
    ///  Switchable bank 8, with 512K.
    /// </summary>
    Bank8,

    /// <summary>
    ///  Switchable bank 9, with 512K.
    /// </summary>
    Bank9,

    /// <summary>
    ///  Switchable bank 10, with 512K.
    /// </summary>
    Bank10,

    /// <summary>
    ///  Switchable bank 11, with 512K.
    /// </summary>
    Bank11,

    /// <summary>
    ///  Switchable bank 12, with 512K.
    /// </summary>
    Bank12,

    /// <summary>
    ///  Switchable bank 13, with 512K.
    /// </summary>
    Bank13,

    /// <summary>
    ///  Switchable bank 14, with 512K.
    /// </summary>
    Bank14
}
