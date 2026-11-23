// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;
using Retrocore.Assembler;
using Retrocore.Debug.Language;
using Retrocore.Documentation;

namespace Retrocore.Tests;

// The editor's handling of a struct member's historical name (docs/backlog/MemberDocumentation.md).
public sealed partial class LanguageAnalysisTests
{
    // A strict file whose struct has an anonymous union of documented members, used by their old names.
    private const string MemberProbe = """
        ; retrocore: style=strict
        ;; A probe.

        .cpu Mos6502
        .org $0300

        ;; An I/O block.
        .struct Iob
            ;; The block's type.
            ;; Also: IBTYPE (A2RM78)
            TYPE .byte
            .union
                ;; The command, before the call.
                ;; Also: IBCMD (A2RM78)
                COMMAND .byte
                ;; The status, after it.
                ;; Also: IBSTAT (A2RM78)
                STATUS .byte
            .endunion
        .endstruct

        ;; Echoes <IBCMD> and <Iob::STATUS>.
        Echo:
            lda #IBCMD
            ldy #Iob::STATUS
            rts
        """;

    // The probe's folder's own bibliography, with the document its Also: sections cite.
    private const string MemberBibliography = """
        | Key | Title | Year | Publisher | Link |
        | --- | --- | --- | --- | --- |
        | A2RM78 | A Manual | 1978 | Apple | |
        """;

    /// <summary>
    ///  A member's old name works in the editor like any definition's: the file is clean apart from the information
    ///  hint, whose quick fix writes the qualified name; hover says whose old name it is; completion and workspace
    ///  symbols find the member by it; and go to definition lands on the member's line.
    /// </summary>
    /// <returns>The test.</returns>
    [TestMethod]
    public async Task MembersOldNamesWorkInTheEditor()
    {
        string folder = Directory.CreateTempSubdirectory("retrocore-members").FullName;
        try
        {
            string text = MemberProbe.ReplaceLineEndings("\n");
            string[] lines = text.Split('\n');
            // The editor reads the folders beside a source's, so the probe gets a folder of its own inside the
            // temporary one, away from other tests' temporary folders, which come and go while it runs.
            string probe = Directory.CreateDirectory(Path.Join(folder, "probe")).FullName;
            string path = Path.GetFullPath(Path.Join(probe, "Probe.asm"));
            File.WriteAllText(path, text);
            File.WriteAllText(Path.Join(probe, "Bibliography.md"), MemberBibliography);
            RecordingLanguageClient client = new();
            LanguageWorkspace workspace = new(client);
            workspace.Update(path, text);
            // The first assembly can take longer than a request waits when other tests load the machine.
            SourceAnalysis? analysis = null;
            for (int attempt = 0; attempt < 6 && analysis is null; attempt++)
            {
                analysis = await workspace.AnalysisOfAsync(path, CancellationToken.None);
            }

            analysis.Should().NotBeNull();
            DocumentUri uri = DocumentUri.FromFileSystemPath(path);

            int use = Array.FindIndex(lines, line => line.Contains("lda #IBCMD", StringComparison.Ordinal));
            int column = lines[use].IndexOf("IBCMD", StringComparison.Ordinal);
            int member = Array.FindIndex(lines, line => line.Contains("COMMAND .byte", StringComparison.Ordinal));
            LspParams at = Request(uri, use, column + 1);

            // The only problem is the hint on the old name, and its quick fix writes the qualified name.
            // The workspace can publish an earlier set first (the assembly's, before the documentation's), so wait for
            // the one that holds the hint; a wrong extra problem then times out and fails below.
            List<Diagnostic> published = await client.Wait(
                uri,
                diagnostics => diagnostics.Count == 1 && diagnostics[0].Code == DocumentationRules.HistoricalName);

            Diagnostic hint = published.Should().ContainSingle().Which;
            hint.Code.Should().Be(DocumentationRules.HistoricalName);
            hint.Message.Should().Be("IBCMD is a historical name of Iob::COMMAND.");
            hint.Range.Start.Should().Be(new Position(use, column));
            JsonNode? actions = new CodeActionHandler(workspace, new BasicDocuments(client)).Handle(new JsonObject
            {
                ["textDocument"] = new JsonObject { ["uri"] = uri.Text },
                ["context"] = new JsonObject { ["diagnostics"] = new JsonArray(hint.ToJson()) }
            });

            // Beside the fix, the lint offers exclusions that ignore the rule; the fix is the one that uses the name.
            JsonNode? fix = (actions as JsonArray)?.FirstOrDefault(
                action => action?["title"]?.GetValue<string>() == "Use Iob::COMMAND");

            JsonNode? edit = fix?["edit"]?["changes"]?[uri.Text]?[0];
            (edit?["newText"]?.GetValue<string>()).Should().Be("Iob::COMMAND");

            Hover? hover = await new HoverHandler(workspace, new BasicDocuments(client)).Handle(at);
            (hover?.Contents.Value).Should().Contain("`IBCMD` is a historical name of `Iob::COMMAND`.");

            List<CompletionItem> completions = await new CompletionHandler(workspace, new BasicDocuments(client))
                .Handle(Request(uri, use, column));

            CompletionItem completion = completions.Should().ContainSingle(item => item.Label == "Iob::COMMAND").Which;
            completion.FilterText.Should().Contain("IBCMD");

            LspParams query = Request(uri, 0, 0) with { Query = "IBCMD" };
            IEnumerable<WorkspaceSymbol> symbols = await new WorkspaceSymbolHandler(workspace).Handle(query);
            symbols.Select(symbol => symbol.Name).Should().Contain("Iob::COMMAND (IBCMD)");

            IEnumerable<LspLocation> definitions = await new DefinitionHandler(workspace, new BasicDocuments(client)).Handle(at);
            LspLocation definition = definitions.Should().ContainSingle().Which;
            definition.Range.Start.Line.Should().Be(member);
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    // An old name that a .using brings to another type's member inside one procedure.
    private const string ShadowProbe = """
        ;; An I/O block.
        .struct Iob
            ;; The block's type, which a listing also calls TYPE.
            ;; Also: TYPE (A2RM78)
            TYPE .byte
            ;; The command.
            ;; Also: IBCMD (A2RM78)
            COMMAND .byte
        .endstruct

        ;; Uses an old name that the .using here brings to the old name's own definition.
        .proc Agreeing
        .using Iob
            lda #TYPE
            rts
        .endproc

        ;; Another block, with a field of the same spelling.
        .struct Other
            ;; Padding.
            PAD .byte
            ;; Its own field.
            IBCMD .byte
        .endstruct

        ;; Uses the name under a .using.
        .proc Shadowed
        .using Other
            lda #IBCMD
            rts
        .endproc

        ;; Uses the old name, which nothing shadows here, and the other field by its full name.
        .proc Plain
            lda #IBCMD
            lda #Other::IBCMD
            rts
        .endproc
        """;

    /// <summary>
    ///  A historical name that a <c>.using</c> makes mean another definition gets a <c>using-shadow</c> warning where
    ///  code uses it, with quick fixes that write either name; elsewhere it is an ordinary historical name, and a
    ///  qualified name is neither. A <c>.using</c> that brings the old name to its own definition is not reported.
    /// </summary>
    /// <returns>The test.</returns>
    [TestMethod]
    public async Task ShadowedOldNamesAreReported()
    {
        string folder = Directory.CreateTempSubdirectory("retrocore-shadow").FullName;
        try
        {
            string text = ShadowProbe.ReplaceLineEndings("\n");
            string[] lines = text.Split('\n');
            string probe = Directory.CreateDirectory(Path.Join(folder, "probe")).FullName;
            string path = Path.GetFullPath(Path.Join(probe, "Shadow.asm"));
            File.WriteAllText(path, text);
            File.WriteAllText(Path.Join(probe, "Bibliography.md"), MemberBibliography);
            RecordingLanguageClient client = new();
            LanguageWorkspace workspace = new(client);
            workspace.Update(path, text);
            DocumentUri uri = DocumentUri.FromFileSystemPath(path);

            int shadowedLine = Array.FindIndex(lines, line => line.Contains("lda #IBCMD", StringComparison.Ordinal));
            int plainLine = Array.FindLastIndex(lines, line => line.Contains("lda #IBCMD", StringComparison.Ordinal));
            List<Diagnostic> published = await client.Wait(uri, diagnostics => diagnostics.Count == 2);
            published.Select(diagnostic => (diagnostic.Code, diagnostic.Range.Start.Line, diagnostic.Message)).Should().BeEquivalentTo(
            [
                (DocumentationRules.UsingShadow, shadowedLine,
                    "IBCMD is a historical name of Iob::COMMAND, but the .using in effect here makes it Other::IBCMD."),
                (DocumentationRules.HistoricalName, plainLine, "IBCMD is a historical name of Iob::COMMAND.")
            ]);

            Diagnostic shadowed = published.Single(diagnostic => diagnostic.Code == DocumentationRules.UsingShadow);
            shadowed.Severity.Should().Be(DiagnosticSeverity.Warning);
            JsonNode? actions = new CodeActionHandler(workspace, new BasicDocuments(client)).Handle(new JsonObject
            {
                ["textDocument"] = new JsonObject { ["uri"] = uri.Text },
                ["context"] = new JsonObject { ["diagnostics"] = new JsonArray(shadowed.ToJson()) }
            });

            List<(string? Title, bool Preferred, string? Text)> fixes = [.. ((actions as JsonArray) ?? [])
                .Where(action => action?["title"]?.GetValue<string>()?.StartsWith("Use ", StringComparison.Ordinal) == true)
                .Select(action => (
                    action?["title"]?.GetValue<string>(),
                    action?["isPreferred"]?.GetValue<bool>() == true,
                    action?["edit"]?["changes"]?[uri.Text]?[0]?["newText"]?.GetValue<string>()))];

            fixes.Should().Equal(("Use Other::IBCMD", true, "Other::IBCMD"), ("Use Iob::COMMAND", false, "Iob::COMMAND"));
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    /// <summary>
    ///  A definition in a branch of conditional assembly that the build does not take is found in the text, and is
    ///  qualified by its scope as the assembler would qualify it: it is not taken for a root name, so an old name of
    ///  the same spelling still gets its hint where code uses it, and its warning where a <c>.using</c> of the scope
    ///  makes it the scope's.
    /// </summary>
    /// <returns>The test.</returns>
    [TestMethod]
    public async Task UnassembledDefinitionsKeepTheirScope()
    {
        const string Probe = """
            ;; Picks the build.
            VARIANT = 1

            ;; An I/O block.
            .struct Iob
                ;; The block's type.
                TYPE .byte
                ;; The command.
                ;; Also: IBCMD (A2RM78)
                COMMAND .byte
            .endstruct

            ;; Constants that differ by build.
            .scope Other
            .if VARIANT
            ;; The first build's value.
            IBCMD = 1
            .else
            ;; The second build's value.
            IBCMD = 2
            .endif
            .endscope

            ;; Uses the old name, outside the scope.
            .proc Use
                lda #IBCMD
                rts
            .endproc

            ;; Uses the name under a .using of the scope.
            .proc Shadowed
            .using Other
                lda #IBCMD
                rts
            .endproc
            """;

        string folder = Directory.CreateTempSubdirectory("retrocore-unassembled").FullName;
        try
        {
            string text = Probe.ReplaceLineEndings("\n");
            string[] lines = text.Split('\n');
            string probe = Directory.CreateDirectory(Path.Join(folder, "probe")).FullName;
            string path = Path.GetFullPath(Path.Join(probe, "Builds.asm"));
            File.WriteAllText(path, text);
            File.WriteAllText(Path.Join(probe, "Bibliography.md"), MemberBibliography);
            RecordingLanguageClient client = new();
            LanguageWorkspace workspace = new(client);
            workspace.Update(path, text);
            DocumentUri uri = DocumentUri.FromFileSystemPath(path);

            SourceAnalysis? analysis = null;
            for (int attempt = 0; attempt < 6 && analysis is null; attempt++)
            {
                analysis = await workspace.AnalysisOfAsync(path, CancellationToken.None);
            }

            // The taken branch is assembled; the other is found in the text, in its scope, where the assembled one
            // already defines the name. Neither is a root name.
            int taken = Array.FindIndex(lines, line => line.Contains("IBCMD = 1", StringComparison.Ordinal));
            (analysis?.Definitions ?? []).Where(site => site.Name.EndsWith("IBCMD", StringComparison.Ordinal))
                .Select(site => (site.Name, site.Line)).Should().Equal(("Other::IBCMD", taken));

            int use = Array.FindIndex(lines, line => line.Contains("lda #IBCMD", StringComparison.Ordinal));
            int shadowed = Array.FindLastIndex(lines, line => line.Contains("lda #IBCMD", StringComparison.Ordinal));
            List<Diagnostic> published = await client.Wait(uri, diagnostics => diagnostics.Count == 2);
            published.Select(diagnostic => (diagnostic.Code, diagnostic.Range.Start.Line, diagnostic.Message)).Should().BeEquivalentTo(
            [
                (DocumentationRules.HistoricalName, use, "IBCMD is a historical name of Iob::COMMAND."),
                (DocumentationRules.UsingShadow, shadowed,
                    "IBCMD is a historical name of Iob::COMMAND, but the .using in effect here makes it Other::IBCMD.")
            ]);
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    /// <summary>
    ///  A file included inside two scopes defines its text-only names in each: a definition in a branch the build
    ///  does not take is recorded once per scope, and never as a root name. That holds for a file the assembly reaches
    ///  (whose statements show where it is included) and for one whose whole content the build skips (whose
    ///  <c>.include</c> lines show it).
    /// </summary>
    [TestMethod]
    public void TextOnlyDefinitionsAreInEachScopeAFileIsIncludedIn()
    {
        string folder = Directory.CreateTempSubdirectory("retrocore-included").FullName;
        try
        {
            string main = Path.Join(folder, "Main.asm");
            File.WriteAllText(main, """
                .org $0300
                .scope First
                .include "Shared.asm"
                .include "Skipped.asm"
                .endscope
                .scope Second
                .include "Shared.asm"
                .include "Skipped.asm"
                .endscope
                """.ReplaceLineEndings("\n"));

            // This file assembles a statement; the other assembles nothing.
            File.WriteAllText(Path.Join(folder, "Shared.asm"), """
                    nop
                .if 0
                VALUE = 1
                .endif
                """.ReplaceLineEndings("\n"));

            File.WriteAllText(Path.Join(folder, "Skipped.asm"), """
                .if 0
                SKIPPED = 1
                .endif
                """.ReplaceLineEndings("\n"));

            SourceAnalysis analysis = SourceAnalysis.Assemble(Path.GetFullPath(main), _ => null);
            List<string> names = [.. analysis.Definitions.Select(site => site.Name)];
            names.Where(name => name.EndsWith("VALUE", StringComparison.Ordinal)).Should().BeEquivalentTo("First::VALUE", "Second::VALUE");
            names.Where(name => name.EndsWith("SKIPPED", StringComparison.Ordinal)).Should().BeEquivalentTo("First::SKIPPED", "Second::SKIPPED");
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    /// <summary>
    ///  In a source with errors, a text-only definition written qualified keeps its spelling rather than gaining its
    ///  scope twice, and a cheap local keeps its own, while a plain label is qualified by its scope.
    /// </summary>
    [TestMethod]
    public void TextOnlyQualifiedNamesAndCheapLocalsKeepTheirSpelling()
    {
        string folder = Directory.CreateTempSubdirectory("retrocore-spelling").FullName;
        try
        {
            string main = Path.Join(folder, "Broken.asm");
            File.WriteAllText(main, """
                .org $0300
                .scope Outer
                Outer::Written:
                    nop
                Plain:
                @loop:
                    bne @loop
                    lda #
                .endscope
                """.ReplaceLineEndings("\n"));

            SourceAnalysis analysis = SourceAnalysis.Assemble(Path.GetFullPath(main), _ => null);
            analysis.Result.Success.Should().BeFalse();
            analysis.Definitions.Select(site => site.Name).Should().Contain(["Outer::Written", "Outer::Plain", "@loop"])
                .And.NotContain(["Outer::Outer::Written", "Outer::@loop", "Plain"]);
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    /// <summary>
    ///  A file named by an absolute path in an <c>.include</c> is found where the workspace's resolver finds it: a
    ///  skipped file is placed in the scope it is included in, and the root search finds the source that includes it.
    ///  A name no path can hold is passed over rather than failing the search.
    /// </summary>
    [TestMethod]
    public void AbsoluteIncludesAreFoundWhereTheResolverFindsThem()
    {
        string folder = Directory.CreateTempSubdirectory("retrocore-absolute").FullName;
        try
        {
            // The included file is in another folder, so a name resolved from the including file's folder misses it.
            string library = Directory.CreateDirectory(Path.Join(folder, "library")).FullName;
            string program = Directory.CreateDirectory(Path.Join(folder, "program")).FullName;
            string skipped = Path.GetFullPath(Path.Join(library, "Skipped.asm"));
            File.WriteAllText(skipped, """
                .if 0
                ABSOLUTE = 1
                .endif
                """.ReplaceLineEndings("\n"));

            string main = Path.GetFullPath(Path.Join(program, "Main.asm"));
            File.WriteAllText(main, $"""
                .org $0300
                .scope First
                .include "{skipped}"
                .endscope
                .include "bad{'\0'}name.asm"
                """.ReplaceLineEndings("\n"));

            SourceIncludes.IncludesOf(main).Should().Equal(skipped);
            SourceIncludes.IncludeLines(main, File.ReadAllLines(main)).Should().Equal((2, skipped));
            SourceIncludes.RootOf(skipped).Should().Be(main);

            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);
            analysis.Definitions.Select(site => site.Name).Where(name => name.EndsWith("ABSOLUTE", StringComparison.Ordinal))
                .Should().Equal("First::ABSOLUTE");
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    /// <summary>
    ///  The editor resolves an included name as the assembler's file resolver does, so it names a file by the path
    ///  the assembler reads it from (relative, parent and fully qualified), and rejects the Windows names the
    ///  assembler rejects because they depend on current-directory state.
    /// </summary>
    /// <param name="request">The included name.</param>
    [TestMethod]
    [DataRow("Library.asm")]
    [DataRow("../lib/Library.asm")]
    [DataRow("/shared/Library.asm")]
    [DataRow(@"\lib\Library.asm")]
    [DataRow(@"C:Library.asm")]
    [DataRow(@"C:\lib\Library.asm")]
    [DataRow(@"\\server\share\Library.asm")]
    public void IncludesResolveAsTheAssemblerResolvesThem(string request)
    {
        string from = Path.GetFullPath(Path.Join(Path.GetTempPath(), "retrocore-paths", "program", "Main.asm"));
        if (AssemblySourcePaths.DependsOnCurrentDirectory(request))
        {
            FluentActions.Invoking(() => LanguagePaths.Resolve(from, request)).Should().Throw<ArgumentException>();
            SourceIncludes.IncludeLines(from, [$".include \"{request}\""]).Should().BeEmpty();
            return;
        }

        LanguagePaths.Resolve(from, request).Should().Be(AssemblySourcePaths.Resolve(from, request));
        LanguagePaths.Resolve("", request).Should().Be(AssemblySourcePaths.Resolve("", request));
        SourceIncludes.IncludeLines(from, [$".include \"{request}\""]).Should().Equal((0, AssemblySourcePaths.Resolve(from, request)));
    }

    /// <summary>
    ///  On Windows, a name rooted without being fully qualified depends on current-directory state, so the editor
    ///  does not take it for an include, as the assembler rejects it; a fully qualified or relative name is.
    /// </summary>
    [TestMethod]
    [OSCondition(OperatingSystems.Windows)]
    public void CurrentDirectoryIncludesAreNotFilesOnWindows()
    {
        const string From = @"C:\work\program\Main.asm";
        string[] lines = [@".include ""\lib\Library.asm""", @".include ""C:Library.asm""", @".include ""D:\lib\Library.asm""", @".include ""lib\Library.asm"""];
        SourceIncludes.IncludeLines(From, lines).Should().Equal((2, @"D:\lib\Library.asm"), (3, @"C:\work\program\lib\Library.asm"));
    }

    private static LspParams Request(DocumentUri uri, int line, int character) =>
        new(new TextDocumentItem(uri, "retrocore-asm", ""), new Position(line, character), new ReferenceContext(IncludeDeclaration: false), "", []);
}
