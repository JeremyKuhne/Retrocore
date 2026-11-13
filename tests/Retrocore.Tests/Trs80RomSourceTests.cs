// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Security.Cryptography;
using System.Text.RegularExpressions;
using Retrocore.Assembler;
using Retrocore.Debug;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the SDK's native sources for the TRS-80 ROMs: the Model I's Level II 1.2 and 1.3, Level I and character
///  generator; the Model III's and Model 4's ROM and character generator; the 4P's boot ROM and character generator;
///  and the Model II's boot ROMs and character generator.
/// </summary>
/// <remarks>
///  <para>
///   Digests pin each build, so no ROM is needed. With the dumps in <c>RETROCORE_TRS80_ROMS</c> or
///   <c>%USERPROFILE%\Retrocore\trs80-roms\extract</c> (Level II 1.2 is <c>rom-a.z1</c>-<c>rom-c.z3</c>,
///   1.3 the <c>_alt</c> parts, and the others are under MAME's names), each also compares byte for byte, which names
///   the first difference.
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
    ///  The Model III's ROM builds byte-identically with either revision of ROM C, and the Model 4's.
    /// </summary>
    /// <param name="model">3 or 4.</param>
    /// <param name="romC">The Model III's ROM C revision.</param>
    /// <param name="expectedHash">The SHA-256 of the 14K ROM.</param>
    [TestMethod]
    [DataRow(3, 'C', "010FD04E1A7B48583685A5554F12ECFF8DB681C926CAA1814F148D552CA53708")]
    [DataRow(3, 'B', "2B3AAB007C784128941B71AD72E2FA669FE9584EC9E93C432DE46C306649EDE5")]
    [DataRow(4, 'C', "89AB093F1B4234B8265122ECD4F45D7CDA5C1A0B26EC929BCE32C1756E826133")]
    public void Model3MatchesTheRom(int model, char romC, string expectedHash)
    {
        AssemblyResult result = Trs80SdkModules.AssembleModel3(Source("Model3.asm"), model, romC);
        result.Diagnostics.Should().BeEmpty();
        Hash(result).Should().Be(expectedHash);
    }

    /// <summary>
    ///  Each Model II boot ROM builds byte-identically.
    /// </summary>
    /// <param name="version">The version.</param>
    /// <param name="fill11Be">Whether to build <c>cpu_11be</c>.</param>
    /// <param name="expectedHash">The SHA-256 of the 2K ROM.</param>
    [TestMethod]
    [DataRow(1, false, "6F211D269F490C50DEDF0733B8531C272AF10E3F6D88A0F7D0EA6CC8924293A8")]
    [DataRow(2, false, "3FBFCC68E8DE9CF9E84663A33661FAE9969190C139B954548256A5C01A9662FB")]
    [DataRow(3, false, "95E326C1DDB703177B1CFF3DDE696B800CD14A01F1027505DE60E1A2CFF0FE71")]
    [DataRow(3, true, "2D0CA46374211C25751FF57BF01FCAAACB7044982B1E50E075BD60D4A6159B8E")]
    [DataRow(5, false, "D6DD67F601A6E1B4D99F6FD729AAA9BC3F628D39B9ADF25261D2ED95622B09C1")]
    public void Model2BootMatchesTheRom(int version, bool fill11Be, string expectedHash)
    {
        AssemblyResult result = Trs80SdkModules.AssembleModel2Boot(Source("Model2Boot.asm"), version, fill11Be);
        result.Diagnostics.Should().BeEmpty();
        Hash(result).Should().Be(expectedHash);
    }

    /// <summary>
    ///  The 4P's boot ROM and the Model III's, 4P's and Model II's character generators build byte-identically.
    /// </summary>
    [TestMethod]
    public void Model4PBootAndCharacterGeneratorsMatch()
    {
        string boot = Hash(Trs80SdkModules.AssembleModel4PBoot(Source("Model4PBoot.asm")));
        boot.Should().Be("6C1E5D5CCD280EE01D9F852B60DDEC07E719A45699A6220EABD50DF9999632C6");
        string model3 = Source("Model3CharacterGenerator.asm");
        string characters = Hash(Trs80SdkModules.AssembleModel3CharacterGenerator(model3, model4P: false));
        characters.Should().Be("BA09F130D24E17DCBBC16290A2F357C731F0D96BF76530F5B80EFFF84376BB01");
        string model4P = Hash(Trs80SdkModules.AssembleModel3CharacterGenerator(model3, model4P: true));
        model4P.Should().Be("F567F196D93E4C169B3DEFF9EF923A1B41D91ACB3F0D91AB350AD41FE59E6273");
        string model2 = Hash(Trs80SdkModules.AssembleModel2CharacterGenerator(Source("Model2CharacterGenerator.asm")));
        model2.Should().Be("1F38CF71BAB4C66BF9BBCB1D3019515971640325FCAA771F32B2AA7CA5AE8232");
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
    /// <param name="variant">
    ///  The Level II revision; the Model III's ROM C revision, or 4 for the Model 4; the Model II boot ROM's version,
    ///  or 4 for <c>cpu_11be</c>; 1 for the 4P's character generator; or 0.
    /// </param>
    /// <param name="dumps">The dump files, concatenated.</param>
    [TestMethod]
    [DataRow("Level2.asm", 12, "rom-a.z1,rom-b.z2,rom-c.z3")]
    [DataRow("Level2.asm", 13, "rom-a_alt.z1,rom-b_alt.z2,rom-c_alt.z3")]
    [DataRow("Level1.asm", 0, "level1.rom")]
    [DataRow("CharacterGenerator.asm", 0, "mcm6670p.z29")]
    [DataRow("Model3.asm", (int)'C', "8041364.u104,8040332.u105,8040316c.u106")]
    [DataRow("Model3.asm", (int)'B', "8041364.u104,8040332.u105,8040316b.u106")]
    [DataRow("Model3.asm", 4, "trs80m4.rom")]
    [DataRow("Model4PBoot.asm", 0, "8075332.u69")]
    [DataRow("Model2Boot.asm", 1, "8043216.u11")]
    [DataRow("Model2Boot.asm", 2, "8047316.u11")]
    [DataRow("Model2Boot.asm", 3, "cpu_2119.u11")]
    [DataRow("Model2Boot.asm", 4, "cpu_11be.u11")]
    [DataRow("Model2Boot.asm", 5, "u54.u11")]
    [DataRow("Model3CharacterGenerator.asm", 0, "8044316a.u36")]
    [DataRow("Model3CharacterGenerator.asm", 1, "8049007.u103")]
    [DataRow("Model2CharacterGenerator.asm", 0, "8043316.u9")]
    public void SourceMatchesTheDumps(string file, int variant, string dumps)
    {
        string directory = Environment.GetEnvironmentVariable("RETROCORE_TRS80_ROMS")
            ?? Path.Join(ExternalTestData.Root, "trs80-roms", "extract");

        string[] paths = [.. dumps.Split(',').Select(name => Path.Join(directory, name))];
        if (!paths.All(File.Exists)) { Assert.Inconclusive($"The dumps ({dumps}) are missing."); }
        byte[] expected = [.. paths.SelectMany(File.ReadAllBytes)];
        AssemblyResult result = file switch
        {
            "Level2.asm" => Trs80SdkModules.AssembleLevel2(Source(file), variant),
            "Level1.asm" => Trs80SdkModules.AssembleLevel1(Source(file)),
            "Model3.asm" => variant == 4
                ? Trs80SdkModules.AssembleModel3(Source(file), 4)
                : Trs80SdkModules.AssembleModel3(Source(file), 3, (char)variant),
            "Model4PBoot.asm" => Trs80SdkModules.AssembleModel4PBoot(Source(file)),
            "Model2Boot.asm" => variant == 4
                ? Trs80SdkModules.AssembleModel2Boot(Source(file), 3, fill11Be: true)
                : Trs80SdkModules.AssembleModel2Boot(Source(file), variant),
            "Model3CharacterGenerator.asm" => Trs80SdkModules.AssembleModel3CharacterGenerator(Source(file), variant == 1),
            "Model2CharacterGenerator.asm" => Trs80SdkModules.AssembleModel2CharacterGenerator(Source(file)),
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
