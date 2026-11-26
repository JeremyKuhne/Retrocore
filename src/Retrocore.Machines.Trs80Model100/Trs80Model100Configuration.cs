// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Trs80Model100;

/// <summary>
///  How a Model 100 is built.
/// </summary>
public sealed class Trs80Model100Configuration
{
    /// <summary>
    ///  Gets or sets the RAM fitted: 8, 16, 24 or 32 KB, filled down from $FFFF. 32 by default.
    /// </summary>
    public int RamKilobytes { get; set; } = 32;

    /// <summary>
    ///  Gets or sets the time the clock starts at, or null for the host's local time when the machine is built.
    /// </summary>
    public DateTime? StartTime { get; set; }

    /// <summary>
    ///  Checks the configuration.
    /// </summary>
    /// <exception cref="ArgumentOutOfRangeException">The RAM is not 8, 16, 24 or 32 KB.</exception>
    public void Validate()
    {
        if (RamKilobytes is not (8 or 16 or 24 or 32))
        {
            throw new ArgumentOutOfRangeException(nameof(RamKilobytes), RamKilobytes, "The Model 100 takes 8, 16, 24 or 32 KB of RAM.");
        }
    }
}
