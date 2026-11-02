// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;

namespace Retrocore.Debug;

/// <summary>
///  The SDK's native sources for the TRS-80 Model I ROMs: Level II BASIC (revisions 1.2 and 1.3), Level I
///  BASIC and the MCM6670P character generator, each byte-identical to the chips.
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
