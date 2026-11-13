// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;

namespace Retrocore.Debug;

/// <summary>
///  The SDK's native sources for the Apple-1's firmware: the Monitor, the Apple Cassette Interface's PROM and the
///  terminal's Signetics 2513 character generator.
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
