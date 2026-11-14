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
        byte[] boot = Apple1(bootDisk);
        PascalVolume.WriteFile(boot, proDosOrder: false, "SYSTEM.WRK.TEXT", PascalFileKind.Text, PascalTextFile.Write(source));

        EmulatedPascalSystem system = new(boot, toolsDisk, roms);
        system.Type("A");
        Expect(system, "LISTING", "The Assembler never asked for a listing");
        system.Type("\n");

        // It ends with its count of errors, or stops at an error with a prompt to go on or stop.
        string ended = system.WaitFor(["ERRORS FLAGGED", "(CONTINUE)"], seconds: 600)
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
        byte[] boot = Apple1(bootDisk);
        PascalVolume.WriteFile(boot, proDosOrder: false, "SYSTEM.WRK.CODE", PascalFileKind.Code, host);
        for (int index = 0; index < libraries.Count; index++)
        {
            PascalVolume.WriteFile(boot, proDosOrder: false, $"LIB{index + 1}.CODE", PascalFileKind.Code, libraries[index]);
        }

        // The host is the workfile; each library by name, then an empty line; no map; and the output.
        EmulatedPascalSystem system = new(boot, toolsDisk, roms);
        system.Type("L");
        Expect(system, "HOST FILE", "The Linker never asked for a host");
        system.Type("\n");
        for (int index = 0; index <= libraries.Count; index++)
        {
            Expect(system, "LIB FILE", "The Linker never asked for a library");
            system.Run(tenths: 5);
            system.Type(index < libraries.Count ? $"LIB{index + 1}\n" : "\n");
            system.Run(tenths: 20);
        }

        Expect(system, "MAP FILE", "The Linker never asked for a map");
        system.Type("\n");
        string? asked = system.WaitFor(["OUTPUT FILE"], seconds: 120);
        string screen = system.Screen;
        if (asked is null) { return (null, screen); }

        system.Type("LINKED.CODE\n");
        Expect(system, "COMMAND: E(DIT", "The Linker never finished");
        screen = system.Screen;
        system.Run(tenths: 50);
        PascalVolume volume = system.Eject();
        return (volume.Files.Any(file => file.Name == "LINKED.CODE") ? volume.ReadFile("LINKED.CODE") : null, screen);
    }

    // APPLE1 with room for the files: the Editor, which none of this needs, is taken off.
    private static byte[] Apple1(string bootDisk)
    {
        byte[] boot = File.ReadAllBytes(bootDisk);
        PascalVolume.DeleteFile(boot, proDosOrder: false, "SYSTEM.EDITOR");
        return boot;
    }

    private static void Expect(EmulatedPascalSystem system, string text, string failure)
    {
        if (system.WaitFor([text], seconds: 300) is null)
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
