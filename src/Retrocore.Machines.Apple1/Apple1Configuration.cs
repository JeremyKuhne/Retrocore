// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Apple1;

/// <summary>
///  How an Apple-1 is built: its memory and the cards fitted to it.
/// </summary>
public sealed record Apple1Configuration
{
    /// <summary>
    ///  Gets the RAM in kilobytes from <c>$0000</c>: 4, as shipped, or 8 with the second row of chips there.
    /// </summary>
    public int RamKilobytes { get; init; } = 4;

    /// <summary>
    ///  Gets whether a 4K bank of RAM is jumpered to <c>$E000</c>-<c>$EFFF</c>, where BASIC loads and runs.
    /// </summary>
    public bool HighRam { get; init; } = true;

    /// <summary>
    ///  Gets whether the Apple Cassette Interface is in the expansion slot, with its PROM at <c>$C100</c>.
    /// </summary>
    public bool CassetteInterface { get; init; } = true;

    /// <summary>
    ///  Checks the configuration.
    /// </summary>
    /// <exception cref="ArgumentException">The RAM size is not one the board takes.</exception>
    internal void Validate()
    {
        if (RamKilobytes is not (4 or 8))
        {
            throw new ArgumentException("An Apple-1 has 4 or 8K of RAM from $0000.");
        }
    }
}
