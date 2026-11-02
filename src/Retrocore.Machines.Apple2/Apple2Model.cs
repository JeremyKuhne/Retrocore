// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Apple2;

/// <summary>
///  The models of the Apple II family. Each is a processor, a set of ROMs and the hardware the board has, which
///  <see cref="Apple2ModelExtensions"/> describes.
/// </summary>
/// <remarks>
///  <para>
///   The IIe models keep the values they had as the IIe's own models, 0 and 1, so settings saved by number still
///   read back.
///  </para>
/// </remarks>
public enum Apple2Model : byte
{
    /// <summary>
    ///  The original (unenhanced) Apple IIe, with an NMOS 6502.
    /// </summary>
    IIe = 0,

    /// <summary>
    ///  The enhanced Apple IIe, with a Rockwell 65C02 and MouseText.
    /// </summary>
    IIeEnhanced = 1,

    /// <summary>
    ///  The Apple II of 1977, with an NMOS 6502, Integer BASIC and the original Monitor or, on later boards, the
    ///  Autostart Monitor.
    /// </summary>
    II = 2,

    /// <summary>
    ///  The Apple II Plus, with an NMOS 6502, AppleSoft and the Autostart Monitor.
    /// </summary>
    IIPlus = 3
}
