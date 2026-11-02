// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Security.Cryptography;
using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Machines.Apple2;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the SDK's AppleSoft II: Microsoft's MACRO-10 BASIC source with Apple's changes as an overlay.
/// </summary>
[TestClass]
public sealed class AppleSoftTests
{
    private const int AppleSoftOffset = SdkModules.AppleSoftOrigin - 0xC000;

    private static readonly string s_overlay = Path.Join(AppContext.BaseDirectory, "Inputs", "AppleSoft", "applesoft.mac");

    /// <summary>
    ///  Each model's build is byte-identical to that model's ROM at $D000-$F7FF, pinned by digest so no ROM is needed.
    /// </summary>
    /// <param name="model">The IIe model.</param>
    /// <param name="expectedHash">The SHA-256 of the model's ROM at $D000-$F7FF.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIe, "9676882149E86EDCAA960639140BB2070439F667997A5405987B9DB8742746EB")]
    [DataRow(Apple2Model.IIeEnhanced, "498D7571F6C6A920075084B84D497619DEF48F9D5A7160A964B3B512EE5214FC")]
    public void AppleSoftMatchesTheModelsRom(Apple2Model model, string expectedHash)
    {
        AssemblyResult result = SdkModules.AssembleAppleSoft(s_overlay, model);

        result.Diagnostics.Should().BeEmpty();
        ReadOnlySpan<byte> bytes = SdkModules.AppleSoftImage(result).Span;
        Convert.ToHexString(SHA256.HashData(bytes)).Should().Be(expectedHash);
    }

    /// <summary>
    ///  With the user's ROM dumps, each build also compares byte for byte, which names the first difference.
    /// </summary>
    /// <param name="model">The IIe model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void AppleSoftMatchesTheDumps(Apple2Model model)
    {
        string? directory = Environment.GetEnvironmentVariable("RETROCORE_IIE_ROMS");
        if (directory is null)
        {
            Assert.Inconclusive("Set RETROCORE_IIE_ROMS to externally supplied CD/EF/video ROM chips.");
        }

        Apple2Roms roms = Apple2Roms.LoadFromDirectory(model, directory);
        ReadOnlySpan<byte> expected = roms.System.Slice(AppleSoftOffset, SdkModules.AppleSoftSize);
        ReadOnlySpan<byte> actual = SdkModules.AppleSoftImage(SdkModules.AssembleAppleSoft(s_overlay, model)).Span;
        int first = actual.CommonPrefixLength(expected);
        first.Should().Be(SdkModules.AppleSoftSize, $"the first difference is at ${SdkModules.AppleSoftOrigin + first:X4}");
    }

    /// <summary>
    ///  Unchanged code debugs in Microsoft's file, single-instruction macros debug as their call line, and the source
    ///  applies only while internal ROM is mapped.
    /// </summary>
    [TestMethod]
    public void AppleSoftDebugsInMicrosoftsSource()
    {
        AssemblyResult result = SdkModules.AssembleAppleSoft(s_overlay, Apple2Model.IIeEnhanced);
        byte[] system = new byte[16384];
        SdkModules.AppleSoftImage(result).Span.CopyTo(system.AsSpan(AppleSoftOffset));
        Apple2Bus bus = new(new Apple2Roms(system, new byte[4096]));
        DebugInfo debug = new();
        debug.Add(new SourceMapModule(result, Apple2MemoryArea.SystemRom, collapseSingleStatementMacros: true));

        ushort gone = (ushort)debug.Resolve("GONE");
        gone.Should().BeInRange((ushort)SdkModules.AppleSoftOrigin, (ushort)0xF7FF);
        DebugPosition? position = debug.Position(new Apple2TestMemory(bus), gone);
        position.Should().NotBeNull();
        position?.Chain.Should().ContainSingle();
        position?.Chain[0].Path.Should().Be(Path.Join(Path.GetDirectoryName(Path.GetFullPath(s_overlay)), "m6502.asm"));
        position?.Chain[0].Line.Should().Be(2165);

        // Language-card RAM at $D000 is someone else's code, such as ProDOS.
        bus.Read(0xC080);
        debug.Position(new Apple2TestMemory(bus), gone).Should().BeNull();
    }
}
