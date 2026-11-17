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
        // Apple Pascal 1.0's APPLE1 comes with a workfile, which C(ompile) would take without asking.
        PascalVolume.DeleteFile(boot, proDosOrder: false, "SYSTEM.WRK.TEXT");
        (byte[] sources, byte[] codes) = Volumes(source, boot);
        byte[]? code = CompileFromVolumes([sources, codes], boot, DiskImageFile.Sectors(compilerDisk), roms, model, out screen);
        if (code is not null) { RestoreAlignment(code, source); }
        return code;
    }

    // Compiles SOURCE:PROGRAM to CODE:PROGRAM, SOURCE: and CODE: in a second Disk II in slot 5.
    // Compiles SOURCE:PROGRAM to CODE:PROGRAM: the volumes are SOURCE: and CODE:, in slot 5, then any in slot 4.
    private static byte[]? CompileFromVolumes(IReadOnlyList<byte[]> volumes, byte[] boot, byte[] tools, string? roms, Apple2Model model, out string screen)
    {
        EmulatedPascalSystem system = new(boot, tools, roms, volumes, model);
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

        return Trimmed(volume.ReadFile("PROGRAM.CODE"));
    }

    // A code file without the blocks of zeros after what the Compiler wrote: the file keeps as many blocks as the
    // volume had free after it, which the Linker then cannot copy onto its own.
    private static byte[] Trimmed(byte[] code)
    {
        const int Block = 512;
        int end = code.Length - (code.Length % Block);
        while (end > Block && !code.AsSpan(end - Block, Block).ContainsAnyExcept((byte)0)) { end -= Block; }
        return code[..end];
    }

    // The characters of source in each piece of one too long for a volume of its own, longest first: shorter pieces
    // leave the main file less of the source.
    private static readonly int[] s_pieceLengths = [40 * 1024, 32 * 1024, 24 * 1024, 16 * 1024, 12 * 1024];

    // The blocks the code file needs on CODE:, Apple Pascal 1.3's Compiler's and some.
    private const int CodeBlocks = 100;

    /// <summary>
    ///  Makes the volumes SOURCE: and CODE: for a source too long for APPLE1.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   A source too long for a volume of its own, such as Apple Pascal 1.3's Compiler's, is cut before procedures of
    ///   the outer block into pieces of about 40K characters, or less where the main file would not fit: the main
    ///   file, <c>PROGRAM.TEXT</c>, keeps every other piece and includes each of the others where it was, as
    ///   <c>INCn.TEXT</c>, as the Compiler includes no file from an included one. The main file goes on SOURCE:, and
    ///   each included file beside it while it fits, then on the boot disk's room, then on CODE:, which keeps room for
    ///   the code file.
    ///  </para>
    /// </remarks>
    /// <param name="source">The source.</param>
    /// <param name="boot">The boot disk's image, which included files may go on, or null for none.</param>
    /// <returns>SOURCE:'s and CODE:'s images.</returns>
    /// <exception cref="IOException">The source does not fit on the volumes.</exception>
    internal static (byte[] Sources, byte[] Codes) Volumes(string source, byte[]? boot = null)
    {
        IOException? last = null;
        foreach (int length in s_pieceLengths)
        {
            byte[]? copy = boot is null ? null : (byte[])boot.Clone();
            try
            {
                (byte[] Sources, byte[] Codes) volumes = Volumes(Pieces(source, length), copy);
                if (boot is not null && copy is not null) { copy.CopyTo(boot, 0); }
                return volumes;
            }
            catch (IOException tooLong)
            {
                last = tooLong;
            }
        }

        throw new IOException($"The source does not fit on SOURCE: and CODE:: {last?.Message}", last);
    }

    // SOURCE: and CODE: for a source's pieces, the included ones on SOURCE:, the boot disk or CODE:, in that order.
    private static (byte[] Sources, byte[] Codes) Volumes(List<string> pieces, byte[]? boot)
    {
        byte[] sources = PascalVolume.Format("SOURCE", proDosOrder: false);
        byte[] codes = PascalVolume.Format("CODE", proDosOrder: false);
        List<(string Name, byte[] Image)> volumes = [("SOURCE", sources)];
        if (boot is not null) { volumes.Add((PascalVolume.Read(boot, proDosOrder: false).Name, boot)); }
        volumes.Add(("CODE", codes));
        List<string> included = [.. pieces.Where((_, index) => index % 2 == 1)];

        // Each directive is as long on any volume, so the main file is as long whichever each piece goes on.
        int longest = volumes.Max(volume => volume.Name.Length);
        string Directive(int number, int on) =>
            $"(*$I {volumes[on].Name}:INC{number}.TEXT{new string(' ', longest - volumes[on].Name.Length)}*)\n";

        string Main(IReadOnlyList<int> on) => string.Concat(pieces.Select((piece, index) =>
            index % 2 == 0 ? piece : Directive((index / 2) + 1, on[index / 2])));

        int[] placed = new int[included.Count];
        PascalVolume.WriteFile(sources, proDosOrder: false, "PROGRAM.TEXT", PascalFileKind.Text, PascalTextFile.Write(Main(placed)));
        for (int number = 1; number <= included.Count; number++)
        {
            byte[] text = PascalTextFile.Write(included[number - 1]);
            for (int on = 0; ; on++)
            {
                try
                {
                    PascalVolume.WriteFile(volumes[on].Image, proDosOrder: false, $"INC{number}.TEXT", PascalFileKind.Text, text);
                    placed[number - 1] = on;
                    break;
                }
                catch (IOException) when (on < volumes.Count - 1)
                {
                }
            }
        }

        // The code file needs its room after the included files.
        PascalVolume.WriteFile((byte[])codes.Clone(), proDosOrder: false, "ROOM.CODE", PascalFileKind.Code, new byte[CodeBlocks * 512]);

        _ = PascalVolume.DeleteFile(sources, proDosOrder: false, "PROGRAM.TEXT");
        PascalVolume.WriteFile(sources, proDosOrder: false, "PROGRAM.TEXT", PascalFileKind.Text, PascalTextFile.Write(Main(placed)));
        return (sources, codes);
    }

    // A source too long for a volume of its own in pieces, cut before procedures of the outer block, each but the
    // last at least the length given; one that fits is one piece.
    private static List<string> Pieces(string source, int pieceLength)
    {
        if (PascalTextFile.Write(source).Length <= 128 * 1024) { return [source]; }

        string[] lines = source.Split('\n');
        List<string> pieces = [];
        int start = 0;
        int length = 0;
        for (int index = 0; index < lines.Length; index++)
        {
            bool outer = lines[index].StartsWith("  PROCEDURE ", StringComparison.Ordinal)
                || lines[index].StartsWith("  FUNCTION ", StringComparison.Ordinal)
                || lines[index].StartsWith("  SEGMENT ", StringComparison.Ordinal);

            if (outer && length >= pieceLength && index > start)
            {
                pieces.Add(string.Join('\n', lines[start..index]) + "\n");
                start = index;
                length = 0;
            }

            length += lines[index].Length + 1;
        }

        pieces.Add(string.Join('\n', lines[start..]));
        return pieces;
    }

    /// <summary>
    ///  Splits a source too long for a volume of its own, such as an Apple III Pascal Compiler's, before the first
    ///  procedure of the outer block past halfway: the first part includes the rest, at most half, which goes on
    ///  another volume beside the code file.
    /// </summary>
    /// <param name="source">The source.</param>
    /// <param name="included">The included file's name, as the first part's <c>$I</c> option names it.</param>
    /// <param name="limit">The longest text file, in bytes, left whole.</param>
    /// <returns>The first part, and the rest, or null when the source is left whole.</returns>
    internal static (string First, string? Included) Split(string source, string included, int limit)
    {
        if (PascalTextFile.Write(source).Length <= limit) { return (source, null); }

        string[] lines = source.Split('\n');
        int half = source.Length / 2;
        int length = 0;
        int split = -1;
        for (int index = 0; index < lines.Length && split < 0; index++)
        {
            bool heading = lines[index].StartsWith("  PROCEDURE ", StringComparison.Ordinal)
                || lines[index].StartsWith("  FUNCTION ", StringComparison.Ordinal)
                || lines[index].StartsWith("  SEGMENT ", StringComparison.Ordinal);

            if (heading && length >= half) { split = index; }
            length += lines[index].Length + 1;
        }

        if (split <= 0) { return (source, null); }

        string first = string.Join('\n', lines[..split]) + $"\n(*$I {included}*)\n";
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
