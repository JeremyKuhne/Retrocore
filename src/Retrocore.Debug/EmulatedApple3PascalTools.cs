// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.RegularExpressions;
using Retrocore.Media;

namespace Retrocore.Debug;

/// <summary>
///  Apple III Pascal's Compiler, Assembler and Linker, run on an emulated Apple III: the system disk (/PASCAL1) and the
///  tools (/PASCAL2) are Apple's, and the files go on a work volume, /WORK, in .D3.
/// </summary>
/// <remarks>
///  <para>
///   Apple III Pascal 1.1's two disks hold all three; for 1.2, build its disks as its update disks say, with
///   <c>--pascal sos</c>. Code files on SOS are file type $02, and text files $03.
///  </para>
/// </remarks>
internal static partial class EmulatedApple3PascalTools
{
    private const int TextType = 0x03;
    private const int CodeType = 0x02;

    /// <summary>
    ///  Gets whether a disk image holds a SOS volume, such as Apple III Pascal's, rather than a Pascal one.
    /// </summary>
    /// <param name="path">The image's path.</param>
    /// <returns>Whether it is SOS.</returns>
    internal static bool IsSos(string path)
    {
        try
        {
            _ = SosVolume.Read(File.ReadAllBytes(path), proDosOrder: false);
            return true;
        }
        catch (InvalidDataException)
        {
            return false;
        }
    }

    /// <summary>
    ///  Compiles a source with Apple III Pascal's Compiler.
    /// </summary>
    /// <param name="source">The program, as plain text.</param>
    /// <param name="systemDisk">/PASCAL1's image.</param>
    /// <param name="toolsDisk">/PASCAL2's image, with <c>SYSTEM.COMPILER</c>.</param>
    /// <param name="listing">A listing file's name to write on /WORK and read back, or null for none.</param>
    /// <param name="roms">The SDK's sources, or null for the copy beside the host.</param>
    /// <returns>The code file, or null on an error; the screen when it finished; and the listing, or null.</returns>
    /// <exception cref="TimeoutException">The system never booted, or the Compiler never finished.</exception>
    internal static (byte[]? Code, string Screen, string? Listing) Compile(
        string source,
        string systemDisk,
        string toolsDisk,
        string? listing,
        string? roms = null)
    {
        SosVolumeBuilder work = new("WORK");
        work.Add("SOURCE.TEXT", TextType, auxType: 0, PascalTextFile.Write(source));
        EmulatedApple3PascalSystem system = new(File.ReadAllBytes(systemDisk), File.ReadAllBytes(toolsDisk), work.Build(proDosOrder: false), roms);

        system.Type("C");
        Expect(system, "Compile what text?", "The Compiler never asked for its text");
        system.Type("/WORK/SOURCE\n");
        Expect(system, "To what codefile?", "The Compiler never asked for a code file");
        system.Type("/WORK/HOST\n");

        // 1.0's Compiler asks for no listing.
        if (system.WaitFor(["Listing file", "Apple /// Pascal Compiler"], seconds: 60) == "Listing file")
        {
            system.Type(listing is null ? "\n" : $"/WORK/{listing}\n");
        }

        // It ends with the space it had left, or stops at an error with a prompt to go on, stop or edit.
        string ended = system.WaitFor(["Smallest available space", "<esc>", "continue"], seconds: 1_800)
            ?? throw new TimeoutException($"The Compiler never finished:\n{system.Screen}");

        string screen = system.Screen;
        if (ended != "Smallest available space") { return (null, screen, null); }

        Expect(system, EmulatedApple3PascalSystem.CommandLine, "The system never came back from the Compiler");
        system.Run(tenths: 20);
        SosVolume volume = system.EjectWork();
        string? text = listing is not null && Has(volume, listing) ? PascalTextFile.Read(volume.ReadFile(listing)) : null;
        return (Has(volume, "HOST.CODE") ? volume.ReadFile("HOST.CODE") : null, screen, text);
    }

    /// <summary>
    ///  Assembles a 6502 source with Apple III Pascal's Assembler.
    /// </summary>
    /// <param name="source">The source, as plain text, in the Assembler's syntax.</param>
    /// <param name="systemDisk">/PASCAL1's image.</param>
    /// <param name="toolsDisk">/PASCAL2's image, with <c>SYSTEM.ASSMBLER</c> and <c>OPCODES.6502</c>.</param>
    /// <param name="roms">The SDK's sources, or null for the copy beside the host.</param>
    /// <returns>The code file, or null when the Assembler flagged errors; and the screen when it finished.</returns>
    /// <exception cref="TimeoutException">The system never booted, or the Assembler never finished.</exception>
    internal static (byte[]? Code, string Screen) Assemble(string source, string systemDisk, string toolsDisk, string? roms = null)
    {
        SosVolumeBuilder work = new("WORK");
        work.Add("SOURCE.TEXT", TextType, auxType: 0, PascalTextFile.Write(source));
        EmulatedApple3PascalSystem system = new(File.ReadAllBytes(systemDisk), File.ReadAllBytes(toolsDisk), work.Build(proDosOrder: false), roms);

        system.Type("A");
        Expect(system, "Assemble what text?", "The Assembler never asked for its text");
        system.Type("/WORK/SOURCE\n");
        Expect(system, "To what codefile?", "The Assembler never asked for a code file");
        system.Type("/WORK/ASSEMBLED\n");
        Expect(system, "Assembler listing", "The Assembler never asked for a listing");
        system.Type("\n");

        // It ends with its count of errors, or stops at an error with a prompt to edit, go on or stop.
        string ended = system.WaitFor(["Errors flagged", "<esc>"], seconds: 1_800)
            ?? throw new TimeoutException($"The Assembler never finished:\n{system.Screen}");

        string screen = system.Screen;
        Match count = Errors().Match(screen);
        if (ended != "Errors flagged" || !count.Success || count.Groups[1].Value != "0") { return (null, screen); }

        Expect(system, EmulatedApple3PascalSystem.CommandLine, "The system never came back from the Assembler");
        system.Run(tenths: 20);
        SosVolume volume = system.EjectWork();
        return (Has(volume, "ASSEMBLED.CODE") ? volume.ReadFile("ASSEMBLED.CODE") : null, screen);
    }

    /// <summary>
    ///  Links a host code file with library code files with Apple III Pascal's Linker.
    /// </summary>
    /// <param name="host">The host code file.</param>
    /// <param name="libraries">The library code files, in the order the Linker opens them.</param>
    /// <param name="systemDisk">/PASCAL1's image.</param>
    /// <param name="toolsDisk">/PASCAL2's image, with <c>SYSTEM.LINKER</c>.</param>
    /// <param name="roms">The SDK's sources, or null for the copy beside the host.</param>
    /// <returns>The linked code file, or null when the Linker wrote none; and the screen when it finished.</returns>
    /// <exception cref="TimeoutException">The system never booted, or the Linker never finished.</exception>
    internal static (byte[]? Code, string Screen) Link(
        byte[] host,
        IReadOnlyList<byte[]> libraries,
        string systemDisk,
        string toolsDisk,
        string? roms = null)
    {
        SosVolumeBuilder work = new("WORK");
        work.Add("HOST.CODE", CodeType, auxType: 0, host);
        for (int index = 0; index < libraries.Count; index++)
        {
            work.Add($"LIB{index + 1}.CODE", CodeType, auxType: 0, libraries[index]);
        }

        // The host by name; each library by name, then an empty line; no map; and the output.
        EmulatedApple3PascalSystem system = new(File.ReadAllBytes(systemDisk), File.ReadAllBytes(toolsDisk), work.Build(proDosOrder: false), roms);
        system.Type("L");
        Expect(system, "Host file?", "The Linker never asked for a host");
        system.Type("/WORK/HOST\n");
        for (int index = 0; index <= libraries.Count; index++)
        {
            Expect(system, index == 0 ? "Lib file?" : $"Opening /WORK/LIB{index}.CODE", "The Linker never asked for a library");
            system.Run(tenths: 5);
            system.Type(index < libraries.Count ? $"/WORK/LIB{index + 1}\n" : "\n");
        }

        Expect(system, "Map file?", "The Linker never asked for a map");
        system.Type("\n");
        string? asked = system.WaitFor(["Output file?"], seconds: 120);
        if (asked is null) { return (null, system.Screen); }

        system.Type("/WORK/LINKED\n");
        Expect(system, EmulatedApple3PascalSystem.CommandLine, "The Linker never finished");
        string screen = system.Screen;
        system.Run(tenths: 20);
        SosVolume volume = system.EjectWork();
        return (Has(volume, "LINKED.CODE") ? volume.ReadFile("LINKED.CODE") : null, screen);
    }

    private static bool Has(SosVolume volume, string name) =>
        volume.Files.Any(file => string.Equals(file.Name, name, StringComparison.OrdinalIgnoreCase));

    private static void Expect(EmulatedApple3PascalSystem system, string text, string failure)
    {
        if (system.WaitFor([text], seconds: 600) is null)
        {
            throw new TimeoutException($"{failure}:\n{system.Screen}");
        }
    }

    [GeneratedRegex(@"(\d+)\s+Errors flagged")]
    private static partial Regex Errors();
}
