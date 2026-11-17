// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

extern alias Generator;

using Retrocore.Assembler;
using System.Runtime.InteropServices;
using GeneratorAssembly = Generator::Retrocore.Assembler;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

/// <summary>
///  Span lexer compatibility, expression semantics and allocation regression checks.
/// </summary>
[TestClass]
public class AssemblerSpanTests
{
    /// <summary>
    ///  Checks direct BCL casing preserves canonical strings and leaves editable mixed-case input unchanged.
    /// </summary>
    /// <param name="operation">The model's original spelling.</param>
    /// <param name="kind">The statement category.</param>
    /// <param name="operand">The native operand.</param>
    /// <param name="firstByte">The expected encoding.</param>
    [TestMethod]
    [DataRow("LDA", AssemblyStatementKind.Instruction, "#$42", (byte)0xA9)]
    [DataRow("lDa", AssemblyStatementKind.Instruction, "#$42", (byte)0xA9)]
    [DataRow(".BYTE", AssemblyStatementKind.Data, "$42", (byte)0x42)]
    [DataRow(".bYtE", AssemblyStatementKind.Data, "$42", (byte)0x42)]
    public void ModelOperationCasingUsesBclSemantics(
        string operation,
        AssemblyStatementKind kind,
        string operand,
        byte firstByte)
    {
        NativeAssembler assembler = new();
        AssemblyProject project = new();
        project.Statements.Add(new(kind, operation, new(operand)));
        AssemblyResult result = assembler.Assemble(project, new(ProcessorVariant.Mos6502, origin: 0, imageSize: 8));
        result.Success.Should().BeTrue();
        result.Sections[0].Bytes.Span[0].Should().Be(firstByte);
        result.SourceMap[0].Operation.Should().Be(operation.ToUpperInvariant());
        project.Statements[0].Operation.Should().BeSameAs(operation);
        if (operation == operation.ToUpperInvariant())
        {
            result.SourceMap[0].Operation.Should().BeSameAs(operation);
        }
    }

    /// <summary>
    ///  Checks linked .NET Standard symbol evaluation does not acquire temporary-string allocations.
    /// </summary>
    [TestMethod]
    public void LinkedExpressionEvaluationAllocatesNoTemporaryObjects()
    {
        GeneratorAssembly.AssemblySymbols symbols = new();
        symbols.SetValue("VALUE", value: 42);
        ReadOnlyMemory<char> expression = " VALUE + VALUE + (VALUE * 2) ".AsMemory();
        for (int index = 0; index < 100; index++)
        {
            GeneratorAssembly.ExpressionEvaluator warmup = new(expression, symbols, address: 0, line: 0);
            warmup.TryEvaluate(out _).Should().BeTrue();
        }

        long total = 0;
        long allocated = Allocations.During(() =>
        {
            total = 0;
            for (int index = 0; index < 1000; index++)
            {
                GeneratorAssembly.ExpressionEvaluator evaluator = new(expression, symbols, address: 0, line: 0);
                if (!evaluator.TryEvaluate(out long value))
                {
                    throw new InvalidOperationException("Linked symbol lookup failed.");
                }

                total += value;
            }
        });

        total.Should().Be(168000);
        allocated.Should().Be(0);
    }

    /// <summary>
    ///  Checks built-in memory trimming preserves whitespace semantics and the original memory owner.
    /// </summary>
    /// <param name="text">The original memory slice.</param>
    /// <param name="expected">The trimmed contents.</param>
    [TestMethod]
    [DataRow("", "")]
    [DataRow(" \t\r\n", "")]
    [DataRow("value", "value")]
    [DataRow(" \tvalue \r\n", "value")]
    [DataRow("\u00A0\u2003value\u2003\u00A0", "value")]
    [DataRow("  a b  ", "a b")]
    [DataRow("' '", "' '")]
    public void TrimmingRetainsTheOriginalMemory(string text, string expected)
    {
        string original = "[" + text + "]";
        ReadOnlySpan<char> characters = text;
        ReadOnlyMemory<char> trimmed = original.AsMemory(1, text.Length).Trim();
        trimmed.ToString().Should().Be(expected);
        MemoryMarshal.TryGetString(trimmed, out string? owner, out int start, out int length).Should().BeTrue();
        owner.Should().BeSameAs(original);
        start.Should().Be(1 + text.Length - characters.TrimStart().Length);
        length.Should().Be(expected.Length);
        ReadOnlyMemory<char> empty = default;
        empty.Trim().IsEmpty.Should().BeTrue();
    }

    /// <summary>
    ///  Checks numeric syntax, precedence, extraction and checked arithmetic without regex tokens.
    /// </summary>
    /// <param name="text">The expression.</param>
    /// <param name="expected">Its exact signed value.</param>
    [TestMethod]
    [DataRow("1 + 2 * 3", 7L)]
    [DataRow("(1 + 2) * 3", 9L)]
    [DataRow("1 | 2 ^ 3 & 4", 3L)]
    [DataRow("1 << 2 + 1", 8L)]
    [DataRow("16 >> 2", 4L)]
    [DataRow("<$1234", 0x34L)]
    [DataRow(">$1234", 0x12L)]
    [DataRow("~0", -1L)]
    [DataRow("-(-42)", 42L)]
    [DataRow("+5", 5L)]
    [DataRow("5 / 2", 2L)]
    [DataRow("1 = 1", 1L)]
    [DataRow("1 == 2", 0L)]
    [DataRow("1 != 2", 1L)]
    [DataRow("1 < 2", 1L)]
    [DataRow("1 <= 1", 1L)]
    [DataRow("2 > 1", 1L)]
    [DataRow("2 >= 3", 0L)]
    [DataRow("%101010 + 0x10", 58L)]
    [DataRow("' ' + ';' + ','", 135L)]
    [DataRow("* + 2", 0x1236L)]
    [DataRow("9223372036854775807", long.MaxValue)]
    [DataRow("$FFFFFFFFFFFFFFFF", -1L)]
    [DataRow("$8000000000000000", long.MinValue)]
    [DataRow("%1111111111111111111111111111111111111111111111111111111111111111", -1L)]
    public void ExpressionsPreserveNativeSemantics(string text, long expected)
    {
        ExpressionEvaluator evaluator = new(text.AsMemory(), new AssemblySymbols(), address: 0x1234, line: 0);
        evaluator.TryEvaluate(out long value).Should().BeTrue();
        value.Should().Be(expected);
    }

    /// <summary>
    ///  Checks malformed expressions stay explicit diagnostics rather than partial evaluations.
    /// </summary>
    /// <param name="text">The invalid expression.</param>
    /// <param name="message">The diagnostic fragment.</param>
    [TestMethod]
    [DataRow("", "Invalid")]
    [DataRow("   ", "Invalid")]
    [DataRow("1 +", "Missing")]
    [DataRow("(1 + 2", "parenthesis")]
    [DataRow("1 2", "suffix")]
    [DataRow("'AB'", "one character")]
    [DataRow("''", "one character")]
    [DataRow("$", "Invalid")]
    [DataRow("%", "Invalid")]
    [DataRow("1 @ 2", "Invalid")]
    [DataRow("9223372036854775808", "overflow")]
    [DataRow("$10000000000000000", "overflow")]
    [DataRow("%10000000000000000000000000000000000000000000000000000000000000000", "overflow")]
    [DataRow("1 / 0", "Division")]
    [DataRow("1 << -1", "shift")]
    [DataRow("1 >> 64", "shift")]
    public void InvalidExpressionsRemainDiagnostics(string text, string message)
    {
        Action evaluate = () =>
        {
            ExpressionEvaluator evaluator = new(text.AsMemory(), new AssemblySymbols(), address: 0, line: 0);
            evaluator.TryEvaluate(out _);
        };

        evaluate.Should().Throw<AssemblyError>().Which.Message.Should().Contain(message);
    }

    /// <summary>
    ///  Checks the linked .NET Standard matcher and runtime parser agree on statement syntax and locations.
    /// </summary>
    /// <param name="text">Native source, including mixed line endings and Unicode word tails.</param>
    [TestMethod]
    [DataRow("entry:\tlda #1\n.export entry")]
    [DataRow("; heading\r\nentry: lda #';'\r.byte ' ', ',', '\"'\n.export entry")]
    [DataRow("name_\u00E9:\tnop\r\n")]
    [DataRow("Value = (1 + 2) * 3\n.word Value")]
    [DataRow("entry:")]
    [DataRow(".unsupported 1")]
    [DataRow("lda#1")]
    [DataRow(".")]
    public void LinkedAndRuntimeParsersAgree(string text)
    {
        AssemblyParseResult runtime = NativeAssembler.Parse(new(text, "span.asm"));
        GeneratorAssembly.AssemblyParseResult linked = GeneratorAssembly.Assembler.Parse(new(text, "span.asm"));
        linked.Success.Should().Be(runtime.Success);
        linked.Diagnostics.Select(error => (error.Message, error.Location?.Line))
            .Should().Equal(runtime.Diagnostics.Select(error => (error.Message, error.Location?.Line)));

        linked.Project.Statements.Select(node => (node.Operation, node.Operand.Text, node.Label, node.Location?.Line))
            .Should().Equal(
                runtime.Project.Statements.Select(
                    node => (node.Operation, node.Operand.Text, node.Label, node.Location?.Line)));
    }

    /// <summary>
    ///  Checks quote-aware compaction, physical lines and per-element current addresses survive compilation.
    /// </summary>
    [TestMethod]
    public void CompilationPreservesQuotesLocationsAndOperandSpelling()
    {
        NativeAssembler assembler = new();
        AssemblySource source = new("; comment\r\nentry: lda # ' ' ; comment\r.byte ',', ';', '\"'\n.word *, *");
        AssemblyResult result = assembler.Assemble(source, new(ProcessorVariant.Mos6502, origin: 0x2000, imageSize: 9));
        result.Success.Should().BeTrue();
        result.Sections[0].Bytes.ToArray().Should().Equal(0xA9, 0x20, 0x2C, 0x3B, 0x22, 0x05, 0x20, 0x07, 0x20);
        result.SourceMap.Select(entry => entry.Location?.Line).Should().Equal(1, 2, 3);
        result.SourceMap[0].Operand.Should().Be("# ' '");
    }

    /// <summary>
    ///  Checks multiple layout passes reuse symbol storage without losing forward-reference convergence.
    /// </summary>
    [TestMethod]
    public void ForwardConstantsAndZeroPageLayoutStillConverge()
    {
        NativeAssembler assembler = new();
        AssemblyResult result = assembler.Assemble(
            new AssemblySource("First = Second\nSecond = $42\nlda First\nlda Target\nTarget:\n.byte 0"),
            new(ProcessorVariant.Mos6502, origin: 0xFA, imageSize: 8));

        result.Success.Should().BeTrue();
        result.Symbols["First"].Should().Be(0x42);
        result.Symbols["Target"].Should().Be(0xFE);
        result.Sections[0].Bytes.Span[..5].ToArray().Should().Equal(0xA5, 0x42, 0xA5, 0xFE, 0);
    }

    /// <summary>
    ///  Checks a location-counter expression is never reused from a pass where an earlier instruction was wider.
    /// </summary>
    [TestMethod]
    public void LocationCounterExpressionsAreReevaluatedEachPass()
    {
        // The first pass encodes the forward zero-page load as absolute, placing the .org target one byte later.
        NativeAssembler assembler = new();
        AssemblyResult result = assembler.Assemble(
            new AssemblySource("lda Zero\n.org * + 4\nAfter:\n.byte 1\nZero = $10"),
            new(ProcessorVariant.Mos6502, origin: 0x1000, imageSize: 8));

        result.Success.Should().BeTrue();
        result.Symbols["After"].Should().Be(0x1006);
        result.Sections[0].Bytes.Span[..7].ToArray().Should().Equal(0xA5, 0x10, 0, 0, 0, 0, 1);
    }

    /// <summary>
    ///  Checks operands that only start and end with parentheses are expressions, not indirect addressing.
    /// </summary>
    /// <param name="text">The instruction.</param>
    /// <param name="expected">The expected encoding.</param>
    [TestMethod]
    [DataRow("jmp (Base)+(Offset)", new byte[] { 0x4C, 0x30, 0x00 })]
    [DataRow("lda (Base)+(Offset),y", new byte[] { 0xB9, 0x30, 0x00 })]
    [DataRow("lda (Base+Offset)", new byte[] { 0xB2, 0x30 })]
    [DataRow("lda (Base),y", new byte[] { 0xB1, 0x10 })]
    [DataRow("lda ((Base)+(Offset),x)", new byte[] { 0xA1, 0x30 })]
    [DataRow("lda #(')')", new byte[] { 0xA9, 0x29 })]
    public void IndirectOperandsRequireOneEnclosingGroup(string text, byte[] expected)
    {
        NativeAssembler assembler = new();
        AssemblyResult result = assembler.Assemble(
            new AssemblySource($".cpu Wdc65C02\nBase = $10\nOffset = $20\n{text}"),
            new(ProcessorVariant.Wdc65C02, origin: 0x1000, imageSize: 4));

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..expected.Length].ToArray().Should().Equal(expected);
    }

    /// <summary>
    ///  Checks string literals emit ASCII, and .hiascii sets bit 7 on strings and numbers alike.
    /// </summary>
    /// <param name="text">The data directive.</param>
    /// <param name="expected">The expected bytes.</param>
    [TestMethod]
    [DataRow(".byte \"HI\", 0", new byte[] { 0x48, 0x49, 0x00 })]
    [DataRow(".hiascii \"HI\", $0D", new byte[] { 0xC8, 0xC9, 0x8D })]
    [DataRow(".HiAscii $C1", new byte[] { 0xC1 })]
    [DataRow(".byte \"A;B\" ; comment", new byte[] { 0x41, 0x3B, 0x42 })]
    [DataRow(".byte \"a b\", ',', \"\", 1", new byte[] { 0x61, 0x20, 0x62, 0x2C, 0x01 })]
    [DataRow(".byte \"AB\", <*", new byte[] { 0x41, 0x42, 0x12 })]
    public void StringLiteralsEmitOneBytePerCharacter(string text, byte[] expected)
    {
        NativeAssembler assembler = new();
        AssemblyResult result = assembler.Assemble(
            new AssemblySource(text),
            new(ProcessorVariant.Mos6502, origin: 0x10, imageSize: 8));

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..expected.Length].ToArray().Should().Equal(expected);
        result.SourceMap[0].Size.Should().Be(expected.Length);
    }

    /// <summary>
    ///  Checks strings are rejected outside byte data and must be ASCII.
    /// </summary>
    /// <param name="text">The invalid statement.</param>
    /// <param name="message">The expected diagnostic fragment.</param>
    [TestMethod]
    [DataRow(".word \"AB\"", "only valid in .byte and .hiascii")]
    [DataRow(".byte \"\u00E9\"", "ASCII")]
    [DataRow("lda #\"A\"", "Invalid expression")]
    [DataRow(".byte \"A\"+1", "Invalid expression")]
    public void StringLiteralsAreOnlyByteData(string text, string message)
    {
        NativeAssembler assembler = new();
        AssemblyResult result = assembler.Assemble(
            new AssemblySource(text),
            new(ProcessorVariant.Mos6502, origin: 0, imageSize: 8));

        result.Diagnostics.Single().Message.Should().Contain(message);
    }

    /// <summary>
    ///  Checks .section starts named fixed-size outputs with their own origins and bounds.
    /// </summary>
    [TestMethod]
    public void SectionsHaveIndependentOriginsAndBounds()
    {
        NativeAssembler assembler = new();
        AssemblyResult result = assembler.Assemble(
            new AssemblySource(string.Join(
                "\n",
                "Start: lda #1",
                "Vectors: .section Vectors, $FFFA, 6",
                ".word Start, Start, Start",
                ".section Data, $2000, 8",
                ".org $2004",
                "Table: .byte 1")),
            new(ProcessorVariant.Mos6502, origin: 0xC000, imageSize: 4));

        result.Diagnostics.Should().BeEmpty();
        result.Sections.Select(section => section.Name).Should().Equal(".text", "Vectors", "Data");
        result.Sections.Select(section => section.Origin).Should().Equal(0xC000, 0xFFFA, 0x2000);

        result.Sections[0].Bytes.ToArray().Should().Equal(0xA9, 0x01, 0, 0);
        result.Sections[1].Bytes.ToArray().Should().Equal(0x00, 0xC0, 0x00, 0xC0, 0x00, 0xC0);
        result.Sections[2].Bytes.ToArray().Should().Equal(0, 0, 0, 0, 1, 0, 0, 0);
        result.Symbols["Vectors"].Should().Be(0xFFFA);
        result.Symbols["Table"].Should().Be(0x2004);
    }

    /// <summary>
    ///  Checks section declarations that conflict or overflow are diagnosed at the section.
    /// </summary>
    /// <param name="text">The invalid source.</param>
    /// <param name="message">The expected diagnostic fragment.</param>
    [TestMethod]
    [DataRow("nop\n.section Low, $C002, 4", "overlaps section '.text'")]
    [DataRow(".section A, $D000, 2\n.section A, $E000, 2", "Duplicate section 'A'")]
    [DataRow(".section A, $FFFE, 2\n.byte 1, 2, 3", "exceeds the current section")]
    [DataRow(".section A, $FFFE, 3", "64 KiB")]
    [DataRow(".section A, $D000", "name, origin and size")]
    [DataRow(".section $D000, $D000, 1", "name, origin and size")]
    public void InvalidSectionsAreDiagnosed(string text, string message)
    {
        NativeAssembler assembler = new();
        AssemblyResult result = assembler.Assemble(
            new AssemblySource(text),
            new(ProcessorVariant.Mos6502, origin: 0xC000, imageSize: 4));

        result.Diagnostics.Single().Message.Should().Contain(message);
    }

    /// <summary>
    ///  Padding to an address with .res or .org works when the counter is past that address only until forward
    ///  references to zero page shrink, as for a module placed in a file after one whose code ends there.
    /// </summary>
    /// <param name="padding">The padding statement.</param>
    [TestMethod]
    [DataRow(".res $2004 - *")]
    [DataRow(".org $2004")]
    public void PaddingAllowsCodeThatShrinks(string padding)
    {
        NativeAssembler assembler = new();
        AssemblyResult result = assembler.Assemble(
            new AssemblySource(string.Join(
                '\n',
                ".logicalorg $1E00",
                "lda Later",
                "lda Later",
                ".logicalorg",
                padding,
                ".byte $EE",
                "Later = $10")),
            new(ProcessorVariant.Mos6502, origin: 0x2000, imageSize: 5));

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.ToArray().Should().Equal(0xA5, 0x10, 0xA5, 0x10, 0xEE);
    }

    /// <summary>
    ///  Padding to an address the final layout has already passed is still an error.
    /// </summary>
    /// <param name="padding">The padding statement.</param>
    /// <param name="message">The expected diagnostic fragment.</param>
    [TestMethod]
    [DataRow(".res $2003 - *", "exceeds the current section")]
    [DataRow(".org $2003", "cannot overlap or move backwards")]
    public void PaddingBehindTheFinalLayoutIsDiagnosed(string padding, string message)
    {
        NativeAssembler assembler = new();
        AssemblyResult result = assembler.Assemble(
            new AssemblySource(string.Join(
                '\n',
                "lda Later",
                "lda Later",
                padding,
                ".byte $EE",
                "Later = $10")),
            new(ProcessorVariant.Mos6502, origin: 0x2000, imageSize: 8));

        result.Diagnostics.Single().Message.Should().Contain(message);
    }

    /// <summary>
    ///  Checks parsing reports every invalid line rather than stopping at the first.
    /// </summary>
    [TestMethod]
    public void ParsingReportsEveryInvalidLine()
    {
        AssemblyParseResult parsed = NativeAssembler.Parse(new("lda? #1\nlda #1\n.bogus 1\n\n%%", "many.asm"));
        parsed.Success.Should().BeFalse();
        parsed.Diagnostics.Select(diagnostic => diagnostic.Location?.Line).Should().Equal(0, 2, 4);
        parsed.Project.Statements.Should().ContainSingle();
    }

    /// <summary>
    ///  Checks declaration and first-pass layout errors are all reported, in statement order.
    /// </summary>
    [TestMethod]
    public void LayoutReportsEveryIndependentStatementError()
    {
        NativeAssembler assembler = new();
        AssemblyResult result = assembler.Assemble(
            new AssemblySource("xyz #1\nSame:\nSame:\nlda #1\n.cpu Nope\nlda ($12),x,y"),
            new(ProcessorVariant.Mos6502, origin: 0, imageSize: 16));

        result.Success.Should().BeFalse();
        result.Diagnostics.Select(diagnostic => diagnostic.StatementIndex).Should().Equal(0, 2, 4, 5);
        result.Diagnostics[1].Message.Should().Contain("Duplicate symbol 'Same'");
    }

    /// <summary>
    ///  Checks emission reports every statement whose final value is invalid.
    /// </summary>
    [TestMethod]
    public void EmissionReportsEveryInvalidValue()
    {
        NativeAssembler assembler = new();
        AssemblyResult result = assembler.Assemble(
            new AssemblySource("lda #$100\nnop\nldx #Missing\n.assert 0\n.export Gone"),
            new(ProcessorVariant.Mos6502, origin: 0, imageSize: 16));

        result.Success.Should().BeFalse();
        result.Sections.Should().BeEmpty();
        result.Diagnostics.Select(diagnostic => diagnostic.Message).Should().SatisfyRespectively(
            message => message.Should().Contain("byte range"),
            message => message.Should().Contain("Export 'Gone'"),
            message => message.Should().Contain("Unresolved expression 'Missing'"),
            message => message.Should().Contain("assertion failed"));
    }

    /// <summary>
    ///  Checks every forced-width syntax keeps the absolute form of a zero-page value.
    /// </summary>
    /// <param name="text">The instruction.</param>
    /// <param name="expected">The expected encoding.</param>
    [TestMethod]
    [DataRow("lda a:$12", new byte[] { 0xAD, 0x12, 0x00 })]
    [DataRow("lda A:Zero,x", new byte[] { 0xBD, 0x12, 0x00 })]
    [DataRow("lda !$12,y", new byte[] { 0xB9, 0x12, 0x00 })]
    [DataRow("lda.w Zero", new byte[] { 0xAD, 0x12, 0x00 })]
    [DataRow("STA.W $12,X", new byte[] { 0x9D, 0x12, 0x00 })]
    [DataRow("lda $12", new byte[] { 0xA5, 0x12 })]
    public void WidthSyntaxForcesAbsoluteAddressing(string text, byte[] expected)
    {
        NativeAssembler assembler = new();
        AssemblyResult result = assembler.Assemble(
            new AssemblySource($"Zero = $12\n{text}"),
            new(ProcessorVariant.Mos6502, origin: 0x1000, imageSize: 4));

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..expected.Length].ToArray().Should().Equal(expected);
    }

    /// <summary>
    ///  Checks a forced width is rejected where no absolute address form applies.
    /// </summary>
    /// <param name="text">The instruction.</param>
    [TestMethod]
    [DataRow("lda a:#1")]
    [DataRow("lda.w #1")]
    [DataRow("lda !($12),y")]
    [DataRow("stx a:$12,y")]
    public void WidthSyntaxRequiresAnAbsoluteAddressForm(string text)
    {
        NativeAssembler assembler = new();
        AssemblyResult result = assembler.Assemble(
            new AssemblySource(text),
            new(ProcessorVariant.Mos6502, origin: 0x1000, imageSize: 4));

        result.Success.Should().BeFalse();
    }

    /// <summary>
    ///  Checks numeric literals accept either hexadecimal prefix case and only ASCII digits.
    /// </summary>
    [TestMethod]
    public void NumericLiteralsUseAsciiDigits()
    {
        NativeAssembler assembler = new();
        AssemblyOptions options = new(ProcessorVariant.Mos6502, origin: 0, imageSize: 4);
        assembler.Assemble(new AssemblySource("lda #0X1f\nldx #0x1F"), options)
            .Sections[0].Bytes.Span.ToArray().Should().Equal(0xA9, 0x1F, 0xA2, 0x1F);

        AssemblyResult result = assembler.Assemble(new AssemblySource("lda #\u0663"), options);
        result.Success.Should().BeFalse();
        result.Diagnostics.Single().Message.Should().Contain("Invalid expression");
    }

    /// <summary>
    ///  Checks an operand that leaves zero page whenever its instruction shrinks still converges.
    /// </summary>
    [TestMethod]
    public void OscillatingZeroPageOperandSettlesAsAbsolute()
    {
        // A zero-page load moves Label down a byte, which pushes Value to $100; the absolute form brings it back.
        NativeAssembler assembler = new();
        AssemblyResult result = assembler.Assemble(
            new AssemblySource("lda Value\nLabel:\nValue = $1102 - Label"),
            new(ProcessorVariant.Mos6502, origin: 0x1000, imageSize: 4));

        result.Diagnostics.Should().BeEmpty();
        result.Symbols["Value"].Should().Be(0xFF);
        result.Sections[0].Bytes.Span[..3].ToArray().Should().Equal(0xAD, 0xFF, 0x00);
    }

    /// <summary>
    ///  Checks expressions that resolve only in a later pass replay every operator as interpretation would.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   Forward is defined last, so each constant is unresolved in the first pass, recorded, and then replayed
    ///   both by the second pass and by emission.
    ///  </para>
    /// </remarks>
    [TestMethod]
    public void RecordedExpressionsReplayEveryOperator()
    {
        const long Forward = 0x1234;
        NativeAssembler assembler = new();
        AssemblyResult result = assembler.Assemble(
            new AssemblySource(string.Join(
                "\n",
                "Negated = -Forward + 1",
                "Bytes = <Forward | (>Forward << 8)",
                "Complement = ~Forward & $FF",
                "Arithmetic = (Forward * 3 - 1) / 2",
                "Compared = Forward >= $1000 = 1",
                "Different = Forward ^ $FFFF != 0",
                "Located = * + Forward",
                "Shifted = Forward >> 4",
                "lda Forward - $1200",
                "Forward = $1234")),
            new(ProcessorVariant.Mos6502, origin: 0x1000, imageSize: 4));

        result.Diagnostics.Should().BeEmpty();
        result.Symbols["Negated"].Should().Be(-Forward + 1);
        result.Symbols["Bytes"].Should().Be(Forward);
        result.Symbols["Complement"].Should().Be(~Forward & 0xFF);
        result.Symbols["Arithmetic"].Should().Be(((Forward * 3) - 1) / 2);
        result.Symbols["Compared"].Should().Be(1);
        result.Symbols["Different"].Should().Be(1);
        result.Symbols["Located"].Should().Be(0x1000 + Forward);
        result.Symbols["Shifted"].Should().Be(Forward >> 4);
        result.Sections[0].Bytes.Span[..2].ToArray().Should().Equal(0xA5, 0x34);
    }

    /// <summary>
    ///  Checks value errors that appear only once a later pass resolves the operands are still reported.
    /// </summary>
    /// <param name="text">The source.</param>
    /// <param name="message">The expected diagnostic fragment.</param>
    [TestMethod]
    [DataRow("Ratio = 1 / (Later - Here)\nHere:\nLater:", "Division by zero")]
    [DataRow("Shifted = 1 << (Later - Here + 64)\nHere:\nLater:", "Invalid shift count")]
    [DataRow("Huge = $7FFFFFFFFFFFFFFF + (Later - Here + 1)\nHere:\nLater:", "Expression overflow")]
    [DataRow("lda Missing", "Unresolved expression 'Missing'")]
    public void RecordedExpressionsReportLaterValueErrors(string text, string message)
    {
        NativeAssembler assembler = new();
        AssemblyResult result = assembler.Assemble(
            new AssemblySource(text),
            new(ProcessorVariant.Mos6502, origin: 0x1000, imageSize: 8));

        result.Diagnostics.Single().Message.Should().Contain(message);
    }

    /// <summary>
    ///  Checks literal layout values reused across passes still lay out at each pass's shifted address.
    /// </summary>
    [TestMethod]
    public void LiteralLayoutValuesSurviveShiftingPasses()
    {
        NativeAssembler assembler = new();
        AssemblyResult result = assembler.Assemble(
            new AssemblySource("lda Zero\n.res 2, $FF\n.org $1008\nAfter:\n.byte 1\nZero = $10"),
            new(ProcessorVariant.Mos6502, origin: 0x1000, imageSize: 16));

        result.Success.Should().BeTrue();
        result.Symbols["Zero"].Should().Be(0x10);
        result.Symbols["After"].Should().Be(0x1008);
        result.Sections[0].Bytes.Span[..9].ToArray().Should().Equal(0xA5, 0x10, 0xFF, 0xFF, 0, 0, 0, 0, 1);
    }

    /// <summary>
    ///  Checks checked expression overflow is surfaced as a compiler diagnostic.
    /// </summary>
    /// <param name="text">An overflowing expression.</param>
    [TestMethod]
    [DataRow("9223372036854775807 + 1")]
    [DataRow("-$8000000000000000")]
    [DataRow("$8000000000000000 / -1")]
    public void ArithmeticOverflowRemainsADiagnostic(string text)
    {
        NativeAssembler assembler = new();
        AssemblyResult result = assembler.Assemble(
            new AssemblySource("Value = " + text),
            new(ProcessorVariant.Mos6502, origin: 0, imageSize: 8));

        result.Success.Should().BeFalse();
        result.Diagnostics.Single().Message.Should().Contain("overflow");
    }

    /// <summary>
    ///  Checks operand compaction falls back to pooled storage without losing quoted whitespace.
    /// </summary>
    [TestMethod]
    public void LargeOperandsUseThePooledBufferPath()
    {
        string operand = "#" + new string(c: ' ', count: 512) + "' '";
        AssemblySyntax.Compact(operand).Should().Be("#' '");
        string compact = "#' '";
        AssemblySyntax.Compact(compact).Should().BeSameAs(compact);
    }

    /// <summary>
    ///  Checks both parsers classify original spans and retain spelling instead of normalizing model text.
    /// </summary>
    /// <param name="operation">The operation as written in the source.</param>
    /// <param name="operand">The native operand syntax.</param>
    [TestMethod]
    [DataRow("lDa", "#1")]
    [DataRow(".bYtE", "1")]
    [DataRow(".wOrD", "1")]
    [DataRow(".rEs", "1")]
    [DataRow(".oRg", "0")]
    [DataRow(".cPu", "Mos6502")]
    [DataRow(".aSsErT", "1")]
    [DataRow(".eXpOrT", "Entry")]
    public void ParsingPreservesOperationSpelling(string operation, string operand)
    {
        string text = "Entry:\n" + operation + " " + operand;
        AssemblyParseResult native = NativeAssembler.Parse(new(text));
        GeneratorAssembly.AssemblyParseResult linked = GeneratorAssembly.Assembler.Parse(new(text));
        native.Success.Should().BeTrue();
        linked.Success.Should().BeTrue();
        native.Project.Statements[1].Operation.Should().Be(operation);
        linked.Project.Statements[1].Operation.Should().Be(operation);
        NativeAssembler assembler = new();
        assembler.Assemble(native.Project, new(ProcessorVariant.Mos6502, origin: 0, imageSize: 8))
            .Diagnostics.Should().BeEmpty();
    }

    /// <summary>
    ///  Checks symbol lookup compares slice contents, remains ordinal and supports reused evaluator cursors.
    /// </summary>
    [TestMethod]
    public void ExpressionEvaluationAllocatesNoTemporaryObjects()
    {
        AssemblySymbols symbols = new();
        symbols.SetValue("VALUE", value: 42);
        ReadOnlyMemory<char> expression = " VALUE + VALUE + (VALUE * 2) ".AsMemory();
        for (int index = 0; index < 100; index++)
        {
            ExpressionEvaluator warmup = new(expression, symbols, address: 0, line: 0);
            warmup.TryEvaluate(out _).Should().BeTrue();
        }

        long total = 0;
        long allocated = Allocations.During(() =>
        {
            total = 0;
            for (int index = 0; index < 1000; index++)
            {
                ExpressionEvaluator evaluator = new(expression, symbols, address: 0, line: 0);
                if (!evaluator.TryEvaluate(out long value))
                {
                    throw new InvalidOperationException("Symbol lookup failed.");
                }

                total += value;
            }
        });

        total.Should().Be(168000);
        allocated.Should().Be(0);
        ExpressionEvaluator missing = new("value".AsMemory(), symbols, address: 0, line: 0);
        missing.TryEvaluate(out _).Should().BeFalse();
    }

    /// <summary>
    ///  Checks line and operand cursors allocate no strings, arrays or iterator objects.
    /// </summary>
    [TestMethod]
    public void LineAndOperandCursorsAllocateNoTemporaryObjects()
    {
        ReadOnlyMemory<char> lines = "one\r\ntwo\rthree\n".AsMemory();
        ReadOnlyMemory<char> operands = "(1 + 2), ',', ';', (4+(5)), ' '".AsMemory();
        CountSlices(lines, operands).Should().Be(9);
        int count = 0;
        long allocated = Allocations.During(() =>
        {
            count = 0;
            for (int index = 0; index < 1000; index++) { count += CountSlices(lines, operands); }
        });

        count.Should().Be(9000);
        allocated.Should().Be(0);
    }

    private static int CountSlices(ReadOnlyMemory<char> lines, ReadOnlyMemory<char> operands)
    {
        int count = 0;
        foreach (ReadOnlyMemory<char> line in new AssemblyLines(lines)) { count++; }
        foreach (ReadOnlyMemory<char> operand in new AssemblyOperands(operands, line: 0)) { count++; }
        return count;
    }
}
