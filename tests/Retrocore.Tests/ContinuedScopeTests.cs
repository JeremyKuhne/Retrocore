// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Documentation;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

/// <summary>
///  <c>.scope Name continued</c>, which goes on with a scope opened earlier, so a family of routines spread among other
///  code is still one scope (docs/NativeAssembly.md, "Continued scopes").
/// </summary>
[TestClass]
public sealed class ContinuedScopeTests
{
    private const string Pieces = """
            jsr Commands::Go
            jsr Commands::List
            rts
        .scope Commands
        Go:
            jmp List
        .endscope
        Other:
            rts
        .scope Commands continued
        List:
            jmp Go
        .endscope
        """;

    /// <summary>
    ///  The pieces are one scope: each reaches the other's names, and code outside reaches both.
    /// </summary>
    [TestMethod]
    public void PiecesShareTheirNames()
    {
        AssemblyResult result = Assemble(Pieces);
        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..14].ToArray().Should().Equal(
            0x20, 0x07, 0x13, 0x20, 0x0B, 0x13, 0x60, 0x4C, 0x0B, 0x13, 0x60, 0x4C, 0x07, 0x13);

        result.Symbols["Commands::Go"].Should().Be(0x1307);
        result.Symbols["Commands::List"].Should().Be(0x130B);
    }

    /// <summary>
    ///  A constant defined in one piece can be used by conditional assembly in a later one.
    /// </summary>
    [TestMethod]
    public void ConditionsSeeEarlierPieces()
    {
        AssemblyResult result = Assemble("""
            .scope Settings
            WIDE = 1
            .endscope
            .scope Settings continued
            .if WIDE
                lda #80
            .else
                lda #40
            .endif
            .endscope
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..2].ToArray().Should().Equal(0xA9, 80);
    }

    /// <summary>
    ///  The debug file has one scope for all the pieces.
    /// </summary>
    [TestMethod]
    public void TheDebugFileHasOneScope()
    {
        AssemblyResult result = Assemble(Pieces);
        StringWriter writer = new();
        AssemblyDebugFile.Write(result, writer);
        string debug = writer.ToString();
        debug.Split('\n').Count(line => line.StartsWith("scope\t", StringComparison.Ordinal) && line.Contains("\"Commands\""))
            .Should().Be(1);
    }

    /// <summary>
    ///  A continuation needs a scope opened earlier in the same enclosing scope, a .proc cannot be continued, a name
    ///  defined in two pieces is a duplicate, and a plain second .scope is still an error.
    /// </summary>
    /// <param name="text">The source.</param>
    /// <param name="message">The error it reports.</param>
    [TestMethod]
    [DataRow(".scope Nope continued\n.endscope\n", "No .scope Nope here to continue: it must be opened earlier, in the same scope.")]
    [DataRow(".proc P\n.endproc\n.scope P continued\n.endscope\n", "No .scope P here to continue: it must be opened earlier, in the same scope.")]
    [DataRow(".scope A\n.endscope\n.scope B\n.scope A continued\n.endscope\n.endscope\n", "No .scope A here to continue: it must be opened earlier, in the same scope.")]
    [DataRow(".scope A\nX:\n    rts\n.endscope\n.scope A continued\nX:\n    rts\n.endscope\n", "Duplicate symbol 'A::X'.")]
    [DataRow(".scope A\n.endscope\n.scope A\n.endscope\n", "Duplicate scope 'A'.")]
    [DataRow(".scope A\n    rts\n.endscope\n.scope A continued\n    rts\n.endscope\n    lda #.sizeof(A)\n", ".sizeof requires a contiguous scope or procedure: no section or .logicalorg changes, no storage map across its ends, and not a continued scope.")]
    [DataRow(".scope A\n    rts\n.endscope\n.scope A continued\n    rts\n.endscope\nSIZE = .sizeof(A)\n    lda #SIZE\n", ".sizeof requires a contiguous scope or procedure: no section or .logicalorg changes, no storage map across its ends, and not a continued scope.")]
    [DataRow(".byte .sizeof(Point)\n.struct Point\nfirst .byte\n.endstruct\n.scope Point continued\n    rts\n.endscope\n", ".sizeof requires a contiguous scope or procedure: no section or .logicalorg changes, no storage map across its ends, and not a continued scope.")]
    public void MistakesAreReported(string text, string message)
    {
        Assemble(text).Diagnostics.Select(diagnostic => diagnostic.Message).Should().Contain(message);
    }

    /// <summary>
    ///  A scope is documented where it first opens: a <c>;;</c> comment above a continuation is an error, and the
    ///  continuation's names are qualified by the scope like the first piece's.
    /// </summary>
    [TestMethod]
    public void ContinuationsAreDocumentedWhereTheScopeOpens()
    {
        DocumentationFile file = DocumentationParser.Parse("""
            ;; The commands.
            .scope Commands
            .endscope
            ;; More commands.
            .scope Commands continued
            ;; Lists memory.
            List:
                rts
            .endscope
            """, "test.asm");

        file.Diagnostics.Select(diagnostic => diagnostic.Message).Should().Equal(
            "Document a scope where it first opens; give a continued piece a plain ; comment.");

        file.Comments.Select(comment => comment.Name).Should().Equal("Commands", "Commands::List");
    }

    /// <summary>
    ///  A label on a continuation is reported as a label, not as a missing scope.
    /// </summary>
    [TestMethod]
    public void LabelsOnContinuationsAreReported()
    {
        Assemble(".scope A\n.endscope\nHere: .scope A continued\n.endscope\n").Diagnostics
            .Select(diagnostic => diagnostic.Message).Should().Contain(
                "A scope requires an unqualified name; .proc requires a name and neither takes a label.");
    }

    /// <summary>
    ///  The editor keeps a continued piece's names in its scope even while the source does not assemble.
    /// </summary>
    [TestMethod]
    public void TheEditorFollowsPiecesOfAFailedAssembly()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-continued").FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            File.WriteAllText(main, """
                .scope Commands
                .proc Go
                    rts
                .endproc
                .endscope
                .scope Commands continued
                .proc List
                    rts
                .endproc
                .endscope
                    lda #Undefined1

                """);

            Retrocore.Debug.Language.SourceAnalysis analysis = Retrocore.Debug.Language.SourceAnalysis.Assemble(main, _ => null);
            analysis.Result.Success.Should().BeFalse();
            analysis.Find("Commands::List").Should().NotBeEmpty();
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    private static AssemblyResult Assemble(string text) =>
        new NativeAssembler().Assemble(
            new AssemblySource(".cpu Mos6502\n" + text, "test.asm"),
            new AssemblyOptions(ProcessorVariant.Mos6502, origin: 0x1300, imageSize: 0x100));
}
