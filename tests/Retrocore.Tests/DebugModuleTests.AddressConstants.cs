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
    ///  offset or a term added to another address; names that differ only in case or scope name their own values.
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
            start:
              sta CH
              cmp #CR
              sta cell
              lda (BASL),y
              lda $0400+OFF
              sta Inner::Spot
              rts

            """);

        named.Should().BeEquivalentTo(new Dictionary<string, long>
        {
            ["CH"] = 0x24,
            ["cell"] = 0x31,
            ["BASL"] = 0x28,
            ["Inner::Spot"] = 0x50
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
