// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using System.Text.RegularExpressions;
using Retrocore.Media;

namespace Retrocore.Debug;

/// <summary>
///  Compiles a Pascal source with Apple Pascal's own Compiler, on an emulated Apple II Plus.
/// </summary>
/// <remarks>
///  <para>
///   The source goes onto a copy of the boot disk (APPLE1) as the workfile, <c>SYSTEM.WRK.TEXT</c>; the machine boots
///   with the Compiler's disk (APPLE2) in drive 2, C(ompile)s the workfile, and the code file it writes,
///   <c>SYSTEM.WRK.CODE</c>, is read back from the disk. Units the program uses come from APPLE1's
///   <c>SYSTEM.LIBRARY</c>, as on the machine.
///  </para>
/// </remarks>
internal static partial class EmulatedPascalCompiler
{
    /// <summary>
    ///  Compiles a source.
    /// </summary>
    /// <param name="source">The program, as plain text.</param>
    /// <param name="bootDisk">APPLE1's image, as a 140K <c>.dsk</c>.</param>
    /// <param name="compilerDisk">APPLE2's image, with <c>SYSTEM.COMPILER</c>.</param>
    /// <param name="roms">The SDK's ROM sources, or null for the copy beside the host.</param>
    /// <returns>
    ///  The code file the Compiler wrote, or null when it stopped with an error; and the screen when it finished, which
    ///  shows an error.
    /// </returns>
    /// <exception cref="TimeoutException">The system never booted, or the Compiler never finished.</exception>
    internal static (byte[]? Code, string Screen) Compile(string source, string bootDisk, string compilerDisk, string? roms = null)
    {
        (byte[]? code, string screen, _) = CompileWithListing(source, bootDisk, compilerDisk, listing: null, roms);
        return (code, screen);
    }

    /// <summary>
    ///  Compiles a source, and reads back the listing it asks for.
    /// </summary>
    /// <param name="source">The program, as plain text.</param>
    /// <param name="bootDisk">APPLE1's image, as a 140K <c>.dsk</c>.</param>
    /// <param name="compilerDisk">APPLE2's image, with <c>SYSTEM.COMPILER</c>.</param>
    /// <param name="listing">
    ///  The listing file the source's <c>(*$L APPLE1:NAME.TEXT*)</c> names, on APPLE1, to read back; null for none.
    /// </param>
    /// <param name="roms">The SDK's ROM sources, or null for the copy beside the host.</param>
    /// <returns>
    ///  The code file, or null on an error; the screen when it finished; and the listing's text, or null.
    /// </returns>
    /// <exception cref="TimeoutException">The system never booted, or the Compiler never finished.</exception>
    internal static (byte[]? Code, string Screen, string? Listing) CompileWithListing(
        string source,
        string bootDisk,
        string compilerDisk,
        string? listing,
        string? roms = null)
    {
        byte[] boot = File.ReadAllBytes(bootDisk);
        // A listing takes a free area of its own besides the code file's: APPLE1 has one, so the Editor, which a
        // compile does not need, makes room.
        if (listing is not null) { PascalVolume.DeleteFile(boot, proDosOrder: false, "SYSTEM.EDITOR"); }
        PascalVolume.WriteFile(boot, proDosOrder: false, "SYSTEM.WRK.TEXT", PascalFileKind.Text, PascalTextFile.Write(source));

        EmulatedPascalSystem system = new(boot, compilerDisk, roms);
        system.Type("C");

        // The Compiler ends with the space it had left, or stops at an error with a prompt to go on, stop or edit.
        string ended = system.WaitFor(["SMALLEST AVAILABLE", "(CONTINUE)"], seconds: 1_800)
            ?? throw new TimeoutException($"The Compiler never finished:\n{system.Screen}");

        string screen = system.Screen;
        if (ended != "SMALLEST AVAILABLE") { return (null, screen, null); }

        // The code file and listing are closed as the system comes back to its command line; its line is still on the
        // screen from before, so the wait is long enough for both.
        system.Run(tenths: listing is null ? 50 : 300);
        PascalVolume volume = system.Eject();
        string? text = listing is not null && volume.Files.Any(file => string.Equals(file.Name, listing, StringComparison.OrdinalIgnoreCase))
            ? PascalTextFile.Read(volume.ReadFile(listing))
            : null;

        if (!volume.Files.Any(file => file.Name == "SYSTEM.WRK.CODE")) { return (null, screen, text); }

        byte[] code = volume.ReadFile("SYSTEM.WRK.CODE");
        RestoreAlignment(code, source);
        return (code, screen, text);
    }

    /// <summary>
    ///  Puts back the bytes a decompiled source records after its <c>END.</c>, as
    ///  <c>(* Alignment bytes SEGMENT $OFFSET=$VALUE ... *)</c>: the byte the Compiler skips to put an LDC's or XJP's
    ///  words on a word boundary holds whatever its buffer had there, which no source says.
    /// </summary>
    /// <param name="code">The code file the Compiler wrote.</param>
    /// <param name="source">The source it compiled.</param>
    /// <returns>How many bytes were put back.</returns>
    internal static int RestoreAlignment(byte[] code, string source)
    {
        int restored = 0;
        foreach (Match recorded in AlignmentBytes().Matches(source))
        {
            string name = recorded.Groups["segment"].Value;
            for (int slot = 0; slot < 16; slot++)
            {
                string slotName = System.Text.Encoding.ASCII.GetString(code, 0x40 + (slot * 8), 8).TrimEnd();
                if (!string.Equals(slotName, name, StringComparison.OrdinalIgnoreCase)) { continue; }

                int start = (code[slot * 4] | (code[(slot * 4) + 1] << 8)) * 512;
                foreach (Match pad in Pad().Matches(recorded.Groups["pads"].Value))
                {
                    int at = start + int.Parse(pad.Groups["at"].Value, NumberStyles.HexNumber, CultureInfo.InvariantCulture);
                    if (at < code.Length && code[at] == 0)
                    {
                        code[at] = byte.Parse(pad.Groups["value"].Value, NumberStyles.HexNumber, CultureInfo.InvariantCulture);
                        restored++;
                    }
                }
            }
        }

        return restored;
    }

    [GeneratedRegex(@"\(\* Alignment bytes (?<segment>\S+) (?<pads>[^*]*)\*\)")]
    private static partial Regex AlignmentBytes();

    [GeneratedRegex(@"\$(?<at>[0-9A-F]{4})=\$(?<value>[0-9A-F]{2})")]
    private static partial Regex Pad();
}
