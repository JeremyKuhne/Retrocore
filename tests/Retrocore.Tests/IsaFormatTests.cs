// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu.Z80;
using Retrocore.Isa;

namespace Retrocore.Tests;

/// <summary>
///  The description format's features beyond the 6502's: split opcodes, opcode fields, cycles, literal forms,
///  vectors and entry points.
/// </summary>
[TestClass]
public class IsaFormatTests
{
    private const string Header = """
        [isa]
        literal-forms
        entry-points 0000 0038
        vectors FFFE
        access write LD:Store
        [forms]
        Implied ""
        Store   "[{}],A"    fields=word memory
        Bit     "{},B"      fields=bit
        Index   "[IX{}]"    fields=disp8
        BitIndex "{},[IX{}]" fields=bit,disp8
        [Cpu]
        """;

    /// <summary>
    ///  A <c>*</c> splits an opcode around its operand bytes, and decoding skips them to find the last byte.
    /// </summary>
    [TestMethod]
    public void SplitOpcodesPlaceOperandsBeforeTheLastByte()
    {
        InstructionSet set = Parse("DD CB * 46 BIT BitIndex\nDD 34 INC Index");
        set.TryDecode([0xDD, 0xCB, 0x7E, 0x5E], out int encoding).Should().BeTrue();
        IsaEncoding bit = set.GetEncoding(encoding);
        bit.SplitAt.Should().Be(2);
        bit.OpcodeBytesBeforeOperands.Should().Be(2);
        bit.OpcodeBytePosition(2, operandSize: 1).Should().Be(3);
        set.Size(encoding).Should().Be(4);
        set.TryDecode([0xDD, 0x34, 0x05], out int increment).Should().BeTrue();
        set.MnemonicName(set.GetEncoding(increment).Mnemonic).Should().Be("INC");
    }

    /// <summary>
    ///  <c>entry-points in Name</c> adds entry points to one set and the sets built on it, and <c>target</c> gives an
    ///  instruction the address its opcode implies.
    /// </summary>
    [TestMethod]
    public void SetsHaveTheirOwnEntryPointsAndFixedTargets()
    {
        const string Text = """
            [isa]
            literal-forms
            entry-points 0000
            entry-points in Plus 0024
            entry-points in Plus 003C
            flow call RSTV
            target RSTV 0040
            [forms]
            Implied ""
            [Base]
            00 NOP Implied
            [Plus : Base]
            CB RSTV Implied
            [Derived : Plus]
            01 NOP Implied
            """;

        IsaDescription description = IsaParser.Parse(Text);
        description.InstructionSets["Base"].EntryPoints.Should().Equal(0x0000);
        description.InstructionSets["Plus"].EntryPoints.Should().Equal(0x0000, 0x0024, 0x003C);
        description.InstructionSets["Derived"].EntryPoints.Should().Equal(0x0000, 0x0024, 0x003C);
        description.EntryPoints.Should().Equal(0x0000);

        InstructionSet plus = description.InstructionSets["Plus"];
        plus.TryDecode([0xCB], out int rstv).Should().BeTrue();
        plus.GetEncoding(rstv).FixedTarget.Should().Be(0x0040);
        plus.TryDecode([0x00], out int nop).Should().BeTrue();
        plus.GetEncoding(nop).FixedTarget.Should().BeNull();

        Action unknown = () => IsaParser.Parse(Text.Replace("in Plus 003C", "in Missing 003C", StringComparison.Ordinal));
        unknown.Should().Throw<FormatException>().WithMessage("*unknown instruction set 'Missing'*");
        Action malformed = () => IsaParser.Parse(Text.Replace("target RSTV 0040", "target RSTV", StringComparison.Ordinal));
        malformed.Should().Throw<FormatException>().WithMessage("*target Mnemonic hex-address*");
    }

    /// <summary>
    ///  The <c>conditional</c> line marks instructions by mnemonic or by mnemonic and form; cycles alone do not, as the
    ///  6809's <c>RTI</c> lists two counts without being conditional.
    /// </summary>
    [TestMethod]
    public void ConditionalLineMarksInstructions()
    {
        InstructionSet set = IsaParser.Parse("""
            [isa]
            literal-forms
            conditional CNZ CALL:NZ
            [forms]
            Implied ""
            [Cpu]
            C4 CNZ Implied t=17/11
            CD CALL Implied t=17
            DC CALL NZ t=17/10
            3B RTI Implied t=15/6
            """).InstructionSets["Cpu"];

        bool Conditional(byte opcode) => set.TryDecode([opcode], out int id) && set.GetEncoding(id).IsConditional;
        Conditional(0xC4).Should().BeTrue();
        Conditional(0xDC).Should().BeTrue();
        Conditional(0xCD).Should().BeFalse();
        Conditional(0x3B).Should().BeFalse();

        Retrocore.Cpu.Z80.Z80Isa.InstructionSet.TryDecode([0xC4, 0, 0], out int z80).Should().BeTrue();
        Retrocore.Cpu.Z80.Z80Isa.InstructionSet.GetEncoding(z80).IsConditional.Should().BeTrue("CALL NZ,nn");
    }

    /// <summary>
    ///  A subset may not reuse the name of its base, of another subset or of a set, which would replace it.
    /// </summary>
    /// <param name="subsets">The subset lines.</param>
    [TestMethod]
    [Timeout(10_000)]
    [DataRow("subset Base of Base exclude NOP message \"x\"")]
    [DataRow("subset Small of Base exclude NOP message \"x\"\nsubset Small of Base exclude NOP message \"y\"")]
    [DataRow("subset Other of Base exclude NOP message \"x\"")]
    public void SubsetNamesMustBeNew(string subsets)
    {
        string text = $"""
            [isa]
            {subsets}
            [forms]
            Implied ""
            [Base]
            00 NOP Implied
            [Other : Base]
            01 NOP Implied
            """;

        Action parse = () => IsaParser.Parse(text);
        parse.Should().Throw<FormatException>().WithMessage("*repeats the name*");
    }

    /// <summary>
    ///  A mnemonic made of hex digits, such as the 8080's <c>CC</c>, follows the opcode bytes rather than joining
    ///  them.
    /// </summary>
    [TestMethod]
    public void MnemonicsThatReadAsHexAreNotOpcodeBytes()
    {
        // The 8080's CC (call if carry) at $DC, with and without options after its form.
        foreach (string line in (string[])["DC CC Word", "DC CC Word t=17/11", "DC CC Word t=17/11 undocumented"])
        {
            InstructionSet set = Parse(line);
            set.TryDecode([0xDC, 0x34, 0x12], out int encoding).Should().BeTrue(line);
            set.MnemonicName(set.GetEncoding(encoding).Mnemonic).Should().Be("CC", line);
            set.GetEncoding(encoding).OpcodeLength.Should().Be(1, line);
        }
    }

    /// <summary>
    ///  A bit-number field makes all eight values of opcode bits 3-5 decode to one encoding.
    /// </summary>
    [TestMethod]
    public void OpcodeFieldsCoverEightOpcodes()
    {
        InstructionSet set = Parse("CB 40 BIT Bit");
        for (int bit = 0; bit < 8; bit++)
        {
            set.TryDecode([0xCB, (byte)(0x40 | (bit << 3))], out int encoding).Should().BeTrue();
            encoding.Should().Be(0);
        }

        set.TryDecode([0xCB, 0x41], out _).Should().BeFalse();
        Action parse = () => Parse("CB 48 BIT Bit");
        parse.Should().Throw<FormatException>().WithMessage("*bits 3-5*");
    }

    /// <summary>
    ///  Undeclared forms become literal forms, cycles are recorded, and the setting lists reach the description.
    /// </summary>
    [TestMethod]
    public void ReadsLiteralFormsCyclesAndAddresses()
    {
        InstructionSet set = Parse("78 LD A,B t=4\n32 LD Store t=13\nC8 RET Z t=11/5 undocumented");
        set.Description.Form("A,B")?.Patterns.Should().Equal("A,B");
        // Encodings are in opcode order: $32, $78, $C8.
        set.GetEncoding(1).Cycles.Should().Be(4);
        set.GetEncoding(1).CyclesTaken.Should().Be(4);
        set.GetEncoding(2).Cycles.Should().Be(5);
        set.GetEncoding(2).CyclesTaken.Should().Be(11);
        set.GetEncoding(2).Undocumented.Should().BeTrue();
        set.EncodingAccess(0).Should().Be(MemoryAccess.Write);
        set.EncodingAccess(1).Should().Be(MemoryAccess.Read);
        set.Description.EntryPoints.Should().Equal(0x0000, 0x0038);
        set.Description.Vectors.Should().Equal(0xFFFE);
    }

    /// <summary>
    ///  Malformed opcode lines and forms are rejected with their line.
    /// </summary>
    /// <param name="line">The opcode line or form declaration.</param>
    [TestMethod]
    [DataRow("* 46 BIT BitIndex")]
    [DataRow("DD CB * BIT BitIndex")]
    [DataRow("78 LD A,B t=0")]
    [DataRow("78 LD A,B t=4 t=5")]
    [DataRow("78 LD A,B fast")]
    [DataRow("78 LD A,{}")]
    [DataRow("78 LD A,B\n78 LD A,C")]
    public void RejectsMalformedLines(string line)
    {
        Action parse = () => Parse(line);
        parse.Should().Throw<FormatException>();
    }

    /// <summary>
    ///  A pattern needs a hole per field, or one hole for a field list.
    /// </summary>
    [TestMethod]
    public void FormsNeedHolesForTheirFields()
    {
        Action parse = () => IsaParser.Parse("[isa]\n[forms]\nPair \"{},{},{}\" fields=byte,byte\n");
        parse.Should().Throw<FormatException>().WithMessage("Line 3:*hole*");
    }

    /// <summary>
    ///  The Z80's canonical encodings are its documented ones, and its description gives cycles and flow.
    /// </summary>
    [TestMethod]
    public void Z80CanonicalEncodingsAreDocumented()
    {
        InstructionSet set = Z80Isa.InstructionSet;
        Canonical(set, "BIT", "b,[IX+d]").Should().Be(0x46CBDDu);
        Canonical(set, "IM", "0").Should().Be(0x46EDu);
        Canonical(set, "NEG", "Implied").Should().Be(0x44EDu);
        Canonical(set, "LD", "[nn],HL").Should().Be(0x22u);
        Canonical(set, "NOP", "Implied").Should().Be(0x00u);
        Canonical(set, "RETN", "Implied").Should().Be(0x45EDu);

        set.TryDecode([0x10, 0x00], out int djnz).Should().BeTrue();
        set.GetEncoding(djnz).CyclesTaken.Should().Be(13);
        set.GetEncoding(djnz).Cycles.Should().Be(8);
        set.Flow(djnz).Should().Be(InstructionFlow.ConditionalBranch);
        set.TryDecode([0xC8], out int returnZ).Should().BeTrue();
        set.Flow(returnZ).Should().Be(InstructionFlow.Next, "a conditional return may continue");
        set.TryDecode([0xC9], out int ret).Should().BeTrue();
        set.Flow(ret).Should().Be(InstructionFlow.Return);
        set.Description.Registers.Select(register => register.Name).Should().Contain(["A", "IX", "SP", "AF'"]);
    }

    private static uint Canonical(InstructionSet set, string mnemonic, string form)
    {
        set.TryGet(set.GetMnemonic(mnemonic), set.Description.Form(form)?.Id ?? -1, out int encoding).Should().BeTrue();
        return set.GetEncoding(encoding).Opcode;
    }

    private static InstructionSet Parse(string lines) => IsaParser.Parse($"{Header}\n{lines}\n").InstructionSets["Cpu"];
}
