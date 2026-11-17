// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;

namespace Retrocore.Debug;

/// <summary>
///  The SDK's native sources for the Kaypro II's ROMs, each byte-identical to the chips: the 81-149C monitor ROM and
///  the 81-146A character generator; and for MBASIC 5.21, byte-identical to MBASIC.COM.
/// </summary>
internal static class KayproSdkModules
{
    /// <summary>
    ///  Gets the size of the monitor ROM.
    /// </summary>
    internal const int MonitorSize = 0x800;

    /// <summary>
    ///  Gets the size of the character generator.
    /// </summary>
    internal const int CharacterGeneratorSize = 0x800;

    /// <summary>
    ///  Gets the monitor ROM's source file name.
    /// </summary>
    internal const string MonitorSource = "Kaypro2.asm";

    /// <summary>
    ///  Gets the character generator's source file name.
    /// </summary>
    internal const string CharacterGeneratorSource = "Kaypro2CharacterGenerator.asm";

    /// <summary>
    ///  Gets MBASIC's source file name.
    /// </summary>
    internal const string MbasicSource = "Mbasic.asm";

    /// <summary>
    ///  Gets where MBASIC loads, CP/M's transient program area.
    /// </summary>
    internal const int MbasicOrigin = 0x0100;

    /// <summary>
    ///  Gets MBASIC.COM's size.
    /// </summary>
    internal const int MbasicSize = 0x5F00;

    /// <summary>
    ///  Gets the SDK's Kaypro ROM source directory beside the debug host.
    /// </summary>
    internal static string RomDirectory => Path.Join(SdkModules.RomDirectory, "Kaypro");

    /// <summary>
    ///  Gets the directory that holds the Kaypro sources: the one given if it holds them, else its <c>Kaypro</c> folder.
    /// </summary>
    /// <param name="directory">The SDK ROM directory, or null for the one beside the debug host.</param>
    /// <returns>The directory.</returns>
    internal static string SourceDirectory(string? directory)
    {
        if (directory is null) { return RomDirectory; }
        return File.Exists(Path.Join(directory, MonitorSource)) ? directory : Path.Join(directory, "Kaypro");
    }

    /// <summary>
    ///  Assembles the monitor ROM.
    /// </summary>
    /// <param name="path">The <c>Kaypro2.asm</c> source.</param>
    /// <returns>The 2K assembly, byte-identical to the 81-149C ROM.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleMonitor(string path) => Assemble(path, MonitorSize);

    /// <summary>
    ///  Assembles the character generator.
    /// </summary>
    /// <param name="path">The <c>Kaypro2CharacterGenerator.asm</c> source.</param>
    /// <returns>The 2K assembly, byte-identical to the 81-146A chip.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleCharacterGenerator(string path) => Assemble(path, CharacterGeneratorSize);

    /// <summary>
    ///  Assembles MBASIC.
    /// </summary>
    /// <param name="path">The <c>Mbasic.asm</c> source.</param>
    /// <returns>The assembly, byte-identical to MBASIC.COM from <c>$0100</c>.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleMbasic(string path) => Assemble(path, MbasicSize, MbasicOrigin);

    private static AssemblyResult Assemble(string path, int size, int origin = 0)
    {
        string full = Path.GetFullPath(path);
        AssemblyOptions options = new("Z80", origin, size) { SourceResolver = new FileAssemblySourceResolver() };
        AssemblyResult result = new Assembler.Assembler().Assemble(new AssemblySource(File.ReadAllText(full), full), options);
        return result.Success
            ? result
            : throw new InvalidDataException(string.Join(Environment.NewLine, result.Diagnostics.Select(diagnostic => diagnostic.Message)));
    }
}
