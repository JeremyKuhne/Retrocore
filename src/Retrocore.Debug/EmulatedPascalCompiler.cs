// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using System.Text.RegularExpressions;
using Retrocore.Machines.Apple2;
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
    /// <param name="files">Code files to put beside the source, by name, such as the units it USES.</param>
    /// <returns>
    ///  The code file the Compiler wrote, or null when it stopped with an error; and the screen when it finished, which
    ///  shows an error.
    /// </returns>
    /// <exception cref="TimeoutException">The system never booted, or the Compiler never finished.</exception>
    internal static (byte[]? Code, string Screen) Compile(
        string source,
        string bootDisk,
        string compilerDisk,
        string? roms = null,
        IReadOnlyDictionary<string, byte[]>? files = null)
    {
        (byte[]? code, string screen, _) = CompileWithListing(source, bootDisk, compilerDisk, listing: null, roms, files);
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
    /// <param name="files">
    ///  Code files to put beside the source, by name, such as the units it USES, which its <c>(*$U NAME.CODE*)</c> names.
    /// </param>
    /// <param name="model">
    ///  The machine: a 64K II Plus, or a 128K IIe, where Apple Pascal 1.2 keeps code in auxiliary memory.
    /// </param>
    /// <returns>
    ///  The code file, or null on an error; the screen when it finished; and the listing's text, or null.
    /// </returns>
    /// <exception cref="TimeoutException">The system never booted, or the Compiler never finished.</exception>
    internal static (byte[]? Code, string Screen, string? Listing) CompileWithListing(
        string source,
        string bootDisk,
        string compilerDisk,
        string? listing,
        string? roms = null,
        IReadOnlyDictionary<string, byte[]>? files = null,
        Apple2Model model = Apple2Model.IIPlus)
    {
        // An Apple III Pascal system disk is SOS: its Compiler runs on an emulated Apple III.
        if (EmulatedApple3PascalTools.IsSos(bootDisk))
        {
            (byte[]? compiled, string shown, string? listed) = EmulatedApple3PascalTools.Compile(source, bootDisk, compilerDisk, listing, roms, files);
            if (compiled is not null) { RestoreAlignment(compiled, source); }
            return (compiled, shown, listed);
        }

        byte[] boot = DiskImageFile.Sectors(bootDisk);
        if (listing is null && files is null or { Count: 0 } && !Fits(boot, source))
        {
            return (CompileLarge(source, boot, compilerDisk, roms, model, out string large), large, null);
        }

        // A listing takes a free area of its own besides the code file's: APPLE1 has one, so the Editor, which a
        // compile does not need, makes room.
        if (listing is not null) { PascalVolume.DeleteFile(boot, proDosOrder: false, "SYSTEM.EDITOR"); }
        PascalVolume.WriteFile(boot, proDosOrder: false, "SYSTEM.WRK.TEXT", PascalFileKind.Text, PascalTextFile.Write(source));
        foreach ((string name, byte[] data) in files ?? new Dictionary<string, byte[]>())
        {
            PascalVolume.WriteFile(boot, proDosOrder: false, name, PascalFileKind.Code, data);
        }


        EmulatedPascalSystem system = new(boot, compilerDisk, roms, model: model);
        system.Type("C");

        // The Compiler ends with the space it had left, or stops at an error with a prompt to go on, stop or edit.
        string ended = Ended(system, seconds: 1_800);

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

    // Waits for the Compiler to end with the space it had left, or stop at an error or out of memory, which leaves the
    // system to be reset. 1.3 asks first for a listing
    // file, even of a workfile, which RETURN answers with none: a listing the source names is its own.
    private static string Ended(EmulatedPascalSystem system, int seconds)
    {
        string? ended = system.WaitFor(["SMALLEST AVAILABLE", "(CONTINUE)", "STACK OVERFLOW", "LISTING FILE"], seconds);
        if (ended == "LISTING FILE")
        {
            system.Type("\n");
            ended = system.WaitFor(["SMALLEST AVAILABLE", "(CONTINUE)", "STACK OVERFLOW"], seconds);
        }

        return ended ?? throw new TimeoutException($"The Compiler never finished:\n{system.Screen}");
    }

    // Whether a source fits on APPLE1 as the workfile, beside the code file the Compiler writes, about as long.
    private static bool Fits(byte[] boot, string source)
    {
        byte[] copy = (byte[])boot.Clone();
        byte[] text = PascalTextFile.Write(source);
        try
        {
            PascalVolume.WriteFile(copy, proDosOrder: false, "SYSTEM.WRK.TEXT", PascalFileKind.Text, text);
            PascalVolume.WriteFile(copy, proDosOrder: false, "SYSTEM.WRK.CODE", PascalFileKind.Code, new byte[text.Length / 2]);
            return true;
        }
        catch (IOException)
        {
            return false;
        }
    }

    // A source too long for APPLE1, such as a Compiler's own, goes on a volume of its own in a second card's first
    // drive, SOURCE:, and the code file onto another in its second, CODE:; the Compiler asks for both by name.
    private static byte[]? CompileLarge(string source, byte[] boot, string compilerDisk, string? roms, Apple2Model model, out string screen)
    {
        byte[] sources = PascalVolume.Format("SOURCE", proDosOrder: false);
        byte[] codes = PascalVolume.Format("CODE", proDosOrder: false);
        (string first, string? rest) = Split(source);
        PascalVolume.WriteFile(sources, proDosOrder: false, "PROGRAM.TEXT", PascalFileKind.Text, PascalTextFile.Write(first));
        if (rest is not null)
        {
            PascalVolume.WriteFile(codes, proDosOrder: false, "REST.TEXT", PascalFileKind.Text, PascalTextFile.Write(rest));
        }

        EmulatedPascalSystem system = new(boot, compilerDisk, roms, [sources, codes], model);
        system.Type("C");
        if (system.WaitFor(["COMPILE WHAT TEXT"], seconds: 30) is null)
        {
            throw new TimeoutException($"The Compiler never asked for its source:\n{system.Screen}");
        }

        system.Type("SOURCE:PROGRAM\n");
        if (system.WaitFor(["TO WHAT CODEFILE"], seconds: 30) is null)
        {
            throw new TimeoutException($"The Compiler never asked for its code file:\n{system.Screen}");
        }

        system.Type("CODE:PROGRAM\n");
        string ended = Ended(system, seconds: 7_200);

        screen = system.Screen;
        if (ended != "SMALLEST AVAILABLE") { return null; }

        system.Run(tenths: 50);
        PascalVolume volume = system.EjectSlot5(drive: 2);
        if (!volume.Files.Any(file => file.Name == "PROGRAM.CODE")) { return null; }

        byte[] code = volume.ReadFile("PROGRAM.CODE");
        RestoreAlignment(code, source);
        return code;
    }

    // A source too long for a volume of its own, such as Apple Pascal 1.3's Compiler's, is split before a procedure of
    // the outer block's, about halfway: the first part includes the rest, which goes on CODE: beside the code file.
    private static (string First, string? Included) Split(string source)
    {
        byte[] whole = PascalTextFile.Write(source);
        if (whole.Length <= 128 * 1024) { return (source, null); }

        string[] lines = source.Split('\n');
        int half = source.Length / 2;
        int length = 0;
        int split = -1;
        for (int index = 0; index < lines.Length && length < half; index++)
        {
            if (lines[index].StartsWith("  PROCEDURE ", StringComparison.Ordinal)
                || lines[index].StartsWith("  FUNCTION ", StringComparison.Ordinal)
                || lines[index].StartsWith("  SEGMENT ", StringComparison.Ordinal))
            {
                split = index;
            }

            length += lines[index].Length + 1;
        }

        if (split <= 0) { return (source, null); }

        string first = string.Join('\n', lines[..split]) + "\n(*$I CODE:REST.TEXT*)\n";
        return (first, string.Join('\n', lines[split..]));
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
