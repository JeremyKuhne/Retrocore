// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Trs80;

/// <summary>
///  The machines of the Model III family, which share the Model III's ports and keyboard.
/// </summary>
public enum Trs80Model3Variant : byte
{
    /// <summary>
    ///  The Model III: a 2.03 MHz Z80, the 14K Model III ROM, 16 to 48K of RAM and a 64x16 display.
    /// </summary>
    Model3,

    /// <summary>
    ///  The Model 4: the Model III's ROM and ports, plus 4 MHz, 64 or 128K of banked RAM, four memory maps and an
    ///  80x24 display.
    /// </summary>
    Model4,

    /// <summary>
    ///  The Model 4P: a Model 4 whose only ROM is a 4K boot loader, which loads the Model III ROM image from disk
    ///  when the disk asks for Model III mode. It has no cassette port.
    /// </summary>
    Model4P
}
