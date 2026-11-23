// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

/// <summary>
///  The native dialect shares ca65's text definitions, types, character map, data directives and functions,
///  with native expression syntax.
/// </summary>
[TestClass]
public class NativeExtensionTests
{
    /// <summary>
    ///  Each native source produces the expected bytes without diagnostics.
    /// </summary>
    /// <param name="text">The source.</param>
    /// <param name="expected">The leading output bytes.</param>
    [TestMethod]
    [DataRow(".define TWO 2\n.byte TWO, TWO * 3", new byte[] { 2, 6 })]
    [DataRow(
        ".define PAIR(a, b) a, b\n.byte PAIR 1, 2\n.undefine PAIR\nPAIR = 9\n.byte PAIR",
        new byte[] { 1, 2, 9 })]
    [DataRow(
        ".enum Mode\nIMP\nIMM = 5\nZP\n.endenum\n.byte Mode::IMP, Mode::IMM, Mode::ZP",
        new byte[] { 0, 5, 6 })]
    [DataRow(".enum\nA0\nA1\n.endenum\n.byte A1", new byte[] { 1 })]
    [DataRow(
        ".struct Point\nx .byte\ny .word\n.endstruct\n.byte Point::x, Point::y, .sizeof(Point)",
        new byte[] { 0, 1, 3 })]
    [DataRow(
        ".struct Point\nx .byte\ny .word\n.endstruct\nP: .tag Point\n.byte .sizeof(P)",
        new byte[] { 0, 0, 0, 3 })]
    [DataRow(".charmap 'A', $C1\n.byte \"AB\", 'A'", new byte[] { 0xC1, 0x42, 0xC1 })]
    [DataRow(".asciiz \"Hi\"", new byte[] { 0x48, 0x69, 0 })]
    [DataRow(".lobytes $1234, $5678\n.hibytes $1234, $5678", new byte[] { 0x34, 0x78, 0x12, 0x56 })]
    [DataRow(".byte .strlen(\"abc\"), .strat(\"abc\", 1)", new byte[] { 3, 0x62 })]
    [DataRow("M_3 = 7\n.byte .ident(.concat(\"M_\", .string(1 + 2)))", new byte[] { 7 })]
    [DataRow(".byte .strlen(.sprintf(\"%02X-%d%s\", 10, 7, \"ab\"))", new byte[] { 6 })]
    [DataRow(".byte .max(3, 9), .min(3, 9), .max(-1, 1)", new byte[] { 9, 3, 1 })]
    [DataRow(".word .loword($123456), .hiword($123456)", new byte[] { 0x56, 0x34, 0x12, 0 })]
    [DataRow(
        "X = 1\n.ifconst X\n.byte 1\n.endif\n.ifnconst Later\n.byte 2\n.endif\nLater:",
        new byte[] { 1, 2 })]
    [DataRow(
        ".ifnblank 1\n.byte 1\n.endif\n.ifp02\n.byte 2\n.endif\n.ifpc02\n.byte 3\n.endif",
        new byte[] { 1, 2 })]
    [DataRow(
        ".macro M\n.endmacro\n.ifdef M\n.byte 1\n.endif\n.byte .defined(M), .definedmacro(M)",
        new byte[] { 1, 0, 1 })]
    [DataRow("Known = 1\n.if .defined(Known) && Known = 1\n.byte 5\n.endif", new byte[] { 5 })]
    [DataRow(".out \"note\"\n.warning \"ignored\"\n.byte 1", new byte[] { 1 })]
    [DataRow("CPU_6502 = 7\n.byte CPU_6502", new byte[] { 7 })]
    public void NativeSourcesUseSharedFeatures(string text, byte[] expected)
    {
        AssemblyResult result = Assemble(text);
        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..expected.Length].ToArray().Should().Equal(expected);
    }

    /// <summary>
    ///  An equate can name the size of a structure, a procedure or a scope, before or after it, as data can, though
    ///  a procedure's or scope's size is known only once it is assembled.
    /// </summary>
    /// <param name="text">The source.</param>
    /// <param name="expected">The leading output bytes.</param>
    [TestMethod]
    [DataRow(
        ".struct Point\nx .byte\ny .word\n.endstruct\nSIZE = .sizeof(Point)\n.byte SIZE",
        new byte[] { 3 })]
    [DataRow(
        "SIZE = .sizeof(Point)\n.struct Point\nx .byte\ny .word\n.endstruct\n.byte SIZE",
        new byte[] { 3 })]
    [DataRow(
        ".proc Block\n.res 3, $EA\n.endproc\n.byte .sizeof(Block)\nSIZE = .sizeof(Block)\n.byte SIZE",
        new byte[] { 0xEA, 0xEA, 0xEA, 3, 3 })]
    [DataRow(
        "SIZE = .sizeof(Block)\n.proc Block\n.res 3, $EA\n.endproc\n.byte SIZE",
        new byte[] { 0xEA, 0xEA, 0xEA, 3 })]
    [DataRow(
        ".scope Table\nFirst: .byte 1\nSecond: .word 2\n.endscope\nSIZE = .sizeof(Table) * 2 + 1\n.byte SIZE",
        new byte[] { 1, 2, 0, 7 })]
    [DataRow(
        "SIZE = .sizeof(Table)\n.scope Table\nFirst: .byte 1\nSecond: .word 2\n.endscope\n.byte SIZE",
        new byte[] { 1, 2, 0, 3 })]
    [DataRow(
        ".scope Outer\nSIZE = .sizeof(Inner)\n.proc Inner\nnop\nnop\n.endproc\n.endscope\n.byte Outer::SIZE",
        new byte[] { 0xEA, 0xEA, 2 })]
    public void EquatesNameSizes(string text, byte[] expected)
    {
        AssemblyResult result = Assemble(text);
        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..expected.Length].ToArray().Should().Equal(expected);
    }

    /// <summary>
    ///  Data can name the size of a structure or union defined later, including one nested in a scope, rather than
    ///  the empty layout of the scope that holds its fields.
    /// </summary>
    [TestMethod]
    public void DataNamesSizesOfLaterTypes()
    {
        AssemblyResult result = Assemble("""
            .byte .sizeof(Point), .sizeof(Outer::Pair), .sizeof(Either)
            .struct Point
            x .byte
            y .word
            .endstruct
            .scope Outer
            .struct Pair
            first .dword
            second .tag Point
            .endstruct
            .endscope
            .union Either
            narrow .word
            wide .dword
            .endunion
            .byte .sizeof(Point), .sizeof(Outer::Pair), .sizeof(Either)
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..6].ToArray().Should().Equal(3, 7, 4, 3, 7, 4);
    }

    /// <summary>
    ///  A structure defined later has its size inside an anonymous scope, and in the ca65 dialect, whose statements
    ///  go through the linker.
    /// </summary>
    /// <param name="text">The source.</param>
    /// <param name="ca65">Whether the source is in the ca65 dialect.</param>
    [TestMethod]
    [DataRow(".scope\n.byte .sizeof(Point)\n.struct Point\nfirst .byte\nsecond .word\n.endstruct\n.endscope", false)]
    [DataRow(".scope\n.scope Inner\n.byte .sizeof(Point)\n.struct Point\nfirst .byte\nsecond .word\n.endstruct\n.endscope\n.endscope", false)]
    [DataRow(".byte .sizeof(Point)\n.struct Point\nfirst .byte\nsecond .word\n.endstruct", true)]
    public void LaterTypesHaveTheirSizeInEveryLayout(string text, bool ca65)
    {
        AssemblyResult result = new NativeAssembler().Assemble(
            new AssemblySource(text, "main.asm"),
            new AssemblyOptions(ProcessorVariant.Mos6502, origin: 0x1000, imageSize: 32)
            {
                Dialect = ca65 ? AssemblyDialect.Ca65 : AssemblyDialect.Native
            });

        result.Diagnostics.Should().BeEmpty();
        ReadOnlySpan<byte> bytes = ca65 ? result.Files["output.bin"].Span : result.Sections[0].Bytes.Span;
        bytes[0].Should().Be(3);
    }

    /// <summary>
    ///  Conditional assembly runs before a procedure is assembled, so its size, directly or through an equate, is not
    ///  yet known there, and neither is it unknown for good: <c>.ifconst</c> refuses it rather than choose a branch.
    /// </summary>
    /// <param name="condition">The conditional directive and its operand.</param>
    /// <param name="ca65">Whether the source is in the ca65 dialect.</param>
    /// <param name="message">The error it reports.</param>
    [TestMethod]
    [DataRow(".if .sizeof(Block) = 2", false, "Conditional requires a constant known at this point in source order.")]
    [DataRow(".if SIZE = 2", false, "Conditional requires a constant known at this point in source order.")]
    [DataRow(".ifconst SIZE", false, "Conditional requires a constant known at this point in source order.")]
    [DataRow(".ifnconst NEXT", false, "Conditional requires a constant known at this point in source order.")]
    [DataRow(".ifconst .sizeof(Block)", false, "Conditional requires a constant known at this point in source order.")]
    [DataRow(".ifconst SIZE", true, "ca65 directive requires a constant known at this point.")]
    [DataRow(".if 1 || .sizeof(Block) = 2", false, "Conditional requires a constant known at this point in source order.")]
    [DataRow(".if 1 || NEXT = 2", false, "Conditional requires a constant known at this point in source order.")]
    public void ConditionsCannotUseAProcedureSize(string condition, bool ca65, string message)
    {
        AssemblyResult result = new NativeAssembler().Assemble(
            new AssemblySource(
                $".proc Block\nnop\nnop\n.endproc\nSIZE = .sizeof(Block)\nNEXT = SIZE + 1\n{condition}\n.byte 1\n.endif",
                "main.asm"),
            new AssemblyOptions(ProcessorVariant.Mos6502, origin: 0x1000, imageSize: 32)
            {
                Dialect = ca65 ? AssemblyDialect.Ca65 : AssemblyDialect.Native
            });

        result.Diagnostics.Select(diagnostic => diagnostic.Message).Should().Equal(message);
    }

    /// <summary>
    ///  A variable's historical name keeps the procedure size it had when it was documented, so <c>.ifconst</c>
    ///  refuses it too.
    /// </summary>
    [TestMethod]
    public void AHistoricalNameOfAProcedureSizeIsNotYetKnown()
    {
        AssemblyResult result = Assemble("""
            .proc Block
            nop
            nop
            .endproc
            ;; The width.
            ;; Also: OLD (TEST)
            Width .set .sizeof(Block)
            Width .set 9
            .ifconst OLD
            .byte 1
            .endif
            """);

        result.Diagnostics.Select(diagnostic => diagnostic.Message).Should().Equal(
            "Conditional requires a constant known at this point in source order.");
    }

    /// <summary>
    ///  <c>.const</c> refuses a procedure's size, directly or through an equate, rather than call it unknown.
    /// </summary>
    /// <param name="operand">The <c>.const</c> operand.</param>
    [TestMethod]
    [DataRow(".sizeof(Block)")]
    [DataRow("NEXT")]
    public void ConstRefusesAProcedureSize(string operand)
    {
        Assemble($".proc Block\nnop\n.endproc\nSIZE = .sizeof(Block)\nNEXT = SIZE + 1\n.byte .const({operand})")
            .Diagnostics.Select(diagnostic => diagnostic.Message)
            .Should().Equal(".const cannot test a size known only once the program is laid out.");
    }

    /// <summary>
    ///  A variable given a procedure's size and then an ordinary value is a known constant again.
    /// </summary>
    [TestMethod]
    public void AVariableReassignedFromASizeIsKnownAgain()
    {
        AssemblyResult result = Assemble("""
            .proc Block
            nop
            .endproc
            V .set .sizeof(Block)
            .byte V
            V .set 7
            .ifconst V
            .byte V, .const(V)
            .endif
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..4].ToArray().Should().Equal(0xEA, 1, 7, 1);
    }

    /// <summary>
    ///  A procedure or scope whose code is not one run of addresses has no one size: a <c>.logicalorg</c> in it, or a
    ///  storage map across one of its ends, is refused wherever its size is used.
    /// </summary>
    /// <param name="body">The procedure's body and what follows it, up to the use of its size.</param>
    /// <param name="use">The statement that uses its size.</param>
    [TestMethod]
    [DataRow("nop\n.logicalorg $0300\nnop\n.endproc", ".byte .sizeof(Block)")]
    [DataRow("nop\n.dum $80\nZero: .res 4\n.endproc\n.dend", ".byte .sizeof(Block)")]
    [DataRow("nop\n.dum $80\nZero: .res 4\n.endproc\n.dend", "SIZE = .sizeof(Block)\n.byte SIZE")]
    [DataRow("nop\n.dum $80\nZero: .res 4\n.endproc\n.dend", ".assert .sizeof(Block) = 1")]
    public void SizesNeedOneRunOfAddresses(string body, string use)
    {
        Assemble($".proc Block\n{body}\n{use}").Diagnostics.Select(diagnostic => diagnostic.Message)
            .Should().Contain(".sizeof requires a contiguous scope or procedure: no section or .logicalorg changes, no storage map across its ends, and not a continued scope.");
    }

    /// <summary>
    ///  A storage map that a procedure opened outside it ends inside it leaves the procedure without one size.
    /// </summary>
    [TestMethod]
    public void AStorageMapEndingInsideAProcedureLeavesItWithoutASize()
    {
        Assemble(".dum $80\n.proc Block\nZero: .res 4\n.dend\nnop\n.endproc\n.byte .sizeof(Block)")
            .Diagnostics.Select(diagnostic => diagnostic.Message)
            .Should().Equal(".sizeof requires a contiguous scope or procedure: no section or .logicalorg changes, no storage map across its ends, and not a continued scope.");
    }

    /// <summary>
    ///  A storage map that opens in one procedure and ends in the next leaves both without one size: the first ends
    ///  inside the map, and the second starts inside it.
    /// </summary>
    /// <param name="use">The procedure whose size is used.</param>
    [TestMethod]
    [DataRow("First")]
    [DataRow("Second")]
    public void AStorageMapAcrossTwoProceduresLeavesBothWithoutASize(string use)
    {
        Assemble($".proc First\nnop\n.dum $80\nZero: .res 2\n.endproc\n.proc Second\nOne: .res 1\n.dend\nnop\n.endproc\n.byte .sizeof({use})")
            .Diagnostics.Select(diagnostic => diagnostic.Message)
            .Should().Equal(".sizeof requires a contiguous scope or procedure: no section or .logicalorg changes, no storage map across its ends, and not a continued scope.");
    }

    /// <summary>
    ///  An <c>.org</c> only moves forward, filling the gap, so like <c>.align</c> it leaves a procedure one run of
    ///  addresses whose size counts the fill. A storage map wholly inside a procedure adds nothing to its size, even
    ///  with an <c>.org</c> placing its fields, and a scope wholly inside a storage map has the size of the storage
    ///  it lays out.
    /// </summary>
    [TestMethod]
    public void OriginsAndStorageMapsWhollyInsideKeepSizes()
    {
        AssemblyResult result = Assemble("""
            .proc Filled
            nop
            .org $1004
            nop
            .endproc
            .proc Block
            nop
            .dum $80
            Zero: .res 2
            .org $90
            Later: .res 1
            .dend
            nop
            .endproc
            .dum $A0
            .scope Variables
            Pointer: .res 2
            .org $A4
            Count: .res 1
            .endscope
            .dend
            .byte .sizeof(Filled), .sizeof(Block), .sizeof(Variables), <Block::Later
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..11].ToArray().Should().Equal(
            0xEA, 0, 0, 0, 0xEA, 0xEA, 0xEA, 5, 2, 5, 0x90);
    }

    /// <summary>
    ///  A table can be built from definitions named by computed identifiers, as the Monitor's disassembler does.
    /// </summary>
    [TestMethod]
    public void RepeatBuildsTablesFromComputedNames()
    {
        AssemblyResult result = Assemble("""
            .macro Entry index, value
            .ident(.concat("E_", .string(index))) = value
            .endmacro
            Entry 2, $22
            Entry 0, $11
            .repeat 3, i
            .ifdef .ident(.concat("E_", .string(i)))
            .byte .ident(.concat("E_", .string(i)))
            .else
            .byte 0
            .endif
            .endrepeat
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..3].ToArray().Should().Equal(0x11, 0, 0x22);
    }

    /// <summary>
    ///  A source with no expansion still takes the native fast path, and errors keep their native wording.
    /// </summary>
    [TestMethod]
    public void ErrorsKeepNativeMessages()
    {
        Assemble(".if Later\n.endif\nLater:").Diagnostics.Single().Message
            .Should().Be("Conditional requires a constant known at this point in source order.");

        Assemble(".error \"stop\"").Diagnostics.Single().Message.Should().Be("stop");
        Assemble(".byte .sprintf(\"%d\")").Diagnostics.Single().Message.Should().Contain("too few");
        Assemble(".byte .referenced(X)").Diagnostics.Single().Message.Should().Contain("unsupported");
    }

    /// <summary>
    ///  A label on a preprocessing directive's line names the address where the directive appears.
    /// </summary>
    /// <param name="text">The source, assembled at $1000.</param>
    /// <param name="expected">The leading output bytes.</param>
    [TestMethod]
    [DataRow("L: .if 1\n.byte 1\n.endif\n.word L", new byte[] { 1, 0x00, 0x10 })]
    [DataRow(".byte 9\nR: .repeat 2\n.byte 1\n.endrepeat\n.word R", new byte[] { 9, 1, 1, 0x01, 0x10 })]
    [DataRow(".byte 9\nD: .define X 3\n.byte X\n.word D", new byte[] { 9, 3, 0x01, 0x10 })]
    [DataRow(".byte 9\nC: .charmap 'A', 1\n.byte 'A'\n.word C", new byte[] { 9, 1, 0x01, 0x10 })]
    [DataRow(".byte 9\nM: .macro Two\n.byte 2\n.endmacro\nTwo\n.word M", new byte[] { 9, 2, 0x01, 0x10 })]
    [DataRow(".if 1\n.byte 1\nE: .else\n.byte 2\n.endif\n.word E", new byte[] { 1, 0x01, 0x10 })]
    [DataRow(".if 0\nE: .else\n.endif\nE = 5\n.byte E", new byte[] { 5 })]
    [DataRow(".if 0\nL: .if 1\n.endif\n.endif\nL = 5\n.byte L", new byte[] { 5 })]
    [DataRow(".if 0\n.byte 1\nL: .endif\nL = 5\n.byte L", new byte[] { 5 })]
    [DataRow(".if 1\n.byte 1\nL: .endif\n.word L", new byte[] { 1, 0x01, 0x10 })]
    [DataRow(".macro Here\nH: .if 1\n.endif\n.endmacro\n.byte 9\nHere\n.word H", new byte[] { 9, 0x01, 0x10 })]
    [DataRow(".byte 9\n: .if 1\n.endif\n.word :-", new byte[] { 9, 0x01, 0x10 })]
    public void LabelsOnPreprocessingLinesAreDefined(string text, byte[] expected)
    {
        AssemblyResult result = Assemble(text);
        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..expected.Length].ToArray().Should().Equal(expected);
    }

    /// <summary>
    ///  A label cannot be on the line that closes a macro or repeat, since it ends every expansion.
    /// </summary>
    /// <param name="text">The source.</param>
    [TestMethod]
    [DataRow(".repeat 2\n.byte 1\nL: .endrepeat")]
    [DataRow(".macro M\n.byte 1\nL: .endmacro")]
    public void LabelsOnClosingLinesAreErrors(string text) =>
        Assemble(text).Diagnostics.Single().Message.Should().Contain("label cannot be on");

    /// <summary>
    ///  Other assemblers' <c>&lt;&gt;</c> is an error rather than a less-than of a high byte.
    /// </summary>
    /// <param name="text">The source.</param>
    [TestMethod]
    [DataRow(".byte 1 <> 2")]
    [DataRow("X = 1\n.if X <> 2\n.endif")]
    [DataRow(".macro M\n.endmacro\n.byte 1<>2")]
    public void InequalityNeedsBang(string text) =>
        Assemble(text).Diagnostics.Single().Message.Should().Contain("Use != for inequality");

    /// <summary>
    ///  A character literal holds one character whether or not the source is preprocessed.
    /// </summary>
    /// <param name="text">The source.</param>
    [TestMethod]
    [DataRow(".byte 'AB'")]
    [DataRow(".macro M\n.endmacro\n.byte 'AB'")]
    [DataRow(".byte .strlen(\"x\"), 'AB'")]
    [DataRow(".charmap 'A', 1\n.byte 'AB'")]
    public void CharacterLiteralsHoldOneCharacter(string text) =>
        Assemble(text).Diagnostics.Single().Message.Should().Contain("holds one character");

    /// <summary>
    ///  The <c>.ifp*</c> tests follow the latest <c>.cpu</c> in source order, and the host's CPU before one.
    /// </summary>
    /// <param name="text">The source.</param>
    /// <param name="expected">The output bytes.</param>
    [TestMethod]
    [DataRow(
        ".ifp02\n.byte 1\n.endif\n.cpu Wdc65C02\n.ifpwc02\n.byte 2\n.endif\n.ifp02\n.byte 3\n.endif",
        new byte[] { 1, 2 })]
    [DataRow(
        ".cpu 65sc02\n.ifpsc02\n.byte 1\n.endif\n.cpu Rockwell65C02\n.ifpc02\n.byte 2\n.endif",
        new byte[] { 1, 2 })]
    [DataRow(".cpu Z80\n.ifp02\n.byte 1\n.endif\n.byte 2", new byte[] { 2 })]
    [DataRow(".cpu M6809\n.ifp02\n.byte 1\n.endif\n.byte 2", new byte[] { 2 })]
    [DataRow(".cpu I8080\n.ifp02\n.byte 1\n.endif\n.byte 2", new byte[] { 2 })]
    [DataRow(".cpu I8085\n.ifp02\n.byte 1\n.endif\n.byte 2", new byte[] { 2 })]
    public void CpuConditionsFollowCpu(string text, byte[] expected)
    {
        AssemblyResult result = Assemble(text);
        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..expected.Length].ToArray().Should().Equal(expected);
        result.Sections[0].Bytes.Span[expected.Length..].IndexOfAnyExcept((byte)0).Should().Be(-1);
    }

    private static AssemblyResult Assemble(string text) =>
        new NativeAssembler().Assemble(
            new AssemblySource(text, "main.asm"),
            new AssemblyOptions(ProcessorVariant.Mos6502, origin: 0x1000, imageSize: 32));
}
