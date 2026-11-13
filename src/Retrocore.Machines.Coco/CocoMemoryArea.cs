// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Coco;

/// <summary>
///  What backs a Color Computer address.
/// </summary>
public enum CocoMemoryArea : byte
{
    /// <summary>
    ///  Nothing: reads see the floating bus.
    /// </summary>
    None,

    /// <summary>
    ///  RAM.
    /// </summary>
    Ram,

    /// <summary>
    ///  Extended Color BASIC, or on a CoCo 3 the lower half of its ROM.
    /// </summary>
    ExtendedBasic,

    /// <summary>
    ///  Color BASIC, or on a CoCo 3 the upper half of its ROM.
    /// </summary>
    ColorBasic,

    /// <summary>
    ///  The cartridge port's ROM.
    /// </summary>
    Cartridge,

    /// <summary>
    ///  The PIAs, the SAM or GIME, and the cartridge's I/O.
    /// </summary>
    Io
}
