// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Documentation;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

/// <summary>
///  Links in a source that builds several variants with <c>.if</c>: each build's links reach only the definitions
///  that build assembles, and the build's lint reports a link only another build can follow.
/// </summary>
[TestClass]
public sealed class DocumentationBuildTests
{
    // Two models: Shared is in both, OnlyOne only in model 1's branch, and Twice in both branches, each with a comment
    // of its own.
    private const string Source = """
        ;; Runs the model's start: <Common>, then <OnlyOne> on model 1.
        .proc Shared
            jsr Common
        .if MODEL = 1
            jsr OnlyOne
        .endif
            rts
        .endproc

        .if MODEL = 1
        ;; Model 1's own start.
        ;; Also: ONE (TEST)
        .proc OnlyOne
            rts
        .endproc

        ;; Model 1's version, which calls <OnlyOne>.
        Twice:
            jsr OnlyOne
            rts
        .else
        ;; Model 2's version, which calls <Common>.
        Twice:
            jsr Common
            rts
        .endif

        ;; Common to both models.
        Common:
            rts
        """;

    /// <summary>
    ///  A comment every build assembles that links a definition only one build has resolves in that build, and in the
    ///  other resolves to nothing and is reported there, as a link.
    /// </summary>
    [TestMethod]
    public void ALinkToAnotherBuildsDefinitionIsReportedInTheBuildThatLacksIt()
    {
        DocumentationSet one = Build(Source, model: 1);
        DocumentationSet two = Build(Source, model: 2);
        Resolve(one, "Shared", "OnlyOne").Topic.Should().NotBeNull();

        DocumentationTarget missing = Resolve(two, "Shared", "OnlyOne");
        missing.Kind.Should().Be(DocumentationTargetKind.Unresolved);
        missing.OnlyInOtherBuilds.Should().BeTrue();
        missing.Topic.Should().BeNull("hover and go to definition must not open a definition this build leaves out");
        two.InOtherBuild(Required(two.Find("OnlyOne"))).Should().BeTrue();
        one.InOtherBuild(Required(one.Find("OnlyOne"))).Should().BeFalse();

        Links(one).Should().BeEmpty();
        DocumentationDiagnostic problem = Links(two).Should().ContainSingle().Subject;
        problem.Line.Should().Be(0);
        problem.Name.Should().Be("OnlyOne");
        problem.Message.Should().Contain("only in other builds");
    }

    /// <summary>
    ///  A comment in the branch a build leaves out is checked by the build that takes it: its link to its own branch's
    ///  definition is not reported in the other build.
    /// </summary>
    [TestMethod]
    public void ABranchTheBuildLeavesOutIsCheckedByTheBuildThatTakesIt()
    {
        string source = Source.Replace(
            ";; Runs the model's start: <Common>, then <OnlyOne> on model 1.",
            ";; Runs the model's start: <Common>, then model 1's own.",
            StringComparison.Ordinal);

        DocumentationSet two = Build(source, model: 2);
        DocumentationTopic twice = Required(two.Find("Twice"));
        twice.Comments.Should().HaveCount(2);
        new DocumentationResolver(two).Resolve(twice, "OnlyOne", twice.Comments[0]).OnlyInOtherBuilds.Should().BeTrue();
        Links(two).Should().BeEmpty();
        Links(Build(source, model: 1)).Should().BeEmpty();
    }

    /// <summary>
    ///  A historical name only a definition another build has gives reaches nothing in this build.
    /// </summary>
    [TestMethod]
    public void AnOldNameOfAnotherBuildsDefinitionReachesNothing()
    {
        Required(Resolve(Build(Source, model: 1), "Shared", "ONE").Topic).Name.Should().Be("OnlyOne");
        Resolve(Build(Source, model: 2), "Shared", "ONE").OnlyInOtherBuilds.Should().BeTrue();
    }

    /// <summary>
    ///  The scope rules pass over a name only another build defines in an inner scope, for the build's own definition
    ///  in an outer one.
    /// </summary>
    [TestMethod]
    public void AnInnerScopesOtherBuildNameGivesWayToAnOuterOne()
    {
        const string Scoped = """
            .scope Outer
            .if MODEL = 1
            ;; Model 1's helper.
            Helper:
                rts
            .endif

            ;; Calls <Helper>.
            Caller:
                jsr Helper
                rts
            .endscope

            ;; Every model's helper.
            Helper:
                rts
            """;

        Required(Resolve(Build(Scoped, model: 1), "Outer::Caller", "Helper").Topic).Name.Should().Be("Outer::Helper");
        Required(Resolve(Build(Scoped, model: 2), "Outer::Caller", "Helper").Topic).Name.Should().Be("Helper");
    }

    /// <summary>
    ///  A link that names this source's own module reaches this build's definition before another build's set of the
    ///  module, and a definition only the other build has through that build's set.
    /// </summary>
    [TestMethod]
    public void ALinkNamingTheSourcesModuleKeepsToThisBuild()
    {
        DocumentationSet one = Build(Source, model: 1, module: "Test", modelName: "One");
        DocumentationSet two = Build(Source, model: 2, module: "Test", modelName: "Two");
        DocumentationResolver both = new(two, [one]);
        DocumentationTopic shared = Required(two.Find("Shared"));

        DocumentationTarget common = both.Resolve(shared, "Test:Common");
        common.Kind.Should().Be(DocumentationTargetKind.Topic, "the builds' Common is at different addresses, which was ambiguous");
        common.Set.Should().BeSameAs(two);
        both.Resolve(shared, "Test:OnlyOne").Set.Should().BeSameAs(one);
        new DocumentationResolver(two).Resolve(shared, "Test:OnlyOne").OnlyInOtherBuilds.Should().BeTrue();
    }

    /// <summary>
    ///  A macro defined in a branch the build leaves out, and the definitions in its body, are only in other builds.
    /// </summary>
    [TestMethod]
    public void AMacroInABranchTheBuildLeavesOutIsOnlyInOtherBuilds()
    {
        const string Expanded = """
            ;; Reads the table at <First>, which <Table> defines.
            Reader:
                rts

            .if MODEL = 1
            ;; Defines model 1's table.
            .macro Table
            ;; The table's first byte.
            First:
                .byte 1
            .endmacro

                Table
            .endif
            """;

        DocumentationSet one = Build(Expanded, model: 1);
        DocumentationSet two = Build(Expanded, model: 2);
        Required(Resolve(one, "Reader", "First").Topic).Name.Should().Be("First");
        Required(Resolve(one, "Reader", "Table").Topic).Name.Should().Be("Table");
        Resolve(two, "Reader", "First").OnlyInOtherBuilds.Should().BeTrue();
        Resolve(two, "Reader", "Table").OnlyInOtherBuilds.Should().BeTrue();
        Links(one).Should().BeEmpty();
        Links(two).Select(problem => problem.Name).Should().BeEquivalentTo(["First", "Table"]);
    }

    /// <summary>
    ///  A macro the build defines keeps the definitions in its body, though no expansion in the build defines them:
    ///  nothing tells a macro only another build expands from a library's macro no build does.
    /// </summary>
    [TestMethod]
    public void AMacroTheBuildDefinesKeepsItsBodysDefinitions()
    {
        const string Library = """
            ;; Defines a table.
            .macro Table
            ;; The table's first byte.
            First:
                .byte 1
            .endmacro

            ;; Reads the table at <First>.
            Reader:
                rts

            .if MODEL = 1
                Table
            .endif
            """;

        DocumentationSet two = Build(Library, model: 2);
        Required(Resolve(two, "Reader", "First").Topic).Name.Should().Be("First");
        Links(two).Should().BeEmpty();
    }

    /// <summary>
    ///  The body of a macro defined in a branch the build leaves out is only in other builds, though the build defines a
    ///  macro of the same name in its own branch, and though the macro has no documentation.
    /// </summary>
    [TestMethod]
    public void AMacrosBodyFollowsItsOwnDefinitionsBranch()
    {
        const string Branches = """
            ;; Reads <First>, and <Second>.
            Reader:
                rts

            .if MODEL = 1
            ;; Defines model 1's table.
            .macro Table
            ;; Model 1's first byte.
            First:
                .byte 1
            .endmacro
            .else
            ;; Defines model 2's table.
            .macro Table
                .byte 2
            .endmacro
            .macro Spare
            ;; A byte only model 2's undocumented macro defines.
            Second:
                .byte 3
            .endmacro
            .endif
            """;

        DocumentationSet one = Build(Branches, model: 1);
        DocumentationSet two = Build(Branches, model: 2);
        Resolve(one, "Reader", "Second").OnlyInOtherBuilds.Should().BeTrue("model 1 skips the undocumented Spare");
        Resolve(two, "Reader", "First").OnlyInOtherBuilds.Should().BeTrue("model 2 defines its own Table");
        Required(Resolve(one, "Reader", "First").Topic).Name.Should().Be("First");
        Required(Resolve(two, "Reader", "Second").Topic).Name.Should().Be("Second");
    }

    /// <summary>
    ///  In a macro the build expands, a definition in a branch of the body that no expansion takes is not in the build.
    /// </summary>
    [TestMethod]
    public void ABodysBranchNoExpansionTakesIsNotInTheBuild()
    {
        const string Body = """
            ;; Defines a table, with a byte for mode 1.
            .macro Table mode
                .byte 0
            .if mode = 1
            ;; Mode 1's byte.
            First:
                .byte 1
            .endif
            .endmacro

            ;; Reads <First>.
            Reader:
                rts

                Table MODEL
            """;

        Required(Resolve(Build(Body, model: 1), "Reader", "First").Topic).Name.Should().Be("First");
        Resolve(Build(Body, model: 2), "Reader", "First").OnlyInOtherBuilds.Should().BeTrue();

        // The macro's own documentation is held to the same rule as any other comment.
        Resolve(Build(Body, model: 2), "Table", "First").OnlyInOtherBuilds.Should().BeTrue();
    }

    /// <summary>
    ///  A comment in the body of a macro the build doesn't expand is checked by the builds that expand it.
    /// </summary>
    [TestMethod]
    public void AnUnexpandedMacrosBodyIsCheckedWhereItIsExpanded()
    {
        string source = Source + """

            .if MODEL = 2
            ;; Model 2's own start.
            OnlyTwo:
                rts
            .endif

            ;; Calls model 1's start.
            .macro Starter
            ;; A common entry that jumps to <OnlyOne>, not <OnlyTwo>.
            Common:
                jmp OnlyOne
            .endmacro

            .if MODEL = 1
            .scope Started
                Starter
            .endscope
            .endif
            """;

        source = source.Replace(", then <OnlyOne> on model 1.", ".", StringComparison.Ordinal);
        Links(Build(source, model: 1)).Should().ContainSingle().Which.Name.Should().Be("OnlyTwo");
        Links(Build(source, model: 2)).Should().BeEmpty();
    }

    /// <summary>
    ///  A scope or structure only a branch the build leaves out defines is only in other builds, its members with it.
    /// </summary>
    [TestMethod]
    public void AScopeOrStructOnlyAnotherBuildDefinesIsOnlyInOtherBuilds()
    {
        const string Scopes = """
            ;; Uses <Tools> and <Block>.
            Caller:
                rts

            .if MODEL = 1
            ;; Model 1's tools.
            .scope Tools
            Helper:
                rts
            .endscope

            ;; Model 1's block.
            .struct Block
            ;; Its first byte.
            First   .byte
            .endstruct
            .endif
            """;

        Required(Resolve(Build(Scopes, model: 1), "Caller", "Tools").Topic).Name.Should().Be("Tools");
        Resolve(Build(Scopes, model: 2), "Caller", "Tools").OnlyInOtherBuilds.Should().BeTrue();
        Resolve(Build(Scopes, model: 2), "Caller", "Block").OnlyInOtherBuilds.Should().BeTrue();
        Resolve(Build(Scopes, model: 2), "Caller", "Block::First").OnlyInOtherBuilds.Should().BeTrue();
        Links(Build(Scopes, model: 1)).Should().BeEmpty();
        Links(Build(Scopes, model: 2)).Select(problem => problem.Name).Should().BeEquivalentTo(["Tools", "Block"]);
    }

    /// <summary>
    ///  A <c>.define</c> in a branch the build leaves out is only in other builds.
    /// </summary>
    [TestMethod]
    public void ADefineInABranchTheBuildLeavesOutIsOnlyInOtherBuilds()
    {
        const string Defines = """
            ;; Reads with <READER>.
            Caller:
                rts

            .if MODEL = 1
            ;; Model 1's reader.
            .define READER lda $C000
            .endif
            """;

        Required(Resolve(Build(Defines, model: 1), "Caller", "READER").Topic).Name.Should().Be("READER");
        Resolve(Build(Defines, model: 2), "Caller", "READER").OnlyInOtherBuilds.Should().BeTrue();
    }

    /// <summary>
    ///  Documentation of an assembly that failed links every branch as before: its definitions aren't known.
    /// </summary>
    [TestMethod]
    public void DocumentationOfAFailedAssemblyResolvesEveryBranch()
    {
        string broken = Source + "\n.if MODEL = 1\n;; Model 1's tools.\n.scope Tools\nHelper:\n    rts\n.endscope\n.endif\n    jmp Nowhere\n";
        AssemblyResult result = Assemble(broken, model: 2);
        result.Success.Should().BeFalse();
        DocumentationSet set = DocumentationSet.Create([DocumentationParser.Parse(broken, "test.asm")], result);
        DocumentationTopic shared = Required(set.Find("Shared"));
        DocumentationResolver resolver = new(set);
        Required(resolver.Resolve(shared, "OnlyOne").Topic).Name.Should().Be("OnlyOne");

        // A scope only model 1 opens: the failed assembly's symbols, which needn't be complete, don't decide it.
        Required(resolver.Resolve(shared, "Tools").Topic).Name.Should().Be("Tools");
    }

    /// <summary>
    ///  A scope a <c>.using</c> directive names passes over a name only another build defines in it.
    /// </summary>
    [TestMethod]
    public void AUsedScopesOtherBuildNameReachesNothing()
    {
        const string Used = """
            .scope Tools
            .if MODEL = 1
            ;; Model 1's helper.
            Helper:
                rts
            .endif
            .endscope

            .using Tools
            ;; Calls <Helper>.
            Caller:
                rts
            """;

        Required(Resolve(Build(Used, model: 1), "Caller", "Helper").Topic).Name.Should().Be("Tools::Helper");
        Resolve(Build(Used, model: 2), "Caller", "Helper").OnlyInOtherBuilds.Should().BeTrue();
    }

    /// <summary>
    ///  An old name reaches the definition the build has of two branches that give it, and nothing where only the
    ///  branch the build leaves out gives it to a definition both builds have.
    /// </summary>
    [TestMethod]
    public void AnOldNameReachesOnlyWhatTheBuildGives()
    {
        const string Given = """
            .if MODEL = 1
            ;; Model 1's start.
            ;; Also: START (TEST)
            StartOne:
                rts

            ;; Model 1's version.
            ;; Also: ONLYONE (TEST)
            Both:
                rts
            .else
            ;; Model 2's start.
            ;; Also: START (TEST)
            StartTwo:
                rts

            ;; Model 2's version.
            Both:
                rts
            .endif

            ;; Starts through <START>, then <ONLYONE>.
            Caller:
                rts
            """;

        DocumentationSet one = Build(Given, model: 1);
        DocumentationSet two = Build(Given, model: 2);
        Required(Resolve(one, "Caller", "START").Topic).Name.Should().Be("StartOne");
        Required(Resolve(two, "Caller", "START").Topic).Name.Should().Be("StartTwo");
        Required(Resolve(one, "Caller", "ONLYONE").Topic).Name.Should().Be("Both");
        Resolve(two, "Caller", "ONLYONE").OnlyInOtherBuilds.Should().BeTrue();
    }

    /// <summary>
    ///  A link that names a model reaches that model's set, though this build leaves the definition out.
    /// </summary>
    [TestMethod]
    public void ALinkNamingAModelReachesThatBuildsSet()
    {
        DocumentationSet original = Build(Source, model: 1, module: "Test", modelName: "Original");
        DocumentationSet enhanced = Build(Source, model: 2, module: "Test", modelName: "Enhanced");
        DocumentationTopic shared = Required(enhanced.Find("Shared"));
        new DocumentationResolver(enhanced, [original]).Resolve(shared, "Test:OnlyOne@Original").Set.Should().BeSameAs(original);
        new DocumentationResolver(enhanced, [original]).Resolve(shared, "OnlyOne").OnlyInOtherBuilds.Should().BeTrue();
    }

    /// <summary>
    ///  A section's entries are names, not links: a contract every build shares may list what one build has.
    /// </summary>
    [TestMethod]
    public void AnEntryMayNameAnotherBuildsDefinition()
    {
        string source = Source.Replace(
            ";; Runs the model's start: <Common>, then <OnlyOne> on model 1.",
            ";; Runs the model's start.\n;; Uses: A, OnlyOne",
            StringComparison.Ordinal);

        new DocumentationResolver(Build(source, model: 2)).Check().Should().BeEmpty();
    }

    /// <summary>
    ///  Documentation without the assembly's report of what it skipped, as a debug file's, resolves as before: a link
    ///  reaches a definition of any branch.
    /// </summary>
    [TestMethod]
    public void DocumentationWithoutItsBuildResolvesEveryBranch()
    {
        AssemblyResult result = Assemble(Source, model: 2);
        DocumentationSet set = DocumentationSet.Create([DocumentationParser.Parse(Source, "test.asm")], result.Symbols);
        DocumentationTarget target = new DocumentationResolver(set).Resolve(Required(set.Find("Shared")), "OnlyOne");
        Required(target.Topic).Name.Should().Be("OnlyOne");
        target.OnlyInOtherBuilds.Should().BeFalse();
    }

    /// <summary>
    ///  A source that builds one way resolves its links as before, a definition in a macro's body it expands among
    ///  them.
    /// </summary>
    [TestMethod]
    public void ASingleBuildResolvesAsBefore()
    {
        const string Single = """
            ;; Defines a table.
            .macro Table
            ;; The table's first byte.
            First:
                .byte 1
            .endmacro

            ;; Calls <Helper> and reads <First>.
            Caller:
                jsr Helper
                rts

            ;; Helps.
            Helper:
                rts

                Table
            """;

        DocumentationSet set = Build(Single, model: 1);
        Required(Resolve(set, "Caller", "Helper").Topic).Name.Should().Be("Helper");
        Required(Resolve(set, "Caller", "First").Topic).Name.Should().Be("First");
        new DocumentationResolver(set).Check().Should().BeEmpty();
    }

    // The link problems of a build's documentation.
    private static List<DocumentationDiagnostic> Links(DocumentationSet set) =>
        [.. new DocumentationResolver(set).Check().Where(problem => problem.Rule == DocumentationRules.Link)];

    private static DocumentationTarget Resolve(DocumentationSet set, string from, string target) =>
        new DocumentationResolver(set).Resolve(Required(set.Find(from)), target);

    private static DocumentationSet Build(string text, int model, string? module = null, string? modelName = null)
    {
        AssemblyResult result = Assemble(text, model);
        result.Success.Should().BeTrue(string.Join(Environment.NewLine, result.Diagnostics.Select(diagnostic => diagnostic.Message)));
        return DocumentationSet.Create([DocumentationParser.Parse(text, "test.asm")], result, module, modelName);
    }

    private static AssemblyResult Assemble(string text, int model) =>
        new NativeAssembler().Assemble(
            new AssemblySource(text, "test.asm"),
            new AssemblyOptions(ProcessorVariant.Mos6502, origin: 0x1000, imageSize: 0x100)
            {
                PredefinedSymbols = new Dictionary<string, long> { ["MODEL"] = model }
            });

    private static T Required<T>(T? value) where T : class =>
        value ?? throw new AssertFailedException($"Expected a {typeof(T).Name}.");
}
