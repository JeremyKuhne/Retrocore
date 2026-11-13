// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  The code a segment of an Apple Pascal code file holds, from its segment information.
/// </summary>
public enum PascalMachineType
{
    /// <summary>
    ///  Not given, as in an older code file.
    /// </summary>
    Unknown = 0,

    /// <summary>
    ///  P-code, with words most significant byte first.
    /// </summary>
    PcodeMostFirst = 1,

    /// <summary>
    ///  P-code, with words least significant byte first, as the 6502's interpreters take it.
    /// </summary>
    PcodeLeastFirst = 2,

    /// <summary>
    ///  PDP-11 code.
    /// </summary>
    Pdp11 = 3,

    /// <summary>
    ///  8080 code.
    /// </summary>
    I8080 = 4,

    /// <summary>
    ///  Z80 code.
    /// </summary>
    Z80 = 5,

    /// <summary>
    ///  GA 440 code.
    /// </summary>
    Ga440 = 6,

    /// <summary>
    ///  6502 code.
    /// </summary>
    M6502 = 7,

    /// <summary>
    ///  6800 code.
    /// </summary>
    M6800 = 8,

    /// <summary>
    ///  TI 9900 code.
    /// </summary>
    Ti9900 = 9
}
