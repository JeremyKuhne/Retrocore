// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

public sealed partial class DebugModuleTests
{
    /// <summary>
    ///  An equate names the address an instruction's bytes access through it, not an immediate value, an index's
    ///  offset, a term added to another address or data that looks like an instruction; names that differ only in
    ///  case or scope name their own values, and a width override does not hide a name.
    /// </summary>
    [TestMethod]
    public void AddressConstantsAreTheEquatesInstructionsAccess()
    {
        Dictionary<string, long> named = AddressConstants("""
            CH = $24
            CR = $0D
            Cell = $30
            cell = $31
            BASL = $28
            OFF = 2
            .scope Inner
            Spot = $50
            .endscope
            Spot = $51
            Wide = $60
            Narrow = $61
            Table = $70
            start:
              sta CH
              cmp #CR
              sta cell
              lda (BASL),y
              lda $0400+OFF
              sta Inner::Spot
              sta a:Wide
              sta z:Narrow
              rts
              .byte $85, Table

            """);

        named.Should().BeEquivalentTo(new Dictionary<string, long>
        {
            ["CH"] = 0x24,
            ["cell"] = 0x31,
            ["BASL"] = 0x28,
            ["Inner::Spot"] = 0x50,
            ["Wide"] = 0x60,
            ["Narrow"] = 0x61
        });
    }

    /// <summary>
    ///  On the 6809, an indirect or PC-relative postbyte's address counts, and an offset from a register does not.
    /// </summary>
    [TestMethod]
    public void AddressConstantsReadThe6809sPostbytes()
    {
        Dictionary<string, long> named = AddressConstants("""
            .cpu M6809
            Vector = $FFFE
            Table = $0480
            Offset = 4
            start:
              lda [Vector]
              leax Table,pcr
              lda Offset,x
              rts

            """);

        named.Should().BeEquivalentTo(new Dictionary<string, long> { ["Vector"] = 0xFFFE, ["Table"] = 0x0480 });
    }

    /// <summary>
    ///  An equate an instruction accesses by one of its historical names, from its Also: section, is named by its own
    ///  name, and once when code uses both names.
    /// </summary>
    [TestMethod]
    public void AddressConstantsFollowHistoricalNames()
    {
        Dictionary<string, long> named = AddressConstants("""
            ;; The keyboard.
            ;; Also: KBD (UNKN)
            Keyboard = $C000
            ;; The cursor's column.
            ;; Also: CH (UNKN)
            CursorColumn = $24
            start:
              lda KBD
              sta Keyboard
              sta CH
              rts

            """);

        named.Should().BeEquivalentTo(new Dictionary<string, long> { ["Keyboard"] = 0xC000, ["CursorColumn"] = 0x24 });
    }

    /// <summary>
    ///  An equate both CPUs of a module access is named for each.
    /// </summary>
    [TestMethod]
    public void AddressConstantsKeepEachCpuThatAccessesThem()
    {
        AssemblyResult result = Assemble("""
            .cpu Mos6502
            Shared = $0300
              sta Shared
            .cpu Z80
              ld a,[Shared]
              ret

            """);

        SourceMapModule module = new(result, area: null);
        module.AddressConstants.Select(constant => (constant.Name, constant.Value)).Should().Equal(("Shared", 0x0300L), ("Shared", 0x0300L));
        module.AddressConstants.Select(constant => constant.Cpu).Distinct().Should().HaveCount(2);
    }

    /// <summary>
    ///  Where the SDK's modules name one address, the Monitor's name comes first even when BASIC's module was added
    ///  first, as a memory view's first name wins: AppleSoft's TRMPOS is the Monitor's CH. A program's names come
    ///  before every SDK name, modules of one rank keep their order, and each constant carries its source.
    /// </summary>
    [TestMethod]
    public void AddressConstantsRankTheMonitorsNamesFirst()
    {
        string folder = Directory.CreateTempSubdirectory().FullName;
        try
        {
            SourceMapModule program = Module(Path.Join(folder, "Program", "main.s"), """
                CURSOR = $24
                  sta CURSOR
                  rts
                """);

            SourceMapModule basic = Module(Path.Join(folder, "AppleSoft", "AppleSoft.Equates.asm"), """
                TRMPOS = $24
                HOLD = $50
                  sta TRMPOS
                  sta HOLD
                  rts
                """);

            SourceMapModule dos = Module(Path.Join(folder, "Dos", "Dos33.asm"), """
                SPOT = $50
                  sta SPOT
                  rts
                """);

            SourceMapModule dos32 = Module(Path.Join(folder, "Dos", "Dos32.asm"), """
                OTHER = $50
                  sta OTHER
                  rts
                """);

            SourceMapModule monitor = Module(Path.Join(folder, "System", "Monitor.asm"), """
                CH = $24
                  sta CH
                  rts
                """);

            monitor.AddressConstants.Single().Path.Should().Be(Path.Join(folder, "System", "Monitor.asm"));
            (string Name, long Value)[] Ranked(params SourceMapModule[] modules) => [.. MachineSymbols.ByRank(
                modules.SelectMany(module => module.AddressConstants
                    .Select(constant => (constant.Name, constant.Value, constant.Path, Ranked: module != program))))];

            Ranked(basic, dos, dos32, monitor)
                .Should().Equal(("CH", 0x24L), ("TRMPOS", 0x24L), ("HOLD", 0x50L), ("SPOT", 0x50L), ("OTHER", 0x50L));

            // The program's names come before even the Monitor's, though its main.s would rank with DOS's.
            Ranked(program, basic, monitor)
                .Should().Equal(("CURSOR", 0x24L), ("CH", 0x24L), ("TRMPOS", 0x24L), ("HOLD", 0x50L));
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    private static SourceMapModule Module(string path, string source)
    {
        AssemblyResult result = new NativeAssembler().Assemble(
            new AssemblySource(source, path),
            new(ProcessorVariant.Mos6502, 0x6000, 0x100));

        result.Diagnostics.Should().BeEmpty();
        return new SourceMapModule(result, area: null);
    }

    private static Dictionary<string, long> AddressConstants(string source) =>
        new SourceMapModule(Assemble(source), area: null).AddressConstants.ToDictionary(constant => constant.Name, constant => constant.Value);

    private static AssemblyResult Assemble(string source)
    {
        AssemblyResult result = new NativeAssembler().Assemble(
            new AssemblySource(source, "constants.s"),
            new(ProcessorVariant.Mos6502, 0x6000, 0x100));

        result.Diagnostics.Should().BeEmpty();
        return result;
    }
}
