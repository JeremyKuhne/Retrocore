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
    ///   volume; each file goes on the first volume with room for it, SOURCE:, the boot disk, or CODE:, which keeps
    ///   room for the code file, and its directive is given that volume's name. The main file goes on SOURCE:. The
    ///   Compiler includes no file from an included one, so only the main file's directives are read.
    ///  </para>
    /// </remarks>
    /// <param name="main">The main file's text.</param>
    /// <param name="included">The included files' texts, by name, such as <c>PASCALCO.TEXT</c>.</param>
    /// <param name="bootDisk">APPLE1's image.</param>
    /// <param name="compilerDisk">APPLE2's image, with <c>SYSTEM.COMPILER</c>.</param>
    /// <param name="roms">The SDK's ROM sources, or null for the copy beside the host.</param>
    /// <param name="model">The machine.</param>
    /// <returns>The code file, or null on an error; and the screen when it finished.</returns>
    /// <exception cref="IOException">The files do not fit on the volumes.</exception>
    internal static (byte[]? Code, string Screen) CompileFiles(
        string main,
        IReadOnlyDictionary<string, string> included,
        string bootDisk,
        string compilerDisk,
        string? roms = null,
        Apple2Model model = Apple2Model.IIPlus)
    {
        byte[] boot = DiskImageFile.Sectors(bootDisk);
        PascalVolume.DeleteFile(boot, proDosOrder: false, "SYSTEM.WRK.TEXT");
        (byte[] sources, byte[] codes) = FileVolumes(main, included, boot);
        byte[]? code = CompileFromVolumes(sources, codes, boot, compilerDisk, roms, model, out string screen);
        if (code is not null) { RestoreAlignment(code, main + string.Concat(included.Values)); }
        return (code, screen);
    }

    /// <summary>
    ///  Makes the volumes SOURCE: and CODE: for a main file and the files it includes.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   Each included file goes on SOURCE:, the boot disk or CODE:, whichever has room first, and the main file's
    ///   directive for it names where it is.
    ///  </para>
    /// </remarks>
    /// <param name="main">The main file's text.</param>
    /// <param name="included">The included files' texts, by name.</param>
    /// <param name="boot">The boot disk's image, which included files may go on, or null for none.</param>
    /// <returns>SOURCE:'s and CODE:'s images.</returns>
    /// <exception cref="IOException">The files do not fit, or a directive names no file given.</exception>
    internal static (byte[] Sources, byte[] Codes) FileVolumes(string main, IReadOnlyDictionary<string, string> included, byte[]? boot = null)
    {
        Dictionary<string, string> files = new(StringComparer.OrdinalIgnoreCase);
        foreach ((string name, string text) in included) { files[Normalized(name)] = text; }

        byte[] sources = PascalVolume.Format("SOURCE", proDosOrder: false);
        byte[] codes = PascalVolume.Format("CODE", proDosOrder: false);
        List<(string Name, byte[] Image)> volumes = [("SOURCE", sources)];
        if (boot is not null) { volumes.Add((PascalVolume.Read(boot, proDosOrder: false).Name, boot)); }
        volumes.Add(("CODE", codes));
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

        foreach (string name in placed.Keys.ToList())
        {
            byte[] text = PascalTextFile.Write(files[name]);
            for (int on = 0; ; on++)
            {
                try
                {
                    PascalVolume.WriteFile(volumes[on].Image, proDosOrder: false, name, PascalFileKind.Text, text);
                    placed[name] = volumes[on].Name;
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
