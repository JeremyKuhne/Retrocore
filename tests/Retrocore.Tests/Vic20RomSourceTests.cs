// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Security.Cryptography;
using Retrocore.Debug;
using Retrocore.Machines.Chips;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the SDK's sources for the VIC-20's ROMs: BASIC, 901486-01 and its part of 901486-06 and -07, and the
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
}
