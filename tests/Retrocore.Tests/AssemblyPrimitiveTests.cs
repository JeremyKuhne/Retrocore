// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

extern alias Generator;

using Retrocore.Assembler;
using System.Runtime.CompilerServices;
using GeneratorAssembly = Generator::Retrocore.Assembler;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

/// <summary>
///  Verifies compiler primitives shared by native and translated dialects.
/// </summary>
[TestClass]
public class AssemblyPrimitiveTests
{
    /// <summary>
    ///  Extra source-map metadata is offset by removing redundant strings from private layout storage.
    /// </summary>
    [TestMethod]
    public void LayoutStorageRemainsCompact() => Unsafe.SizeOf<LayoutStatement>().Should().Be(80);

    /// <summary>
    ///  Re-entering a section preserves its address, offset and accumulated bytes.
    /// </summary>
    [TestMethod]
    public void NativeSectionsResumeTheirOwnCounters()
    {
        AssemblyResult result = Assemble("""
            .byte $11
            .section Data, $2000, 4
            D0: .byte $22
            .section Code, $3000, 4
            .byte $33
            .section Data
            D1: .byte $44
            .section .text
            .byte $55
            """, size: 4);

        result.Diagnostics.Should().BeEmpty();
        result.Sections.Select(section => section.Name).Should().Equal(".text", "Data", "Code");
        result.Sections[0].Bytes.ToArray().Should().Equal(0x11, 0x55, 0, 0);
        result.Sections[1].Bytes.ToArray().Should().Equal(0x22, 0x44, 0, 0);
        result.Sections[2].Bytes.ToArray().Should().Equal(0x33, 0, 0, 0);
        result.Symbols["D1"].Should().Be(0x2001);
        result.Symbols["__Data_SIZE__"].Should().Be(2);
        result.Symbols["__Code_LOAD__"].Should().Be(0x3000);
        AssemblySourceMapEntry map = result.SourceMap.Single(entry => entry.Label == "D1");
        map.Section.Should().Be(1);
        map.Offset.Should().Be(1);
        map.Address.Should().Be(0x2001);
    }

    /// <summary>
    ///  Placement participates in convergence as forward references shrink predecessor sections.
    /// </summary>
    [TestMethod]
    public void AutomaticPlacementUsesPreviousPassSizes()
    {
        AssemblyProject project = NativeAssembler.Parse(new("""
            .section First
            lda Zero
            FirstEnd:
            .section Second
            SecondStart: .word FirstEnd
            Zero = $10
            """)).Project;

        project.SectionDefinitions.Add(new("First", origin: 0x1000, size: 8));
        project.SectionDefinitions.Add(new("Second", size: 8) { Alignment = 4 });
        AssemblyResult result = new NativeAssembler().Assemble(project, new(ProcessorVariant.Mos6502, 0x1000, 16));
        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.IsEmpty.Should().BeTrue();
        result.Sections[1].Bytes.ToArray().Should().Equal(0xA5, 0x10);
        result.Sections[2].Origin.Should().Be(0x1004);
        result.Sections[2].Bytes.ToArray().Should().Equal(0x02, 0x10);
        result.Symbols["FirstEnd"].Should().Be(0x1002);
        result.Symbols["SecondStart"].Should().Be(0x1004);
        result.Symbols["__First_SIZE__"].Should().Be(2);
        result.Symbols["__Second_LOAD__"].Should().Be(0x1004);
        result.Symbols["__Second_RUN__"].Should().Be(0x1004);
    }

    /// <summary>
    ///  Trim and fill affect output padding without changing logical section size symbols.
    /// </summary>
    [TestMethod]
    public void NativeSectionPaddingCanBeFilledOrTrimmed()
    {
        AssemblyResult result = Assemble("""
            .section Filled, $2000, 4, $FF
            .org $2002
            .byte $AA
            .section Trimmed, $3000, 8, $CC, 1
            .res 2, $11
            """, size: 1);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[1].Bytes.ToArray().Should().Equal(0xFF, 0xFF, 0xAA, 0xFF);
        result.Sections[2].Bytes.ToArray().Should().Equal(0x11, 0x11);
        result.Sections[1].Size.Should().Be(4);
        result.Sections[2].Size.Should().Be(2);
        result.Symbols["__Filled_SIZE__"].Should().Be(3);
    }

    /// <summary>
    ///  Logical origins change labels and per-element * values, not file placement.
    /// </summary>
    [TestMethod]
    public void LogicalOriginsDoNotPadOrMoveFileOffsets()
    {
        AssemblyResult result = Assemble("""
            Mapped: .logicalorg $8000
            start: lda #<*
            .word *, *
            .org * + 2
            .byte $CC
            .logicalorg $42
            zp: .byte <*
            .export start, zp
            """, size: 10);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.ToArray().Should().Equal(0xA9, 0, 2, 0x80, 4, 0x80, 0, 0, 0xCC, 0x42);
        result.Symbols["Mapped"].Should().Be(0x8000);
        result.Symbols["start"].Should().Be(0x8000);
        result.Symbols["zp"].Should().Be(0x42);
        AssemblySourceMapEntry map = result.SourceMap.Single(entry => entry.Label == "zp");
        map.Offset.Should().Be(9);
        map.Address.Should().Be(0x42);
    }

    /// <summary>
    ///  An empty .logicalorg ends the logical region, returning the counter to the section's own address.
    /// </summary>
    [TestMethod]
    public void EmptyLogicalOriginReturnsToTheSectionAddress()
    {
        AssemblyResult result = Assemble(".byte 1\n.logicalorg $8000\nmapped: nop\n.logicalorg\nback: .word *", size: 4);
        result.Diagnostics.Should().BeEmpty();
        result.Symbols["mapped"].Should().Be(0x8000);
        result.Symbols["back"].Should().Be(0x1002);
        result.Sections[0].Bytes.ToArray().Should().Equal(1, 0xEA, 2, 0x10);
    }

    /// <summary>
    ///  Run addresses and load addresses remain distinct through section re-entry.
    /// </summary>
    [TestMethod]
    public void SectionRunOriginsDriveLabelsAndRelativeBranches()
    {
        AssemblyProject project = NativeAssembler.Parse(new("""
            .section Relocated
            Entry: nop
            bne Entry
            .section .text
            .byte $22
            .section Relocated
            .word *
            """)).Project;

        project.SectionDefinitions.Add(new("Relocated", origin: 0x2000, size: 8) { RunOrigin = 0x8000 });
        AssemblyResult result = new NativeAssembler().Assemble(project, new(ProcessorVariant.Mos6502, 0x1000, 8));
        result.Diagnostics.Should().BeEmpty();
        result.Sections[1].Origin.Should().Be(0x2000);
        result.Sections[1].RunOrigin.Should().Be(0x8000);
        result.Sections[1].Bytes.ToArray().Should().Equal(0xEA, 0xD0, 0xFD, 3, 0x80);
        result.Symbols["__Relocated_LOAD__"].Should().Be(0x2000);
        result.Symbols["__Relocated_RUN__"].Should().Be(0x8000);
        result.SourceMap.Single(entry => entry.Label == "Entry").Offset.Should().Be(0);
    }

    /// <summary>
    ///  Dummy storage advances logical addresses but does not consume the image's limited capacity.
    /// </summary>
    [TestMethod]
    public void DummyRegionsRestoreTheOutputLocation()
    {
        AssemblyResult result = Assemble("""
            .byte $11
            .dum $20
            Work: .res 4
            Next: .word *
            .dend
            After: .byte $22
            .export Work, Next, After
            """, size: 2);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.ToArray().Should().Equal(0x11, 0x22);
        result.Symbols["Work"].Should().Be(0x20);
        result.Symbols["Next"].Should().Be(0x24);
        result.Symbols["After"].Should().Be(0x1001);
        result.SourceMap.Single(entry => entry.Label == "Next").Size.Should().Be(0);
        result.SourceMap.Single(entry => entry.Label == "After").Offset.Should().Be(1);
    }

    /// <summary>
    ///  BSS occupies memory after the final code size while contributing no file bytes.
    /// </summary>
    [TestMethod]
    public void BssParticipatesInPlacementWithoutEmittingBytes()
    {
        AssemblyProject project = NativeAssembler.Parse(new("""
            .section Code
            lda #$10
            .section Bss
            Counter: .res 3
            .section Code
            .word Counter
            """)).Project;

        project.SectionDefinitions.Add(new("Code", origin: 0x1000, size: 16));
        project.SectionDefinitions.Add(new("Bss", size: 8) { NoOutput = true });
        AssemblyResult result = new NativeAssembler().Assemble(project, new(ProcessorVariant.Mos6502, 0x1000, 16));
        result.Diagnostics.Should().BeEmpty();
        result.Sections[1].Bytes.ToArray().Should().Equal(0xA9, 0x10, 4, 0x10);
        result.Sections[2].Origin.Should().Be(0x1004);
        result.Sections[2].Size.Should().Be(3);
        result.Sections[2].Bytes.IsEmpty.Should().BeTrue();
        result.Symbols["Counter"].Should().Be(0x1004);
        result.Symbols["__Bss_SIZE__"].Should().Be(3);
        result.SourceMap.Single(entry => entry.Label == "Counter").Size.Should().Be(0);
    }

    /// <summary>
    ///  No-output instructions and data still receive normal final-value validation.
    /// </summary>
    [TestMethod]
    public void DummyEmissionStillValidatesOperands()
    {
        AssemblyResult result = Assemble(".dum $20\nlda #$100\n.word Missing\n.dend", size: 1);
        result.Success.Should().BeFalse();
        result.Diagnostics.Should().HaveCount(2);
        result.Diagnostics[0].Message.Should().Contain("byte range");
        result.Diagnostics[1].Message.Should().Contain("Unresolved");
    }

    /// <summary>
    ///  Alignments and checksums operate on the final, independently mapped output.
    /// </summary>
    [TestMethod]
    public void AlignmentDwordsAndChecksumsEmitExactBytes()
    {
        AssemblyResult aligned = Assemble("lda Zero\n.align 4, $EA\n.dword $12345678\nZero = $10", size: 8);
        aligned.Diagnostics.Should().BeEmpty();
        aligned.Sections[0].Bytes.ToArray().Should().Equal(0xA5, 0x10, 0xEA, 0xEA, 0x78, 0x56, 0x34, 0x12);
        aligned.SourceMap.Single(entry => entry.Operation == ".ALIGN").Size.Should().Be(2);

        // ca65 accepts a negative .dword and emits its two's-complement form.
        Assemble(".dword -1", size: 4).Sections[0].Bytes.ToArray().Should().Equal(0xFF, 0xFF, 0xFF, 0xFF);
        AssemblyResult checksum = Assemble(".byte 1, 2, 3\n.checksum\n.byte $40\n.checksum", size: 6);
        checksum.Diagnostics.Should().BeEmpty();
        checksum.Sections[0].Bytes.ToArray().Should().Equal(1, 2, 3, 0, 0x40, 0x40);
    }

    /// <summary>
    ///  Each instruction's width is chosen using the values available at its first layout.
    /// </summary>
    [TestMethod]
    public void SourceOrderWidthDoesNotShrinkForwardReferences()
    {
        const string Source = "lda Later\nLater = $42\nlda Later\nldx z:Other\nOther = $20";
        AssemblyResult result = Assemble(Source, size: 7, policy: AssemblyWidthPolicy.SourceOrder);
        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.ToArray().Should().Equal(0xAD, 0x42, 0, 0xA5, 0x42, 0xA6, 0x20);
        Assemble(Source, size: 6).Sections[0].Bytes.ToArray().Should().Equal(0xA5, 0x42, 0xA5, 0x42, 0xA6, 0x20);
    }

    /// <summary>
    ///  Width overrides can coexist without changing the assembly's default shrink policy.
    /// </summary>
    [TestMethod]
    public void StatementWidthOverridesAreIndependent()
    {
        AssemblyProject project = NativeAssembler.Parse(new("lda Forward\nlda Forward\nForward = $12")).Project;
        project.Statements[0].WidthPolicy = AssemblyWidthPolicy.SourceOrder;
        AssemblyResult result = new NativeAssembler().Assemble(project, new(ProcessorVariant.Mos6502, 0x1000, 5));
        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.ToArray().Should().Equal(0xAD, 0x12, 0, 0xA5, 0x12);
    }

    /// <summary>
    ///  Transient widths may exceed capacity, but final bounds must still reject genuine overflows.
    /// </summary>
    [TestMethod]
    public void ShrinkingCanFitExactCapacityWithoutRelaxingFinalBounds()
    {
        AssemblyResult fitting = Assemble("lda Zero\nZero = $10", origin: 0xFFFE, size: 2);
        fitting.Diagnostics.Should().BeEmpty();
        fitting.Sections[0].Bytes.ToArray().Should().Equal(0xA5, 0x10);
        AssemblyResult overflow = Assemble("lda Later\n.res 3\nLater = $1000", size: 5);
        overflow.Diagnostics.Single().StatementIndex.Should().Be(1);
        overflow.Sections.Should().BeEmpty();
    }

    /// <summary>
    ///  Zero-page prefixes accept direct and already zero-page-only address forms.
    /// </summary>
    [TestMethod]
    public void ZeroPagePrefixesForceOrConfirmAddressWidth()
    {
        AssemblyResult result = Assemble("lda z:Forward\nstx z:$10,y\nlda z:($20),y\nForward = $42", size: 6);
        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.ToArray().Should().Equal(0xA5, 0x42, 0x96, 0x10, 0xB1, 0x20);
        AssemblySyntax.AbsolutePrefixLength("a::b").Should().Be(0);
        AssemblySyntax.ZeroPagePrefixLength("z::b").Should().Be(0);
    }

    /// <summary>
    ///  CPU switches resolve opcodes in source order, including the 65SC02 subset.
    /// </summary>
    [TestMethod]
    public void CpuSwitchesDoNotRetroactivelyChangeInstructions()
    {
        AssemblyResult result = Assemble("""
            .cpu Mos6502
            slo $10
            .cpu 65SC02
            stz $20
            .cpu Rockwell65C02
            rmb0 $30
            .cpu Wdc65C02
            wai
            .cpu Mos6502
            slo $40
            """, size: 9);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.ToArray().Should().Equal(0x07, 0x10, 0x64, 0x20, 0x07, 0x30, 0xCB, 0x07, 0x40);
        Assemble("stz $10\n.cpu Wdc65C02", size: 2).Sections[0].Bytes.ToArray().Should().Equal(0x64, 0x10);
        AssemblyResult invalid = Assemble(".cpu Wdc65C02\nwai\n.cpu Mos6502\nwai");
        invalid.Diagnostics.Single().StatementIndex.Should().Be(3);
    }

    /// <summary>
    ///  Each assignment's references remain tied to that version across repeated layout passes.
    /// </summary>
    [TestMethod]
    public void SetAssignmentsAreVersionedAndPublicNamesArePreserved()
    {
        AssemblyResult result = Assemble("""
            .set Value, 1
            .byte Value
            Value .set Value + 1
            .byte Value
            Value: .set Value + 2
            .byte Value
            .export Value
            """, size: 3);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.ToArray().Should().Equal(1, 2, 4);
        result.Symbols.Keys.Should().Equal("Value");
        result.Exports["Value"].Should().Be(4);
        result.SymbolDefinitions.Single().IsConstant.Should().BeTrue();
        result.SourceMap.Where(entry => entry.Operation == ".SET").Select(entry => entry.Label)
            .Should().Equal("Value", "Value", "Value");

        result.SourceMap.Last().Operand.Should().Be("Value");
        AssemblyResult shifting = Assemble(
            ".set N, 0\nlda Zero\n.set N, N + 1\n.byte N\n.set N, N + 1\n.byte N\nZero = $10",
            size: 4);

        shifting.Diagnostics.Should().BeEmpty();
        shifting.Sections[0].Bytes.ToArray().Should().Equal(0xA5, 0x10, 1, 2);
        shifting.Symbols["N"].Should().Be(2);
    }

    /// <summary>
    ///  Substitution avoids strings, longer names, width prefixes, registers and generated-name collisions.
    /// </summary>
    [TestMethod]
    public void SetResolutionIsTokenAndSyntaxAware()
    {
        AssemblyResult result = Assemble("""
            __retro_set_N_1 = 9
            .set N, 1
            Name = 2
            .byte "N", N, Name, __retro_set_N_1
            .set X, $20
            .set A, $10
            lda $40,X
            asl A
            .byte X, A
            .set a, 9
            .set z, 8
            lda a:$10
            lda z:$10
            .byte a, z
            """, size: 16);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.ToArray().Should().Equal(
            0x4E,
            1,
            2,
            9,
            0xB5,
            0x40,
            0x0A,
            0x20,
            0x10,
            0xAD,
            0x10,
            0,
            0xA5,
            0x10,
            9,
            8);

        result.Symbols["__retro_set_N_1"].Should().Be(9);
    }

    /// <summary>
    ///  Version resolution preserves independent errors rather than hiding earlier use-before-assignment.
    /// </summary>
    [TestMethod]
    public void SetResolutionReportsSourceOrderErrorsAlongsideInstructionErrors()
    {
        AssemblyResult result = Assemble("bogus\n.byte N\n.set N, 1");
        result.Diagnostics.Select(error => error.StatementIndex).Should().Equal(0, 1);
        result.Diagnostics[1].Message.Should().Contain("before assignment");
        Assemble(".set N, 1\nN: nop").Diagnostics.Should().Contain(error => error.Message.Contains("Duplicate symbol"));
    }

    /// <summary>
    ///  New expression operators agree between the runtime interpreter and the linked generator.
    /// </summary>
    /// <param name="text">The expression.</param>
    /// <param name="expected">Its signed value.</param>
    [TestMethod]
    [DataRow(".not 0", 1L)]
    [DataRow(".NOT 4", 0L)]
    [DataRow("2 .and 4", 1L)]
    [DataRow("0 .OR 4", 1L)]
    [DataRow("1 .xor 8", 0L)]
    [DataRow("1 .XOR 0", 1L)]
    [DataRow("7 .mod 3", 1L)]
    [DataRow("-7 .mod 3", -1L)]
    [DataRow(".lobyte($123456 + 1)", 0x57L)]
    [DataRow(".HIBYTE($123456)", 0x34L)]
    [DataRow(".bankbyte($123456)", 0x12L)]
    [DataRow(".bankbyte(-1)", 0xFFL)]
    [DataRow("1 = 1 .and 2 < 3", 1L)]
    [DataRow("0 || 2 && 0", 0L)]
    [DataRow("2 && 4 || 0", 1L)]
    [DataRow("1!=2", 1L)]
    public void NewExpressionsPreserveInterpreterParity(string text, long expected)
    {
        ExpressionEvaluator runtime = new(text.AsMemory(), new AssemblySymbols(), address: 0, line: 0);
        runtime.TryEvaluate(out long value).Should().BeTrue();
        value.Should().Be(expected);
        GeneratorAssembly.ExpressionEvaluator linked = new(text.AsMemory(), new GeneratorAssembly.AssemblySymbols(), 0, 0);
        linked.TryEvaluate(out long linkedValue).Should().BeTrue();
        linkedValue.Should().Be(expected);
    }

    /// <summary>
    ///  Forward values exercise recording and replay for every newly added expression operation.
    /// </summary>
    [TestMethod]
    public void RecordedProgramsReplayNewOperations()
    {
        AssemblyResult result = Assemble("""
            Low = .lobyte(Forward + 1)
            High = .hibyte(Forward)
            Bank = .bankbyte(Forward)
            Not = .not (Forward = 0)
            And = Forward && 1
            Or = Forward || 0
            Xor = Forward .xor 0
            Mod = Forward .mod 5
            Forward = $123456
            .byte Low, High, Bank, Not, And, Or, Xor, Mod
            """, size: 8);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.ToArray().Should().Equal(0x57, 0x34, 0x12, 1, 1, 1, 1, 1);
        Assemble("N = 1 .mod (Later - Here)\nHere:\nLater:").Diagnostics.Single().Message.Should().Contain("Division by zero");
    }

    /// <summary>
    ///  Expansion chains and fixed build timestamps are retained as immutable metadata.
    /// </summary>
    [TestMethod]
    public void ExpansionLocationsAndBuildTimeRemainStable()
    {
        AssemblyLocation outer = new("root.asm", line: 3);
        AssemblyLocation inner = new("macro.inc", line: 7, column: 2, expandedFrom: outer);
        AssemblyProject project = new();
        project.Statements.Add(new(AssemblyStatementKind.Instruction, "nop") { Location = inner });
        AssemblyOptions options = new(ProcessorVariant.Mos6502, origin: 0x1000, imageSize: 1)
        {
            BuildTime = DateTimeOffset.FromUnixTimeSeconds(1234567)
        };

        AssemblyResult result = new NativeAssembler().Assemble(project, options);
        result.Diagnostics.Should().BeEmpty();
        project.Statements[0].Location = new("edited.asm", line: 0);
        result.SourceMap[0].Location.Should().BeSameAs(inner);
        result.SourceMap[0].Location?.ExpandedFrom.Should().BeSameAs(outer);
        options.BuildTime.ToUnixTimeSeconds().Should().Be(1234567);
    }

    /// <summary>
    ///  New primitives reject invalid inputs explicitly, including after no-output lowering.
    /// </summary>
    /// <param name="source">The invalid source.</param>
    /// <param name="message">The required diagnostic fragment.</param>
    [TestMethod]
    [DataRow(".section Missing", "Unknown section")]
    [DataRow(".section S, $2000, 2\n__S_SIZE__ = 0", "Compiler-defined")]
    [DataRow(".align 0", "power-of-two")]
    [DataRow(".align 3", "power-of-two")]
    [DataRow(".align $20000", "power-of-two")]
    [DataRow(".dword $100000000", "32-bit range")]
    [DataRow(".dword -2147483649", "32-bit range")]
    [DataRow(".dword \"A\"", "only valid in .byte")]
    [DataRow(".logicalorg $10000", "16-bit")]
    [DataRow(".logicalorg $FFFF\n.byte 1, 2", "exceeds")]
    [DataRow(".dum $20\n.res 2", "Unterminated .dum")]
    [DataRow(".dum $20\n.dum $30\n.dend", "Nested .dum")]
    [DataRow(".dend", "open .dum")]
    [DataRow(".dum $20\n.section S, $2000, 2\n.dend", "inside .dum")]
    [DataRow(".checksum 1", "no operand")]
    [DataRow(".dum $20\n.checksum\n.dend", "file output")]
    [DataRow("lda.w z:$10", "zero-page")]
    [DataRow("lda z:#1", "zero-page")]
    [DataRow("jmp z:$10", "unsupported")]
    [DataRow("lda z:$100", "byte range")]
    [DataRow(".cpu 65SC02\nwai", "65SC02")]
    [DataRow(".cpu 65SC02\nrmb0 $10", "65SC02")]
    [DataRow(".byte .lobyte 1", "parentheses")]
    [DataRow(".byte 7%10", "suffix")]
    [DataRow(".byte !1", "Invalid expression")]
    [DataRow(".byte 0 && (1 / 0)", "Division by zero")]
    public void InvalidPrimitivesReportDiagnostics(string source, string message)
    {
        AssemblyResult result = Assemble(source);
        result.Success.Should().BeFalse();
        result.Sections.Should().BeEmpty();
        result.Diagnostics.Should().Contain(error => error.Message.Contains(message));
    }

    /// <summary>
    ///  Checks native operator spellings, alignments and dwords against the actual ca65 toolchain.
    /// </summary>
    [TestMethod]
    public void ExpressionsAlignmentAndDwordsMatchCa65()
    {
        Ca65Toolchain tools = Ca65Toolchain.Require();
        const string Source = """
            .export Low, High, Bank, Not, LogicalAndValue, Or, Xor, Mod, Forward
            Low = .lobyte(Forward + 1)
            High = .hibyte(Forward)
            Bank = .bankbyte(Forward)
            Not = .not (Forward = 0)
            LogicalAndValue = Forward && 1
            Or = Forward || 0
            Xor = Forward .xor 0
            Mod = Forward .mod 5
            Forward = $123456
            .byte Low, High, Bank, Not, LogicalAndValue, Or, Xor, Mod
            .align 16, $EA
            .dword $89ABCDEF
            """;

        string directory = Directory.CreateTempSubdirectory("retrocore-ca65-primitives-").FullName;
        try
        {
            string path = Path.Join(directory, "primitives.s");
            File.WriteAllText(path, Source);
            Ca65Assembly reference = tools.Assemble(path);
            AssemblyResult actual = Assemble(Source, size: 20);
            actual.Diagnostics.Should().BeEmpty();
            reference.AssertMatches(actual.Sections.Single().Bytes.Span, actual.Symbols);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    private static AssemblyResult Assemble(
        string source,
        int origin = 0x1000,
        int size = 32,
        AssemblyWidthPolicy policy = AssemblyWidthPolicy.Shrink) =>
            new NativeAssembler().Assemble(new AssemblySource(source, "primitives.asm"), new(ProcessorVariant.Mos6502, origin, size)
            {
                WidthPolicy = policy
            });
}
