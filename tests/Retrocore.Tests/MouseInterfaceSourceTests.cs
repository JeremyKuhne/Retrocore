// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Security.Cryptography;
using Retrocore.Assembler;
using Retrocore.Machines.Apple2;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the source of Apple's mouse card firmware, and that the emulator's own mouse firmware answers where
///  programs look at it.
/// </summary>
[TestClass]
public sealed class MouseInterfaceSourceTests
{
    private const int RomSize = 0x800;
    private static readonly string s_source = Path.Join(AppContext.BaseDirectory, "Inputs", "Mouse", "MouseInterface.asm");

    /// <summary>
    ///  The source builds byte-identically to the 341-0270-C EPROM, pinned by digest so no ROM is needed.
    /// </summary>
    [TestMethod]
    public void SourceMatchesTheChip()
    {
        ReadOnlySpan<byte> bytes = Assemble();
        bytes.Length.Should().Be(RomSize);
        Convert.ToHexString(SHA256.HashData(bytes)).Should().Be("7F8E50C0E8A409991264201F9300F109B872B68E09C43F3E6C26AF35FD8B89AF");
    }

    /// <summary>
    ///  With the chip in <c>%USERPROFILE%\Retrocore\mouse-roms</c> (or <c>RETROCORE_MOUSE_ROMS</c>), the source also
    ///  compares byte for byte, which names the first difference.
    /// </summary>
    [TestMethod]
    public void SourceMatchesTheDump()
    {
        string directory = Environment.GetEnvironmentVariable("RETROCORE_MOUSE_ROMS") ?? Path.Join(ExternalTestData.Root, "mouse-roms");
        string path = Path.Join(directory, "342-0270-C.bin");
        if (!File.Exists(path)) { Assert.Inconclusive($"The mouse card's EPROM dump ({path}) is missing."); }

        byte[] expected = File.ReadAllBytes(path);
        ReadOnlySpan<byte> actual = Assemble();
        int first = actual.CommonPrefixLength(expected);
        first.Should().Be(expected.Length, $"the first difference is at offset ${first:X3}");
    }

    /// <summary>
    ///  The emulator's firmware has Apple's identification bytes and its offsets for the mouse routines in the same
    ///  places, so a program that finds Apple's card finds ours, and every offset in $Cn12-$Cn1F lands on code.
    /// </summary>
    [TestMethod]
    public void EmulatedFirmwareIdentifiesAsApplesCard()
    {
        ReadOnlySpan<byte> apple = Assemble()[..256];
        ReadOnlySpan<byte> ours = MouseRom.Bytes;
        foreach (int offset in (ReadOnlySpan<int>)[0x05, 0x07, 0x0B, 0x0C, 0x11, 0xFB])
        {
            ours[offset].Should().Be(apple[offset], $"$Cn{offset:X2} identifies the card");
        }

        for (int entry = 0x12; entry <= 0x1F; entry++)
        {
            ours[entry].Should().BeGreaterThan(0x1F, $"$Cn{entry:X2}'s offset must land past the table, on code");
        }
    }

    private static ReadOnlySpan<byte> Assemble()
    {
        AssemblyOptions options = new(ProcessorVariant.Mos6502, origin: 0, RomSize) { SourceResolver = new FileAssemblySourceResolver() };
        AssemblyResult result = new Assembler.Assembler().Assemble(new AssemblySource(File.ReadAllText(s_source), s_source), options);
        result.Diagnostics.Should().BeEmpty();
        return result.Sections[0].Bytes.Span;
    }
}
