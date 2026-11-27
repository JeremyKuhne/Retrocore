// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Machines.Chips;
using Retrocore.Machines.Commodore.Vic20;

namespace Retrocore.Debug;

/// <summary>
///  Assembles the SDK's VIC-20 ROM sources: BASIC, the kernal for NTSC or PAL, and the character ROM.
/// </summary>
/// <remarks>
///  <para>
///   BASIC runs past <c>$DFFF</c> into the kernal chip's first bytes, to <c>$E47B</c>, so the kernal chip is built
///   from both sources, as the PET's editor chip is.
///  </para>
/// </remarks>
internal static class Vic20SdkModules
{
    /// <summary>
    ///  The address BASIC starts at.
    /// </summary>
    internal const int BasicOrigin = 0xC000;

    /// <summary>
    ///  The address the kernal chip starts at.
    /// </summary>
    internal const int KernalChipOrigin = 0xE000;

    /// <summary>
    ///  The address the kernal's source starts at, after BASIC's last byte.
    /// </summary>
    internal const int KernalOrigin = 0xE47C;

    /// <summary>
    ///  The size of each 8K ROM chip.
    /// </summary>
    internal const int ChipSize = 0x2000;

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
    ///  Assembles the kernal, <c>$E47C-$FFFF</c>.
    /// </summary>
    /// <param name="directory">The VIC-20 sources' directory.</param>
    /// <param name="standard">The video standard: 901486-06 for NTSC, -07 for PAL.</param>
    /// <returns>The assembly.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleKernal(string directory, VicVideoStandard standard) => Assemble(
        Path.Join(directory, "Kernal.asm"),
        KernalOrigin,
        0x10000 - KernalOrigin,
        standard);

    /// <summary>
    ///  Assembles the character ROM, 901460-03.
    /// </summary>
    /// <param name="directory">The VIC-20 sources' directory.</param>
    /// <returns>The assembly.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleCharacters(string directory) =>
        Assemble(Path.Join(directory, "CharacterGenerator.asm"), 0, CharacterRomSize, standard: null);

    /// <summary>
    ///  Builds the ROMs from the sources, byte-identical to the chips: BASIC 901486-01, the kernal 901486-06 or -07,
    ///  and the characters 901460-03.
    /// </summary>
    /// <param name="standard">The video standard, which picks the kernal.</param>
    /// <param name="directory">The VIC-20 sources' directory, or null for the copy beside the debug host.</param>
    /// <returns>The ROMs.</returns>
    /// <exception cref="InvalidDataException">A source has errors.</exception>
    internal static Vic20Roms BuildRoms(VicVideoStandard standard, string? directory = null)
    {
        string roms = directory ?? RomDirectory;
        ReadOnlySpan<byte> basic = AssembleBasic(roms, standard).Sections[0].Bytes.Span;
        byte[] kernal = new byte[ChipSize];
        basic[ChipSize..].CopyTo(kernal);
        AssembleKernal(roms, standard).Sections[0].Bytes.Span.CopyTo(kernal.AsSpan(KernalOrigin - KernalChipOrigin));
        return new(basic[..ChipSize], kernal, AssembleCharacters(roms).Sections[0].Bytes.Span);
    }

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
