// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Security.Cryptography;
using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Documentation;
using Retrocore.Machines.Chips;
using Retrocore.Machines.Commodore.Vic20;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the SDK's sources for the VIC-20's ROMs: BASIC, 901486-01, the kernal, 901486-06 and -07, and the
///  character ROM, 901460-03.
/// </summary>
/// <remarks>
///  <para>
///   Digests pin each build, so no ROM is needed. With the dumps (see <see cref="Vic20MachineTests"/>), a build that
///   differs names its first different byte.
///  </para>
/// </remarks>
[TestClass]
public sealed class Vic20RomSourceTests
{
    // The documents the kernal's old names cite.
    private static readonly string[] s_kernalKeys = ["KV20", "MTV", "V20PRG"];

    // Fewer old names than this means the check found almost none: the kernal keeps about 800.
    private const int MinimumKernalOldNames = 700;

    private static string Sources => Path.Join(BasicNames.Inputs, "Pet", "Vic20");

    /// <summary>
    ///  The character ROM builds byte-identically to 901460-03: the PET 2001-N's sets with £ and reversed copies.
    /// </summary>
    [TestMethod]
    public void CharactersMatchTheChip()
    {
        ReadOnlySpan<byte> image = Vic20SdkModules.AssembleCharacters(Sources).Sections[0].Bytes.Span;
        image.Length.Should().Be(0x1000);
        string hash = Convert.ToHexString(SHA256.HashData(image));
        if (hash == "BDA280726CFE069CA70EF5E2F2D95A29F69D3950C859A12E6979464963FCF502") { return; }

        string because = "the digest pins the chip (without its dump the first different byte can't be named)";
        string chip = Path.Join(Vic20MachineTests.RomDirectory(VicVideoStandard.Ntsc), "901460-03.ud7");
        if (File.Exists(chip))
        {
            because = $"the first difference is at ${image.CommonPrefixLength(File.ReadAllBytes(chip)):X3}";
        }

        hash.Should().Be("BDA280726CFE069CA70EF5E2F2D95A29F69D3950C859A12E6979464963FCF502", because);
    }

    /// <summary>
    ///  The reversed copy of each set is its set with every dot the other way round, as the VIC-20's editor expects:
    ///  it stores a reversed character as its code plus $80.
    /// </summary>
    [TestMethod]
    public void EachSetIsFollowedByItsReversedCopy()
    {
        ReadOnlySpan<byte> image = Vic20SdkModules.AssembleCharacters(Sources).Sections[0].Bytes.Span;
        foreach (int set in (ReadOnlySpan<int>)[0x000, 0x800])
        {
            for (int i = 0; i < 0x400; i++)
            {
                image[set + 0x400 + i].Should().Be((byte)~image[set + i], $"${set + 0x400 + i:X3} reverses ${set + i:X3}");
            }
        }

        // £ is at $1C in both sets.
        image.Slice(0x1C * 8, 8).SequenceEqual(image.Slice(0x800 + (0x1C * 8), 8)).Should().BeTrue();
        image[(0x1C * 8) + 6].Should().Be(0x6E, "the pound sign's foot");
    }

    /// <summary>
    ///  BASIC builds byte-identically to 901486-01 and to the kernal chip's first part, <c>$E000-$E47B</c>, where one
    ///  byte, <c>$E475</c>, differs between NTSC's 901486-06 and PAL's -07.
    /// </summary>
    /// <param name="standard">The build's video standard.</param>
    /// <param name="chip">The kernal chip's file in its MAME set.</param>
    /// <param name="expected">The build's SHA-256.</param>
    [TestMethod]
    [DataRow(VicVideoStandard.Ntsc, "901486-06.ue12", "9480B8D1EC74AE60FB6EB6CDAD66391D74957C16B4E56E117C46D970E61EBE1F")]
    [DataRow(VicVideoStandard.Pal, "901486-07.ue12", "33D0885057173EE13773BD035072F9473C4756AB7A91391796F3B3B7E5417BCF")]
    public void BasicMatchesTheChips(VicVideoStandard standard, string chip, string expected)
    {
        ReadOnlySpan<byte> image = Vic20SdkModules.AssembleBasic(Sources, standard).Sections[0].Bytes.Span;
        image.Length.Should().Be(Vic20SdkModules.KernalOrigin - Vic20SdkModules.BasicOrigin);
        string hash = Convert.ToHexString(SHA256.HashData(image));
        if (hash == expected) { return; }

        string because = "the digest pins the chips (without their dumps the first different byte can't be named)";
        string directory = Vic20MachineTests.RomDirectory(standard);
        if (File.Exists(Path.Join(directory, "901486-01.ue11")) && File.Exists(Path.Join(directory, chip)))
        {
            byte[] basic = File.ReadAllBytes(Path.Join(directory, "901486-01.ue11"));
            byte[] chips = [.. basic, .. File.ReadAllBytes(Path.Join(directory, chip))];
            because = $"the first difference is at ${Vic20SdkModules.BasicOrigin + image.CommonPrefixLength(chips):X4}";
        }

        hash.Should().Be(expected, because);
    }

    /// <summary>
    ///  The kernal builds byte-identically to the chip from <c>$E47C</c>, where BASIC's part ends: 901486-06 for NTSC
    ///  and 901486-07 for PAL.
    /// </summary>
    /// <param name="standard">The build's video standard.</param>
    /// <param name="chip">The chip's file in its MAME set.</param>
    /// <param name="expected">The build's SHA-256.</param>
    [TestMethod]
    [DataRow(VicVideoStandard.Ntsc, "901486-06.ue12", "78B6C911D939211ABBAEFAEA4627E904F6B0717587186747D2E54C67F2B0499B")]
    [DataRow(VicVideoStandard.Pal, "901486-07.ue12", "E1B0B1FCD694ADCC9DCA4682A064EF714EF519C78628594F8BFB3E6DABF08B90")]
    public void KernalMatchesTheChip(VicVideoStandard standard, string chip, string expected)
    {
        ReadOnlySpan<byte> image = Vic20SdkModules.AssembleKernal(Sources, standard).Sections[0].Bytes.Span;
        image.Length.Should().Be(0x10000 - Vic20SdkModules.KernalOrigin);
        string hash = Convert.ToHexString(SHA256.HashData(image));
        if (hash == expected) { return; }

        string because = "the dumps are missing";
        string path = Path.Join(Vic20MachineTests.RomDirectory(standard), chip);
        if (File.Exists(path))
        {
            int origin = Vic20SdkModules.KernalOrigin;
            int first = image.CommonPrefixLength(File.ReadAllBytes(path).AsSpan(origin - Vic20SdkModules.KernalChipOrigin));
            because = $"the first difference is at ${origin + first:X4}";
        }

        hash.Should().Be(expected, because);
    }

    /// <summary>
    ///  In each build of the kernal, every old name in a file the build assembles cites only the kernal's documents,
    ///  Commodore's listing (KV20), the Programmer's Reference Guide (V20PRG) and <i>Mapping the VIC</i> (MTV), each in
    ///  the bibliography, and is one of the build's historical names.
    /// </summary>
    /// <param name="standard">The build's video standard.</param>
    [TestMethod]
    [DataRow(VicVideoStandard.Ntsc)]
    [DataRow(VicVideoStandard.Pal)]
    public void KernalOldNamesCiteItsDocuments(VicVideoStandard standard)
    {
        AssemblyResult result = Vic20SdkModules.AssembleKernal(Sources, standard);
        string[] files = result.SourceMap
            .Select(entry => entry.Location?.Path)
            .OfType<string>()
            .Where(path => Path.GetFileName(path).StartsWith("Kernal", StringComparison.Ordinal))
            .Select(Path.GetFullPath)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();

        files.Length.Should().Be(11, "the kernal is Kernal.asm and the ten files it includes");

        List<string> wrong = [];
        int count = 0;
        foreach (string path in files)
        {
            string name = Path.GetFileName(path);
            foreach (DocumentationAlso also in DocumentationParser.Parse(File.ReadAllText(path), path).Comments
                .SelectMany(comment => DocumentationAlso.Of(comment.Sections)))
            {
                count++;
                if (also.Sources.Count == 0)
                {
                    wrong.Add($"{name}: {also.Name} cites no document");
                }

                foreach (string key in also.Sources)
                {
                    if (!s_kernalKeys.Contains(key))
                    {
                        wrong.Add($"{name}: {also.Name} cites {key}, not a kernal document");
                    }

                    if (BasicAttribution.Bibliography.Find(key) is null)
                    {
                        wrong.Add($"{name}: {also.Name} cites {key}, not in the bibliography");
                    }
                }

                if (!result.HistoricalNames.ContainsKey(also.Name))
                {
                    wrong.Add($"{name}: {also.Name} is not an old name of the build");
                }
            }
        }

        wrong.Should().BeEmpty($"the kernal's old names cite its documents:{Environment.NewLine}{string.Join(Environment.NewLine, wrong)}");
        count.Should().BeGreaterThan(MinimumKernalOldNames, "the kernal keeps the listing's and the references' names");
    }

    /// <summary>
    ///  The machine starts from the SDK's builds, with no dumps, to BASIC's banner, the bytes free and <c>READY.</c>.
    /// </summary>
    /// <param name="standard">The video standard.</param>
    [TestMethod]
    [DataRow(VicVideoStandard.Ntsc)]
    [DataRow(VicVideoStandard.Pal)]
    public void BootsFromTheSdkBuilds(VicVideoStandard standard)
    {
        Vic20Machine machine = new(Vic20SdkModules.BuildRoms(standard, Sources), standard);
        string[] screen = Vic20MachineTests.RunToReady(machine);
        string text = string.Join('\n', screen);
        screen.Should().Contain(line => line.Trim() == "**** CBM BASIC V2 ****", text);
        screen.Should().Contain(line => line.Trim() == "3583 BYTES FREE", text);
        screen.Should().Contain(line => line.StartsWith("READY.", StringComparison.Ordinal), text);
    }

    /// <summary>
    ///  With the dumps, the SDK's kernal chip, BASIC and characters are the chips' bytes.
    /// </summary>
    /// <param name="standard">The video standard.</param>
    [TestMethod]
    [DataRow(VicVideoStandard.Ntsc)]
    [DataRow(VicVideoStandard.Pal)]
    public void SdkBuildsAreTheChips(VicVideoStandard standard)
    {
        string directory = Vic20MachineTests.RomDirectory(standard);
        string[] files = ["901486-01.ue11", Vic20Roms.KernalFile(standard), "901460-03.ud7"];
        if (!files.All(file => File.Exists(Path.Join(directory, file))))
        {
            Assert.Inconclusive("Set RETROCORE_VIC20_ROMS to a folder with MAME's vic20 and vic20p sets unzipped.");
        }

        Vic20Roms chips = Vic20Roms.LoadFromDirectory(directory, standard);
        Vic20Roms built = Vic20SdkModules.BuildRoms(standard, Sources);
        built.Basic.SequenceEqual(chips.Basic).Should().BeTrue("BASIC is 901486-01");
        built.Kernal.SequenceEqual(chips.Kernal).Should().BeTrue($"the kernal is {Vic20Roms.KernalFile(standard)}");
        built.Characters.SequenceEqual(chips.Characters).Should().BeTrue("the characters are 901460-03");
    }
}
