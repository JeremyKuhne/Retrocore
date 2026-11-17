// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  The machines a launch configuration's <c>machine</c> can name.
/// </summary>
internal static class DebugMachines
{
    /// <summary>
    ///  The Apple II family; the launch's <c>model</c> says which.
    /// </summary>
    internal const string Apple2 = "apple2";

    /// <summary>
    ///  The Apple IIe's name before the family shared one, which launches may still use for <see cref="Apple2"/>.
    /// </summary>
    internal const string Apple2e = "apple2e";

    /// <summary>
    ///  The TRS-80 Model I, with Level II or Level I BASIC.
    /// </summary>
    internal const string Trs80Model1 = "trs80-model1";

    /// <summary>
    ///  The TRS-80 Model III, 4 or 4P; the launch's <c>model</c> says which.
    /// </summary>
    internal const string Trs80Model3 = "trs80-model3";

    /// <summary>
    ///  The Model 4's own name, which launches may use for <see cref="Trs80Model3"/> with the Model 4 as its default.
    /// </summary>
    internal const string Trs80Model4 = "trs80-model4";

    /// <summary>
    ///  The TRS-80 Model II, 12 or 16; the launch's <c>model</c> says which.
    /// </summary>
    internal const string Trs80Model2 = "trs80-model2";

    /// <summary>
    ///  The Apple III.
    /// </summary>
    internal const string Apple3 = "apple3";

    /// <summary>
    ///  The Apple-1, with the Woz Monitor and the Apple Cassette Interface.
    /// </summary>
    internal const string Apple1 = "apple1";

    /// <summary>
    ///  The TRS-80 Color Computer 1, 2 or 3; the launch's <c>model</c> says which.
    /// </summary>
    internal const string Coco = "coco";

    /// <summary>
    ///  The MITS Altair 8800.
    /// </summary>
    internal const string Altair = "altair";

    /// <summary>
    ///  Gets the machine a launch names.
    /// </summary>
    /// <param name="machine">The launch's <c>machine</c> value.</param>
    /// <returns>The machine's identifier.</returns>
    /// <exception cref="ArgumentException">The value is missing or names no known machine.</exception>
    internal static string Require(string? machine) => machine switch
    {
        Apple2 or Apple2e => Apple2,
        Trs80Model1 => Trs80Model1,
        Trs80Model3 or Trs80Model4 => Trs80Model3,
        Trs80Model2 => Trs80Model2,
        Apple3 => Apple3,
        Apple1 => Apple1,
        Coco => Coco,
        Altair => Altair,
        null => throw new ArgumentException($"machine is required, such as \"{Apple2}\", \"{Apple3}\", \"{Trs80Model1}\" or \"{Coco}\"."),
        _ => throw new ArgumentException(
            $"Unknown machine \"{machine}\"; the known machines are \"{Apple2}\", \"{Apple1}\", \"{Apple3}\", \"{Trs80Model1}\", "
                + $"\"{Trs80Model2}\", \"{Trs80Model3}\", \"{Trs80Model4}\", \"{Coco}\" and \"{Altair}\".")
    };
}
