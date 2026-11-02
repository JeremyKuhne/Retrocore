// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

extern alias Generator;

using Retrocore.Assembler;
using System.Text;
using GeneratorAssembly = Generator::Retrocore.Assembler;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

/// <summary>
///  Definition-first lexical lookup, cheap locals and anonymous branch targets.
/// </summary>
[TestClass]
public class AssemblyScopeTests
{
    /// <summary>
    ///  Later inner definitions shadow already-known outer values.
    /// </summary>
    [TestMethod]
    public void InnerForwardDefinitionShadowsOuterDefinitions()
    {
        AssemblyResult result = Assemble("""
            Value = $11
            .scope Outer
            Value = $22
            .scope Inner
            .byte Value
            Value = $33
            .endscope
            .byte Value
            .endscope
            .byte Value
            .word Outer::Inner::Value
            """, size: 5);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.ToArray().Should().Equal(0x33, 0x22, 0x11, 0x33, 0);
        result.Symbols["Outer::Inner::Value"].Should().Be(0x33);
        result.Symbols["Outer::Value"].Should().Be(0x22);
        result.Symbols["Value"].Should().Be(0x11);
    }

    /// <summary>
    ///  As in ca65, a qualifying namespace binds to one already opened at that point; only without one does a
    ///  later namespace apply.
    /// </summary>
    [TestMethod]
    public void QualifiedNamespacesBindInSourceOrder()
    {
        AssemblyResult result = Assemble("""
            .scope A
            Value = 1
            .endscope
            .scope Outer
            .byte A::Value
            .scope A
            Value = 2
            .endscope
            .byte A::Value, ::A::Value
            .endscope
            """, size: 3);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.ToArray().Should().Equal(1, 2, 1);
        AssemblyResult missing = Assemble("""
            .scope Outer
            .byte A::Value
            .scope A
            Different = 2
            .endscope
            .endscope
            """);

        missing.Diagnostics.Single().Message.Should().Contain("Outer::A::Value");
    }

    /// <summary>
    ///  Procedures define entry addresses and recursive references resolve through their enclosing namespace.
    /// </summary>
    [TestMethod]
    public void ProceduresDefineLabelsWithoutReorderingStatements()
    {
        AssemblyResult result = Assemble(".export Start\n.proc Start\nnop\nbne Start\n.endproc\n.word Start", size: 5);
        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.ToArray().Should().Equal(0xEA, 0xD0, 0xFD, 0, 0x10);
        result.Exports["Start"].Should().Be(0x1000);
        result.SymbolDefinitions.Single().IsConstant.Should().BeFalse();
        result.SourceMap[0].Operation.Should().Be(".PROC");
        result.SourceMap[0].Address.Should().Be(0x1000);
        result.SourceMap[0].Size.Should().Be(0);
        result.SourceMap[1].Location?.Line.Should().Be(2);
    }

    /// <summary>
    ///  As in ca65, the first definition of any ordinary symbol, including an equate, starts a cheap-local context.
    /// </summary>
    [TestMethod]
    public void CheapLocalsCanRepeatAfterNonLocalSymbols()
    {
        AssemblyResult result = Assemble("""
            .proc Main
            @again: lda #1
            bne @again
            Constant = 9
            @again: rts
            bne @again
            Next: nop
            @again: rts
            .endproc
            """, size: 9);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.ToArray().Should().Equal(0xA9, 1, 0xD0, 0xFC, 0x60, 0xD0, 0xFD, 0xEA, 0x60);
        result.Symbols["Main::@again"].Should().Be(0x1000);
        result.Symbols["Main::Constant::@again"].Should().Be(0x1004);
        result.Symbols["Main::Next::@again"].Should().Be(0x1008);
        result.SourceMap[1].Label.Should().Be("@again");
        Assemble("First:\n@again: nop\nSecond:\nbne @again").Diagnostics.Single().Message.Should().Contain("Second::@again");
    }

    /// <summary>
    ///  Unnamed forward and backward references select the requested occurrence, including the current label.
    /// </summary>
    [TestMethod]
    public void UnnamedReferencesResolveInBothDirections()
    {
        AssemblyResult result = Assemble("""
            bne :+
            : nop
            bne :-
            .word :++, :-
            : nop
            : rts
            """, size: 11);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.ToArray().Should().Equal(0xD0, 0, 0xEA, 0xD0, 0xFD, 0x0A, 0x10, 2, 0x10, 0xEA, 0x60);
        result.Symbols.Should().BeEmpty();
        result.SymbolDefinitions.Should().BeEmpty();
        result.SourceMap[1].Label.Should().Be(":");
        Assemble(":bne :-", size: 2).Sections[0].Bytes.ToArray().Should().Equal(0xD0, 0xFE);
    }

    /// <summary>
    ///  Qualified a:: and z:: names are never misread as forced-width prefixes.
    /// </summary>
    [TestMethod]
    public void QualifiedNamesDoNotCollideWithWidthPrefixes()
    {
        AssemblyResult result = Assemble("""
            .scope a
            b = $42
            .endscope
            .scope z
            b = $43
            .endscope
            .scope Context
            a = 1
            z = 2
            lda ::a::b
            lda ::z::b
            lda a:$10
            lda z:$10
            .endscope
            """, size: 9);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.ToArray().Should().Equal(0xA5, 0x42, 0xA5, 0x43, 0xAD, 0x10, 0, 0xA5, 0x10);
        Assemble(".scope a\nb=$44\n.endscope\nlda a::b", size: 2).Sections[0].Bytes.ToArray().Should().Equal(0xA5, 0x44);
    }

    /// <summary>
    ///  Register-shaped symbols are rewritten only when the selected CPU treats them as expressions.
    /// </summary>
    [TestMethod]
    public void AccumulatorsIndexRegistersAndBitTargetsRemainDistinct()
    {
        AssemblyResult result = Assemble("""
            .scope Inner
            .cpu Mos6502
            X = $12
            A = $20
            lda X,X
            asl A
            inc A
            lda #A
            .cpu Wdc65C02
            inc A
            bbr0 X,Y
            Y: nop
            .endscope
            """, size: 12);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.ToArray().Should().Equal(0xB5, 0x12, 0x0A, 0xE6, 0x20, 0xA9, 0x20, 0x1A, 0x0F, 0x12, 0, 0xEA);
    }

    /// <summary>
    ///  Scoped .set versions remain source-ordered and plain exports bind to the intended symbol.
    /// </summary>
    [TestMethod]
    public void ScopedVariablesAndExportAliasesPreservePublicMetadata()
    {
        AssemblyResult result = Assemble("""
            Value = 9
            .scope Inner
            .set Value, 1
            .byte Value
            .set Value, Value + 1
            .byte Value
            .export Value
            .endscope
            .byte Value
            """, size: 3);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.ToArray().Should().Equal(1, 2, 9);
        result.Exports.Keys.Should().Equal("Value");
        result.Exports["Value"].Should().Be(2);
        result.Symbols["Inner::Value"].Should().Be(2);
        result.SymbolDefinitions.Single(symbol => symbol.Name == "Inner::Value").IsExported.Should().BeTrue();
        result.SymbolDefinitions.Single(symbol => symbol.Name == "Value").IsExported.Should().BeFalse();
        result.SourceMap.Single(entry => entry.Location?.Line == 5).Operand.Should().Be("Value");
    }

    /// <summary>
    ///  One exported member cannot silently alias two distinct scoped symbols.
    /// </summary>
    [TestMethod]
    public void ExportAliasesCannotSilentlyChooseBetweenScopes()
    {
        AssemblyResult ambiguous = Assemble("""
            .scope First
            Value=1
            .export Value
            .endscope
            .scope Second
            Value=2
            .export Value
            .endscope
            """);

        ambiguous.Success.Should().BeFalse();
        ambiguous.Diagnostics.Single().Message.Should().Contain("duplicate exported symbol");
    }

    /// <summary>
    ///  Repeated anonymous scopes cannot leak their ordinary definitions into each other.
    /// </summary>
    [TestMethod]
    public void AnonymousScopesHaveIndependentDefinitions()
    {
        AssemblyResult result = Assemble(".scope\nX=4\n.byte X\n.export X\n.endscope\n.scope\nX=5\n.byte X\n.endscope", size: 2);
        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.ToArray().Should().Equal(4, 5);
        result.Exports["X"].Should().Be(4);
    }

    /// <summary>
    ///  Scopes and local contexts continue across roots in a single dialect.
    /// </summary>
    [TestMethod]
    public void ScopesCanNestAcrossSourceBoundaries()
    {
        AssemblySource[] roots =
        [
            new(".scope Outer\n@start: nop\nbne :+", "first.asm"),
            new(":bne @start\nValue=7\n.endscope\n.byte Outer::Value", "second.asm")
        ];

        AssemblyResult result = new NativeAssembler().Assemble(roots, Options(size: 6));
        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.ToArray().Should().Equal(0xEA, 0xD0, 0, 0xD0, 0xFB, 7);
        result.SourceMap.Single(entry => entry.Label == ":").Location?.Path.Should().Be("second.asm");
    }

    /// <summary>
    ///  Unnamed labels count expanded source positions across lexical scopes.
    /// </summary>
    [TestMethod]
    public void UnnamedLabelsCrossScopeBoundaries()
    {
        AssemblyResult result = Assemble("bne :+\n.scope Inner\n:nop\n.endscope\nbne :-", size: 5);
        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.ToArray().Should().Equal(0xD0, 0, 0xEA, 0xD0, 0xFD);
        result.Symbols.Should().BeEmpty();
    }

    /// <summary>
    ///  Large anonymous-label streams preserve every self-branch and hide generated definitions.
    /// </summary>
    [TestMethod]
    public void LargeUnnamedLabelStreamsResolveEveryOccurrence()
    {
        const int Count = 4096;
        AssemblyResult result = Assemble(string.Concat(Enumerable.Repeat(":bne :-\n", Count)), size: Count * 2);
        result.Diagnostics.Should().BeEmpty();
        result.Symbols.Should().BeEmpty();
        ReadOnlySpan<byte> bytes = result.Sections[0].Bytes.Span;
        bytes.Length.Should().Be(Count * 2);
        for (int index = 0; index < bytes.Length; index += 2)
        {
            bytes[index].Should().Be(0xD0);
            bytes[index + 1].Should().Be(0xFE);
        }
    }

    /// <summary>
    ///  Programmatic dialect changes cannot bind local labels from a different dialect epoch.
    /// </summary>
    /// <param name="text">A local definition followed by a reference.</param>
    [TestMethod]
    [DataRow(":nop\nbne :-")]
    [DataRow("@target:nop\nbne @target")]
    public void DialectBoundariesResetLocalReferences(string text)
    {
        AssemblyProject project = NativeAssembler.Parse(new(text)).Project;
        project.Statements[1].Dialect = AssemblyDialect.Ca65;
        AssemblyResult result = new NativeAssembler().Assemble(project, Options());
        result.Success.Should().BeFalse();
        result.Diagnostics.Should().ContainSingle();
        result.Sections.Should().BeEmpty();
    }

    /// <summary>
    ///  Both hosts reject unknown model dialects instead of silently accepting foreign syntax.
    /// </summary>
    [TestMethod]
    public void InvalidModelDialectsAreDiagnosedInBothHosts()
    {
        AssemblyProject project = NativeAssembler.Parse(new("nop")).Project;
        project.Statements[0].Dialect = (AssemblyDialect)255;
        AssemblyResult result = new NativeAssembler().Assemble(project, Options());
        result.Diagnostics.Single().Message.Should().Contain("Invalid source dialect");
        GeneratorAssembly.AssemblyProject linked = GeneratorAssembly.Assembler.Parse(new("nop")).Project;
        linked.Statements[0].Dialect = (GeneratorAssembly.AssemblyDialect)255;
        GeneratorAssembly.Assembler generator = new(new Dictionary<string, Generator::Retrocore.Isa.InstructionSet>());
        GeneratorAssembly.AssemblyResult generated = generator.Assemble(
            linked,
            new(Generator::Retrocore.Cpu.M6502.ProcessorVariant.Mos6502, origin: 0x1000, imageSize: 1));

        generated.Diagnostics.Single().Message.Should().Contain("Invalid source dialect");
    }

    /// <summary>
    ///  Repeat iterations and macro-call labels retain expansion order during anonymous lookup.
    /// </summary>
    [TestMethod]
    public void MacroInvocationLabelsAndRepeatsUseExpandedOrder()
    {
        AssemblyResult result = Assemble("""
            .macro Emit value
            lda #value
            bne :-
            .endmacro
            .repeat 2, Index
            :Emit Index
            .endrepeat
            """, size: 8);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.ToArray().Should().Equal(0xA9, 0, 0xD0, 0xFC, 0xA9, 1, 0xD0, 0xFC);
    }

    /// <summary>
    ///  Macro parameters can supply individual namespace and member tokens without replacing literal text.
    /// </summary>
    [TestMethod]
    public void MacroParametersSubstituteQualifiedNameSegments()
    {
        AssemblyResult result = Assemble("""
            .scope Outer
            Value=$42
            .endscope
            .macro Emit Namespace, Member
            .byte Namespace::Member, ::Namespace::Member
            .byte "Namespace::Member"
            .endmacro
            Emit Outer, Value
            """, size: 19);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..2].ToArray().Should().Equal(0x42, 0x42);
        result.Sections[0].Bytes.Span[2..].ToArray().Should().Equal(Encoding.ASCII.GetBytes("Namespace::Member"));
    }

    /// <summary>
    ///  A later scoped variable shadows an outer constant without making its first assignment retroactive.
    /// </summary>
    [TestMethod]
    public void ScopedVariablesCannotBeReadBeforeTheirFirstAssignment()
    {
        AssemblyResult result = Assemble("Value=9\n.scope Inner\n.byte Value\n.set Value, 2\n.endscope");
        result.Diagnostics.Should().ContainSingle(error => error.Message.Contains("Inner::Value"));
        result.Success.Should().BeFalse();
    }

    /// <summary>
    ///  Preprocessor constants use the current namespace and restore outer values on scope exit.
    /// </summary>
    [TestMethod]
    public void ScopedConditionsDoNotOverwriteOuterConstants()
    {
        AssemblyResult result = Assemble("""
            Value = 9
            .scope Inner
            Value = 2
            .if Value = 2
            .byte Value
            .endif
            .ifdef Inner::Value
            .byte ::Value
            .endif
            .endscope
            .if Value = 9
            .byte Value
            .endif
            """, size: 3);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.ToArray().Should().Equal(2, 9, 9);
    }

    /// <summary>
    ///  Conditions use source-order bindings while ordinary references use the complete lexical inventory.
    /// </summary>
    [TestMethod]
    public void ConditionalLookupDoesNotSpeculateAboutLaterDefinitions()
    {
        AssemblyResult result = Assemble("""
            Value=9
            .scope Inner
            .if Value=9
            .byte Value
            .endif
            Value=2
            .endscope
            """, size: 1);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.ToArray().Should().Equal(2);
    }

    /// <summary>
    ///  Quoted text and section names remain syntax, not lexical symbol references.
    /// </summary>
    [TestMethod]
    public void RewritingPreservesStringsSectionNamesAndSnapshots()
    {
        AssemblyParseResult parsed = NativeAssembler.Parse(new("""
            .scope Inner
            Data = 9
            .section Data, $2000, 32, 0, 1
            .byte "Data @Missing :+", Data
            .endscope
            """));

        AssemblyResult first = new NativeAssembler().Assemble(parsed.Project, Options());
        first.Diagnostics.Should().BeEmpty();
        first.Sections[1].Name.Should().Be("Data");
        first.Sections[1].Bytes.Span[..16].ToArray().Should().Equal(Encoding.ASCII.GetBytes("Data @Missing :+"));
        first.Sections[1].Bytes.Span[16].Should().Be(9);
        parsed.Project.Statements[1].Operand = new("7");
        AssemblyResult second = new NativeAssembler().Assemble(parsed.Project, Options());
        second.Diagnostics.Should().BeEmpty();
        first.Symbols["Inner::Data"].Should().Be(9);
        second.Symbols["Inner::Data"].Should().Be(7);
        parsed.Project.Statements[1].Label.Should().Be("Data");
    }

    /// <summary>
    ///  As in ca65, reassigning a variable keeps the cheap-local context its first assignment started.
    /// </summary>
    [TestMethod]
    public void VariableReassignmentKeepsTheCheapLocalContext()
    {
        Assemble("V .set 1\n@a: nop\nV .set 2\n@a: rts").Diagnostics.Single().Message.Should().Contain("@a");
        Assemble("@a: nop\nV .set 1\n@a: rts\nbne @a").Diagnostics.Should().BeEmpty();
    }

    /// <summary>
    ///  As in ca65, entering a scope keeps the cheap-local context, and leaving one starts a new context.
    /// </summary>
    [TestMethod]
    public void ScopeBoundariesFollowCa65CheapLocalContexts()
    {
        AssemblyResult result = Assemble("""
            @before: nop
            .scope Inner
            bne @before
            @inside: rts
            .endscope
            @before: nop
            bne @before
            """, size: 7);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.ToArray().Should().Equal(0xEA, 0xD0, 0xFD, 0x60, 0xEA, 0xD0, 0xFD);
        result.Symbols.Keys.Should().BeEquivalentTo("@before", "@inside");
        Assemble(".proc P\nInner: nop\n@x: nop\n.endproc\njmp @x").Success.Should().BeFalse();
    }

    /// <summary>
    ///  Symbols and scopes occupy separate namespaces, as in ca65.
    /// </summary>
    [TestMethod]
    public void SymbolsAndScopesMayShareNames()
    {
        AssemblyResult result = Assemble("""
            S = 1
            .scope Outer
            .scope S
            Value = 2
            .endscope
            .byte S, S::Value
            .endscope
            .scope T
            Value = 3
            .endscope
            T = 4
            .byte T, T::Value
            """, size: 4);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.ToArray().Should().Equal(1, 2, 4, 3);
    }

    /// <summary>
    ///  Labels in anonymous scopes and anonymous cheap-local contexts stay out of the public symbol table.
    /// </summary>
    [TestMethod]
    public void PrivateResolverNamesAreNotPublished()
    {
        AssemblyResult result = Assemble(".scope\nHidden: nop\n.endscope\n@local: nop\nVisible: rts", size: 3);
        result.Diagnostics.Should().BeEmpty();
        result.Symbols.Keys.Should().BeEquivalentTo("Visible");
    }

    /// <summary>
    ///  Conditionals and emitted operands agree on qualified lookup and cheap-local contexts.
    /// </summary>
    [TestMethod]
    public void ConditionalsUseTheSameScopeRulesAsEmission()
    {
        AssemblyResult result = Assemble("""
            .scope A
            Value = 1
            .endscope
            .scope Outer
            .if A::Value = 1
            .byte A::Value
            .endif
            .scope A
            Value = 2
            .endscope
            .if A::Value = 2
            .byte A::Value
            .endif
            .endscope
            @k = 3
            K = 9
            @k = 4
            .if @k = 4
            .byte @k
            .endif
            """, size: 3);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.ToArray().Should().Equal(1, 2, 4);
    }

    /// <summary>
    ///  Shared identifier grammar accepts qualified references without admitting qualified definitions or exports.
    /// </summary>
    /// <param name="text">The reference spelling.</param>
    [TestMethod]
    [DataRow("Outer::Inner::X")]
    [DataRow("::X")]
    [DataRow("@1loop")]
    [DataRow("Outer::@loop")]
    public void IdentifierGrammarIsSharedByRuntimeAndGenerator(string text)
    {
        AssemblySyntax.IsIdentifier(text).Should().BeTrue();
        GeneratorAssembly.AssemblySyntax.IsIdentifier(text).Should().BeTrue();
        AssemblySyntax.IdentifierLength(text + " + 1").Should().Be(text.Length);
    }

    /// <summary>
    ///  Scope and anonymous-label errors have source positions and never produce success-shaped output.
    /// </summary>
    /// <param name="text">The invalid source.</param>
    /// <param name="message">The required diagnostic fragment.</param>
    [TestMethod]
    [DataRow(".scope Outer\nnop", "Unterminated")]
    [DataRow(".proc Entry\nnop", "Unterminated")]
    [DataRow(".endproc", "terminator")]
    [DataRow(".scope Outer\n.endproc\n.endscope", "terminator")]
    [DataRow(".scope A\n.endscope extra", "no operand")]
    [DataRow(".scope A::B\n.endscope", "unqualified")]
    [DataRow("Outer::X: nop", "unqualified")]
    [DataRow("Outer::X = 1", "unqualified")]
    [DataRow(".set Outer::X, 1", ".set requires")]
    [DataRow(".export Outer::X", "exported symbol")]
    [DataRow(".export @local", "exported symbol")]
    [DataRow(".scope A\n.endscope\n.scope A\n.endscope", "Duplicate scope")]
    [DataRow(".scope A\nX=1\nX=2\n.endscope", "Duplicate symbol")]
    [DataRow(".proc Main\n@x: nop\n.endproc\njmp Main::@x", "cannot be qualified")]
    [DataRow("bne :+", "No matching unnamed")]
    [DataRow("bne :-", "No matching unnamed")]
    public void InvalidScopesAreDiagnosed(string text, string message)
    {
        AssemblyResult result = Assemble(text);
        result.Success.Should().BeFalse();
        result.Sections.Should().BeEmpty();
        result.Diagnostics.Should().Contain(error => error.Message.Contains(message));
    }

    private static AssemblyOptions Options(int size = 32) => new(ProcessorVariant.Mos6502, origin: 0x1000, imageSize: size);
    private static AssemblyResult Assemble(string text, int size = 32) =>
        new NativeAssembler().Assemble(new AssemblySource(text, "scopes.asm"), Options(size));
}
