// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.DiskTool;

/// <summary>
///  What to put on a DOS disk.
/// </summary>
internal sealed class DosDiskOptions
{
    /// <summary>
    ///  Gets which DOS: 3.3 or 3.2.
    /// </summary>
    public string Dos { get; init; } = "3.3";

    /// <summary>
    ///  Gets which DOS 3.3: 1983 or 1980.
    /// </summary>
    public int Year { get; init; } = 1983;

    /// <summary>
    ///  Gets a value indicating whether to write the System Master's relocatable DOS.
    /// </summary>
    public bool Master { get; init; }

    /// <summary>
    ///  Gets the volume number.
    /// </summary>
    public int Volume { get; init; } = 254;

    /// <summary>
    ///  Gets the folder of files to add, if any.
    /// </summary>
    public string? Files { get; init; }

    /// <summary>
    ///  Gets the file a generated HELLO runs, if any.
    /// </summary>
    public string? Run { get; init; }

    /// <summary>
    ///  Gets the image format, as an extension: .dsk, .do or .woz for DOS 3.3, .d13 or .woz for DOS 3.2.
    /// </summary>
    public string Format { get; init; } = ".dsk";

    /// <summary>
    ///  Gets the folder holding the <c>Dos</c> source folder, beside the <c>System</c> folder with the IIe equates
    ///  DOS includes; by default the tool's own.
    /// </summary>
    public string? Sources { get; init; }
}
