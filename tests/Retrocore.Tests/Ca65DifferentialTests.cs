// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

/// <summary>
///  Byte and symbol comparisons against optional external ca65/ld65 tools.
/// </summary>
[TestClass]
public class Ca65DifferentialTests
{
    /// <summary>
    ///  Reproduces Build-IIeSample.ps1 using its actual source and config.
    /// </summary>
    [TestMethod]
    public void IIeSampleMatchesNativeEquivalent()
    {
        string input = Path.Join(AppContext.BaseDirectory, "Inputs", "IIe");
        Ca65Assembly reference = Ca65Toolchain.Require().Assemble(
            Path.Join(input, "main.s"),
            Path.Join(input, "link.cfg"));

        // Retain the native backend comparison alongside Ca65FrontendTests' unchanged source/config coverage.
        AssemblySource source = new("""
            entry: lda #$C1
                sta $0400
                ldx #0
            loop:
                jsr increment
            after_call:
                stx counter
                cpx #3
                bne loop
            done:
                jmp done
            increment:
                inx
                rts
            counter = *
            .export entry, after_call, counter
            """);

        AssemblyResult actual = new NativeAssembler().Assemble(
            source,
            new(ProcessorVariant.Mos6502, origin: 0x6000, imageSize: 22));

        actual.Diagnostics.Should().BeEmpty();
        actual.Symbols.Keys.Should().BeEquivalentTo("entry", "loop", "after_call", "done", "increment", "counter");
        reference.AssertMatches(actual.Sections.Single().Bytes.Span, actual.Symbols);
        reference.Bytes.Should().Equal(
            0xA9,
            0xC1,
            0x8D,
            0x00,
            0x04,
            0xA2,
            0x00,
            0x20,
            0x14,
            0x60,
            0x8E,
            0x16,
            0x60,
            0xE0,
            0x03,
            0xD0,
            0xF6,
            0x4C,
            0x11,
            0x60,
            0xE8,
            0x60);

        reference.Symbols.Resolve("counter").Should().Be(0x6016);
        reference.Symbols.Addresses(Path.Join(input, "main.s"), line: 10).Should().Contain((ushort)0x6000);
    }

    /// <summary>
    ///  Tests the none target, a path containing spaces, and quoted relative includes.
    /// </summary>
    [TestMethod]
    public void NoneTargetMatchesNativeBytesAndSymbols()
    {
        Ca65Toolchain tools = Ca65Toolchain.Require();
        string directory = Directory.CreateTempSubdirectory("retrocore-ca65 source ").FullName;
        try
        {
            string sourcePath = Path.Join(directory, "main.s");
            File.WriteAllText(Path.Join(directory, "values.inc"), "Value = $42\n");
            File.WriteAllText(sourcePath, """
                .include "values.inc"
                .export entry, Value
                entry: lda #Value
                rts
                """);

            Ca65Assembly reference = tools.Assemble(sourcePath);
            AssemblyResult actual = new NativeAssembler().Assemble(
                new AssemblySource("Value = $42\nentry: lda #Value\nrts\n.export entry, Value"),
                new(ProcessorVariant.Mos6502, origin: 0x1000, imageSize: 3));

            actual.Diagnostics.Should().BeEmpty();
            reference.AssertMatches(actual.Sections.Single().Bytes.Span, actual.Symbols);
            reference.Symbols.Resolve("entry").Should().Be(0x1000);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  Common scope and branch syntax matches ca65 without flattening duplicate scoped symbols.
    /// </summary>
    /// <param name="body">The common assembly syntax.</param>
    [TestMethod]
    [DataRow("""
        Value = $11
        .scope Outer
        Value = $22
        .scope Inner
        .byte Value
        Value = $33
        .endscope
        .byte Value
        .endscope
        .byte ::Value
        .word Outer::Inner::Value
        """)]
    [DataRow("""
        .scope Namespace
        Value = 1
        .endscope
        .scope Outer
        .scope Namespace
        Value = 2
        .endscope
        .byte Namespace::Value
        .byte ::Namespace::Value
        .endscope
        """)]
    [DataRow("""
        .proc Main
        @again: lda #1
        bne @again
        Next: nop
        @again: rts
        bne @again
        .endproc
        .word Main
        """)]
    [DataRow("""
        bne :+
        :nop
        bne :-
        .word :++, :-
        :nop
        :rts
        """)]
    [DataRow("""
        bne :+
        .scope Inner
        :nop
        .endscope
        bne :-
        """)]
    [DataRow("""
        .scope Outer
        Value=$42
        .endscope
        .macro Emit Namespace, Member
        .byte Namespace::Member, ::Namespace::Member
        .endmacro
        Emit Outer, Value
        """)]
    [DataRow("""
        @loop:nop
        Value=1
        @loop:rts
        bne @loop
        """)]
    [DataRow("""
        @before:nop
        .scope Inner
        bne @before
        @inside:rts
        .endscope
        @before:nop
        bne @before
        """)]
    [DataRow("""
        @first:nop
        Variable .set 1
        @first:nop
        Variable .set 2
        bne @first
        """)]
    [DataRow("""
        .scope Namespace
        Value=1
        .endscope
        .scope Outer
        .byte Namespace::Value
        .scope Namespace
        Value=2
        .endscope
        .byte Namespace::Value
        .endscope
        """)]
    [DataRow("""
        .scope Outer
        .byte Later::Value
        .scope Later
        Value=3
        .endscope
        .endscope
        """)]
    [DataRow("""
        Shared=1
        .scope Outer
        .scope Shared
        Value=2
        .endscope
        .byte Shared, Shared::Value
        .endscope
        .scope Other
        Value=3
        .endscope
        Other=4
        .byte Other, Other::Value
        """)]
    public void NativeScopesMatchCa65(string body)
    {
        Ca65Toolchain tools = Ca65Toolchain.Require();
        string directory = Directory.CreateTempSubdirectory("retrocore-ca65-scopes-").FullName;
        try
        {
            string text = ".export Entry, End\nEntry:\n" + body + "\nEnd:\nrts";
            string sourcePath = Path.Join(directory, "scopes.s");
            File.WriteAllText(sourcePath, text);
            Ca65Assembly reference = tools.Assemble(sourcePath);
            AssemblyResult actual = new NativeAssembler().Assemble(
                new AssemblySource(text, sourcePath),
                new(ProcessorVariant.Mos6502, origin: 0x1000, imageSize: reference.Bytes.Length)
                {
                    WidthPolicy = AssemblyWidthPolicy.SourceOrder
                });

            actual.Diagnostics.Should().BeEmpty();
            reference.AssertMatches(actual.Sections.Single().Bytes.Span, actual.Exports);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  ca65 byte-extraction prefixes bind more tightly than addition; parentheses change the extracted value.
    /// </summary>
    [TestMethod]
    public void Ca65ByteExtractionPrecedenceIsExplicit()
    {
        Ca65Assembly reference = AssembleReference("""
            .word <$12FF + 1, >$12FE + 1, ^$FFFE + 1
            .word .lobyte($12FF + 1), .hibyte($12FE + 1), .bankbyte($FFFE + 1)
            .word 1 <> 0, 2 && 1, 0 || 2, .not 0
            """);

        reference.AssertMatches(
            [0, 1, 0x13, 0, 1, 0, 0, 0, 0x12, 0, 0, 0, 1, 0, 1, 0, 1, 0, 1, 0],
            new Dictionary<string, long> { ["Entry"] = 0x1000 });
    }

    /// <summary>
    ///  ca65 binds a known namespace before a later inner namespace is declared.
    /// </summary>
    [TestMethod]
    public void Ca65QualifiedNamespaceLookupUsesSourceOrder()
    {
        Ca65Assembly reference = AssembleReference("""
            .scope Namespace
            Value=1
            .endscope
            .scope Outer
            .byte Namespace::Value
            .scope Namespace
            Value=2
            .endscope
            .byte Namespace::Value
            .endscope
            """);

        reference.AssertMatches([1, 2], new Dictionary<string, long> { ["Entry"] = 0x1000 });
    }

    /// <summary>
    ///  An ordinary equate starts a new ca65 cheap-local context.
    /// </summary>
    [TestMethod]
    public void Ca65EquatesStartNewCheapLocalContexts()
    {
        Ca65Assembly reference = AssembleReference("""
            @loop:nop
            Value=1
            @loop:rts
            bne @loop
            """);

        reference.AssertMatches([0xEA, 0x60, 0xD0, 0xFD], new Dictionary<string, long> { ["Entry"] = 0x1000 });
    }

    /// <summary>
    ///  Leaving a ca65 scope does not restore its parent's earlier cheap-local context.
    /// </summary>
    [TestMethod]
    public void Ca65ScopeExitStartsANewCheapLocalContext()
    {
        Ca65Assembly reference = AssembleReference("""
            @before:nop
            .scope Inner
            @inside:rts
            .endscope
            @before:nop
            bne @before
            """);

        reference.AssertMatches([0xEA, 0x60, 0xEA, 0xD0, 0xFD], new Dictionary<string, long> { ["Entry"] = 0x1000 });
    }

    /// <summary>
    ///  A missing toolchain is optional, not an instruction to fetch dependencies.
    /// </summary>
    [TestMethod]
    public void MissingToolsAreNotDetectedAsUsable() =>
        Ca65Toolchain.Find(Path.Join(Path.GetTempPath(), Guid.NewGuid().ToString("N"))).Should().BeNull();

    /// <summary>
    ///  Real tool failures must fail tests rather than appearing as skipped coverage.
    /// </summary>
    /// <param name="text">Source rejected by the assembler or linker.</param>
    /// <param name="tool">The failing executable.</param>
    /// <param name="diagnostic">Text proving the intended failure was reached.</param>
    [TestMethod]
    [DataRow(".this_is_not_a_directive\n", "ca65", "invalid.s")]
    [DataRow(".import missing\n.word missing\n", "ld65", "missing")]
    public void InvalidReferenceSourceReportsToolFailure(string text, string tool, string diagnostic)
    {
        Ca65Toolchain tools = Ca65Toolchain.Require();
        string directory = Directory.CreateTempSubdirectory("retrocore-ca65-invalid-").FullName;
        try
        {
            string sourcePath = Path.Join(directory, "invalid.s");
            File.WriteAllText(sourcePath, text);
            Action assemble = () => tools.Assemble(sourcePath);
            assemble.Should().Throw<InvalidOperationException>().WithMessage($"{tool} exited with code *")
                .Which.Message.Should().Contain(diagnostic);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  Ensures a differential check cannot pass on empty work or miss byte and symbol differences.
    /// </summary>
    [TestMethod]
    public void ComparisonRejectsEmptyWorkAndMismatches()
    {
        Ca65Toolchain tools = Ca65Toolchain.Require();
        string directory = Directory.CreateTempSubdirectory("retrocore-ca65-compare-").FullName;
        try
        {
            string sourcePath = Path.Join(directory, "compare.s");
            File.WriteAllText(sourcePath, ".export entry\nentry: nop\n");
            Ca65Assembly reference = tools.Assemble(sourcePath);
            Dictionary<string, long> symbols = new() { ["entry"] = 0x1000 };
            reference.AssertMatches([0xEA], symbols);

            Action bytesDiffer = () => reference.AssertMatches([0x00], symbols);
            bytesDiffer.Should().Throw<AssertFailedException>().WithMessage("*offset $0000*");
            Action lengthsDiffer = () => reference.AssertMatches([], symbols);
            lengthsDiffer.Should().Throw<AssertFailedException>().WithMessage("*lengths differ*");
            Action noSymbols = () => reference.AssertMatches([0xEA], new Dictionary<string, long>());
            noSymbols.Should().Throw<AssertFailedException>().WithMessage("*compare symbols*");
            Action symbolsDiffer = () => reference.AssertMatches([0xEA], new Dictionary<string, long>
            {
                ["entry"] = 0x1001
            });

            symbolsDiffer.Should().Throw<AssertFailedException>().WithMessage("*symbol 'entry' differs*");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    private static Ca65Assembly AssembleReference(string body)
    {
        Ca65Toolchain tools = Ca65Toolchain.Require();
        string directory = Directory.CreateTempSubdirectory("retrocore-ca65-semantics-").FullName;
        try
        {
            string path = Path.Join(directory, "semantics.s");
            File.WriteAllText(path, ".export Entry\nEntry:\n" + body);
            return tools.Assemble(path);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }
}
