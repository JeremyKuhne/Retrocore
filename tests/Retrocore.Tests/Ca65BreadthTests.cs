// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

/// <summary>
///  Bounded expansion and explicit errors for ca65's richer preprocessing directives.
/// </summary>
[TestClass]
public class Ca65BreadthTests
{
    /// <summary>
    ///  Invalid metadata and token functions fail with physical source diagnostics and no file images.
    /// </summary>
    /// <param name="text">The invalid source.</param>
    /// <param name="message">The required diagnostic text.</param>
    [TestMethod]
    [DataRow(".struct Missing\nField .byte", "Unterminated")]
    [DataRow(".struct Wrong\n.endunion", "terminator")]
    [DataRow(".struct Bad\nField .res -1\n.endstruct", "positive")]
    [DataRow(".struct Bad\nField .byte 0\n.endstruct", "positive")]
    [DataRow(".struct Bad\nField .byte\nField .word\n.endstruct", "Duplicate")]
    [DataRow(".tag Missing", "known type")]
    [DataRow(".scope Test\n.byte .sizeof()\n.endscope", "parenthesized")]
    [DataRow(".charmap 256,0", "byte")]
    [DataRow(".byte .ident(\"\")", "identifier")]
    [DataRow(".define Loop Loop\n.byte Loop", "recursion")]
    [DataRow(".undefine Missing", "existing")]
    [DataRow(".ifref Anything\n.endif", "Reference-dependent")]
    [DataRow(".ifnref Anything\n.endif", "Reference-dependent")]
    [DataRow(".error \"explicit error\"", "explicit error")]
    [DataRow(".fatal \"explicit fatal\"", "explicit fatal")]
    [DataRow(".faraddr $1000000", "24-bit")]
    [DataRow(".dbyt $10000", "16-bit")]
    [DataRow(".dbyt -1", "16-bit")]
    [DataRow(".faraddr -1", "24-bit")]
    public void InvalidBreadthSourcesHaveExplicitDiagnostics(string text, string message)
    {
        AssemblyResult result = new NativeAssembler().Assemble(
            new AssemblySource(text, "breadth.s"),
            new(ProcessorVariant.Mos6502, 0x1000, 0x6800) { Dialect = AssemblyDialect.Ca65 });

        result.Success.Should().BeFalse();
        result.Files.Should().BeEmpty();
        result.Diagnostics.Should().Contain(diagnostic => diagnostic.Message.Contains(message, StringComparison.OrdinalIgnoreCase));
        result.Diagnostics.Select(diagnostic => diagnostic.Location).Should().NotContainNulls();
    }

    /// <summary>
    ///  Listing and message controls do not emit bytes; inactive types and errors remain unparsed.
    /// </summary>
    [TestMethod]
    public void InactiveCa65MetadataCannotChangeState()
    {
        AssemblyResult result = new NativeAssembler().Assemble(
            new AssemblySource("""
                .if 0
                .charmap 'A',$C1
                .struct Broken
                invalid garbage
                .endstruct
                .error "inactive"
                .endif
                .list on
                .debuginfo on
                .out "status"
                .warning "message"
                .byte "A"
                """),
            new(ProcessorVariant.Mos6502, 0x1000, 0x6800) { Dialect = AssemblyDialect.Ca65 });

        result.Diagnostics.Should().BeEmpty();
        result.Files["output.bin"].ToArray().Should().Equal(0x41);
    }
}
