// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;

namespace Retrocore.Debug;

/// <summary>
///  The SDK's native sources for the TRS-80 ROMs, each byte-identical to the chips: the Model I's Level II BASIC
///  (revisions 1.2 and 1.3), Level I BASIC and MCM6670P character generator; the Model III's and Model 4's BASIC
///  and character generator; the Model 4P's boot ROM and character generator; and the Model II's boot ROMs and
///  character generator.
/// </summary>
internal static class Trs80SdkModules
{
    /// <summary>
    ///  Gets the size of the Level II ROM, $0000-$2FFF.
    /// </summary>
    internal const int Level2Size = 0x3000;

    /// <summary>
    ///  Gets the size of the Level I ROM, $0000-$0FFF.
    /// </summary>
    internal const int Level1Size = 0x1000;

    /// <summary>
    ///  Gets the size of the character generator.
    /// </summary>
    internal const int CharacterGeneratorSize = 0x400;

    /// <summary>
    ///  Gets the size of the Model III's and Model 4's ROM, $0000-$37FF.
    /// </summary>
    internal const int Model3Size = 0x3800;

    /// <summary>
    ///  Gets the size of the Model 4P's boot ROM.
    /// </summary>
    internal const int Model4PBootSize = 0x1000;

    /// <summary>
    ///  Gets the size of the Model II's boot ROM.
    /// </summary>
    internal const int Model2BootSize = 0x800;

    /// <summary>
    ///  Gets the size of the Model III's, 4P's and Model II's character generators.
    /// </summary>
    internal const int LargeCharacterGeneratorSize = 0x800;

    // Where the power-up messages differ: 1.2 asks "MEMORY SIZE", 1.3 "MEM SIZE".
    private const int MemorySizeMessage = 0x0105;

    /// <summary>
    ///  Gets the SDK's Model I ROM source directory beside the debug host.
    /// </summary>
    internal static string RomDirectory => Path.Join(SdkModules.RomDirectory, "Trs80");

    /// <summary>
    ///  Identifies the Level II revision of a ROM image.
    /// </summary>
    /// <param name="rom">The 12K Level II image.</param>
    /// <returns>12 or 13, or null when the image is neither revision's power-up message.</returns>
    internal static int? RevisionOf(ReadOnlySpan<byte> rom)
    {
        if (rom.Length < Level2Size) { return null; }
        ReadOnlySpan<byte> message = rom.Slice(MemorySizeMessage, 12);
        if (message.SequenceEqual("MEMORY SIZE\0"u8)) { return 12; }
        return message[..9].SequenceEqual("MEM SIZE\0"u8) ? 13 : null;
    }

    /// <summary>
    ///  Assembles Level II BASIC for a revision.
    /// </summary>
    /// <param name="path">The <c>Level2.asm</c> source.</param>
    /// <param name="revision">12 or 13, given to the source as <c>REVISION</c>.</param>
    /// <returns>The assembly, byte-identical to that revision's ROM.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleLevel2(string path, int revision) =>
        Assemble(path, Level2Size, new Dictionary<string, long> { ["REVISION"] = revision });

    /// <summary>
    ///  Assembles Level I BASIC.
    /// </summary>
    /// <param name="path">The <c>Level1.asm</c> source.</param>
    /// <returns>The assembly, byte-identical to the Level I ROM.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleLevel1(string path) => Assemble(path, Level1Size, symbols: null);

    /// <summary>
    ///  Assembles the character generator.
    /// </summary>
    /// <param name="path">
    ///  The <c>CharacterGenerator.asm</c> source, or <c>CharacterGeneratorKit.asm</c> for the lowercase kit's.
    /// </param>
    /// <returns>The 1K assembly: for the stock source, byte-identical to the MCM6670P.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleCharacterGenerator(string path) =>
        Assemble(path, CharacterGeneratorSize, symbols: null);

    /// <summary>
    ///  Assembles the Model III's or Model 4's ROM.
    /// </summary>
    /// <param name="path">The <c>Model3.asm</c> source.</param>
    /// <param name="model">3 or 4, given to the source as <c>MODEL</c>.</param>
    /// <param name="romC">For the Model III, the revision of ROM C: 'B' or 'C', given as <c>ROMC</c>.</param>
    /// <returns>The 14K assembly, byte-identical to that ROM.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleModel3(string path, int model, char romC = 'C') =>
        Assemble(path, Model3Size, new Dictionary<string, long> { ["MODEL"] = model, ["ROMC"] = romC });

    /// <summary>
    ///  Assembles the Model 4P's boot ROM.
    /// </summary>
    /// <param name="path">The <c>Model4PBoot.asm</c> source.</param>
    /// <returns>The 4K assembly, byte-identical to the ROM.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleModel4PBoot(string path) => Assemble(path, Model4PBootSize, symbols: null);

    /// <summary>
    ///  Assembles a Model II boot ROM.
    /// </summary>
    /// <param name="path">The <c>Model2Boot.asm</c> source.</param>
    /// <param name="version">1, 2, 3 or 5, given to the source as <c>VERSION</c>.</param>
    /// <param name="fill11Be">
    ///  Whether to build MAME's <c>cpu_11be</c>, version 3 with stray bytes in its unused space.
    /// </param>
    /// <returns>The 2K assembly, byte-identical to that ROM.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleModel2Boot(string path, int version, bool fill11Be = false) =>
        Assemble(
            path,
            Model2BootSize,
            new Dictionary<string, long> { ["VERSION"] = version, ["FILL_11BE"] = fill11Be ? 1 : 0 });

    /// <summary>
    ///  Assembles the Model III's and Model 4's character generator, or the 4P's.
    /// </summary>
    /// <param name="path">The <c>Model3CharacterGenerator.asm</c> source.</param>
    /// <param name="model4P">Whether to build the 4P's, given to the source as <c>MODEL4P</c>.</param>
    /// <returns>The 2K assembly, byte-identical to the chip.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleModel3CharacterGenerator(string path, bool model4P) =>
        Assemble(path, LargeCharacterGeneratorSize, new Dictionary<string, long> { ["MODEL4P"] = model4P ? 1 : 0 });

    /// <summary>
    ///  Assembles the Model II's character generator.
    /// </summary>
    /// <param name="path">The <c>Model2CharacterGenerator.asm</c> source.</param>
    /// <returns>The 2K assembly, byte-identical to the chip.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleModel2CharacterGenerator(string path) =>
        Assemble(path, LargeCharacterGeneratorSize, symbols: null);

    /// <summary>
    ///  Finds the build of a source that a ROM is, from a list of candidates.
    /// </summary>
    /// <param name="rom">The ROM the machine runs.</param>
    /// <param name="builds">The builds to try, in order.</param>
    /// <returns>The first build whose bytes are the ROM's, or null.</returns>
    internal static AssemblyResult? Matching(ReadOnlySpan<byte> rom, IEnumerable<Func<AssemblyResult>> builds)
    {
        foreach (Func<AssemblyResult> build in builds)
        {
            AssemblyResult result = build();
            if (result.Sections[0].Bytes.Span.SequenceEqual(rom)) { return result; }
        }

        return null;
    }

    private static AssemblyResult Assemble(string path, int size, Dictionary<string, long>? symbols)
    {
        string full = Path.GetFullPath(path);
        AssemblyOptions options = new("Z80", 0, size)
        {
            SourceResolver = new FileAssemblySourceResolver(),
            PredefinedSymbols = symbols ?? []
        };

        AssemblyResult result = new Assembler.Assembler().Assemble(new AssemblySource(File.ReadAllText(full), full), options);
        return result.Success
            ? result
            : throw new InvalidDataException(string.Join(Environment.NewLine, result.Diagnostics.Select(diagnostic => diagnostic.Message)));
    }
}
