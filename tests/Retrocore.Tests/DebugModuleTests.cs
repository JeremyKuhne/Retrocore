// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Machines.Apple2;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

/// <summary>
///  Verifies debug modules read from source maps and the memory areas that decide where they apply.
/// </summary>
[TestClass]
public sealed partial class DebugModuleTests
{
    private const string MacroSource = """
        .macro inner v
          lda #v
          sta $10
        .endmacro
        .macro outer v
          inner v
          inx
        .endmacro
        start: outer 5
          inner 7
          nop
        .macro one
          iny
        .endmacro
          one

        """;

    /// <summary>
    ///  Reads report the storage the memory map selects: RAM banks, language-card banks, and internal or slot ROM.
    /// </summary>
    [TestMethod]
    public void ReadAreaFollowsTheMemoryMap()
    {
        Apple2Bus bus = new(new Apple2Roms(new byte[16384], new byte[4096]), new BlockDevice());
        bus.ReadArea(0x6000).Should().Be(Apple2MemoryArea.MainRam);
        bus.ReadArea(0xC050).Should().Be(Apple2MemoryArea.Io);
        bus.ReadArea(0xD000).Should().Be(Apple2MemoryArea.SystemRom);
        bus.ReadArea(0xC300).Should().Be(Apple2MemoryArea.SystemRom);
        bus.ReadArea(0xC500).Should().Be(Apple2MemoryArea.None);
        bus.ReadArea(0xC700).Should().Be(Apple2MemoryArea.Slot7Rom);

        bus.Read(0xC080);
        bus.ReadArea(0xD000).Should().Be(Apple2MemoryArea.MainLanguageCard);
        bus.Read(0xC088);
        bus.ReadArea(0xD000).Should().Be(Apple2MemoryArea.MainLanguageCardBank1);
        bus.ReadArea(0xE000).Should().Be(Apple2MemoryArea.MainLanguageCard);

        bus.Write(0xC009, 0);
        bus.ReadArea(0xD000).Should().Be(Apple2MemoryArea.AuxiliaryLanguageCardBank1);
        bus.ReadArea(0x0080).Should().Be(Apple2MemoryArea.AuxiliaryRam);
        bus.ReadArea(0x6000).Should().Be(Apple2MemoryArea.MainRam);
        bus.Write(0xC003, 0);
        bus.ReadArea(0x6000).Should().Be(Apple2MemoryArea.AuxiliaryRam);

        bus.Write(0xC007, 0);
        bus.ReadArea(0xC700).Should().Be(Apple2MemoryArea.SystemRom);
    }

    /// <summary>
    ///  Each address has its macro chain, innermost first, with the invocations that start there counted, and a
    ///  line's entries are each start of its code.
    /// </summary>
    [TestMethod]
    public void SourceMapModulesKeepMacroChains()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-module-").FullName;
        try
        {
            (string path, Apple2Bus bus, AssemblyResult result) = Load(directory);
            SourceMapModule module = new(result, Apple2MemoryArea.MainRam);

            DebugPosition first = At(module, bus, 0x6000);
            first.Chain.Should().Equal(
                new SourceLine(path, 2, "inner v"),
                new SourceLine(path, 6, "start: outer 5"),
                new SourceLine(path, 9));

            first.EntryDepth.Should().Be(2);
            At(module, bus, 0x6002).Chain[0].Should().Be(new SourceLine(path, 3, "inner v"));
            At(module, bus, 0x6002).EntryDepth.Should().Be(0);
            At(module, bus, 0x6004).Chain.Should().Equal(new SourceLine(path, 7, "start: outer 5"), new SourceLine(path, 9));
            At(module, bus, 0x6005).EntryDepth.Should().Be(1);
            At(module, bus, 0x6009).Chain.Should().Equal(new SourceLine(path, 11));
            At(module, bus, 0x600A).Chain.Should().Equal(new SourceLine(path, 13, "one"), new SourceLine(path, 15));

            module.Entries(path, 2).Should().Equal(0x6000, 0x6005);
            module.Entries(path, 9).Should().Equal(0x6000);
            module.Entries(path, 6).Should().Equal(0x6000);
            module.Entries(path, 10).Should().Equal(0x6005);
            module.TryResolve("start", out long start).Should().BeTrue();
            start.Should().Be(0x6000);
            module.Label(0x6004).Should().Be("start");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  Collapsed single-statement macros debug as their call line, as MACRO-10 instruction macros will.
    /// </summary>
    [TestMethod]
    public void SingleStatementMacrosCanDebugAsTheirCallLine()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-module-").FullName;
        try
        {
            (string path, Apple2Bus bus, AssemblyResult result) = Load(directory);
            SourceMapModule module = new(result, Apple2MemoryArea.MainRam, collapseSingleStatementMacros: true);

            At(module, bus, 0x600A).Chain.Should().Equal(new SourceLine(path, 15));
            At(module, bus, 0x600A).EntryDepth.Should().Be(0);
            At(module, bus, 0x6000).Chain.Should().HaveCount(3);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  Source applies only where memory holds the code it assembled to, and only in the module's memory area.
    /// </summary>
    [TestMethod]
    public void SourceAppliesOnlyToItsOwnCode()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-module-").FullName;
        try
        {
            (_, Apple2Bus bus, AssemblyResult result) = Load(directory);
            DebugInfo debug = new();
            debug.Add(new SourceMapModule(result, Apple2MemoryArea.MainRam));

            debug.Position(new Apple2TestMemory(bus), 0x6009).Should().NotBeNull();
            bus.SetRam(auxiliary: false, 0x6009, 0x00);
            debug.Position(new Apple2TestMemory(bus), 0x6009).Should().BeNull();

            bus.Write(0xC003, 0);
            debug.Position(new Apple2TestMemory(bus), 0x6000).Should().BeNull();
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  The SDK's slot-seven firmware source describes the slot's ROM while it is mapped, and not internal ROM.
    /// </summary>
    [TestMethod]
    public void SlotSevenSourceDescribesTheSlotRom()
    {
        string source = Path.Join(AppContext.BaseDirectory, "Inputs", "Slot7.rom.asm");
        Apple2Bus bus = new(new Apple2Roms(new byte[16384], new byte[4096]), new BlockDevice());
        DebugInfo debug = new();
        debug.Add(new SourceMapModule(SdkModules.AssembleRom(source), Apple2MemoryArea.Slot7Rom));

        DebugPosition? entry = debug.Position(new Apple2TestMemory(bus), 0xC700);
        entry.Should().NotBeNull();
        entry?.Chain[0].Path.Should().Be(Path.GetFullPath(source));
        debug.Resolve("DriverEntry").Should().BeInRange(0xC700, 0xC7FF);

        bus.Write(0xC007, 0);
        debug.Position(new Apple2TestMemory(bus), 0xC700).Should().BeNull();
    }

    private static DebugPosition At(SourceMapModule module, Apple2Bus bus, ushort address) =>
        module.Position(new Apple2TestMemory(bus), address) ?? throw new AssertFailedException($"No source at ${address:X4}.");

    private static (string Path, Apple2Bus Bus, AssemblyResult Result) Load(string directory)
    {
        string path = Path.Join(directory, "main.s");
        File.WriteAllText(path, MacroSource);
        AssemblyResult result = new NativeAssembler().Assemble(
            new AssemblySource(File.ReadAllText(path), path),
            new(ProcessorVariant.Mos6502, 0x6000, 0x100));

        result.Diagnostics.Should().BeEmpty();
        Apple2Bus bus = new(new Apple2Roms(new byte[16384], new byte[4096]));
        ReadOnlySpan<byte> bytes = result.Sections[0].Bytes.Span;
        for (int index = 0; index < bytes.Length; index++)
        {
            bus.SetRam(auxiliary: false, (ushort)(0x6000 + index), bytes[index]);
        }

        return (path, bus, result);
    }
}
