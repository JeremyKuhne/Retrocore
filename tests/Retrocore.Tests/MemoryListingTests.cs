// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Cpu.I8080;
using Retrocore.Isa;
using Retrocore.Cpu.M6809;
using Retrocore.Cpu.Z80;
using Retrocore.Debug;

namespace Retrocore.Tests;

/// <summary>
///  The targets and names Retrocore Memory's listing gives instruction operands.
/// </summary>
[TestClass]
public sealed class MemoryListingTests
{
    /// <summary>
    ///  A 6809 direct-page operand is an offset in DP's page: with DP at $12, <c>LDA $34</c> accesses $1234, which
    ///  its label names in place of the $34 the text shows; with the page unknown it names nothing.
    /// </summary>
    [TestMethod]
    public void DirectPageOperandsAreInDpsPage()
    {
        bool decoded = Disassembler.TryDecode([0x96, 0x34], address: 0x3000, M6809Isa.InstructionSet, out DisassembledInstruction load);
        decoded.Should().BeTrue();
        (int? target, int? shown) = ListingOperands.OperandAddress(load, directPage: 0x12);
        (target, shown).Should().Be(((int?)0x1234, (int?)0x34));

        SortedDictionary<int, string> names = new() { [0x1234] = "BUFFER", [0x0034] = "ZERO" };
        string text = ListingOperands.Named(load.ToString(), target, shown, names);
        text.Should().Contain("BUFFER").And.NotContain("$34").And.NotContain("ZERO");

        ListingOperands.OperandAddress(load, directPage: -1).Should().Be(((int?)null, (int?)null));
    }

    /// <summary>
    ///  A Z80 restart's target is the address its opcode implies, so <c>RST $08</c> goes to $0008 by its label.
    /// </summary>
    [TestMethod]
    public void RestartsTargetTheirAddress()
    {
        bool decoded = Disassembler.TryDecode([0xCF], address: 0x1000, Z80Isa.InstructionSet, out DisassembledInstruction restart);
        decoded.Should().BeTrue();
        (int? target, int? shown) = ListingOperands.OperandAddress(restart, directPage: null);
        target.Should().Be(0x0008);
        SortedDictionary<int, string> names = new() { [0x0008] = "SYNTAX" };
        ListingOperands.Named(restart.ToString(), target, shown, names).Should().Contain("SYNTAX");
    }

    /// <summary>
    ///  An 8080 restart's text gives its number, as <c>RST 1</c> does for $0008, which the label names in its place.
    /// </summary>
    [TestMethod]
    public void IntelRestartsNameTheirTarget()
    {
        bool decoded = Disassembler.TryDecode([0xCF], address: 0x1000, I8080Isa.InstructionSet, out DisassembledInstruction restart);
        decoded.Should().BeTrue();
        (int? target, int? shown) = ListingOperands.OperandAddress(restart, directPage: null);
        target.Should().Be(0x0008);
        SortedDictionary<int, string> names = new() { [0x0008] = "SYNTAX" };
        string text = ListingOperands.Named(restart.ToString(), target, shown, names);
        text.Should().Be(restart.ToString().Replace(" 1", " SYNTAX", StringComparison.Ordinal), restart.ToString());
    }

    /// <summary>
    ///  A 65C02 bit branch names its destination, the last operand, even where the byte it tests has the same value,
    ///  as <c>BBR0 $12,$0012</c> does.
    /// </summary>
    [TestMethod]
    public void BitBranchesNameTheirDestination()
    {
        InstructionSet set = M6502Isa.Description.InstructionSets["Wdc65C02"];
        bool decoded = Disassembler.TryDecode([0x0F, 0x12, 0x0F], address: 0x0000, set, out DisassembledInstruction branch);
        decoded.Should().BeTrue();
        (int? target, int? shown) = ListingOperands.OperandAddress(branch, directPage: null);
        target.Should().Be(0x0012);
        SortedDictionary<int, string> names = new() { [0x0012] = "DEST" };
        string text = ListingOperands.Named(branch.ToString(), target, shown, names);
        text.Should().EndWith("DEST", branch.ToString()).And.Contain("$12,", branch.ToString());
    }
}
