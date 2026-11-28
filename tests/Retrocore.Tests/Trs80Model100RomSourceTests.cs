// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Machines.Trs80Model100;
using System.Security.Cryptography;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the SDK's native source for the Model 100's ROM, <c>Model100.asm</c>, for the US Model 100 and Tandy 102.
/// </summary>
/// <remarks>
///  <para>
///   Digests pin each build, so no ROM is needed: each is the SHA-256 of that model's ROM, MAME 0.264's dump. With the
///   ROMs where <see cref="Trs80Model100RomTests"/> reads them, each also compares byte for byte, which names the
///   first difference.
///  </para>
/// </remarks>
[TestClass]
public sealed class Trs80Model100RomSourceTests
{
    /// <summary>
    ///  The source builds each model's ROM byte for byte.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <param name="expectedHash">The SHA-256 of its ROM.</param>
    [TestMethod]
    [DataRow(Trs80Model100Variant.Model100, "0ACCD7E877AD6AAD6CED81424F69E876093041F633E4900EA9D5B855830D0236")]
    [DataRow(Trs80Model100Variant.Tandy102, "21598A9172CBD7803C4B0BBEB096358343AD06B22E608AC98BCD5B2D3F1B7473")]
    public void SourceMatchesTheRom(Trs80Model100Variant model, string expectedHash)
    {
        AssemblyResult result = Trs80Model100SdkModules.Assemble(Source(), model);
        result.Diagnostics.Should().BeEmpty();
        ReadOnlySpan<byte> bytes = result.Sections[0].Bytes.Span;
        bytes.Length.Should().Be(Trs80Model100Roms.RomSize);
        Convert.ToHexString(SHA256.HashData(bytes)).Should().Be(expectedHash);
    }

    /// <summary>
    ///  With the ROMs, each build compares byte for byte, naming the first byte that differs; inconclusive without
    ///  them.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <param name="name">Its ROM's file.</param>
    [TestMethod]
    [DataRow(Trs80Model100Variant.Model100, "m100.bin")]
    [DataRow(Trs80Model100Variant.Tandy102, "t102.bin")]
    public void SourceComparesWithTheDump(Trs80Model100Variant model, string name)
    {
        byte[] rom = Trs80Model100RomTests.Rom(name);
        ReadOnlySpan<byte> bytes = Trs80Model100SdkModules.Assemble(Source(), model).Sections[0].Bytes.Span;
        int first = bytes.CommonPrefixLength(rom);
        first.Should().Be(rom.Length, $"the first difference is at ${first:X4}");
    }

    /// <summary>
    ///  The names the debugger and the documentation rely on are where the ROM has them: Microsoft's interpreter core,
    ///  and Tandy's documented entry points.
    /// </summary>
    [TestMethod]
    public void NamesAreWhereTheRomHasThem()
    {
        AssemblyResult result = Trs80Model100SdkModules.Assemble(Source(), Trs80Model100Variant.Model100);
        Dictionary<string, long> expected = new()
        {
            ["NEWSTT"] = 0x0804, ["GONE"] = 0x083A, ["CHRGTR"] = 0x0858, ["READY"] = 0x0502, ["MAIN"] = 0x0511,
            ["ERROR"] = 0x045D, ["CRUNCH"] = 0x0646, ["FRMEVL"] = 0x0DAB, ["ST_RUN"] = 0x090F, ["ST_CONT"] = 0x40DA,
            ["CONSTP"] = 0x40A9, ["STPEND"] = 0x40B3, ["ENDCON"] = 0x40B6, ["STMDSP"] = 0x0262, ["FUNDSP"] = 0x0040,
            ["MENU"] = 0x5797, ["LCD"] = 0x4B44, ["CHGET"] = 0x12CB, ["INLIN"] = 0x4644, ["TXTTAB"] = 0xF67C,
            ["CURLIN"] = 0xF67A, ["VARTAB"] = 0xFBB2, ["MEMSIZ"] = 0xFB67
        };

        foreach ((string name, long value) in expected)
        {
            result.Symbols.Should().ContainKey(name);
            result.Symbols[name].Should().Be(value, name);
        }
    }

    private static string Source() =>
        Path.Join(AppContext.BaseDirectory, "Inputs", "Trs80Model100", Trs80Model100SdkModules.Source);
}
