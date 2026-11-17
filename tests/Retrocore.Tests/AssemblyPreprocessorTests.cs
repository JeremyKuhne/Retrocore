// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

/// <summary>
///  Bounded, source-ordered preprocessing with physical diagnostic locations.
/// </summary>
[TestClass]
public partial class AssemblyPreprocessorTests
{
    /// <summary>
    ///  Gives a test file name, written with <c>/</c>, with the platform's separator, as the resolver's paths have it.
    /// </summary>
    /// <param name="path">The name, such as <c>root/main.asm</c>.</param>
    /// <returns>The name with the platform's separator.</returns>
    private static string P(string path) => path.Replace('/', Path.DirectorySeparatorChar);

    /// <summary>
    ///  Inactive branches do not parse operands, unknown statements, includes or arithmetic.
    /// </summary>
    [TestMethod]
    public void InactiveBranchesAreNotParsedOrResolved()
    {
        Resolver resolver = new();
        AssemblyResult result = Assemble("""
            Value = 2
            .if Value = 1
            %% invalid text
            .include "missing.inc"
            .byte 1 / 0
            .elseif Value = 2
            .byte $42
            .elseif 1 / 0
            .byte $99
            .else
            .unsupported
            .endif
            """, resolver);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[0].Should().Be(0x42);
        resolver.Requests.Should().BeEmpty();
    }

    /// <summary>
    ///  Equates and the latest .set value determine later conditionals, but label addresses do not.
    /// </summary>
    [TestMethod]
    public void ConditionsUseOnlyValuesKnownAtTheirSourcePosition()
    {
        AssemblyResult result = Assemble("""
            .set Flag, 0
            .if Flag
            .byte 99
            .endif
            .set Flag, 1
            .if Flag
            .byte 7
            .endif
            .ifdef Flag
            .byte 8
            .endif
            .ifndef Missing
            .byte 9
            .endif
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..3].ToArray().Should().Equal(7, 8, 9);
        AssemblyParseResult label = NativeAssembler.Parse(new("Target:\n.if Target\n.byte 1\n.endif", "label.asm"));
        label.Diagnostics.Single().Message.Should().Contain("requires a constant");
        label.Diagnostics[0].Location?.Line.Should().Be(1);
        NativeAssembler.Parse(new(".if *\n.endif")).Diagnostics.Single().Message.Should().Contain("requires a constant");
    }

    /// <summary>
    ///  Quoted paths resolve beside the includer, then through explicit include paths.
    /// </summary>
    [TestMethod]
    public void IncludesPreserveSearchOrderAndPhysicalLocations()
    {
        Resolver resolver = new();
        resolver.Add(P("root/local.inc"), ".byte $11");
        resolver.Add(P("search/fallback.inc"), ".byte $22");
        AssemblyOptions options = Options(resolver, includePaths: ["search"]);
        AssemblyResult result = new NativeAssembler().Assemble(
            new AssemblySource(".include \"local.inc\"\n.include \"fallback.inc\"\n.byte $33", P("root/main.asm")),
            options);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..3].ToArray().Should().Equal(0x11, 0x22, 0x33);
        result.SourceMap[0].Location?.Path.Should().Be(P("root/local.inc"));
        result.SourceMap[0].Location?.ExpandedFrom?.Path.Should().Be(P("root/main.asm"));
        result.SourceMap[1].Location?.Path.Should().Be(P("search/fallback.inc"));
        resolver.Requests.Select(request => request.Request).Should().Equal("local.inc", "fallback.inc", P("search/fallback.inc"));
    }

    /// <summary>
    ///  SDK includes never fall back to an includer's local directory.
    /// </summary>
    [TestMethod]
    public void AngleIncludesSearchOnlySdkPaths()
    {
        Resolver resolver = new();
        resolver.Add(P("root/api.inc"), ".byte 99");
        resolver.Add(P("sdk/api.inc"), ".byte 4");
        AssemblyResult result = new NativeAssembler().Assemble(
            new AssemblySource(".include <api.inc>", P("root/main.asm")),
            Options(resolver, sdkPaths: ["sdk"]));

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[0].Should().Be(4);
        resolver.Requests.Should().ContainSingle(request => request.From.Length == 0 && request.Request == P("sdk/api.inc"));
        AssemblyResult escape = new NativeAssembler().Assemble(
            new AssemblySource(".include <../root/api.inc>", P("root/main.asm")),
            Options(resolver, sdkPaths: ["sdk"]));

        escape.Diagnostics.Single().Message.Should().Contain("within a configured SDK directory");
    }

    /// <summary>
    ///  Runtime filesystem access is explicit and keeps relative include semantics.
    /// </summary>
    [TestMethod]
    public void FilesystemResolutionRequiresAnExplicitResolver()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-include-").FullName;
        try
        {
            string path = Path.Join(directory, "main.asm");
            File.WriteAllText(Path.Join(directory, "values.inc"), "Value = $42\n");
            AssemblyOptions options = new(ProcessorVariant.Mos6502, origin: 0x1000, imageSize: 2)
            {
                SourceResolver = new FileAssemblySourceResolver()
            };

            AssemblyResult result = new NativeAssembler().Assemble(
                new AssemblySource(".include \"values.inc\"\nlda #Value", path),
                options);

            result.Diagnostics.Should().BeEmpty();
            result.Sections[0].Bytes.ToArray().Should().Equal(0xA9, 0x42);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  Parameters are whole tokens and quoted text stays unchanged.
    /// </summary>
    [TestMethod]
    public void MacroParametersDoNotReplaceStringsOrLongerNames()
    {
        AssemblyResult result = Assemble("""
            ParameterLong = 9
            .macro Emit Parameter
            .byte "Parameter", Parameter, ParameterLong
            .endmacro
            Emit $42
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..11].ToArray().Should().Equal(
            0x50,
            0x61,
            0x72,
            0x61,
            0x6D,
            0x65,
            0x74,
            0x65,
            0x72,
            0x42,
            9);
    }

    /// <summary>
    ///  Locals remain distinct across calls and a call-site label names the first expanded byte.
    /// </summary>
    [TestMethod]
    public void MacroLocalsAreHygienicAcrossInvocations()
    {
        AssemblyResult result = Assemble("""
            .macro Loop value
            .local Again
            Again: lda #value
            bne Again
            .endmacro
            First: Loop 1
            Second: Loop 2
            .export First, Second
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..8].ToArray().Should().Equal(0xA9, 1, 0xD0, 0xFC, 0xA9, 2, 0xD0, 0xFC);
        result.Exports["First"].Should().Be(0x1000);
        result.Exports["Second"].Should().Be(0x1004);
        result.SourceMap.Where(entry => entry.Operation == "LDA").Select(entry => entry.Location?.ExpandedFrom?.Line)
            .Should().Equal(5, 6);
    }

    /// <summary>
    ///  Macros defined under a macro-only CPU, as p-code's are under <c>.cpu Pcode</c>, expand only under it: an
    ///  instruction of the same name under another CPU is that CPU's, and the macro-only CPU has no instructions.
    /// </summary>
    [TestMethod]
    public void MacroOnlyCpusOwnTheirMacros()
    {
        AssemblyResult result = Assemble("""
            .cpu Pcode
            .macro LDA level, offset
            .byte 178, level, offset
            .endmacro
            LDA 1, 4
            .cpu Mos6502
            LDA #1
            .cpu Pcode
            LDA 2, 5
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..8].ToArray().Should().Equal(178, 1, 4, 0xA9, 1, 178, 2, 5);

        AssemblyResult stray = Assemble("""
            .cpu Pcode
            lda #1
            """);

        stray.Diagnostics.Should().ContainSingle().Which.Message.Should().Contain("Unknown instruction");
    }

    /// <summary>
    ///  Optional arguments, .paramcount and .exitmacro control expansion without compiler statement kinds.
    /// </summary>
    [TestMethod]
    public void OptionalArgumentsAndExitMacroUseExpansionState()
    {
        AssemblyResult result = Assemble("""
            .macro Optional value
            .byte .paramcount
            .ifblank value
            .byte 7
            .exitmacro
            .endif
            .byte value
            .endmacro
            Optional
            Optional $42
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..4].ToArray().Should().Equal(0, 7, 1, 0x42);
    }

    /// <summary>
    ///  Repeat counters are constant during each expansion and nesting restores the outer value.
    /// </summary>
    [TestMethod]
    public void NestedRepeatsRestoreCounterBindings()
    {
        AssemblyResult result = Assemble("""
            .repeat 2, I
            .byte I
            .repeat 2, I
            .byte I + 10
            .endrepeat
            .byte I
            .endrepeat
            .repeat 0
            this is invalid %%
            .endrepeat
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..8].ToArray().Should().Equal(0, 10, 11, 0, 1, 10, 11, 1);
    }

    /// <summary>
    ///  Multiple roots share macros and constants while retaining each document's physical identity.
    /// </summary>
    [TestMethod]
    public void RootDocumentsShareOneOrderedEnvironment()
    {
        AssemblySource[] roots =
        [
            new("Value = $42\n.macro Emit arg\n.byte arg\n.endmacro", "sdk.asm"),
            new(".if Value = $42\nEmit Value\n.endif", "program.asm")
        ];

        AssemblyResult result = new NativeAssembler().Assemble(roots, Options());
        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[0].Should().Be(0x42);
        result.SourceMap.Single(entry => entry.Operation == ".BYTE").Location?.Path.Should().Be("sdk.asm");
        result.SourceMap.Single(entry => entry.Operation == ".BYTE").Location?.ExpandedFrom?.Path.Should().Be("program.asm");
    }

    /// <summary>
    ///  A pragma overrides resolver metadata; an explicit include override outranks both.
    /// </summary>
    [TestMethod]
    public void IncludeDialectPrecedenceIsExplicitAndDoesNotSilentlyFallBack()
    {
        Resolver resolver = new();
        resolver.Add(P("root/metadata.inc"), "; retrocore: dialect=native\n.byte 1", AssemblyDialect.Ca65);
        resolver.Add(P("root/override.inc"), "; retrocore: dialect=ca65\n.byte 2", AssemblyDialect.Ca65);
        AssemblyResult result = new NativeAssembler().Assemble(
            new AssemblySource(
                ".include \"metadata.inc\"\n.include \"override.inc\" dialect=native",
                P("root/main.asm")),
            Options(resolver));

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..2].ToArray().Should().Equal(1, 2);
        AssemblyParseResult supported = NativeAssembler.Parse(new("; retrocore: dialect=ca65\n.byte 1", "other.s"));
        supported.Diagnostics.Should().BeEmpty();
        supported.Project.Statements.Single().Dialect.Should().Be(AssemblyDialect.Ca65);
        // The pragma selects MACRO-10, so a native-only line is not silently read as native.
        AssemblyParseResult macro10 = NativeAssembler.Parse(new("; retrocore: dialect=macro10\n.byte 1", "other.s"));
        macro10.Diagnostics.Should().ContainSingle().Which.Location?.Line.Should().Be(1);
        AssemblyParseResult words = NativeAssembler.Parse(new("; retrocore: dialect=macro10\n\tEXP\t1", "other.s"));
        words.Diagnostics.Should().BeEmpty();
        words.Project.Statements.Single().Dialect.Should().Be(AssemblyDialect.Macro10);
    }

    /// <summary>
    ///  Include and macro parents appear together on the innermost physical diagnostic.
    /// </summary>
    [TestMethod]
    public void MacroErrorsRetainIncludeAndInvocationChains()
    {
        Resolver resolver = new();
        resolver.Add(P("root/body.inc"), ".macro Broken\nlda #$100\n.endmacro\nBroken");
        AssemblyResult result = new NativeAssembler().Assemble(
            new AssemblySource(".include \"body.inc\"", P("root/main.asm")),
            Options(resolver));

        AssemblyLocation location = result.Diagnostics.Single().Location
            ?? throw new AssertFailedException("Expected a physical macro-body location.");

        location.Path.Should().Be(P("root/body.inc"));
        location.Line.Should().Be(1);
        location.ExpandedFrom?.Line.Should().Be(3);
        location.ExpandedFrom?.ExpandedFrom?.Path.Should().Be(P("root/main.asm"));
    }

    /// <summary>
    ///  Source, include, macro, repeat and total-line limits report errors instead of unbounded expansion.
    /// </summary>
    [TestMethod]
    public void ExpansionLimitsAreEnforced()
    {
        Resolver resolver = new();
        resolver.Add(P("root/loop.inc"), ".include \"loop.inc\"");
        AssemblyResult cycle = new NativeAssembler().Assemble(
            new AssemblySource(".include \"loop.inc\"", P("root/main.asm")),
            Options(resolver));

        cycle.Diagnostics.Should().Contain(error => error.Message.Contains("cycle"));
        AssemblyOptions options = new(ProcessorVariant.Mos6502, origin: 0x1000, imageSize: 32)
        {
            MaximumMacroDepth = 3,
            MaximumRepeatCount = 2,
            MaximumExpandedLines = 10
        };

        AssemblyResult recursion = new NativeAssembler().Assemble(
            new AssemblySource(
                ".macro Recurse\nRecurse\n.endmacro\nRecurse"),
            options);

        recursion.Diagnostics.Should().Contain(error => error.Message.Contains("macro recursion depth"));
        new NativeAssembler().Assemble(new AssemblySource(".repeat 3\nnop\n.endrepeat"), options)
            .Diagnostics.Should().Contain(error => error.Message.Contains("Repeat count"));

        new NativeAssembler().Assemble(
            new AssemblySource(
                ".repeat 2\n.repeat 2\n.repeat 2\nnop\n.endrepeat\n.endrepeat\n.endrepeat"),
            options)
            .Diagnostics.Should().Contain(error => error.Message.Contains("expanded-line count"));
    }

    /// <summary>
    ///  Blocks report their opener and independent preprocessing errors stay in expansion order.
    /// </summary>
    [TestMethod]
    public void UnterminatedBlocksAndSyntaxErrorsHavePhysicalLocations()
    {
        AssemblyParseResult conditional = NativeAssembler.Parse(new("\n.if 1\n.byte 1", "open.asm"));
        conditional.Diagnostics.Single().Location?.Line.Should().Be(1);
        AssemblyParseResult macro = NativeAssembler.Parse(new("\n.macro M\nnop", "macro.asm"));
        macro.Diagnostics.Single().Location?.Line.Should().Be(1);
        AssemblyParseResult ordered = NativeAssembler.Parse(new(".if 1\n%%\n.else\n.else\n.endif", "ordered.asm"));
        ordered.Diagnostics.Select(error => error.Location?.Line).Should().Equal(1, 3);
    }

    /// <summary>
    ///  Invalid directives remain explicit diagnostics rather than successful empty output.
    /// </summary>
    /// <param name="text">The invalid source.</param>
    /// <param name="message">The expected diagnostic fragment.</param>
    [TestMethod]
    [DataRow(".else", "Unexpected")]
    [DataRow(".endif", "Unexpected")]
    [DataRow(".endrepeat", "Unexpected")]
    [DataRow(".endmacro", "Unexpected")]
    [DataRow(".local X", "macro invocation")]
    [DataRow(".exitmacro", "macro invocation")]
    [DataRow(".repeat -1\nnop\n.endrepeat", "Repeat count")]
    [DataRow(".macro M x,x\nnop\n.endmacro", "duplicate macro parameter")]
    [DataRow(".macro M x\nnop\n.endmacro\nM (", "Unterminated macro argument")]
    [DataRow(".macro M\n.exitmacro 1\n.endmacro\nM", "takes no operand")]
    [DataRow(".include \"missing\"", "resolver")]
    [DataRow(".incbin \"binary\"", "Binary includes")]
    [DataRow(".if Later\n.endif\nLater = 1", "requires a constant")]
    public void InvalidExpansionProducesDiagnostics(string text, string message)
    {
        AssemblyResult result = Assemble(text);
        result.Success.Should().BeFalse();
        result.Sections.Should().BeEmpty();
        result.Diagnostics.Should().Contain(error => error.Message.Contains(message));
    }

    /// <summary>
    ///  Include depth is measured from the root and metadata collections are copied before use.
    /// </summary>
    [TestMethod]
    public void IncludeDepthAndImmutableSearchPathsAreEnforced()
    {
        Resolver resolver = new();
        resolver.Add(P("root/child.inc"), ".byte 1");
        string[] paths = ["first"];
        AssemblyOptions options = new(ProcessorVariant.Mos6502, origin: 0x1000, imageSize: 8)
        {
            SourceResolver = resolver,
            IncludePaths = paths,
            MaximumIncludeDepth = 1
        };

        paths[0] = "changed";
        options.IncludePaths.Should().Equal("first");
        AssemblyResult result = new NativeAssembler().Assemble(
            new AssemblySource(".include \"child.inc\"", P("root/main.asm")),
            options);

        result.Diagnostics.Single().Message.Should().Contain("include depth");
    }

    /// <summary>
    ///  Conditional recursion terminates and nested macro arguments retain their caller's expansion chain.
    /// </summary>
    [TestMethod]
    public void ConditionalMacroRecursionTerminatesInSourceOrder()
    {
        AssemblyResult result = Assemble("""
            .macro Down count
            .if count > 0
            .byte count
            Down count - 1
            .endif
            .endmacro
            Down 3
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..3].ToArray().Should().Equal(3, 2, 1);
        result.SourceMap.Last().Location?.ExpandedFrom?.ExpandedFrom.Should().NotBeNull();
    }

    /// <summary>
    ///  As in ca65, a local belongs to its whole macro invocation, including repeats nested in the body.
    /// </summary>
    [TestMethod]
    public void MacroLocalsBelongToTheWholeInvocation()
    {
        AssemblyResult result = Assemble("""
            .macro Wait
            .repeat 2
            .local Loop
            .endrepeat
            Loop: dex
            bne Loop
            .endmacro
            Wait
            Wait
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..6].ToArray().Should().Equal(0xCA, 0xD0, 0xFD, 0xCA, 0xD0, 0xFD);

        // Redeclaring in each iteration reuses one name, so defining it per iteration is a duplicate label.
        AssemblyResult duplicate = Assemble(".macro M\n.repeat 2\n.local L\nL: nop\n.endrepeat\n.endmacro\nM");
        duplicate.Diagnostics.Should().ContainSingle(error => error.Message.Contains("Duplicate symbol"));
    }

    /// <summary>
    ///  A repeat counter substitutes only in the repeat body's own lines, not in macros it invokes.
    /// </summary>
    [TestMethod]
    public void RepeatCountersAreNotVisibleInInvokedMacros()
    {
        Assemble(".macro M\n.byte i\n.endmacro\n.repeat 2, i\nM\n.endrepeat").Success.Should().BeFalse();
        AssemblyResult direct = Assemble(".macro M v\n.byte v\n.endmacro\n.repeat 2, i\nM i\n.endrepeat");
        direct.Diagnostics.Should().BeEmpty();
        direct.Sections[0].Bytes.Span[..2].ToArray().Should().Equal(0, 1);
    }

    /// <summary>
    ///  As in ca65, each included file must close the conditionals it opens.
    /// </summary>
    [TestMethod]
    public void IncludedConditionalsMustCloseInTheirOwnFile()
    {
        Resolver resolver = new();
        resolver.Add("open.inc", ".if 1");
        AssemblyResult result = Assemble(".include \"open.inc\"\nnop\n.endif", resolver);
        result.Diagnostics.Select(error => (error.Message, error.Location?.Path, error.Location?.Line)).Should().Equal(
            ("Unterminated conditional.", "open.inc", 0),
            ("Unexpected .ENDIF.", "main.asm", 2));
    }

    /// <summary>
    ///  .incbin lowers file bytes, with an optional start and size, through a binary-capable resolver.
    /// </summary>
    [TestMethod]
    public void BinaryIncludesRequireABinaryResolver()
    {
        BinaryResolver resolver = new();
        resolver.AddBinary("data.bin", Enumerable.Range(1, 20).Select(value => (byte)value).ToArray());
        AssemblyResult result = Assemble(".incbin \"data.bin\", 2, 17\n.byte $EE", resolver);
        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..18].ToArray().Should().Equal(
            Enumerable.Range(3, 17).Select(value => (byte)value).Append((byte)0xEE));

        result.SourceMap.Select(entry => entry.Location?.Line).Should().OnlyContain(line => line == 0 || line == 1);
        Assemble(".incbin \"data.bin\", 30", resolver).Diagnostics.Single().Message.Should().Contain("within the file");
        Assemble(".incbin \"missing.bin\"", resolver).Diagnostics.Single().Message.Should().Contain("not found");
        Assemble(".incbin \"data.bin\"", new Resolver()).Diagnostics.Single().Message.Should().Contain("not supported");
    }

    private static AssemblyResult Assemble(string text, IAssemblySourceResolver? resolver = null) =>
        new NativeAssembler().Assemble(new AssemblySource(text, "main.asm"), Options(resolver));

    private static AssemblyOptions Options(
        IAssemblySourceResolver? resolver = null,
        IReadOnlyList<string>? includePaths = null,
        IReadOnlyList<string>? sdkPaths = null) =>
            new(ProcessorVariant.Mos6502, origin: 0x1000, imageSize: 32)
            {
                SourceResolver = resolver,
                IncludePaths = includePaths ?? [],
                SdkPaths = sdkPaths ?? []
            };

}
