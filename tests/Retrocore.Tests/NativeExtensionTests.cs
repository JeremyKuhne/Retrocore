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
