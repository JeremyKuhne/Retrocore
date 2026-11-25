// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Atari;

/// <summary>
///  A cartridge's hardware, numbered as <c>.car</c> files' headers number them.
/// </summary>
public enum AtariCartridgeType
{
    /// <summary>
    ///  8 KB at <c>$A000-$BFFF</c> in the left slot.
    /// </summary>
    Standard8 = 1,

    /// <summary>
    ///  16 KB at <c>$8000-$BFFF</c> in the left slot.
    /// </summary>
    Standard16 = 2,

    /// <summary>
    ///  Williams 64 KB: eight 8 KB banks at <c>$A000</c>, chosen by an access to <c>$D500-$D507</c>; an access to
    ///  <c>$D508-$D50F</c> turns the cartridge off.
    /// </summary>
    Williams64 = 8,

    /// <summary>
    ///  Express 64 KB: as Williams, at <c>$D570-$D57F</c>, the bank number inverted.
    /// </summary>
    Express64 = 9,

    /// <summary>
    ///  Diamond 64 KB: as Express, at <c>$D5D0-$D5DF</c>.
    /// </summary>
    Diamond64 = 10,

    /// <summary>
    ///  XEGS 32 KB: a bank written to <c>$D5xx</c> at <c>$8000-$9FFF</c>, the last bank fixed at <c>$A000</c>.
    /// </summary>
    Xegs32 = 12,

    /// <summary>
    ///  XEGS 64 KB.
    /// </summary>
    Xegs64 = 13,

    /// <summary>
    ///  XEGS 128 KB.
    /// </summary>
    Xegs128 = 14,

    /// <summary>
    ///  OSS 091M, one 16 KB chip: three 4 KB banks at <c>$A000</c> chosen by an access to <c>$D5xx</c>, the first 4 KB
    ///  fixed at <c>$B000</c>.
    /// </summary>
    Oss091 = 15,

    /// <summary>
    ///  8 KB at <c>$8000-$9FFF</c> in the 800's right slot.
    /// </summary>
    Right8 = 21,

    /// <summary>
    ///  Williams 32 KB: four banks.
    /// </summary>
    Williams32 = 22,

    /// <summary>
    ///  XEGS 256 KB.
    /// </summary>
    Xegs256 = 23,

    /// <summary>
    ///  XEGS 512 KB.
    /// </summary>
    Xegs512 = 24,

    /// <summary>
    ///  XEGS 1 MB.
    /// </summary>
    Xegs1024 = 25,

    /// <summary>
    ///  Atarimax 128 KB: sixteen banks at <c>$A000</c> chosen by an access to <c>$D500-$D50F</c>; <c>$D510-$D51F</c>
    ///  turns the cartridge off.
    /// </summary>
    Atarimax128 = 41,

    /// <summary>
    ///  Atarimax 1 MB: 128 banks, <c>$D500-$D57F</c>; <c>$D580-$D5FF</c> turns it off.
    /// </summary>
    Atarimax1024 = 42,

    /// <summary>
    ///  OSS 8 KB: two 4 KB banks at <c>$A000</c>, the first fixed at <c>$B000</c>.
    /// </summary>
    Oss8 = 44
}
