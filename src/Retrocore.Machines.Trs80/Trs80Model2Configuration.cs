// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Trs80;

/// <summary>
///  How a Model II, 12 or 16 is built.
/// </summary>
public sealed record Trs80Model2Configuration
{
    /// <summary>
    ///  Gets which machine of the family it is.
    /// </summary>
    public Trs80Model2Variant Variant { get; init; } = Trs80Model2Variant.Model2;

    /// <summary>
    ///  Gets the RAM in kilobytes: 32 to 512, in 32K banks. The first 32K is always at <c>$0000</c>; port
    ///  <c>$FF</c> selects which further bank appears at <c>$8000</c>.
    /// </summary>
    public int RamKilobytes { get; init; } = 64;

    /// <summary>
    ///  Checks the configuration.
    /// </summary>
    /// <exception cref="ArgumentException">The RAM size is not one the machine has.</exception>
    internal void Validate()
    {
        if (!Enum.IsDefined(Variant))
        {
            throw new ArgumentException("The machine is not defined.");
        }

        if (RamKilobytes is < 32 or > 512 || RamKilobytes % 32 != 0)
        {
            throw new ArgumentException("A Model II has 32 to 512K of RAM, in 32K banks.");
        }
    }
}
