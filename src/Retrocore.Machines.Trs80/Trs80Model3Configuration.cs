// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Trs80;

/// <summary>
///  How a Model III, 4 or 4P is built.
/// </summary>
public sealed record Trs80Model3Configuration
{
    /// <summary>
    ///  Gets which machine of the family it is.
    /// </summary>
    public Trs80Model3Variant Variant { get; init; } = Trs80Model3Variant.Model3;

    /// <summary>
    ///  Gets the RAM in kilobytes: 16, 32 or 48 on a Model III, from <c>$4000</c>; 64 or 128 on a Model 4 or 4P,
    ///  the whole address space and, with 128, a second 64K bank.
    /// </summary>
    public int RamKilobytes { get; init; } = 48;

    /// <summary>
    ///  Gets whether the floppy disk controller is fitted. Without one, its status port reads <c>$FF</c> and the
    ///  ROM starts BASIC instead of booting a disk.
    /// </summary>
    public bool DiskController { get; init; } = true;

    /// <summary>
    ///  Gets the default RAM for a machine.
    /// </summary>
    /// <param name="variant">The machine.</param>
    /// <returns>48K for a Model III, 128K for a Model 4 or 4P.</returns>
    public static int DefaultRam(Trs80Model3Variant variant) => variant == Trs80Model3Variant.Model3 ? 48 : 128;

    /// <summary>
    ///  Gets whether the machine is a Model 4 or 4P.
    /// </summary>
    public bool IsModel4 => Variant != Trs80Model3Variant.Model3;

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

        if (IsModel4 ? RamKilobytes is not (64 or 128) : RamKilobytes is not (16 or 32 or 48))
        {
            throw new ArgumentException(IsModel4
                ? "A Model 4 or 4P has 64 or 128K of RAM."
                : "A Model III has 16, 32 or 48K of RAM.");
        }
    }
}
