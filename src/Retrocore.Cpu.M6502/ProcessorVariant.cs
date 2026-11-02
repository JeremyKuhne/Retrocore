// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.M6502;

/// <summary>
///  Identifies the processor whose instruction and bus behavior is emulated.
/// </summary>
public enum ProcessorVariant : byte
{
    /// <summary>
    ///  The NMOS MOS 6502.
    /// </summary>
    Mos6502,

    /// <summary>
    ///  The WDC W65C02S.
    /// </summary>
    Wdc65C02,

    /// <summary>
    ///  The Rockwell R65C02.
    /// </summary>
    Rockwell65C02
}
