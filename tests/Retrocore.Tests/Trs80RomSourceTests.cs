// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Security.Cryptography;
using System.Text.RegularExpressions;
using Retrocore.Assembler;
using Retrocore.Debug;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the SDK's native sources for the Model I ROMs: Level II 1.2 and 1.3, Level I and the character
///  generator.
/// </summary>
/// <remarks>
///  <para>
///   Digests pin each build, so no ROM is needed. With the dumps in <c>RETROCORE_TRS80_ROMS</c> or
///   <c>%USERPROFILE%\Retrocore\trs80-roms\extract</c> (Level II 1.2 is <c>rom-a.z1</c>-<c>rom-c.z3</c>,
///   1.3 the <c>_alt</c> parts), each also compares byte for byte, which names the first difference.
///  </para>
/// </remarks>
[TestClass]
public sealed partial class Trs80RomSourceTests
{
    /// <summary>
    ///  Level II builds byte-identically for each revision.
    /// </summary>
    /// <param name="revision">The revision.</param>
    /// <param name="expectedHash">The SHA-256 of that revision's 12K ROM.</param>
    [TestMethod]
    [DataRow(12, "3CD3824D2AC2743750D2179951ED812794302B885CCB4F98AA2579B352C4B00E")]
    [DataRow(13, "5515D95D7C19058400A2E91C6930BB557035DB5CE093BD96FD017F795C346776")]
    public void Level2MatchesTheRevision(int revision, string expectedHash)
    {
        AssemblyResult result = Trs80SdkModules.AssembleLevel2(Source("Level2.asm"), revision);
        result.Diagnostics.Should().BeEmpty();
        Hash(result).Should().Be(expectedHash);
    }

    /// <summary>
    ///  Level I and the character generator build byte-identically.
    /// </summary>
    [TestMethod]
    public void Level1AndCharacterGeneratorMatch()
    {
        string level1 = Hash(Trs80SdkModules.AssembleLevel1(Source("Level1.asm")));
        level1.Should().Be("74040B583672571038C8239695148194B073333CC7808C952CFECF2A78A20F8C");
        string characters = Hash(Trs80SdkModules.AssembleCharacterGenerator(Source("CharacterGenerator.asm")));
        characters.Should().Be("6DD67D0FDAF689E92BFE4DD78615A709BCE88CB3831427DA0E39D062BA9D9A23");
    }

    /// <summary>
    ///  The lowercase kit's character generator builds to its pinned image, and with xtrs's <c>trs_chars.c</c> in
    ///  <c>%USERPROFILE%\Retrocore\trs80-fonts\xtrs</c> it matches xtrs's reconstruction (CG 2) glyph for glyph.
    /// </summary>
    [TestMethod]
    public void LowercaseKitMatchesXtrs()
    {
        AssemblyResult result = Trs80SdkModules.AssembleCharacterGenerator(Source("CharacterGeneratorKit.asm"));
        result.Diagnostics.Should().BeEmpty();
        Hash(result).Should().Be("DC66592EB604EF7B6A123CF9E1ADB4E742CFC9029198FE22080A0A16548BE05E");

        string path = Path.Join(
            ExternalTestData.Root,
            "trs80-fonts",
            "xtrs",
            "trs_chars.c");

        if (!File.Exists(path)) { Assert.Inconclusive($"xtrs's font file ({path}) is missing."); }

        // xtrs keeps twelve rows a glyph with the leftmost dot in bit 0; the generator has eight with it in bit 4.
        string text = File.ReadAllText(path);
        int start = text.IndexOf("/* CG 2 - for Model I */", StringComparison.Ordinal);
        int end = text.IndexOf("/* CG 3 - for Model I */", StringComparison.Ordinal);
        start.Should().BeGreaterThan(0);
        List<byte> expected = [];
        foreach (Match glyph in XtrsGlyph().Matches(text[start..end]))
        {
            string[] rows = glyph.Groups[1].Value.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            for (int row = 0; row < 8; row++)
            {
                int dots = Convert.ToInt32(rows[row], fromBase: 16);
                int reversed = 0;
                for (int bit = 0; bit < 5; bit++) { reversed |= ((dots >> bit) & 1) << (4 - bit); }
                expected.Add((byte)reversed);
            }
        }

        expected.Should().HaveCount(Trs80SdkModules.CharacterGeneratorSize);
        ReadOnlySpan<byte> actual = result.Sections[0].Bytes.Span;
        int first = actual.CommonPrefixLength(expected.ToArray());
        first.Should().Be(actual.Length, $"the first difference is in glyph ${first / 8:X2}");
    }

    /// <summary>
    ///  Without REVISION, Level II builds 1.3, and the revision check knows both builds.
    /// </summary>
    [TestMethod]
    public void Level2DefaultsToTheLastRevision()
    {
        string path = Path.GetFullPath(Source("Level2.asm"));
        AssemblyResult result = new Assembler.Assembler().Assemble(
            new AssemblySource(File.ReadAllText(path), path),
            new AssemblyOptions("Z80", 0, Trs80SdkModules.Level2Size));

        Trs80SdkModules.RevisionOf(result.Sections[0].Bytes.Span).Should().Be(13);
        Trs80SdkModules.RevisionOf(Trs80SdkModules.AssembleLevel2(path, 12).Sections[0].Bytes.Span).Should().Be(12);
        Trs80SdkModules.RevisionOf(new byte[Trs80SdkModules.Level2Size]).Should().BeNull();
    }

    /// <summary>
    ///  With the dumps, each source compares byte for byte.
    /// </summary>
    /// <param name="file">The source.</param>
    /// <param name="revision">The Level II revision, or 0.</param>
    /// <param name="dumps">The dump files, concatenated.</param>
    [TestMethod]
    [DataRow("Level2.asm", 12, "rom-a.z1,rom-b.z2,rom-c.z3")]
    [DataRow("Level2.asm", 13, "rom-a_alt.z1,rom-b_alt.z2,rom-c_alt.z3")]
    [DataRow("Level1.asm", 0, "level1.rom")]
    [DataRow("CharacterGenerator.asm", 0, "mcm6670p.z29")]
    public void SourceMatchesTheDumps(string file, int revision, string dumps)
    {
        string directory = Environment.GetEnvironmentVariable("RETROCORE_TRS80_ROMS")
            ?? Path.Join(ExternalTestData.Root, "trs80-roms", "extract");

        string[] paths = [.. dumps.Split(',').Select(name => Path.Join(directory, name))];
        if (!paths.All(File.Exists)) { Assert.Inconclusive($"The Model I dumps ({dumps}) are missing."); }
        byte[] expected = [.. paths.SelectMany(File.ReadAllBytes)];
        AssemblyResult result = file switch
        {
            "Level2.asm" => Trs80SdkModules.AssembleLevel2(Source(file), revision),
            "Level1.asm" => Trs80SdkModules.AssembleLevel1(Source(file)),
            _ => Trs80SdkModules.AssembleCharacterGenerator(Source(file))
        };

        ReadOnlySpan<byte> actual = result.Sections[0].Bytes.Span;
        int first = actual.CommonPrefixLength(expected.AsSpan(0, actual.Length));
        first.Should().Be(actual.Length, $"the first difference is at ${first:X4}");
    }

    // One of xtrs's glyphs: twelve hexadecimal rows in braces.
    [GeneratedRegex(@"\{((?:\s*0x[0-9a-fA-F]{2}\s*,?){12})\s*\}")]
    private static partial Regex XtrsGlyph();

    private static string Source(string file) => Path.Join(AppContext.BaseDirectory, "Inputs", "Trs80", file);

    private static string Hash(AssemblyResult result) => Convert.ToHexString(SHA256.HashData(result.Sections[0].Bytes.Span));
}
