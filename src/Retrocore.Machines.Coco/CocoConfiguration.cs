// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Coco;

/// <summary>
///  How a Color Computer is built: its model, RAM and video chip.
/// </summary>
public sealed record CocoConfiguration
{
    /// <summary>
    ///  Gets the model.
    /// </summary>
    public CocoModel Model { get; init; } = CocoModel.Coco2;

    /// <summary>
    ///  Gets the RAM in kilobytes: 4, 16, 32 or 64 on a CoCo 1, 16 or 64 on a CoCo 2, 128 or 512 on a CoCo 3; null
    ///  picks the model's default (16, 64 and 128).
    /// </summary>
    public int? RamKilobytes { get; init; }

    /// <summary>
    ///  Gets whether a CoCo 1 or 2 has the MC6847T1, with true lowercase, as the CoCo 2B has.
    /// </summary>
    public bool LowercaseVdg { get; init; }

    /// <summary>
    ///  Gets the artifact colors a composite monitor shows in 256-dot two-color graphics.
    /// </summary>
    public CocoArtifactColors ArtifactColors { get; init; }

    /// <summary>
    ///  Gets whether a CoCo 3 shows its colors on the RGB monitor (the CM-8) rather than a composite one.
    /// </summary>
    public bool RgbMonitor { get; init; }

    /// <summary>
    ///  Gets the RAM in bytes, the default applied.
    /// </summary>
    public int RamBytes => (RamKilobytes ?? DefaultRamKilobytes(Model)) * 1024;

    /// <summary>
    ///  Gets a model's default RAM in kilobytes.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <returns>16 for a CoCo 1, 64 for a CoCo 2 and 128 for a CoCo 3.</returns>
    public static int DefaultRamKilobytes(CocoModel model) => model switch
    {
        CocoModel.Coco1 => 16,
        CocoModel.Coco2 => 64,
        _ => 128
    };

    /// <summary>
    ///  Checks that the parts fit the model.
    /// </summary>
    /// <exception cref="ArgumentException">A setting does not fit the model.</exception>
    internal void Validate()
    {
        int kilobytes = RamKilobytes ?? DefaultRamKilobytes(Model);
        bool valid = Model switch
        {
            CocoModel.Coco1 => kilobytes is 4 or 16 or 32 or 64,
            CocoModel.Coco2 => kilobytes is 16 or 64,
            _ => kilobytes is 128 or 512
        };

        if (!valid)
        {
            throw new ArgumentException(Model switch
            {
                CocoModel.Coco1 => "A CoCo 1 has 4, 16, 32 or 64 KB of RAM.",
                CocoModel.Coco2 => "A CoCo 2 has 16 or 64 KB of RAM.",
                _ => "A CoCo 3 has 128 or 512 KB of RAM."
            });
        }

        if (LowercaseVdg && Model == CocoModel.Coco3)
        {
            throw new ArgumentException("The CoCo 3's GIME has its own character set; the MC6847T1 is a CoCo 1 or 2 option.");
        }
    }
}
