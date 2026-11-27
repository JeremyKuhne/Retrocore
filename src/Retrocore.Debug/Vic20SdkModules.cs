// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Machines.Chips;

namespace Retrocore.Debug;

/// <summary>
///  Assembles the SDK's VIC-20 ROM sources: BASIC and the character ROM.
/// </summary>
/// <remarks>
///  <para>
///   BASIC runs past <c>$DFFF</c> into the kernal chip's first bytes, to <c>$E47B</c>; the kernal's own code begins
///   at <c>$E47C</c>.
///  </para>
/// </remarks>
internal static class Vic20SdkModules
{
    /// <summary>
    ///  The address BASIC starts at.
    /// </summary>
    internal const int BasicOrigin = 0xC000;

    /// <summary>
    ///  The address the kernal's own code starts at, after BASIC's last byte.
    /// </summary>
    internal const int KernalOrigin = 0xE47C;

    /// <summary>
    ///  The size of the character ROM.
    /// </summary>
    internal const int CharacterRomSize = 0x1000;

    /// <summary>
    ///  Gets the VIC-20 sources' directory beside the debug host.
    /// </summary>
    internal static string RomDirectory => Path.Join(SdkModules.RomDirectory, "Pet", "Vic20");

    /// <summary>
    ///  Assembles BASIC, <c>$C000-$E47B</c>.
    /// </summary>
    /// <param name="directory">The VIC-20 sources' directory.</param>
    /// <param name="standard">The video standard, which changes one byte of BASIC's part of the kernal chip.</param>
    /// <returns>The assembly.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleBasic(string directory, VicVideoStandard standard) => Assemble(
        Path.Join(directory, "Basic.asm"),
        BasicOrigin,
        KernalOrigin - BasicOrigin,
        standard);

    /// <summary>
    ///  Assembles the character ROM, 901460-03.
    /// </summary>
    /// <param name="directory">The VIC-20 sources' directory.</param>
    /// <returns>The assembly.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleCharacters(string directory) =>
        Assemble(Path.Join(directory, "CharacterGenerator.asm"), 0, CharacterRomSize, standard: null);

    private static AssemblyResult Assemble(string path, int origin, int size, VicVideoStandard? standard)
    {
        string full = Path.GetFullPath(path);
        AssemblyOptions options = new(ProcessorVariant.Mos6502, origin, size)
        {
            SourceResolver = new FileAssemblySourceResolver(),
            PredefinedSymbols = standard is { } given
                ? new Dictionary<string, long> { ["PAL"] = given == VicVideoStandard.Pal ? 1 : 0 }
                : []
        };

        AssemblyResult result = new Assembler.Assembler().Assemble(new AssemblySource(File.ReadAllText(full), full), options);
        return result.Success
            ? result
            : throw new InvalidDataException(string.Join(Environment.NewLine, result.Diagnostics.Select(diagnostic => diagnostic.Message)));
    }
}
