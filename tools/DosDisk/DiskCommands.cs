// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.DiskTool;

/// <summary>
///  The tool's commands.
/// </summary>
internal static class DiskCommands
{
    /// <summary>
    ///  Builds a bootable DOS disk image from the SDK's DOS sources and a folder of files.
    /// </summary>
    /// <param name="output">-o, The image to write: .dsk or .do (DOS 3.3), .d13 (DOS 3.2), or .woz.</param>
    /// <param name="files">
    ///  -f, A folder of files to put on the disk. NAME.bas is an AppleSoft listing, NAME.txt a text file, and
    ///  NAME#TTAAAA (CiderPress II's naming) a file of ProDOS type TT: 04 text, FA Integer BASIC, FC AppleSoft,
    ///  or 06 binary with load address AAAA.
    /// </param>
    /// <param name="run">-r, Writes a HELLO that runs this file: BRUN for a binary, RUN for a program.</param>
    /// <param name="dos">Which DOS: 3.3 (the default) or 3.2, the 13-sector DOS.</param>
    /// <param name="year">Which DOS 3.3: 1983 (the default) or 1980.</param>
    /// <param name="master">Writes the System Master's relocatable DOS rather than DOS as INIT writes it.</param>
    /// <param name="volume">The volume number, 1 to 254.</param>
    /// <returns>0 on success, 1 on an error.</returns>
    public static int Build(
        string output,
        string? files = null,
        string? run = null,
        string dos = "3.3",
        int year = 1983,
        bool master = false,
        int volume = 254)
    {
        try
        {
            byte[] image = DosDiskBuilder.Build(
                new DosDiskOptions
                {
                    Dos = dos,
                    Year = year,
                    Master = master,
                    Volume = volume,
                    Files = files,
                    Run = run,
                    Format = Path.GetExtension(output)
                });

            File.WriteAllBytes(output, image);
            Console.WriteLine($"Wrote {output}.");
            return 0;
        }
        catch (Exception exception) when (exception is ArgumentException or IOException or InvalidDataException)
        {
            Console.Error.WriteLine(exception.Message);
            return 1;
        }
    }
}
