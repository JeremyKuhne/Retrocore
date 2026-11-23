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
            ;; Also: PRBBYTE (A2RM78)
        PRBBYT:
            rts
        .endmacro

        ;; The interpreter.
        .scope Basic
            Library
        .endscope

        ;; Reads through <PRBBYTE>.
        Echo:
            jsr PRBBYTE
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

            int use = Array.FindIndex(lines, line => line.Contains("jsr PRBBYTE", StringComparison.Ordinal));
            int column = lines[use].IndexOf("PRBBYTE", StringComparison.Ordinal);
            int body = Array.FindIndex(lines, line => line.StartsWith("PRBBYT:", StringComparison.Ordinal));
            LspParams at = Request(uri, use, column + 1);

            List<Diagnostic> published = await client.Wait(
                uri,
                diagnostics => diagnostics.Count == 1 && diagnostics[0].Code == DocumentationRules.HistoricalName);

            Diagnostic hint = published.Should().ContainSingle().Which;
            hint.Message.Should().Be("PRBBYTE is a historical name of Basic::PRBBYT.");
            hint.Range.Start.Should().Be(new Position(use, column));
            JsonNode? actions = new CodeActionHandler(workspace, new BasicDocuments(client)).Handle(new JsonObject
            {
                ["textDocument"] = new JsonObject { ["uri"] = uri.Text },
                ["context"] = new JsonObject { ["diagnostics"] = new JsonArray(hint.ToJson()) }
            });

            JsonNode? fix = (actions as JsonArray)?.FirstOrDefault(
                action => action?["title"]?.GetValue<string>() == "Use Basic::PRBBYT");

            JsonNode? edit = fix?["edit"]?["changes"]?[uri.Text]?[0];
            (edit?["newText"]?.GetValue<string>()).Should().Be("Basic::PRBBYT");

            Hover? hover = await new HoverHandler(workspace, new BasicDocuments(client)).Handle(at);
            (hover?.Contents.Value).Should().Contain("`PRBBYTE` is a historical name of `Basic::PRBBYT`.");

            List<CompletionItem> completions = await new CompletionHandler(workspace, new BasicDocuments(client))
                .Handle(Request(uri, use, column));

            CompletionItem completion = completions.Should().ContainSingle(item => item.Label == "Basic::PRBBYT").Which;
            completion.FilterText.Should().Contain("PRBBYTE");

            LspParams query = Request(uri, 0, 0) with { Query = "PRBBYTE" };
            IEnumerable<WorkspaceSymbol> symbols = await new WorkspaceSymbolHandler(workspace).Handle(query);
            symbols.Select(symbol => symbol.Name).Should().Contain("Basic::PRBBYT (PRBBYTE)");

            IEnumerable<LspLocation> definitions = await new DefinitionHandler(workspace, new BasicDocuments(client)).Handle(at);
            definitions.Should().ContainSingle().Which.Range.Start.Line.Should().Be(body);
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }
}
