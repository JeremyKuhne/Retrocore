// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug.Language;
using Retrocore.Documentation;

namespace Retrocore.Tests;

// The editor's historical-name hint and the names a source declares as scopes.
public sealed partial class LanguageAnalysisTests
{
    // A strict file with a scope named as the SDK names an old Keyboard (KBD), and a use of an old name (CH) that
    // the hint should still report.
    private const string ScopeNameProbe = """
        ; retrocore: style=strict
        ;; A probe.

        .cpu Mos6502
        .org $0300

        ;; A scope of the probe's own.
        .scope KBD

        ;; Reads.
        Read:
            rts

        .endscope

        ; More of it.
        .scope KBD continued

        ;; Reads again.
        Again:
            lda CH
            rts

        .endscope

        ;; Calls it.
        Caller:
            jsr KBD::Read
            rts

        ;; A scope with a CH of its own.
        .scope Local

        ;; Its own.
        CH = 1

        ;; Uses its own CH, then the root's: the old name.
        Use:
            lda CH
            lda ::CH
            rts

        .endscope
        """;

    /// <summary>
    ///  A source's own <c>.scope</c> named as an SDK definition's historical name is the source's definition, so the
    ///  editor does not report its <c>.scope</c> lines, or the scope's name in a qualified name, as uses of the old
    ///  name, while a use of another old name still is, plain or root-qualified (<c>::CH</c>, even in a scope with a
    ///  <c>CH</c> of its own).
    /// </summary>
    /// <returns>The test.</returns>
    [TestMethod]
    public async Task ScopeNamedLikeAHistoricalNameIsNotAUse()
    {
        string folder = Directory.CreateTempSubdirectory("retrocore-scopes").FullName;
        try
        {
            string text = ScopeNameProbe.ReplaceLineEndings("\n");
            string probe = Directory.CreateDirectory(Path.Join(folder, "probe")).FullName;
            string path = Path.GetFullPath(Path.Join(probe, "Probe.asm"));
            File.WriteAllText(path, text);
            RecordingLanguageClient client = new();
            LanguageWorkspace workspace = new(client);
            workspace.Update(path, text);
            DocumentUri uri = DocumentUri.FromFileSystemPath(path);

            List<Diagnostic> published = await client.Wait(
                uri,
                diagnostics => diagnostics.Any(diagnostic => diagnostic.Code == DocumentationRules.HistoricalName));

            // Again's lda CH and Use's lda ::CH, and not Use's lda CH, which is Local's own CH.
            string[] lines = text.Split('\n');
            int again = Array.FindIndex(lines, line => line.Contains("lda CH", StringComparison.Ordinal));
            int root = Array.FindIndex(lines, line => line.Contains("lda ::CH", StringComparison.Ordinal));
            published.Where(diagnostic => diagnostic.Code == DocumentationRules.HistoricalName)
                .Select(diagnostic => (diagnostic.Range.Start.Line, diagnostic.Message))
                .Should().BeEquivalentTo([
                    (again, "CH is a historical name of CursorColumn."),
                    (root, "CH is a historical name of CursorColumn.")]);
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }
}
