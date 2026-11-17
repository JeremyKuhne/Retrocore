// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using System.Text.RegularExpressions;
using Retrocore.Media;

namespace Retrocore.Debug;

/// <summary>
///  Apple Pascal's Assembler and Linker, run on an emulated Apple II Plus as <see cref="EmulatedPascalCompiler"/> runs
///  the Compiler: APPLE2 holds them, and their files go on a copy of APPLE1.
/// </summary>
internal static partial class EmulatedPascalTools
{
    /// <summary>
    ///  Assembles a 6502 source, such as a procedure a Pascal program declares EXTERNAL, with Apple's Assembler.
    /// </summary>
    /// <param name="source">The source, as plain text, in the Assembler's syntax.</param>
    /// <param name="bootDisk">APPLE1's image.</param>
    /// <param name="toolsDisk">APPLE2's image, with <c>SYSTEM.ASSMBLER</c> and <c>6500.OPCODES</c>.</param>
    /// <param name="roms">The SDK's ROM sources, or null for the copy beside the host.</param>
    /// <returns>The code file, or null when the Assembler flagged errors; and the screen when it finished.</returns>
    /// <exception cref="TimeoutException">The system never booted, or the Assembler never finished.</exception>
    internal static (byte[]? Code, string Screen) Assemble(string source, string bootDisk, string toolsDisk, string? roms = null)
    {
        // An Apple III Pascal system disk is SOS: its Assembler runs on an emulated Apple III.
        if (EmulatedApple3PascalTools.IsSos(bootDisk))
        {
            return EmulatedApple3PascalTools.Assemble(source, bootDisk, toolsDisk, roms);
        }

        byte[] boot = Apple1(bootDisk);
        PascalVolume.WriteFile(boot, proDosOrder: false, "SYSTEM.WRK.TEXT", PascalFileKind.Text, PascalTextFile.Write(source));

        EmulatedPascalSystem system = new(boot, toolsDisk, roms);
        system.Type("A");
        Expect(system, "LISTING", "The Assembler never asked for a listing");
        system.Type("\n");

        // It ends with its count of errors, or stops at an error with a prompt to edit, go on or stop.
        string ended = system.WaitFor(["ERRORS FLAGGED", "(CONTINUE)", "<ESC>"], seconds: 600)
            ?? throw new TimeoutException($"The Assembler never finished:\n{system.Screen}");

        string screen = system.Screen;
        if (ended != "ERRORS FLAGGED" || !Clean(screen)) { return (null, screen); }

        system.Run(tenths: 50);
        PascalVolume volume = system.Eject();
        return (volume.Files.Any(file => file.Name == "SYSTEM.WRK.CODE") ? volume.ReadFile("SYSTEM.WRK.CODE") : null, screen);
    }

    /// <summary>
    ///  Links a host code file, such as a compiled program with EXTERNAL procedures, with library code files, such as
    ///  assembled ones, with Apple's Linker.
    /// </summary>
    /// <param name="host">The host code file.</param>
    /// <param name="libraries">The library code files, in the order the Linker opens them.</param>
    /// <param name="bootDisk">APPLE1's image.</param>
    /// <param name="toolsDisk">APPLE2's image, with <c>SYSTEM.LINKER</c>.</param>
    /// <param name="roms">The SDK's ROM sources, or null for the copy beside the host.</param>
    /// <returns>The linked code file, or null when the Linker wrote none; and the screen when it finished.</returns>
    /// <exception cref="TimeoutException">The system never booted, or the Linker never finished.</exception>
    internal static (byte[]? Code, string Screen) Link(byte[] host, IReadOnlyList<byte[]> libraries, string bootDisk, string toolsDisk, string? roms = null)
    {
        if (EmulatedApple3PascalTools.IsSos(bootDisk))
        {
            return EmulatedApple3PascalTools.Link(host, libraries, bootDisk, toolsDisk, roms);
        }

        // The host is the workfile, each library by name; or, where they and the output do not fit on APPLE1, as 1.3's
        // Compiler's do not, all are on a volume of their own, LINK:, in a second card's first drive; and where they do
        // not fit there either, as Wizardry's do not, the output goes on OUT:, in its second.
        byte[] boot = Apple1(bootDisk);
        byte[]? link = Fits(boot, host, libraries) ? null : PascalVolume.Format("LINK", proDosOrder: false);
        bool alone = link is null || Fits(PascalVolume.Format("LINK", proDosOrder: false), host, libraries);
        byte[]? output = alone ? null : PascalVolume.Format("OUT", proDosOrder: false);
        byte[] files = link ?? boot;
        string volume = link is null ? "" : "LINK:";
        PascalVolume.WriteFile(files, proDosOrder: false, link is null ? "SYSTEM.WRK.CODE" : "HOST.CODE", PascalFileKind.Code, host);
        for (int index = 0; index < libraries.Count; index++)
        {
            PascalVolume.WriteFile(files, proDosOrder: false, $"LIB{index + 1}.CODE", PascalFileKind.Code, libraries[index]);
        }

        // Each library by name, then an empty line; no map; and the output.
        IReadOnlyList<byte[]>? more = link is null ? null : output is null ? [link] : [link, output];
        EmulatedPascalSystem system = new(boot, toolsDisk, roms, more);
        system.Type("L");
        Expect(system, "HOST FILE", "The Linker never asked for a host", or: "HOST CODEFILE");
        system.Type(link is null ? "\n" : "LINK:HOST\n");
        for (int index = 0; index <= libraries.Count; index++)
        {
            Expect(system, "LIB FILE", "The Linker never asked for a library", or: "LIBRARY FILE");
            system.Run(tenths: 5);
            system.Type(index < libraries.Count ? $"{volume}LIB{index + 1}\n" : "\n");
            system.Run(tenths: 20);
        }

        Expect(system, "MAP FILE", "The Linker never asked for a map");
        system.Type("\n");
        string? asked = system.WaitFor(["OUTPUT FILE"], seconds: 120);
        string screen = system.Screen;
        if (asked is null) { return (null, screen); }

        system.Type($"{(output is null ? volume : "OUT:")}LINKED.CODE\n");
        if (system.WaitFor(EmulatedPascalSystem.Prompts, seconds: 300) is null)
        {
            throw new TimeoutException($"The Linker never finished:\n{system.Screen}");
        }

        screen = system.Screen;
        system.Run(tenths: 50);
        PascalVolume written = link is null ? system.Eject() : system.EjectSlot5(drive: output is null ? 1 : 2);
        return (written.Files.Any(file => file.Name == "LINKED.CODE") ? written.ReadFile("LINKED.CODE") : null, screen);
    }

    // Whether the host, the libraries and the output, about as long as they, fit on APPLE1.
    private static bool Fits(byte[] boot, byte[] host, IReadOnlyList<byte[]> libraries)
    {
        byte[] copy = (byte[])boot.Clone();
        try
        {
            PascalVolume.WriteFile(copy, proDosOrder: false, "SYSTEM.WRK.CODE", PascalFileKind.Code, host);
            for (int index = 0; index < libraries.Count; index++)
            {
                PascalVolume.WriteFile(copy, proDosOrder: false, $"LIB{index + 1}.CODE", PascalFileKind.Code, libraries[index]);
            }

            PascalVolume.WriteFile(copy, proDosOrder: false, "LINKED.CODE", PascalFileKind.Code, new byte[host.Length + libraries.Sum(library => library.Length)]);
            return true;
        }
        catch (IOException)
        {
            return false;
        }
    }

    // APPLE1 with room for the files: the Editor, which none of this needs, is taken off.
    private static byte[] Apple1(string bootDisk)
    {
        byte[] boot = DiskImageFile.Sectors(bootDisk);
        PascalVolume.DeleteFile(boot, proDosOrder: false, "SYSTEM.EDITOR");
        return boot;
    }

    private static void Expect(EmulatedPascalSystem system, string text, string failure, string? or = null)
    {
        if (system.WaitFor(or is null ? [text] : [text, or], seconds: 300) is null)
        {
            throw new TimeoutException(string.Create(CultureInfo.InvariantCulture, $"{failure}:\n{system.Screen}"));
        }
    }

    // Whether the Assembler's last count of errors is none.
    private static bool Clean(string screen)
    {
        Match count = Errors().Match(screen);
        return count.Success && count.Groups[1].Value == "0";
    }

    [GeneratedRegex(@"(\d+)\s+ERRORS FLAGGED")]
    private static partial Regex Errors();
}
