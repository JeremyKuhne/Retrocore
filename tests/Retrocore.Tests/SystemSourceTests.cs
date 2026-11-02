// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Security.Cryptography;
using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Machines.Apple2;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the SDK's native sources for the IIe Monitor and internal firmware.
/// </summary>
[TestClass]
public sealed class SystemSourceTests
{
    private const int SystemRomOrigin = 0xC000;

    private static readonly string s_monitor = Path.Join(AppContext.BaseDirectory, "Inputs", "System", "Monitor.asm");

    /// <summary>
    ///  Each source builds byte-identically to its part of the model's ROM, pinned by digest so no ROM is needed.
    /// </summary>
    /// <param name="model">The IIe model.</param>
    /// <param name="file">The source.</param>
    /// <param name="origin">Its first address.</param>
    /// <param name="size">Its size.</param>
    /// <param name="expectedHash">The SHA-256 of that part of the model's ROM.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIe, "Monitor.asm", 0xF800, 0x800, "1E884887E88F101688096D3C30216C2101529F5B1B39522BB251BDEEFC249CB9")]
    [DataRow(Apple2Model.IIeEnhanced, "Monitor.asm", 0xF800, 0x800, "72C08E57CF834D3BBDC320977B0C412E977363E1CC26B1BCED5B8A66B1D63BD6")]
    [DataRow(Apple2Model.IIe, "Firmware.Original.asm", 0xC100, 0xF00, "16DCFB9A1F17B04CFB35EBEEEF5DB5B5FEE078D81CB42044D211465FCA90121E")]
    [DataRow(
        Apple2Model.IIeEnhanced,
        "Firmware.Enhanced.asm",
        0xC100,
        0xF00,
        "463FC7DDEC0B5A337D1B98873119FDF77C9CA9ECB50F74684C0668D9B9299375")]
    [DataRow(Apple2Model.IIe, "CharacterGenerator.asm", 0, 0x1000, "ED5BDD4AFA509134E85F1D020685AF7FF50E279226EB869A17825B471CC1634C")]
    [DataRow(
        Apple2Model.IIeEnhanced,
        "CharacterGenerator.asm",
        0,
        0x1000,
        "52C3B87900AC939F6525402CAB1CCFD8F8259290FC6DF54DA48FB4C98AE3ED0F")]
    public void SourceMatchesTheModelsRom(Apple2Model model, string file, int origin, int size, string expectedHash)
    {
        AssemblyResult result = Assemble(file, origin, size, model);

        result.Diagnostics.Should().BeEmpty();
        Convert.ToHexString(SHA256.HashData(result.Sections[0].Bytes.Span)).Should().Be(expectedHash);
    }

    /// <summary>
    ///  With the user's ROM dumps, each source also compares byte for byte, which names the first difference.
    /// </summary>
    /// <param name="model">The IIe model.</param>
    /// <param name="file">The source.</param>
    /// <param name="origin">Its first address.</param>
    /// <param name="size">Its size.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIe, "Monitor.asm", 0xF800, 0x800)]
    [DataRow(Apple2Model.IIeEnhanced, "Monitor.asm", 0xF800, 0x800)]
    [DataRow(Apple2Model.IIe, "Firmware.Original.asm", 0xC100, 0xF00)]
    [DataRow(Apple2Model.IIeEnhanced, "Firmware.Enhanced.asm", 0xC100, 0xF00)]
    public void SourceMatchesTheDumps(Apple2Model model, string file, int origin, int size)
    {
        string? directory = Environment.GetEnvironmentVariable("RETROCORE_IIE_ROMS");
        if (directory is null)
        {
            Assert.Inconclusive("Set RETROCORE_IIE_ROMS to externally supplied CD/EF/video ROM chips.");
        }

        ReadOnlySpan<byte> expected = Apple2Roms.LoadFromDirectory(model, directory).System.Slice(origin - SystemRomOrigin, size);
        ReadOnlySpan<byte> actual = Assemble(file, origin, size, model).Sections[0].Bytes.Span;
        int first = actual.CommonPrefixLength(expected);
        first.Should().Be(size, $"the first difference is at ${origin + first:X4}");
    }

    /// <summary>
    ///  With the user's ROM dumps, the ROMs built from the SDK are the dumps, the video ROM included.
    /// </summary>
    /// <param name="model">The IIe model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void BuiltRomsMatchTheDumps(Apple2Model model)
    {
        string? directory = Environment.GetEnvironmentVariable("RETROCORE_IIE_ROMS");
        if (directory is null)
        {
            Assert.Inconclusive("Set RETROCORE_IIE_ROMS to externally supplied CD/EF/video ROM chips.");
        }

        Apple2Roms dumps = Apple2Roms.LoadFromDirectory(model, directory);
        Apple2Roms built = SdkModules.BuildRoms(model, Path.Join(AppContext.BaseDirectory, "Inputs"));

        // $C000-$C0FF is soft switches, so only the dumps have bytes there.
        int first = built.System[0x100..].CommonPrefixLength(dumps.System[0x100..]);
        first.Should().Be(0x3F00, $"the first difference is at ${0xC100 + first:X4}");
        int glyph = built.Characters.CommonPrefixLength(dumps.Characters);
        glyph.Should().Be(SdkModules.CharacterGeneratorSize, $"the first difference is in glyph ${glyph / 8:X3}");
    }

    /// <summary>
    ///  A IIe built from the SDK's sources draws its text with the source's font: the AppleSoft prompt shows.
    /// </summary>
    [TestMethod]
    public void BuiltRomsDrawThePrompt()
    {
        Apple2Roms roms = SdkModules.BuildRoms(Apple2Model.IIeEnhanced, Path.Join(AppContext.BaseDirectory, "Inputs"));
        Apple2Machine machine = new(Apple2Model.IIeEnhanced, roms);
        machine.Run(BasicMachines.IIeClock * 2);

        // The prompt is at the start of a row: its cell shows the source's picture of "]".
        string[] picture = [".#####.", "....##.", "....##.", "....##.", "....##.", "....##.", ".#####.", "......."];
        int row = Enumerable.Range(0, 24).Last(line => machine.Bus.Peek(TextRow(line)) == (']' | 0x80));
        byte[] pixels = machine.Bus.RenderTextBitmap();
        for (int scanline = 0; scanline < 8; scanline++)
        {
            string dots = string.Concat(Enumerable.Range(0, 7).Select(dot => pixels[(row * 8 + scanline) * 280 + dot] == 1 ? '#' : '.'));
            dots.Should().Be(picture[scanline], $"scanline {scanline}");
        }
    }

    private static ushort TextRow(int row) => (ushort)(0x400 + (row & 7) * 128 + (row >> 3) * 40);

    /// <summary>
    ///  Monitor entry points debug at their own lines, and only while the Monitor's bytes are mapped.
    /// </summary>
    [TestMethod]
    public void MonitorDebugsAtItsEntryPoints()
    {
        AssemblyResult result = SdkModules.AssembleSystem(
            s_monitor,
            SdkModules.MonitorOrigin,
            SdkModules.MonitorSize,
            Apple2Model.IIeEnhanced);

        byte[] system = new byte[16384];
        result.Sections[0].Bytes.Span.CopyTo(system.AsSpan(SdkModules.MonitorOrigin - SystemRomOrigin));
        Apple2Bus bus = new(new Apple2Roms(system, new byte[4096]));
        DebugInfo debug = new();
        debug.Add(new SourceMapModule(result, Apple2MemoryArea.SystemRom));

        debug.Resolve("COUT").Should().Be(0xFDED);
        debug.Resolve("GETLN").Should().Be(0xFD6A);
        DebugPosition? position = debug.Position(new Apple2TestMemory(bus), 0xFDED);
        position.Should().NotBeNull();
        SourceLine line = position?.Chain[0] ?? throw new AssertFailedException("No source for COUT.");
        line.Path.Should().Be(Path.GetFullPath(s_monitor));
        File.ReadAllLines(s_monitor)[line.Line - 2].Should().Be("COUT:");

        // Language-card RAM at $F800 is someone else's code.
        bus.Read(0xC080);
        debug.Position(new Apple2TestMemory(bus), 0xFDED).Should().BeNull();
    }

    private static AssemblyResult Assemble(string file, int origin, int size, Apple2Model model) =>
        SdkModules.AssembleSystem(Path.Join(AppContext.BaseDirectory, "Inputs", "System", file), origin, size, model);
}
