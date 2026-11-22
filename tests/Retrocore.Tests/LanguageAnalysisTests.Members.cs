// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;
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

    private static LspParams Request(DocumentUri uri, int line, int character) =>
        new(new TextDocumentItem(uri, "retrocore-asm", ""), new Position(line, character), new ReferenceContext(IncludeDeclaration: false), "", []);
}
