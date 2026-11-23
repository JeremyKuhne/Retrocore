// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;
using Retrocore.Debug.Language;
using Retrocore.Documentation;

namespace Retrocore.Tests;

// The editor's handling of a historical name given in a macro's body (docs/DocComments.md, section 2.4).
public sealed partial class LanguageAnalysisTests
{
    // A strict file whose macro body documents a routine with an old name, expanded once in a scope.
    private const string MacroProbe = """
        ; retrocore: style=strict
        ;; A probe.

        .cpu Mos6502
        .org $0300

        ;; Emits the byte reader.
        .macro Library
            ;; Requires a comma and reads a byte.
            ;; Also: COMBYTE (A2RM78)
        COMBYT:
            rts
        .endmacro

        ;; The interpreter.
        .scope Basic
            Library
        .endscope

        ;; Reads through <COMBYTE>.
        Echo:
            jsr COMBYTE
            rts
        """;

    /// <summary>
    ///  An old name in the body of a macro the build expands once works in the editor like any definition's: the file
    ///  is clean apart from the information hint, whose quick fix writes the name the expansion defined; hover says
    ///  whose old name it is; completion and workspace symbols find the definition by it; and go to definition lands
    ///  on the line in the macro's body.
    /// </summary>
    /// <returns>The test.</returns>
    [TestMethod]
    public async Task MacroBodiesOldNamesWorkInTheEditor()
    {
        string folder = Directory.CreateTempSubdirectory("retrocore-macros").FullName;
        try
        {
            string text = MacroProbe.ReplaceLineEndings("\n");
            string[] lines = text.Split('\n');
            string probe = Directory.CreateDirectory(Path.Join(folder, "probe")).FullName;
            string path = Path.GetFullPath(Path.Join(probe, "Probe.asm"));
            File.WriteAllText(path, text);
            File.WriteAllText(Path.Join(probe, "Bibliography.md"), MemberBibliography);
            RecordingLanguageClient client = new();
            LanguageWorkspace workspace = new(client);
            workspace.Update(path, text);
            SourceAnalysis? analysis = null;
            for (int attempt = 0; attempt < 6 && analysis is null; attempt++)
            {
                analysis = await workspace.AnalysisOfAsync(path, CancellationToken.None);
            }

            analysis.Should().NotBeNull();
            DocumentUri uri = DocumentUri.FromFileSystemPath(path);

            int use = Array.FindIndex(lines, line => line.Contains("jsr COMBYTE", StringComparison.Ordinal));
            int column = lines[use].IndexOf("COMBYTE", StringComparison.Ordinal);
            int body = Array.FindIndex(lines, line => line.StartsWith("COMBYT:", StringComparison.Ordinal));
            LspParams at = Request(uri, use, column + 1);

            List<Diagnostic> published = await client.Wait(
                uri,
                diagnostics => diagnostics.Count == 1 && diagnostics[0].Code == DocumentationRules.HistoricalName);

            Diagnostic hint = published.Should().ContainSingle().Which;
            hint.Message.Should().Be("COMBYTE is a historical name of Basic::COMBYT.");
            hint.Range.Start.Should().Be(new Position(use, column));
            JsonNode? actions = new CodeActionHandler(workspace, new BasicDocuments(client)).Handle(new JsonObject
            {
                ["textDocument"] = new JsonObject { ["uri"] = uri.Text },
                ["context"] = new JsonObject { ["diagnostics"] = new JsonArray(hint.ToJson()) }
            });

            JsonNode? fix = (actions as JsonArray)?.FirstOrDefault(
                action => action?["title"]?.GetValue<string>() == "Use Basic::COMBYT");

            JsonNode? edit = fix?["edit"]?["changes"]?[uri.Text]?[0];
            (edit?["newText"]?.GetValue<string>()).Should().Be("Basic::COMBYT");

            Hover? hover = await new HoverHandler(workspace, new BasicDocuments(client)).Handle(at);
            (hover?.Contents.Value).Should().Contain("`COMBYTE` is a historical name of `Basic::COMBYT`.");

            List<CompletionItem> completions = await new CompletionHandler(workspace, new BasicDocuments(client))
                .Handle(Request(uri, use, column));

            CompletionItem completion = completions.Should().ContainSingle(item => item.Label == "Basic::COMBYT").Which;
            completion.FilterText.Should().Contain("COMBYTE");

            LspParams query = Request(uri, 0, 0) with { Query = "COMBYTE" };
            IEnumerable<WorkspaceSymbol> symbols = await new WorkspaceSymbolHandler(workspace).Handle(query);
            symbols.Select(symbol => symbol.Name).Should().Contain("Basic::COMBYT (COMBYTE)");

            IEnumerable<LspLocation> definitions = await new DefinitionHandler(workspace, new BasicDocuments(client)).Handle(at);
            definitions.Should().ContainSingle().Which.Range.Start.Line.Should().Be(body);
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    // A file that gives COMBYTE only in a branch its build leaves out, and uses it where an undefined name is no error:
    // the SDK's AppleSoft also gives the name, and neither may become the file's hint.
    private const string OmittedBranchProbe = """
        ; retrocore: style=strict
        ;; A probe.

        .cpu Mos6502
        .org $0300

        .if 0
        ;; Reads a byte, in a build this file leaves out.
        ;; Also: COMBYTE (A2RM78)
        Unused:
            rts
        .endif

        ;; Reads a byte.
        ;; Also: PRBBYTE (A2RM78)
        PRBBYT:
            rts

        ;; Reads through the file's name.
        Echo:
            jsr PRBBYTE
            rts

        .ifdef COMBYTE
        .endif
        """;

    /// <summary>
    ///  A file's own old name takes precedence over an SDK module's only where the file's build gives it: one given
    ///  only in a branch the build leaves out gets no hint naming that branch's definition, as before the precedence.
    /// </summary>
    /// <returns>The test.</returns>
    [TestMethod]
    public async Task OldNamesInAnOmittedBranchDoNotHint()
    {
        string folder = Directory.CreateTempSubdirectory("retrocore-macros").FullName;
        try
        {
            string text = OmittedBranchProbe.ReplaceLineEndings("\n");
            string probe = Directory.CreateDirectory(Path.Join(folder, "probe")).FullName;
            string path = Path.GetFullPath(Path.Join(probe, "Probe.asm"));
            File.WriteAllText(path, text);
            File.WriteAllText(Path.Join(probe, "Bibliography.md"), MemberBibliography);
            RecordingLanguageClient client = new();
            LanguageWorkspace workspace = new(client);
            workspace.Update(path, text);
            DocumentUri uri = DocumentUri.FromFileSystemPath(path);

            // The file's own name in its build gets its hint, so the diagnostics are complete when it appears.
            List<Diagnostic> published = await client.Wait(
                uri,
                diagnostics => diagnostics.Any(diagnostic => diagnostic.Message.StartsWith("PRBBYTE is a historical name", StringComparison.Ordinal)));

            published.Should().Contain(diagnostic => diagnostic.Message == "PRBBYTE is a historical name of PRBBYT.");
            published.Should().NotContain(diagnostic => diagnostic.Severity == DiagnosticSeverity.Error, "the probe assembles");
            published.Should().NotContain(diagnostic => diagnostic.Message.StartsWith("COMBYTE is a historical name", StringComparison.Ordinal));
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    // Two macros whose bodies define the same name, each with its own old name, expanded in two scopes.
    private const string TwoMacroProbe = """
        ; retrocore: style=strict
        ;; A probe.

        .cpu Mos6502
        .org $0300

        ;; Emits one reader.
        .macro First
            ;; One reader.
            ;; Also: OLDA (A2RM78)
        COMBYT:
            rts
        .endmacro

        ;; Emits another.
        .macro Second
            ;; Another reader.
            ;; Also: OLDB (A2RM78)
        COMBYT:
            rts
        .endmacro

        ;; One.
        .scope A
            First
        .endscope

        ;; Two.
        .scope B
            Second
        .endscope

        ;; Reads.
        Echo:
            jsr OLDB
            rts
        """;

    /// <summary>
    ///  Where two macros' bodies define the same name, an old name's hint and go to definition reach the symbol and
    ///  line of its own macro's expansion, not the other's.
    /// </summary>
    /// <returns>The test.</returns>
    [TestMethod]
    public async Task OldNamesOfTwoMacrosReachTheirOwnInTheEditor()
    {
        string folder = Directory.CreateTempSubdirectory("retrocore-macros").FullName;
        try
        {
            string text = TwoMacroProbe.ReplaceLineEndings("\n");
            string[] lines = text.Split('\n');
            string probe = Directory.CreateDirectory(Path.Join(folder, "probe")).FullName;
            string path = Path.GetFullPath(Path.Join(probe, "Probe.asm"));
            File.WriteAllText(path, text);
            File.WriteAllText(Path.Join(probe, "Bibliography.md"), MemberBibliography);
            RecordingLanguageClient client = new();
            LanguageWorkspace workspace = new(client);
            workspace.Update(path, text);
            SourceAnalysis? analysis = null;
            for (int attempt = 0; attempt < 6 && analysis is null; attempt++)
            {
                analysis = await workspace.AnalysisOfAsync(path, CancellationToken.None);
            }

            analysis.Should().NotBeNull();
            DocumentUri uri = DocumentUri.FromFileSystemPath(path);
            int use = Array.FindIndex(lines, line => line.Contains("jsr OLDB", StringComparison.Ordinal));
            int column = lines[use].IndexOf("OLDB", StringComparison.Ordinal);
            int body = Array.FindLastIndex(lines, line => line.StartsWith("COMBYT:", StringComparison.Ordinal));

            List<Diagnostic> published = await client.Wait(
                uri,
                diagnostics => diagnostics.Count == 1 && diagnostics[0].Code == DocumentationRules.HistoricalName);

            published.Should().ContainSingle().Which.Message.Should().Be("OLDB is a historical name of B::COMBYT.");
            IEnumerable<LspLocation> definitions = await new DefinitionHandler(workspace, new BasicDocuments(client))
                .Handle(Request(uri, use, column + 1));

            definitions.Should().ContainSingle().Which.Range.Start.Line.Should().Be(body);

            // Each symbol is found by its own old name only: completion's filter text, workspace symbols and hover.
            List<CompletionItem> completions = await new CompletionHandler(workspace, new BasicDocuments(client))
                .Handle(Request(uri, use, column));

            completions.Should().ContainSingle(item => item.Label == "A::COMBYT").Which.FilterText.Should().Contain("OLDA")
                .And.NotContain("OLDB");

            LspParams query = Request(uri, 0, 0) with { Query = "OLDB" };
            IEnumerable<WorkspaceSymbol> symbols = await new WorkspaceSymbolHandler(workspace).Handle(query);
            symbols.Select(symbol => symbol.Name).Should().Contain("B::COMBYT (OLDB)").And.NotContain("A::COMBYT (OLDB)");

            Hover? hover = await new HoverHandler(workspace, new BasicDocuments(client)).Handle(Request(uri, use, column + 1));
            (hover?.Contents.Value).Should().Contain("`OLDB` is a historical name of `B::COMBYT`.");

            // A link by the old name opens its own macro's body, not the other's.
            DocumentationSet set = (analysis ?? throw new AssertFailedException("No analysis.")).Documentation;
            DocumentationTarget target = new DocumentationResolver(set).Resolve(set.Find("Echo") ?? throw new AssertFailedException("No Echo."), "OLDB");
            int comment = Array.FindIndex(lines, line => line.Contains(";; Another reader.", StringComparison.Ordinal));
            workspace.Href(target, path).Should().EndWith($"#L{comment + 1}");
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    // A macro never expanded beside a definition of the same name outside it.
    private const string UnexpandedProbe = """
        ; retrocore: style=strict
        ;; A probe.

        .cpu Mos6502
        .org $0300

        ;; Emits a reader.
        .macro Library
            ;; The macro's reader.
        COMBYT:
            rts
        .endmacro

        ;; The reader.
        ;; Also: COMBYTE (A2RM78)
        COMBYT:
            rts

        ;; Reads through <COMBYT>.
        Echo:
            jsr COMBYT
            rts
        """;

    // Two macros' bodies that define the same name: the build never expands the first and expands the second once.
    private const string ExpandedBesideProbe = """
        ; retrocore: style=strict
        ;; A probe.

        .cpu Mos6502
        .org $0300

        ;; Emits a reader.
        .macro Library
            ;; The macro's reader.
        COMBYT:
            rts
        .endmacro

        ;; Emits another.
        .macro Other
            ;; The other reader.
        COMBYT:
            rts
        .endmacro

        ;; The scope.
        .scope Basic
            Other
        .endscope

        ;; Reads through <COMBYT>.
        Echo:
            jsr Basic::COMBYT
            rts
        """;

    /// <summary>
    ///  A link to a name a macro's body shares with another definition opens the definition the build has, as without
    ///  the macro, where the build doesn't expand the body: a definition outside the macros, or another macro's body
    ///  the build expands once.
    /// </summary>
    /// <returns>The test.</returns>
    [TestMethod]
    public async Task LinksBesideAnUnexpandedMacroOpenTheOutsideDefinition()
    {
        await LinkOpens(UnexpandedProbe, ";; The reader.");

        // Beside another macro's body the build does expand, the link opens that one.
        await LinkOpens(ExpandedBesideProbe, ";; The other reader.");

        // So does a definition outside the macros in a branch the build leaves out.
        string skipped = ExpandedBesideProbe.Replace(
            ";; Emits a reader.\n.macro Library\n    ;; The macro's reader.\nCOMBYT:\n    rts\n.endmacro\n",
            ".ifdef WIDE\n;; The wide reader.\nCOMBYT:\n    rts\n.endif\n",
            StringComparison.Ordinal);

        skipped.Should().Contain(";; The wide reader.");
        await LinkOpens(skipped, ";; The other reader.");
    }

    private static async Task LinkOpens(string source, string opened)
    {
        string folder = Directory.CreateTempSubdirectory("retrocore-macros").FullName;
        try
        {
            string text = source.ReplaceLineEndings("\n");
            string[] lines = text.Split('\n');
            string probe = Directory.CreateDirectory(Path.Join(folder, "probe")).FullName;
            string path = Path.GetFullPath(Path.Join(probe, "Probe.asm"));
            File.WriteAllText(path, text);
            File.WriteAllText(Path.Join(probe, "Bibliography.md"), MemberBibliography);
            RecordingLanguageClient client = new();
            LanguageWorkspace workspace = new(client);
            workspace.Update(path, text);
            SourceAnalysis? analysis = null;
            for (int attempt = 0; attempt < 6 && analysis is null; attempt++)
            {
                analysis = await workspace.AnalysisOfAsync(path, CancellationToken.None);
            }

            DocumentationSet set = (analysis ?? throw new AssertFailedException("No analysis.")).Documentation;
            DocumentationTopic echo = set.Find("Echo") ?? throw new AssertFailedException("No Echo.");
            DocumentationTarget target = new DocumentationResolver(set).Resolve(echo, "COMBYT");
            int comment = Array.FindIndex(lines, line => line.Contains(opened, StringComparison.Ordinal));
            workspace.Href(target, path).Should().EndWith($"#L{comment + 1}");
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    // A file that gives COMBYTE itself, which the SDK's AppleSoft also gives, and has an unrelated error.
    private const string ErrorProbe = """
        ; retrocore: style=strict
        ;; A probe.

        .cpu Mos6502
        .org $0300

        ;; Requires a comma and reads a byte.
        ;; Also: COMBYTE (A2RM78)
        COMBYT:
            rts

        ;; Reads through the old name.
        Echo:
            jsr COMBYTE
            NOTANINSTRUCTION
            rts
        """;

    /// <summary>
    ///  A file's own old name keeps its hint over an SDK module's of the same spelling while the file has an error,
    ///  when its assembly stops short of the definitions: the definitions its text makes count then.
    /// </summary>
    /// <returns>The test.</returns>
    [TestMethod]
    public async Task OwnOldNamesHintWhileTheFileHasAnError()
    {
        string folder = Directory.CreateTempSubdirectory("retrocore-macros").FullName;
        try
        {
            string text = ErrorProbe.ReplaceLineEndings("\n");
            string probe = Directory.CreateDirectory(Path.Join(folder, "probe")).FullName;
            string path = Path.GetFullPath(Path.Join(probe, "Probe.asm"));
            File.WriteAllText(path, text);
            File.WriteAllText(Path.Join(probe, "Bibliography.md"), MemberBibliography);
            RecordingLanguageClient client = new();
            LanguageWorkspace workspace = new(client);
            workspace.Update(path, text);
            DocumentUri uri = DocumentUri.FromFileSystemPath(path);

            List<Diagnostic> published = await client.Wait(
                uri,
                diagnostics => diagnostics.Any(diagnostic => diagnostic.Code == DocumentationRules.HistoricalName));

            published.Should().Contain(diagnostic => diagnostic.Severity == DiagnosticSeverity.Error, "the probe has an error");
            published.Should().Contain(diagnostic => diagnostic.Message == "COMBYTE is a historical name of COMBYT.");
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    /// <summary>
    ///  While the file has an error, a name it gives only in a branch its build leaves out still gets no hint naming
    ///  that branch's definition: the branch's condition decides, as the assembly cannot.
    /// </summary>
    /// <returns>The test.</returns>
    [TestMethod]
    public async Task OldNamesInAnOmittedBranchDoNotHintWhileTheFileHasAnError()
    {
        string folder = Directory.CreateTempSubdirectory("retrocore-macros").FullName;
        try
        {
            string text = (OmittedBranchProbe + "\n    NOTANINSTRUCTION\n").ReplaceLineEndings("\n");
            string probe = Directory.CreateDirectory(Path.Join(folder, "probe")).FullName;
            string path = Path.GetFullPath(Path.Join(probe, "Probe.asm"));
            File.WriteAllText(path, text);
            File.WriteAllText(Path.Join(probe, "Bibliography.md"), MemberBibliography);
            RecordingLanguageClient client = new();
            LanguageWorkspace workspace = new(client);
            workspace.Update(path, text);
            DocumentUri uri = DocumentUri.FromFileSystemPath(path);

            List<Diagnostic> published = await client.Wait(
                uri,
                diagnostics => diagnostics.Any(diagnostic => diagnostic.Message.StartsWith("PRBBYTE is a historical name", StringComparison.Ordinal)));

            published.Should().Contain(diagnostic => diagnostic.Severity == DiagnosticSeverity.Error, "the probe has an error");
            published.Should().Contain(diagnostic => diagnostic.Message == "PRBBYTE is a historical name of PRBBYT.");
            published.Should().NotContain(diagnostic => diagnostic.Message.StartsWith("COMBYTE is a historical name", StringComparison.Ordinal));
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }
}
