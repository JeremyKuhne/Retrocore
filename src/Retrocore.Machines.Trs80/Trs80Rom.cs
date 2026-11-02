// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Trs80;

/// <summary>
///  The BASIC in a Model I's ROM.
/// </summary>
public enum Trs80Rom : byte
{
    /// <summary>
    ///  Level II BASIC: 12K at <c>$0000</c>-<c>$2FFF</c>, with 500 baud cassettes.
    /// </summary>
    Level2,

    /// <summary>
    ///  Level I BASIC: 4K at <c>$0000</c>-<c>$0FFF</c>, with 250 baud cassettes.
    /// </summary>
    Level1
}
