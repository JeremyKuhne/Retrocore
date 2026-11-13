// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Security.Cryptography;
using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Machines.Apple2;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the SDK's native sources for the Apple-1's firmware: the Monitor, the cassette interface's PROM and the
///  2513 character generator.
/// </summary>
/// <remarks>
///  <para>
///   Digests pin each build, so no ROM is needed. With dumps in <c>RETROCORE_APPLE1_ROMS</c> or
///   <c>%USERPROFILE%\Retrocore\apple1-roms</c> (<c>wozmon.bin</c>, 256 bytes, and <c>aci.bin</c>, 256 bytes), each
///   also compares byte for byte, which names the first difference.
///  </para>
/// </remarks>
[TestClass]
public sealed class Apple1RomTests
{
    /// <summary>
    ///  The Monitor builds byte-identically, with the 6502's vectors in its last six bytes.
    /// </summary>
    [TestMethod]
    public void MonitorMatchesThePublishedListing()
    {
        AssemblyResult result = Apple1SdkModules.AssembleMonitor(Source("WozMonitor.asm"));
        result.Diagnostics.Should().BeEmpty();
        byte[] monitor = Image(result);
        monitor.Should().HaveCount(256);
        Hash(monitor).Should().Be("E5AF0D1C4057BD8E0EF5CB069C208FF7CC0984A7DFF53B12C5CF119DE8CB5C25");

        // RESET at $FF00, NMI at $0F00 and IRQ at $0000.
        monitor.AsSpan(0xFA).ToArray().Should().Equal(0x00, 0x0F, 0x00, 0xFF, 0x00, 0x00);
        CompareWithDump("wozmon.bin", monitor);
    }

    /// <summary>
    ///  The cassette interface's PROM builds byte-identically, with the bytes its input trick reads at the start.
    /// </summary>
    [TestMethod]
    public void CassetteInterfaceMatchesThePublishedListing()
    {
        AssemblyResult result = Apple1SdkModules.AssembleCassette(Source("Aci.asm"));
        result.Diagnostics.Should().BeEmpty();
        byte[] prom = Image(result);
        prom.Should().HaveCount(256);
        Hash(prom).Should().Be("1B9FCF6F3E9E77B8956181F399DFB7905EB7CC947B658A6C202F6B123518A0B7");

        // A read of $C081 gives these two as the tape input is low or high.
        prom[0].Should().Be(0xA9);
        prom[1].Should().Be(0xAA);
        CompareWithDump("aci.bin", prom);
    }

    /// <summary>
    ///  The 2513's glyphs are the original Apple II's: each matches the II board character generator's, which
    ///  replaced the same chip, dot for dot.
    /// </summary>
    [TestMethod]
    public void CharacterGeneratorMatchesTheAppleII()
    {
        AssemblyResult result = Apple1SdkModules.AssembleCharacterGenerator(Source("CharacterGenerator.asm"));
        result.Diagnostics.Should().BeEmpty();
        byte[] glyphs = Image(result);
        glyphs.Should().HaveCount(512);
        Hash(glyphs).Should().Be("B65F711E7CC81B5C319008E1375F6294B70B5B63CF0DEB6AEBC2337B55A9F486");

        // The II board's chip: a blank top row, then seven rows with bit 6 the leftmost of seven dots.
        string path = Path.Join(AppContext.BaseDirectory, "Inputs", "System", "CharacterGenerator.asm");
        byte[] board = Image(SdkModules.AssembleCharacterGenerator(path, Apple2Model.II));
        for (int character = 0; character < 64; character++)
        {
            for (int row = 0; row < 7; row++)
            {
                int dots = board[(character * 8) + row + 1] & 0x7F;
                (dots & 0x41).Should().Be(0, "the 2513's glyphs are five dots wide");
                glyphs[(character * 8) + row].Should().Be((byte)(dots >> 1), "character {0}, row {1}", character, row);
            }

            glyphs[(character * 8) + 7].Should().Be(0);
        }
    }

    /// <summary>
    ///  Gets the path of an Apple-1 ROM source copied beside the tests.
    /// </summary>
    /// <param name="file">The file name.</param>
    /// <returns>The path.</returns>
    internal static string Source(string file) => Path.Join(AppContext.BaseDirectory, "Inputs", "Apple1", file);

    /// <summary>
    ///  Gets an assembly's bytes.
    /// </summary>
    /// <param name="result">The assembly.</param>
    /// <returns>Its first section's bytes.</returns>
    internal static byte[] Image(AssemblyResult result) => result.Sections[0].Bytes.ToArray();

    private static string Hash(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes));

    private static void CompareWithDump(string name, byte[] built)
    {
        string directory = Environment.GetEnvironmentVariable("RETROCORE_APPLE1_ROMS") is { Length: > 0 } configured
            ? configured
            : Path.Join(ExternalTestData.Root, "apple1-roms");

        string path = Path.Join(directory, name);
        if (!File.Exists(path)) { return; }
        byte[] dump = File.ReadAllBytes(path);
        int difference = Enumerable.Range(0, Math.Min(dump.Length, built.Length)).FirstOrDefault(index => dump[index] != built[index], -1);
        difference.Should().Be(-1, "{0} should match the build", name);
        dump.Should().HaveCount(built.Length);
    }
}
