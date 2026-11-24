// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;

namespace Retrocore.Tests;

// Looking a name up after an assembly, as code resolves it: a symbol, or else a historical name.
public sealed partial class HistoricalNameTests
{
    /// <summary>
    ///  A lookup finds each symbol by its name and each old name by the definition it reaches, with the old name's
    ///  value; a symbol of the same name wins, and a name two definitions give or no definition has is not found.
    /// </summary>
    [TestMethod]
    public void LookupsReachOldNamesWhereNoSymbolHasThem()
    {
        AssemblyResult result = Assemble("""
                rts
            ;; Also: COUT (TEST)
            CharacterOut = $FDED
            ;; Also: SHADOW (TEST)
            Shadowed = $1234
            SHADOW = $5678
            ;; Also: BOTH
            First = $0001
            ;; Also: BOTH
            Second = $0002
            Counter .set 1
            ;; Also: OLDCOUNT (TEST)
            Counter .set 2
            Counter .set 3
            """);

        result.Diagnostics.Should().BeEmpty();
        IReadOnlyDictionary<string, long> names = result.SymbolsWithHistoricalNames;
        names["CharacterOut"].Should().Be(0xFDED);
        names["COUT"].Should().Be(0xFDED);
        names["SHADOW"].Should().Be(0x5678, "a symbol of the same name wins, as it does in code");
        names.Should().NotContainKey("BOTH", "two definitions give it");
        names.Should().NotContainKey("NOT_A_NAME");
        names["OLDCOUNT"].Should().Be(2, "a .set variable's old name has the value where it was documented");
        names["Counter"].Should().Be(result.Symbols["Counter"]);
        result.Symbols.Should().NotContainKey("COUT");
        names.Keys.Should().Contain(result.Symbols.Keys);
    }

    /// <summary>
    ///  Without historical names, the lookup is the symbol table itself; a failed assembly has neither.
    /// </summary>
    [TestMethod]
    public void LookupsWithoutOldNamesAreTheSymbols()
    {
        AssemblyResult result = Assemble("""
            Start:
                rts
            """);

        result.Diagnostics.Should().BeEmpty();
        result.SymbolsWithHistoricalNames.Should().BeSameAs(result.Symbols);

        AssemblyResult failed = Assemble("    jmp Nowhere");
        failed.Success.Should().BeFalse();
        failed.SymbolsWithHistoricalNames.Should().BeEmpty();
    }
}
