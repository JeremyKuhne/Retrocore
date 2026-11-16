// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.RegularExpressions;
using Retrocore.Machines.Apple2;
using Retrocore.Media;

namespace Retrocore.Debug;

internal static partial class EmulatedPascalCompiler
{
    /// <summary>
    ///  Compiles a source made of a main file and the files it includes, on Apple Pascal's own Compiler.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The main file's <c>(*$I NAME.TEXT*)</c> and <c>{$I NAME.TEXT}</c> directives name the included files without a
    ///   volume; each file goes on the first volume with room for it, SOURCE:, the boot disk (without the Filer, and
    ///   without the library where the source uses no units), APPLE2 (without the
    ///   Assembler, the Linker and the other tools a compile does not run), CODE:, which keeps room for the code
    ///   file, or MORE1: and MORE2:, the drives of a third Disk II card, in slot 4 (Pascal's units
    ///   9 and 10), which is there only where they are needed; and its directive is given that volume's name. The
    ///   main file goes on SOURCE:. The Compiler includes no file from an included one, so only the main file's
    ///   directives are read.
    ///  </para>
    /// </remarks>
    /// <param name="main">The main file's text.</param>
    /// <param name="included">The included files' texts, by name, such as <c>PASCALCO.TEXT</c>.</param>
    /// <param name="bootDisk">APPLE1's image.</param>
    /// <param name="compilerDisk">APPLE2's image, with <c>SYSTEM.COMPILER</c>.</param>
    /// <param name="roms">The SDK's ROM sources, or null for the copy beside the host.</param>
    /// <param name="model">The machine.</param>
    /// <param name="codeBlocks">The blocks CODE: keeps for the code file, or null for 1.3's Compiler's.</param>
    /// <returns>The code file, or null on an error; and the screen when it finished.</returns>
    /// <exception cref="IOException">The files do not fit on the volumes.</exception>
    internal static (byte[]? Code, string Screen) CompileFiles(
        string main,
        IReadOnlyDictionary<string, string> included,
        string bootDisk,
        string compilerDisk,
        string? roms = null,
        Apple2Model model = Apple2Model.IIPlus,
        int? codeBlocks = null)
    {
        byte[] boot = DiskImageFile.Sectors(bootDisk);
        PascalVolume.DeleteFile(boot, proDosOrder: false, "SYSTEM.WRK.TEXT");

        // The boot disk takes files too, without the Filer, which a compile does not run, and without the library
        // where the source uses no units.
        _ = PascalVolume.DeleteFile(boot, proDosOrder: false, "SYSTEM.FILER");
        if (!UsesUnits(main + string.Concat(included.Values)))
        {
            _ = PascalVolume.DeleteFile(boot, proDosOrder: false, "SYSTEM.LIBRARY");
        }

        // APPLE2 takes files too, without the tools a compile does not run.
        byte[] tools = DiskImageFile.Sectors(compilerDisk);
        foreach (string unused in s_notCompiling) { _ = PascalVolume.DeleteFile(tools, proDosOrder: false, unused); }

        (byte[] sources, byte[] codes, IReadOnlyList<byte[]> more) = FileVolumes(main, included, boot, tools, codeBlocks);
        byte[]? code = CompileFromVolumes([sources, codes, .. more], boot, tools, roms, model, out string screen);
        if (code is not null) { RestoreAlignment(code, main + string.Concat(included.Values)); }
        return (code, screen);
    }

    /// <summary>
    ///  Makes the volumes SOURCE: and CODE: for a main file and the files it includes.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   Each included file goes on SOURCE:, the boot disk, the Compiler's disk, CODE: (while it keeps room for the
    ///   code file), MORE1: or MORE2:, whichever has room first, the longest files first, and the main file's
    ///   directive for it names where it is.
    ///  </para>
    /// </remarks>
    /// <param name="main">The main file's text.</param>
    /// <param name="included">The included files' texts, by name.</param>
    /// <param name="boot">The boot disk's image, which included files may go on, or null for none.</param>
    /// <param name="tools">The Compiler's disk's image, which included files may go on after the boot disk.</param>
    /// <param name="codeBlocks">The blocks CODE: keeps for the code file, or null for 1.3's Compiler's.</param>
    /// <returns>SOURCE:'s and CODE:'s images, and MORE1:'s and MORE2:'s where files went on them.</returns>
    /// <exception cref="IOException">The files do not fit, or a directive names no file given.</exception>
    internal static (byte[] Sources, byte[] Codes, IReadOnlyList<byte[]> More) FileVolumes(
        string main,
        IReadOnlyDictionary<string, string> included,
        byte[]? boot = null,
        byte[]? tools = null,
        int? codeBlocks = null)
    {
        Dictionary<string, string> files = new(StringComparer.OrdinalIgnoreCase);
        foreach ((string name, string text) in included) { files[Normalized(name)] = text; }

        byte[] sources = PascalVolume.Format("SOURCE", proDosOrder: false);
        byte[] codes = PascalVolume.Format("CODE", proDosOrder: false);
        List<(string Name, byte[] Image)> volumes = [("SOURCE", sources)];
        if (boot is not null) { volumes.Add((PascalVolume.Read(boot, proDosOrder: false).Name, boot)); }
        if (tools is not null) { volumes.Add((PascalVolume.Read(tools, proDosOrder: false).Name, tools)); }
        volumes.Add(("CODE", codes));
        int code = volumes.Count - 1;
        volumes.Add(("MORE1", PascalVolume.Format("MORE1", proDosOrder: false)));
        volumes.Add(("MORE2", PascalVolume.Format("MORE2", proDosOrder: false)));
        int longest = volumes.Max(volume => volume.Name.Length);

        List<Match> directives = [.. IncludeDirective().Matches(main).Where(match => !match.Groups["name"].Value.Contains(':', StringComparison.Ordinal))];
        foreach (Match directive in directives)
        {
            if (!files.ContainsKey(Normalized(directive.Groups["name"].Value)))
            {
                throw new IOException($"The main file includes {directive.Groups["name"].Value}, which is not given.");
            }
        }

        // The main file is as long whichever volume each directive names: each is padded to the longest name's.
        string Main(IReadOnlyDictionary<string, string> on) => IncludeDirective().Replace(main, match =>
        {
            string name = Normalized(match.Groups["name"].Value);
            if (!on.TryGetValue(name, out string? volume)) { return match.Value; }

            string padding = new(' ', longest - volume.Length);
            return match.Value.StartsWith('{') ? $"{{$I {volume}:{name}{padding}}}" : $"(*$I {volume}:{name}{padding}*)";
        });

        Dictionary<string, string> placed = new(StringComparer.OrdinalIgnoreCase);
        foreach (Match directive in directives)
        {
            placed[Normalized(directive.Groups["name"].Value)] = volumes[0].Name;
        }

        PascalVolume.WriteFile(sources, proDosOrder: false, "PROGRAM.TEXT", PascalFileKind.Text, PascalTextFile.Write(Main(placed)));

        // The longest first, which leaves the shorter to fill the room the longer leave.
        int used = code;
        foreach (string name in placed.Keys.OrderByDescending(name => files[name].Length).ToList())
        {
            byte[] text = PascalTextFile.Write(files[name]);
            for (int on = 0; ; on++)
            {
                try
                {
                    PascalVolume.WriteFile(volumes[on].Image, proDosOrder: false, name, PascalFileKind.Text, text);
                    if (on == code && !HasRoomForCode(codes, codeBlocks ?? CodeBlocks))
                    {
                        _ = PascalVolume.DeleteFile(codes, proDosOrder: false, name);
                        continue;
                    }

                    placed[name] = volumes[on].Name;
                    used = Math.Max(used, on);
                    break;
                }
                catch (IOException) when (on < volumes.Count - 1)
                {
                }
            }
        }

        _ = PascalVolume.DeleteFile(sources, proDosOrder: false, "PROGRAM.TEXT");
        PascalVolume.WriteFile(sources, proDosOrder: false, "PROGRAM.TEXT", PascalFileKind.Text, PascalTextFile.Write(Main(placed)));
        return (sources, codes, [.. volumes[(code + 1)..(used + 1)].Select(volume => volume.Image)]);
    }

    // Whether CODE: still has room for the code file, of so many blocks, after the included files on it.
    private static bool HasRoomForCode(byte[] codes, int blocks)
    {
        try
        {
            PascalVolume.WriteFile((byte[])codes.Clone(), proDosOrder: false, "ROOM.CODE", PascalFileKind.Code, new byte[blocks * 512]);
            return true;
        }
        catch (IOException)
        {
            return false;
        }
    }

    /// <summary>
    ///  Whether a source uses units: has USES outside its comments and strings.
    /// </summary>
    /// <param name="source">The source.</param>
    /// <returns>Whether it does.</returns>
    internal static bool UsesUnits(string source) =>
        UsesWord().IsMatch(CommentOrString().Replace(source, " "));

    // A comment, (*...*) or {...}, or a string.
    [GeneratedRegex(@"\(\*.*?\*\)|\{[^}]*\}|'[^'\n]*'", RegexOptions.Singleline)]
    private static partial Regex CommentOrString();

    [GeneratedRegex(@"\bUSES\b", RegexOptions.IgnoreCase)]
    private static partial Regex UsesWord();

    // APPLE2's files that compiling does not need: its other tools.
    private static readonly string[] s_notCompiling =
        ["SYSTEM.ASSMBLER", "SYSTEM.LINKER", "LIBRARY.CODE", "LIBMAP.CODE", "6502.OPCODES", "6502.ERRORS"];

    // A file's name on a volume: in capitals, with .TEXT.
    private static string Normalized(string name)
    {
        string upper = name.Trim().ToUpperInvariant();
        return upper.EndsWith(".TEXT", StringComparison.Ordinal) ? upper : $"{upper}.TEXT";
    }

    // An include directive, (*$I NAME*) or {$I NAME}, whose name follows a blank: $I- and $I+ are options.
    [GeneratedRegex(@"\(\*\$I\s+(?<name>[^*\s]+)\s*\*\)|\{\$I\s+(?<name>[^}\s]+)\s*\}", RegexOptions.IgnoreCase)]
    private static partial Regex IncludeDirective();
}
