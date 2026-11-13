// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;

namespace Retrocore.Debug;

/// <summary>
///  The SDK's native sources for the Apple-1's firmware: the Monitor, the Apple Cassette Interface's PROM and the
///  terminal's Signetics 2513 character generator; and Apple-1 BASIC, which loads from tape.
/// </summary>
internal static class Apple1SdkModules
{
    /// <summary>
    ///  Gets where the Monitor's PROMs start.
    /// </summary>
    internal const int MonitorOrigin = 0xFF00;

    /// <summary>
    ///  Gets where the cassette interface's PROM starts.
    /// </summary>
    internal const int CassetteOrigin = 0xC100;

    /// <summary>
    ///  Gets the SDK's Apple-1 ROM source directory beside the debug host.
    /// </summary>
    internal static string RomDirectory => Path.Join(SdkModules.RomDirectory, "Apple1");

    /// <summary>
    ///  Assembles the Monitor.
    /// </summary>
    /// <param name="path">The <c>WozMonitor.asm</c> source.</param>
    /// <returns>The 256-byte assembly at <c>$FF00</c>.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleMonitor(string path) => Assemble(path, MonitorOrigin, 0x100);

    /// <summary>
    ///  Assembles the cassette interface's PROM.
    /// </summary>
    /// <param name="path">The <c>Aci.asm</c> source.</param>
    /// <returns>The 256-byte assembly at <c>$C100</c>.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleCassette(string path) => Assemble(path, CassetteOrigin, 0x100);

    /// <summary>
    ///  Assembles the character generator.
    /// </summary>
    /// <param name="path">The <c>CharacterGenerator.asm</c> source.</param>
    /// <returns>The 512-byte assembly.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleCharacterGenerator(string path) => Assemble(path, 0, 0x200);

    /// <summary>
    ///  Gets where Apple-1 BASIC loads and starts.
    /// </summary>
    internal const int BasicOrigin = 0xE000;

    /// <summary>
    ///  Gets the size of Apple-1 BASIC, the 4K bank at <c>$E000</c>.
    /// </summary>
    internal const int BasicSize = 0x1000;

    /// <summary>
    ///  Gets the root of Apple-1 BASIC's source in a ROM source directory.
    /// </summary>
    /// <param name="roms">The directory that holds the Apple-1's sources.</param>
    /// <returns>The path of <c>Basic/Basic.asm</c>.</returns>
    internal static string BasicPath(string roms) => Path.Join(roms, "Basic", "Basic.asm");

    /// <summary>
    ///  Assembles Apple-1 BASIC.
    /// </summary>
    /// <param name="path">The <c>Basic.asm</c> source, which includes its modules.</param>
    /// <returns>The 4K assembly at <c>$E000</c>.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleBasic(string path) => Assemble(path, BasicOrigin, BasicSize);

    private static AssemblyResult Assemble(string path, int origin, int size)
    {
        string full = Path.GetFullPath(path);
        AssemblyOptions options = new("Mos6502", origin, size) { SourceResolver = new FileAssemblySourceResolver() };
        AssemblyResult result = new Assembler.Assembler().Assemble(new AssemblySource(File.ReadAllText(full), full), options);
        return result.Success
            ? result
            : throw new InvalidDataException(string.Join(Environment.NewLine, result.Diagnostics.Select(diagnostic => diagnostic.Message)));
    }
}
