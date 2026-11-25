// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Documentation;
using Retrocore.Debug.Language;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the language server's analysis: definitions, comments, names under the cursor and instruction help.
/// </summary>
[TestClass]
public sealed partial class LanguageAnalysisTests
{
    private const string Equates = """
        ; Keyboard data, bit 7 set when a key is waiting.
        KBD = $C000

        ; Prints a value.
        .macro show value
            lda #value
        .endmacro

        """;

    private const string ReferencesSource = """
        .include "equates.asm"
        .org $6000
        ;; Waits for <KBD>, then shows it.
        start:
            lda KBD
        wait:
            bit KBD                 ; KBD in a comment is not a reference
            bpl wait
            show 1
            show 2
            .byte "KBD"
            jmp start

        """;

    /// <summary>
    ///  Comment hovers require an explicit link and resolve its complete target at every character of the link.
    /// </summary>
    /// <returns>The test.</returns>
    [TestMethod]
    public async Task CommentHoversResolveOnlyExplicitLinks()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-hover").FullName;
        try
        {
            string path = Path.Join(directory, "Monitor.asm");
            string text = """
                .org $6000
                ;; A decoy qualifier.
                Monitor = 1
                ;; The intended location.
                LOC1 = $42
                ;; Uses Monitor and LOC1 and carry; <Monitor:LOC1> and <location at Monitor:LOC1>.
                ;; Also uses <Monitor:Missing> and <Missing at LOC1>.
                Start:
                    lda LOC1 ; LOC1 carry <Monitor:LOC1>
                    rts
                """.ReplaceLineEndings("\n");

            File.WriteAllText(path, text);
            RecordingLanguageClient client = new();
            LanguageWorkspace workspace = new(client);
            workspace.Update(path, text);
            (await workspace.AnalysisOfAsync(path, CancellationToken.None)).Should().NotBeNull();
            HoverHandler handler = new(workspace, new BasicDocuments(client));
            DocumentUri uri = DocumentUri.FromFileSystemPath(path);
            string[] lines = text.Split('\n');
            foreach (int line in new[] { 5, 6, 8 })
            {
                int comment = SourceText.CommentStart(lines[line]);
                List<DocumentationLink> links = DocumentationText.Links(lines[line]);
                for (int column = comment; column < lines[line].Length; column++)
                {
                    DocumentationLink? link = links.FirstOrDefault(link => column >= link.Start && column < link.Start + link.Length);
                    Hover? hover = await handler.Handle(Request(uri, line, column));
                    if (link is null || link.Target == "Monitor:Missing")
                    {
                        hover.Should().BeNull($"line {line}, column {column} is not a resolved link");
                        continue;
                    }

                    hover.Should().NotBeNull();
                    (hover?.Contents.Value).Should().Contain("(constant) LOC1 = $42").And.Contain("The intended location.");
                    hover?.Range.Should().Be(new LspRange(line, link.Start, line, link.Start + link.Length));
                }
            }

            (await handler.Handle(Request(uri, 8, lines[8].IndexOf("LOC1", StringComparison.Ordinal))))
                ?.Contents.Value.Should().Contain("(constant) LOC1");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  Links in plain comments use the scopes and using directives at the comment, and can describe directives,
    ///  instructions and documented scopes.
    /// </summary>
    /// <returns>The test.</returns>
    [TestMethod]
    public async Task PlainCommentLinkHoversUseTheirOwnContext()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-hover").FullName;
        try
        {
            string path = Path.Join(directory, "test.asm");
            string text = """
                .cpu Mos6502
                .org $6000
                Value = 1
                ;; The imported scope.
                .scope Imported
                Target = 3
                .endscope
                .scope Inner
                Value = 2
                .using Imported
                    lda #0 ; <Value> <Target> <.repeat> <LDA> <Imported>
                .endscope
                """.ReplaceLineEndings("\n");

            File.WriteAllText(path, text);
            RecordingLanguageClient client = new();
            LanguageWorkspace workspace = new(client);
            workspace.Update(path, text);
            (await workspace.AnalysisOfAsync(path, CancellationToken.None)).Should().NotBeNull();
            HoverHandler handler = new(workspace, new BasicDocuments(client));
            DocumentUri uri = DocumentUri.FromFileSystemPath(path);
            string line = text.Split('\n')[10];
            foreach ((string link, string expected) in new (string, string)[]
                {
                    ("<Value>", "Inner::Value = $02"),
                    ("<Target>", "Imported::Target = $03"),
                    ("<.repeat>", ".repeat"),
                    ("<LDA>", "Loads A from memory"),
                    ("<Imported>", "The imported scope.")
                })
            {
                Hover? hover = await handler.Handle(Request(uri, 10, line.IndexOf(link, StringComparison.Ordinal) + 1));
                hover.Should().NotBeNull(link);
                hover?.Contents.Value.Should().Contain(expected);
            }

            string undocumented = ".org $6000\nValue = 7\n    lda #0 ; <Value>\n";
            workspace.Update(path, undocumented);
            await workspace.IdleAsync(path, CancellationToken.None);
            Hover? plain = await handler.Handle(Request(uri, 2, undocumented.Split('\n')[2].IndexOf("<Value>", StringComparison.Ordinal) + 1));
            plain.Should().NotBeNull();
            plain?.Contents.Value.Should().Contain("Value = $07");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  A link keeps its last successful definition and documentation when a later edit does not assemble.
    /// </summary>
    /// <returns>The test.</returns>
    [TestMethod]
    public async Task CommentLinkHoversSurviveAssemblyErrors()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-hover").FullName;
        try
        {
            string path = Path.Join(directory, "test.asm");
            string text = ".org $6000\n;; A documented value.\nValue = 42\n;; See <Value>.\nStart:\n    rts\n";
            File.WriteAllText(path, text);
            RecordingLanguageClient client = new();
            LanguageWorkspace workspace = new(client);
            workspace.Update(path, text);
            (await workspace.AnalysisOfAsync(path, CancellationToken.None)).Should().NotBeNull();
            HoverHandler handler = new(workspace, new BasicDocuments(client));
            DocumentUri uri = DocumentUri.FromFileSystemPath(path);
            int column = text.Split('\n')[3].IndexOf("<Value>", StringComparison.Ordinal) + 1;
            (await handler.Handle(Request(uri, 3, column)))?.Contents.Value.Should().Contain("A documented value.");

            workspace.Update(path, text + "    not_an_instruction\n");
            await workspace.IdleAsync(path, CancellationToken.None);
            Hover? hover = await handler.Handle(Request(uri, 3, column));
            hover.Should().NotBeNull();
            hover?.Contents.Value.Should().Contain("Value = $2A").And.Contain("A documented value.");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  A documentation link in an include uses the including scope and the exact case of its resolved name.
    /// </summary>
    /// <returns>The test.</returns>
    [TestMethod]
    public async Task DocumentationLinkHoverUsesIncludedScopeAndExactName()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-hover").FullName;
        try
        {
            string path = Path.Join(directory, "root.asm");
            string include = Path.Join(directory, "include.asm");
            string root = """
                .org $6000
                ;; The outer value.
                Value = 1
                .scope Outer
                .include "include.asm"
                .endscope
                """.ReplaceLineEndings("\n");

            string text = """
                ;; Upper case.
                WORD = 3
                ;; Mixed case.
                Word = 4
                ;; The included value.
                Value = 2
                ;; Uses <Value> and <Word>.
                Start:
                    rts
                """.ReplaceLineEndings("\n");

            File.WriteAllText(path, root);
            File.WriteAllText(include, text);
            RecordingLanguageClient client = new();
            LanguageWorkspace workspace = new(client);
            workspace.Update(path, root);
            (await workspace.AnalysisOfAsync(path, CancellationToken.None)).Should().NotBeNull();
            workspace.Update(include, text);
            await workspace.IdleAsync(path, CancellationToken.None);
            HoverHandler handler = new(workspace, new BasicDocuments(client));
            DocumentUri uri = DocumentUri.FromFileSystemPath(include);
            string line = text.Split('\n')[6];
            Hover? value = await handler.Handle(Request(uri, 6, line.IndexOf("<Value>", StringComparison.Ordinal) + 1));
            value.Should().NotBeNull();
            value?.Contents.Value.Should().Contain("Outer::Value = $02").And.Contain("The included value.");
            Hover? word = await handler.Handle(Request(uri, 6, line.IndexOf("<Word>", StringComparison.Ordinal) + 1));
            word.Should().NotBeNull();
            word?.Contents.Value.Should().Contain("Outer::Word = $04").And.Contain("Mixed case.");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  A scope documented in an include shadows a scope of the same name at the root.
    /// </summary>
    /// <returns>The test.</returns>
    [TestMethod]
    public async Task DocumentationLinkHoverFindsIncludedScope()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-hover").FullName;
        try
        {
            string path = Path.Join(directory, "root.asm");
            string include = Path.Join(directory, "include.asm");
            string root = """
                .org $6000
                ;; The root scope.
                .scope Local
                .endscope
                .scope Outer
                .include "include.asm"
                .endscope
                ;; Uses <Outer::Local>.
                RootEntry:
                    rts
                """.ReplaceLineEndings("\n");

            string text = """
                ;; The included scope.
                .scope Local
                    nop
                .endscope
                ;; Uses <Local>.
                Entry:
                    rts
                """.ReplaceLineEndings("\n");

            File.WriteAllText(path, root);
            File.WriteAllText(include, text);
            RecordingLanguageClient client = new();
            LanguageWorkspace workspace = new(client);
            workspace.Update(path, root);
            (await workspace.AnalysisOfAsync(path, CancellationToken.None)).Should().NotBeNull();
            workspace.Update(include, text);
            await workspace.IdleAsync(path, CancellationToken.None);
            HoverHandler handler = new(workspace, new BasicDocuments(client));
            DocumentUri uri = DocumentUri.FromFileSystemPath(include);
            int column = text.Split('\n')[4].IndexOf("<Local>", StringComparison.Ordinal) + 1;
            Hover? hover = await handler.Handle(Request(uri, 4, column));
            hover.Should().NotBeNull();
            hover?.Contents.Value.Should().Contain("The included scope.");
            int rootColumn = root.Split('\n')[7].IndexOf("<Outer::Local>", StringComparison.Ordinal) + 1;
            Hover? qualified = await handler.Handle(Request(DocumentUri.FromFileSystemPath(path), 7, rootColumn));
            qualified.Should().NotBeNull();
            qualified?.Contents.Value.Should().Contain("The included scope.");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  A MACRO-10 link reaches the value stored under its six-character symbol.
    /// </summary>
    /// <returns>The test.</returns>
    [TestMethod]
    public async Task CommentLinkHoverUsesMacro10SignificantCharacters()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-hover").FullName;
        try
        {
            string path = Path.Join(directory, "test.mac");
            string text = """
                ; retrocore: dialect=macro10
                    ORG ^O10000
                $Z:: NOP
                ;; Stored value.
                ZSTORDO=$Z
                ;; Uses <ZSTORDO>.
                SOME:: NOP
                UNDOCUM=2
                ; Uses <UNDOCUM>.
                IFE 1,<
                DEFINE VALUE,<NOP>
                >
                VALUE=3
                ; Uses <VALUE>.
                """.ReplaceLineEndings("\n");

            File.WriteAllText(path, text);
            RecordingLanguageClient client = new();
            LanguageWorkspace workspace = new(client);
            workspace.Update(path, text);
            (await workspace.AnalysisOfAsync(path, CancellationToken.None)).Should().NotBeNull();
            HoverHandler handler = new(workspace, new BasicDocuments(client));
            DocumentUri uri = DocumentUri.FromFileSystemPath(path);
            int column = text.Split('\n')[5].IndexOf("<ZSTORDO>", StringComparison.Ordinal) + 1;
            Hover? hover = await handler.Handle(Request(uri, 5, column));
            hover.Should().NotBeNull();
            hover?.Contents.Value.Should().Contain("ZSTORD = $1000").And.Contain("Stored value.");
            int undocumentedColumn = text.Split('\n')[8].IndexOf("<UNDOCUM>", StringComparison.Ordinal) + 1;
            Hover? undocumented = await handler.Handle(Request(uri, 8, undocumentedColumn));
            undocumented.Should().NotBeNull();
            undocumented?.Contents.Value.Should().Contain("UNDOCU = $02");
            int valueColumn = text.Split('\n')[13].IndexOf("<VALUE>", StringComparison.Ordinal) + 1;
            Hover? value = await handler.Handle(Request(uri, 13, valueColumn));
            value.Should().NotBeNull();
            value?.Contents.Value.Should().Contain("VALUE = $03");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  A MACRO-10 include uses its own dialect for the value in its documentation link.
    /// </summary>
    /// <returns>The test.</returns>
    [TestMethod]
    public async Task CommentLinkHoverUsesIncludedMacro10Dialect()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-hover").FullName;
        try
        {
            string path = Path.Join(directory, "root.asm");
            string include = Path.Join(directory, "include.mac");
            string root = """
                .org $6000
                ;; Mixed case.
                Word = 2
                ;; Upper case.
                WORD = 1
                ;; A native namesake.
                ZSTORDO = 2
                .include "include.mac" dialect=macro10
                    rts
                """.ReplaceLineEndings("\n");

            string text = """
                ;; Stored value.
                ZSTORDO=1
                ;; Uses <ZSTORDO> and <WORD>.
                SOME:: NOP
                """.ReplaceLineEndings("\n");

            File.WriteAllText(path, root);
            File.WriteAllText(include, text);
            RecordingLanguageClient client = new();
            LanguageWorkspace workspace = new(client);
            workspace.Update(path, root);
            (await workspace.AnalysisOfAsync(path, CancellationToken.None)).Should().NotBeNull();
            workspace.Update(include, text);
            await workspace.IdleAsync(path, CancellationToken.None);
            HoverHandler handler = new(workspace, new BasicDocuments(client));
            DocumentUri uri = DocumentUri.FromFileSystemPath(include);
            int column = text.Split('\n')[2].IndexOf("<ZSTORDO>", StringComparison.Ordinal) + 1;
            Hover? hover = await handler.Handle(Request(uri, 2, column));
            hover.Should().NotBeNull();
            hover?.Contents.Value.Should().Contain("ZSTORD = $01").And.Contain("Stored value.");
            int wordColumn = text.Split('\n')[2].IndexOf("<WORD>", StringComparison.Ordinal) + 1;
            Hover? word = await handler.Handle(Request(uri, 2, wordColumn));
            word.Should().NotBeNull();
            word?.Contents.Value.Should().Contain("WORD = $01").And.Contain("Upper case.");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  A MACRO-10 link uses significant characters inside the including scope.
    /// </summary>
    /// <returns>The test.</returns>
    [TestMethod]
    public async Task CommentLinkHoverUsesScopedMacro10Name()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-hover").FullName;
        try
        {
            string path = Path.Join(directory, "root.asm");
            string include = Path.Join(directory, "include.mac");
            string root = ".org $6000\n.scope Outer\n.include \"include.mac\" dialect=macro10\n.endscope\n";
            string text = """
                ;; Stored value.
                ZSTORDO=1
                ;; Uses <ZSTORDO>, <Outer::ZSTORDO>, <Outer::zstordo>, <outer::zstordo> and <::Outer::ZSTORDO>.
                SOME:: NOP
                """.ReplaceLineEndings("\n");

            File.WriteAllText(path, root);
            File.WriteAllText(include, text);
            RecordingLanguageClient client = new();
            LanguageWorkspace workspace = new(client);
            workspace.Update(path, root);
            (await workspace.AnalysisOfAsync(path, CancellationToken.None)).Should().NotBeNull();
            workspace.Update(include, text);
            await workspace.IdleAsync(path, CancellationToken.None);
            HoverHandler handler = new(workspace, new BasicDocuments(client));
            DocumentUri uri = DocumentUri.FromFileSystemPath(include);
            foreach (string link in (string[])["<ZSTORDO>", "<Outer::ZSTORDO>", "<Outer::zstordo>", "<outer::zstordo>", "<::Outer::ZSTORDO>"])
            {
                int column = text.Split('\n')[2].IndexOf(link, StringComparison.Ordinal) + 1;
                Hover? hover = await handler.Handle(Request(uri, 2, column));
                hover.Should().NotBeNull(link);
                hover?.Contents.Value.Should().Contain("Outer::ZSTORD = $01").And.Contain("Stored value.");
            }
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  MACRO-10 special-character names use the same case and significant-character rules in links.
    /// </summary>
    /// <returns>The test.</returns>
    [TestMethod]
    public async Task CommentLinkHoverUsesSpecialMacro10Names()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-hover").FullName;
        try
        {
            string path = Path.Join(directory, "root.asm");
            string include = Path.Join(directory, "include.mac");
            string root = ".org $6000\n.scope Native\n__m10_0 = $42\n.endscope\n"
                + ".scope Outer\n.include \"include.mac\" dialect=macro10\n.endscope\n";

            string text = "LONG$NAME=3\nLONG%NAME=4\nLONG.NAME=5\n.CPU=7\n"
                + "; Uses <LONG$N>, <long$name>, <outer::long$name>, <long%name>, <long.name> and <.cpu>.\n";

            File.WriteAllText(path, root);
            File.WriteAllText(include, text);
            RecordingLanguageClient client = new();
            LanguageWorkspace workspace = new(client);
            workspace.Update(path, root);
            SourceAnalysis analysis = await workspace.AnalysisOfAsync(path, CancellationToken.None)
                ?? throw new InvalidOperationException("The assembly was not analyzed.");

            analysis.Definitions.Should().Contain(site => site.Name == "Native::__m10_0" && site.Value == 0x42);
            workspace.Update(include, text);
            await workspace.IdleAsync(path, CancellationToken.None);
            HoverHandler handler = new(workspace, new BasicDocuments(client));
            DocumentUri uri = DocumentUri.FromFileSystemPath(include);
            foreach ((string link, string value) in ((string, string)[])
                [("<LONG$N>", "$03"), ("<long$name>", "$03"), ("<outer::long$name>", "$03"), ("<long%name>", "$04"), ("<long.name>", "$05")])
            {
                int column = text.Split('\n')[4].IndexOf(link, StringComparison.Ordinal) + 1;
                Hover? hover = await handler.Handle(Request(uri, 4, column));
                hover.Should().NotBeNull(link);
                hover?.Contents.Value.Should().Contain(value);
            }

            int directiveColumn = text.Split('\n')[4].IndexOf("<.cpu>", StringComparison.Ordinal) + 1;
            Hover? directive = await handler.Handle(Request(uri, 4, directiveColumn));
            directive.Should().NotBeNull();
            directive?.Contents.Value.Should().Contain("Selects the CPU");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  A quoted semicolon does not turn a later code reference into a comment.
    /// </summary>
    /// <returns>The test.</returns>
    [TestMethod]
    public async Task CodeHoverIgnoresSemicolonsInsideStrings()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-hover").FullName;
        try
        {
            string path = Path.Join(directory, "test.asm");
            string text = ".org $6000\nTarget = 42\n.byte \"DON'T; \", Target\n";
            File.WriteAllText(path, text);
            RecordingLanguageClient client = new();
            LanguageWorkspace workspace = new(client);
            workspace.Update(path, text);
            (await workspace.AnalysisOfAsync(path, CancellationToken.None)).Should().NotBeNull();
            HoverHandler handler = new(workspace, new BasicDocuments(client));
            int column = text.Split('\n')[2].IndexOf("Target", StringComparison.Ordinal);
            Hover? hover = await handler.Handle(Request(DocumentUri.FromFileSystemPath(path), 2, column));
            hover.Should().NotBeNull();
            hover?.Contents.Value.Should().Contain("Target");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  The first declared CPU also applies to statements preceding its directive.
    /// </summary>
    /// <returns>The test.</returns>
    [TestMethod]
    public async Task CommentLinkHoverUsesFirstDeclaredCpuBeforeDirective()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-hover").FullName;
        try
        {
            string path = Path.Join(directory, "root.asm");
            string include = Path.Join(directory, "include.asm");
            string root = ".org $6000\n.include \"include.asm\"\n.cpu Z80\n";
            string text = ";; Uses <LDIR>.\nnop\n";
            File.WriteAllText(path, root);
            File.WriteAllText(include, text);
            RecordingLanguageClient client = new();
            LanguageWorkspace workspace = new(client);
            workspace.Update(path, root);
            SourceAnalysis analysis = await workspace.AnalysisOfAsync(path, CancellationToken.None)
                ?? throw new InvalidOperationException("The assembly was not analyzed.");

            analysis.Result.Success.Should().BeTrue();
            var emitted = analysis.Result.SourceMap.Single(entry => entry.Location?.Path == include && entry.Size > 0);
            emitted.InstructionSet?.Name.Should().Be("Z80");

            workspace.Update(include, text);
            await workspace.IdleAsync(path, CancellationToken.None);
            HoverHandler handler = new(workspace, new BasicDocuments(client));
            Hover? hover = await handler.Handle(Request(DocumentUri.FromFileSystemPath(include), 0, ";; Uses <".Length));
            hover.Should().NotBeNull();
            hover?.Contents.Value.Should().Contain("Repeats LDI until BC is zero.");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  A CPU switch in an include applies after the including line's comment.
    /// </summary>
    /// <returns>The test.</returns>
    [TestMethod]
    public async Task CommentLinkHoverUsesCpuBeforeIncludeSwitch()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-hover").FullName;
        try
        {
            string path = Path.Join(directory, "root.asm");
            string include = Path.Join(directory, "include.asm");
            string root = ".cpu Z80\n.org $6000\n.include \"include.asm\" ; Uses <LDIR>.\n;; After <LDIR>.\nnop\n";
            File.WriteAllText(path, root);
            File.WriteAllText(include, ".cpu Mos6502\nrts\n");
            RecordingLanguageClient client = new();
            LanguageWorkspace workspace = new(client);
            workspace.Update(path, root);
            (await workspace.AnalysisOfAsync(path, CancellationToken.None)).Should().NotBeNull();
            HoverHandler handler = new(workspace, new BasicDocuments(client));
            int column = root.Split('\n')[2].IndexOf("<LDIR>", StringComparison.Ordinal) + 1;
            Hover? hover = await handler.Handle(Request(DocumentUri.FromFileSystemPath(path), 2, column));
            hover.Should().NotBeNull();
            hover?.Contents.Value.Should().Contain("Repeats LDI until BC is zero.");
            int afterColumn = root.Split('\n')[3].IndexOf("<LDIR>", StringComparison.Ordinal) + 1;
            Hover? after = await handler.Handle(Request(DocumentUri.FromFileSystemPath(path), 3, afterColumn));
            after.Should().BeNull();
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  A comment at the top of an include sees the CPU inherited from its include site.
    /// </summary>
    /// <returns>The test.</returns>
    [TestMethod]
    public async Task CommentLinkHoverUsesCpuInheritedByInclude()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-hover").FullName;
        try
        {
            string path = Path.Join(directory, "root.asm");
            string include = Path.Join(directory, "include.asm");
            string root = ".cpu Z80\n.org $6000\n.include \"include.asm\"\n";
            string text = ";; Uses <LDIR>.\n.cpu Mos6502\nStart:\n    rts\n";
            File.WriteAllText(path, root);
            File.WriteAllText(include, text);
            RecordingLanguageClient client = new();
            LanguageWorkspace workspace = new(client);
            workspace.Update(path, root);
            (await workspace.AnalysisOfAsync(path, CancellationToken.None)).Should().NotBeNull();
            workspace.Update(include, text);
            await workspace.IdleAsync(path, CancellationToken.None);
            HoverHandler handler = new(workspace, new BasicDocuments(client));
            int column = text.IndexOf("<LDIR>", StringComparison.Ordinal) + 1;
            Hover? hover = await handler.Handle(Request(DocumentUri.FromFileSystemPath(include), 0, column));
            hover.Should().NotBeNull();
            hover?.Contents.Value.Should().Contain("Repeats LDI until BC is zero.");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  An include also inherits its CPU when its first statement is in a nested include.
    /// </summary>
    /// <returns>The test.</returns>
    [TestMethod]
    public async Task CommentLinkHoverUsesCpuInheritedByNestedInclude()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-hover").FullName;
        try
        {
            string path = Path.Join(directory, "root.asm");
            string include = Path.Join(directory, "include.asm");
            string nested = Path.Join(directory, "nested.asm");
            string root = ".cpu Z80\n.org $6000\n.include \"include.asm\"\n";
            string text = ";; Uses <LDIR>.\n.include \"nested.asm\" ; During <LDIR>.\n;; After <LDIR>.\n";
            File.WriteAllText(path, root);
            File.WriteAllText(include, text);
            File.WriteAllText(nested, ".cpu Mos6502\nStart:\n    rts\n");
            RecordingLanguageClient client = new();
            LanguageWorkspace workspace = new(client);
            workspace.Update(path, root);
            (await workspace.AnalysisOfAsync(path, CancellationToken.None)).Should().NotBeNull();
            workspace.Update(include, text);
            await workspace.IdleAsync(path, CancellationToken.None);
            HoverHandler handler = new(workspace, new BasicDocuments(client));
            int column = text.IndexOf("<LDIR>", StringComparison.Ordinal) + 1;
            Hover? hover = await handler.Handle(Request(DocumentUri.FromFileSystemPath(include), 0, column));
            hover.Should().NotBeNull();
            hover?.Contents.Value.Should().Contain("Repeats LDI until BC is zero.");
            string[] lines = text.Split('\n');
            Hover? during = await handler.Handle(Request(DocumentUri.FromFileSystemPath(include), 1,
                lines[1].IndexOf("<LDIR>", StringComparison.Ordinal) + 1));

            during.Should().NotBeNull();
            Hover? after = await handler.Handle(Request(DocumentUri.FromFileSystemPath(include), 2,
                lines[2].IndexOf("<LDIR>", StringComparison.Ordinal) + 1));

            after.Should().BeNull();
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  A comment-only include still inherits the CPU at its include site.
    /// </summary>
    /// <returns>The test.</returns>
    [TestMethod]
    public async Task CommentLinkHoverUsesCpuInheritedByCommentOnlyInclude()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-hover").FullName;
        try
        {
            string path = Path.Join(directory, "root.asm");
            string include = Path.Join(directory, "include.asm");
            string root = ".cpu Z80\n.include \"include.asm\"\n.cpu Mos6502\n.org $6000\n.byte 0\n";
            string text = ";; Uses <LDIR>.\n";
            File.WriteAllText(path, root);
            File.WriteAllText(include, text);
            RecordingLanguageClient client = new();
            LanguageWorkspace workspace = new(client);
            workspace.Update(path, root);
            (await workspace.AnalysisOfAsync(path, CancellationToken.None)).Should().NotBeNull();
            workspace.Update(include, text);
            await workspace.IdleAsync(path, CancellationToken.None);
            HoverHandler handler = new(workspace, new BasicDocuments(client));
            Hover? hover = await handler.Handle(Request(DocumentUri.FromFileSystemPath(include), 0, ";; Uses <".Length));
            hover.Should().NotBeNull();
            hover?.Contents.Value.Should().Contain("Repeats LDI until BC is zero.");
            workspace.Update(path, ".cpu Z80\n.include \"include.asm\"\n.cpu Mos6502\n.include \"include.asm\"\n.org $6000\n.byte 0\n");
            await workspace.IdleAsync(path, CancellationToken.None);
            hover = await handler.Handle(Request(DocumentUri.FromFileSystemPath(include), 0, ";; Uses <".Length));
            hover.Should().BeNull();
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  A leading instruction link is ambiguous when an include starts under different CPUs.
    /// </summary>
    /// <returns>The test.</returns>
    [TestMethod]
    public async Task CommentLinkHoverDoesNotChooseBetweenIncludeCpus()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-hover").FullName;
        try
        {
            string path = Path.Join(directory, "root.asm");
            string include = Path.Join(directory, "include.asm");
            string root = ".cpu Z80\n.org $6000\n.include \"include.asm\"\n.cpu Mos6502\n.include \"include.asm\"\n";
            string text = ";; Before <LDIR>.\n.byte 0\n.cpu Z80\n;; After <LDIR>.\n.byte 0\n";
            File.WriteAllText(path, root);
            File.WriteAllText(include, text);
            RecordingLanguageClient client = new();
            LanguageWorkspace workspace = new(client);
            workspace.Update(path, root);
            (await workspace.AnalysisOfAsync(path, CancellationToken.None)).Should().NotBeNull();
            workspace.Update(include, text);
            await workspace.IdleAsync(path, CancellationToken.None);
            HoverHandler handler = new(workspace, new BasicDocuments(client));
            DocumentUri uri = DocumentUri.FromFileSystemPath(include);
            Hover? before = await handler.Handle(Request(uri, 0, ";; Before <".Length));
            Hover? after = await handler.Handle(Request(uri, 3, ";; After <".Length));
            before.Should().BeNull();
            after.Should().NotBeNull();
            after?.Contents.Value.Should().Contain("Repeats LDI until BC is zero.");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  Instruction links use the assembled CPU, and document links point to a file URI with its anchor.
    /// </summary>
    /// <returns>The test.</returns>
    [TestMethod]
    public async Task CommentLinksUseTheAssembledCpuAndDocumentUri()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore hover").FullName;
        try
        {
            string path = Path.Join(directory, "test.asm");
            string guide = Path.Join(directory, "guide.md");
            string text = """
                .cpu Mos6502
                .org $6000
                    nop
                .cpu Z80
                .if 0
                .cpu Mos6502
                .endif
                ;; Uses <LDIR> and <guide at doc:guide.md#topic>.
                Start:
                    ldir
                """.ReplaceLineEndings("\n");

            File.WriteAllText(path, text);
            File.WriteAllText(guide, "# Topic\n");
            RecordingLanguageClient client = new();
            LanguageWorkspace workspace = new(client);
            workspace.Update(path, text);
            (await workspace.AnalysisOfAsync(path, CancellationToken.None)).Should().NotBeNull();
            HoverHandler handler = new(workspace, new BasicDocuments(client));
            DocumentUri uri = DocumentUri.FromFileSystemPath(path);
            string line = text.Split('\n')[7];
            Hover? instruction = await handler.Handle(Request(uri, 7, line.IndexOf("<LDIR>", StringComparison.Ordinal) + 1));
            instruction.Should().NotBeNull();
            instruction?.Contents.Value.Should().Contain("Repeats LDI until BC is zero.");
            Hover? document = await handler.Handle(Request(uri, 7, line.IndexOf("<guide", StringComparison.Ordinal) + 1));
            document.Should().NotBeNull();
            document?.Contents.Value.Should().Contain($"{new Uri(guide).AbsoluteUri}#topic");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  Definitions come from the assembly, across includes, with the comment above them; open text overrides disk.
    /// </summary>
    [TestMethod]
    public void DefinitionsSpanIncludes()
    {
        string directory = Directory.CreateTempSubdirectory().FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            string equates = Path.Join(directory, "equates.asm");
            File.WriteAllText(equates, "KBD = $1234\n");
            File.WriteAllText(main, "");
            Dictionary<string, string> open = new(StringComparer.OrdinalIgnoreCase)
            {
                [main] = ".include \"equates.asm\"\n.org $6000\nstart:\n    lda KBD\n    show 1\n",
                [equates] = Equates
            };

            SourceAnalysis analysis = SourceAnalysis.Assemble(main, path => open.GetValueOrDefault(path));

            analysis.Result.Diagnostics.Should().BeEmpty();
            analysis.Members.Should().Contain(equates);
            SymbolSite kbd = analysis.Find("KBD").Single();
            kbd.Path.Should().Be(equates);
            kbd.Line.Should().Be(1);
            kbd.Value.Should().Be(0xC000, "the open document, not disk, is assembled");
            kbd.Kind.Should().Be(SymbolSiteKind.Constant);
            SourceText.CommentFor(analysis.LinesOf(equates), kbd.Line).Should().Equal("Keyboard data, bit 7 set when a key is waiting.");
            analysis.Find("show").Single().Kind.Should().Be(SymbolSiteKind.Macro);
            analysis.Find("start").Single().Value.Should().Be(0x6000);

            // The macro invocation's line produced the macro's bytes.
            analysis.Emitted(main, 4).Should().ContainSingle().Which.Address.Should().Be(0x6003);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  ROM analysis uses its declared image bounds while retaining original source lines.
    /// </summary>
    /// <param name="lineEnding">The physical line terminator.</param>
    [TestMethod]
    [DataRow("\n")]
    [DataRow("\r\n")]
    [DataRow("\r")]
    public void RomMetadataSetsImageBounds(string lineEnding)
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-rom-analysis").FullName;
        try
        {
            string main = Path.Join(directory, "firmware.rom.asm");
            File.WriteAllText(main, "");
            string valid = """
                .ROM Test.Firmware, ($C3C5 + ';'), ($80 * 2) ; image bounds
                .cpu Mos6502
                .assert * == $C400
                Start: .byte 1
                .res $FE
                .assert * == $C4FF
                .byte 2
                """.ReplaceLineEndings(lineEnding);

            SourceAnalysis analysis = SourceAnalysis.Assemble(main, path => path == main ? valid : null);

            analysis.Result.Success.Should().BeTrue(because: string.Join(Environment.NewLine, analysis.Result.Diagnostics));
            analysis.Find("Start").Single().Value.Should().Be(0xC400);
            analysis.Find("Start").Single().Line.Should().Be(3);

            string oversized = """
                .rom Test.Firmware, ($C000 + $400), ($80 * 2)
                .cpu Mos6502
                .res $100
                .byte 1
                """.ReplaceLineEndings(lineEnding);

            SourceAnalysis oversizedAnalysis = SourceAnalysis.Assemble(main, path => path == main ? oversized : null);
            oversizedAnalysis.Result.Success.Should().BeFalse("the declared image ends at $C500");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  The shipped card firmware assembles at its declared addresses in the editor.
    /// </summary>
    /// <param name="file">The ROM source.</param>
    /// <param name="symbol">An entry with a known address.</param>
    /// <param name="address">The entry's expected address.</param>
    [TestMethod]
    [DataRow("Mouse.rom.asm", "BasicInput", 0xC405)]
    [DataRow("Disk35.rom.asm", "ProDosEntry", 0xC51C)]
    [DataRow("ProFile.rom.asm", "Boot", 0xC500)]
    [DataRow("Slot7.rom.asm", "Boot", 0xC700)]
    public void CardRomMetadataSetsEditorAddresses(string file, string symbol, int address)
    {
        string path = Path.GetFullPath(Path.Join(AppContext.BaseDirectory, "Inputs", file));
        File.Exists(path).Should().BeTrue("the test must use the shipped ROM source");

        SourceAnalysis analysis = SourceAnalysis.Assemble(path, _ => null);

        analysis.Result.Diagnostics.Select(diagnostic => diagnostic.Message).Should().BeEmpty();
        analysis.Find(symbol).Single().Value.Should().Be(address);
    }

    /// <summary>
    ///  ROM origins work at zero, outside the Apple II slot pages, and at the end of the address space.
    /// </summary>
    /// <param name="origin">The declared origin.</param>
    /// <param name="size">The declared size.</param>
    /// <param name="address">The expected entry address.</param>
    [TestMethod]
    [DataRow("$0000", "$10000", 0x0000)]
    [DataRow("$0700", "$180", 0x0700)]
    [DataRow("$FFFE", "2", 0xFFFE)]
    public void RomMetadataSupportsAddressSpaceBoundaries(string origin, string size, int address)
    {
        string path = Path.GetFullPath("boundary.rom.asm");
        string text = $".rom Test.Firmware, {origin}, {size}\n.cpu Mos6502\nEntry: nop\n.assert * == {origin} + 1\n";

        SourceAnalysis analysis = SourceAnalysis.Assemble(path, candidate => candidate == path ? text : null);

        analysis.Result.Diagnostics.Select(diagnostic => diagnostic.Message).Should().BeEmpty();
        analysis.Find("Entry").Single().Value.Should().Be(address);
    }

    /// <summary>
    ///  Invalid metadata is reported on its own line rather than silently assembling at zero.
    /// </summary>
    /// <param name="declaration">The bad metadata.</param>
    /// <param name="message">The expected diagnostic.</param>
    /// <param name="line">The zero-based diagnostic line.</param>
    [TestMethod]
    [DataRow(".rom Test.Firmware, $10000, 1", "fit the 16-bit address space", 1)]
    [DataRow(".rom Test.Firmware, Missing, $100", "Unresolved expression", 1)]
    [DataRow(".rom Test.Firmware, $C400, 0", "fit the 16-bit address space", 1)]
    [DataRow(".rom Test.Firmware, $C400,", "Empty or unbalanced", 1)]
    [DataRow(".rom Test.Firmware, $C400, $100\n.rom Test.Other, $C500, $100", "Expected one", 2)]
    public void RomMetadataErrorsAreReported(string declaration, string message, int line)
    {
        string path = Path.GetFullPath("invalid.rom.asm");
        string text = $"; before\n{declaration}\n.cpu Mos6502\nnop\n";

        SourceAnalysis analysis = SourceAnalysis.Assemble(path, candidate => candidate == path ? text : null);

        AssemblyDiagnostic diagnostic = analysis.Result.Diagnostics.Should().ContainSingle().Which;
        diagnostic.Message.Should().Contain(message);
        AssemblyLocation location = diagnostic.Location ?? throw new AssertFailedException("The metadata diagnostic needs a location.");
        location.Path.Should().Be(path);
        location.Line.Should().Be(line);
    }

    /// <summary>
    ///  A ca65 ROM uses its bounded image unless a companion linker configuration supplies one.
    /// </summary>
    /// <param name="withConfiguration">Whether the root has a companion configuration.</param>
    /// <param name="address">The address the editor must use.</param>
    [TestMethod]
    [DataRow(false, 0xC400)]
    [DataRow(true, 0x8000)]
    public void Ca65RomUsesImageOrCompanionConfiguration(bool withConfiguration, int address)
    {
        string path = Path.GetFullPath("configured.rom.asm");
        string configuration = Path.ChangeExtension(path, ".cfg");
        string text = """
            ; retrocore: dialect=ca65
            .rom Test.Firmware, $C400, $100
            .cpu Mos6502
            Entry: nop
            """;

        string config = """
            MEMORY { ROM: start=$8000, size=$100, file=%O; }
            SEGMENTS { CODE: load=ROM, type=ro; }
            """;

        SourceAnalysis analysis = SourceAnalysis.Assemble(
            path,
            candidate => candidate == path ? text : withConfiguration && candidate == configuration ? config : null);

        analysis.Result.Diagnostics.Select(diagnostic => diagnostic.Message).Should().BeEmpty();
        analysis.Find("Entry").Single().Value.Should().Be(address);
    }

    /// <summary>
    ///  Metadata errors reach the client and disappear when the open document is corrected.
    /// </summary>
    /// <returns>The test.</returns>
    [TestMethod]
    public async Task RomMetadataDiagnosticsArePublishedAndCleared()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-rom-diagnostics").FullName;
        try
        {
            string path = Path.Join(directory, "firmware.rom.asm");
            string invalid = "; header\n.rom Test.Firmware, $10000, 1\n.cpu Mos6502\nnop\n";
            string valid = "; header\n.rom Test.Firmware, $C400, $100\n.cpu Mos6502\n.assert * == $C400\nnop\n";
            RecordingLanguageClient client = new();
            LanguageWorkspace workspace = new(client);
            DocumentUri uri = DocumentUri.FromFileSystemPath(path);

            workspace.Update(path, invalid);
            await workspace.IdleAsync(path, CancellationToken.None);
            List<Diagnostic> errors = await client.Wait(uri, _ => true);
            Diagnostic error = errors.Should().ContainSingle(diagnostic => diagnostic.Code == "RETROCOREASM001").Which;
            error.Message.Should().Contain("fit the 16-bit address space");
            error.Range.Start.Line.Should().Be(1);

            workspace.Update(path, valid);
            await workspace.IdleAsync(path, CancellationToken.None);
            List<Diagnostic> corrected = await client.Wait(uri, _ => true);
            corrected.Should().NotContain(diagnostic => diagnostic.Code == "RETROCOREASM001");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  A source that does not assemble still has its definitions, found in its text.
    /// </summary>
    [TestMethod]
    public void DefinitionsSurviveErrors()
    {
        string directory = Directory.CreateTempSubdirectory().FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            File.WriteAllText(main, ".org $6000\nstart:\n    jmp missing\nVALUE = 3\n");

            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);

            analysis.Result.Success.Should().BeFalse();
            analysis.Find("start").Single().Line.Should().Be(1);
            analysis.Find("VALUE").Single().Kind.Should().Be(SymbolSiteKind.Constant);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  A constant defined with <c>:=</c>, spaced or not, is a constant in the text of a source that does not
    ///  assemble, as one defined with <c>=</c> is, not a label.
    /// </summary>
    /// <param name="definition">The constant's definition.</param>
    [TestMethod]
    [DataRow("VALUE := 3")]
    [DataRow("VALUE:=3")]
    public void ColonEqualsConstantsSurviveErrors(string definition)
    {
        string directory = Directory.CreateTempSubdirectory().FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            File.WriteAllText(main, $".org $6000\nstart:\n    jmp missing\n{definition}\n");

            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);

            analysis.Result.Success.Should().BeFalse();
            analysis.Find("VALUE").Single().Kind.Should().Be(SymbolSiteKind.Constant);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  A constant or variable defined with a colon and <c>.equ</c> or <c>.set</c> is a constant in the text of a
    ///  source that does not assemble, as one defined with <c>=</c> is, not a label.
    /// </summary>
    /// <param name="definition">The definition.</param>
    [TestMethod]
    [DataRow("VALUE: .equ 3")]
    [DataRow("VALUE:\t.equ 3")]
    [DataRow("VALUE:.equ 3")]
    [DataRow("VALUE: .set 3")]
    [DataRow("VALUE: .EQU 3")]
    [DataRow("VALUE: .Set 3")]
    [DataRow("VALUE .SET 3")]
    [DataRow("VALUE: .equ 3 ; three")]
    [DataRow("VALUE: .equ")]
    [DataRow("VALUE: .equ\u00A03")]
    public void ColonDirectiveConstantsSurviveErrors(string definition)
    {
        string directory = Directory.CreateTempSubdirectory().FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            File.WriteAllText(main, $".org $6000\nstart:\n    jmp missing\n{definition}\n");

            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);

            analysis.Result.Success.Should().BeFalse();
            analysis.Find("VALUE").Single().Kind.Should().Be(SymbolSiteKind.Constant);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  A label with a colon is still a label in the text of a source that does not assemble, whatever follows it,
    ///  as is a name defined with Merlin's <c>EQU</c> still a constant.
    /// </summary>
    /// <param name="definition">The definition.</param>
    /// <param name="constant">Whether it defines a constant rather than a label.</param>
    [TestMethod]
    [DataRow("VALUE:", false)]
    [DataRow("VALUE: nop", false)]
    [DataRow("VALUE::", false)]
    [DataRow("VALUE: .byte 3", false)]
    [DataRow("VALUE: .equal", false)]
    [DataRow("VALUE: .equ$8D", false)]
    [DataRow("VALUE EQU 3", true)]
    [DataRow("VALUE::1,,2", false)]
    [DataRow("VALUE::0;comment", false)]
    public void ColonLabelsSurviveErrors(string definition, bool constant)
    {
        string directory = Directory.CreateTempSubdirectory().FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            File.WriteAllText(main, $".org $6000\nstart:\n    jmp missing\n{definition}\n");

            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);

            analysis.Result.Success.Should().BeFalse();
            SymbolSiteKind kind = constant ? SymbolSiteKind.Constant : SymbolSiteKind.Label;
            analysis.Find("VALUE").Single().Kind.Should().Be(kind);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  A name defined with Merlin's <c>EQU</c> is a constant in the text of a source that does not assemble in any
    ///  case, as Merlin reads it, while a name followed by a field that only starts with <c>equ</c> stays a label. The
    ///  text is searched whatever the source's dialect, so a native source shows it as well as a Merlin one.
    /// </summary>
    /// <param name="definition">The definition.</param>
    /// <param name="constant">Whether it defines a constant rather than a label.</param>
    [TestMethod]
    [DataRow("VALUE equ 3", true)]
    [DataRow("VALUE Equ 3", true)]
    [DataRow("VALUE\teQu\t3", true)]
    [DataRow("VALUE equal 3", false)]
    [DataRow("VALUE equ_3", false)]
    [DataRow("VALUE equ$10", false)]
    [DataRow("VALUE EQU*", false)]
    [DataRow("VALUE equ;comment", false)]
    [DataRow("VALUE equ ;no operand", true)]
    [DataRow("VALUE equ", true)]
    public void MerlinEquatesSurviveErrorsInAnyCase(string definition, bool constant)
    {
        string directory = Directory.CreateTempSubdirectory().FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            File.WriteAllText(main, $".org $6000\nstart:\n    jmp missing\n{definition}\n");

            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);

            analysis.Result.Success.Should().BeFalse();
            SymbolSiteKind kind = constant ? SymbolSiteKind.Constant : SymbolSiteKind.Label;
            analysis.Find("VALUE").Single().Kind.Should().Be(kind);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  A name ending in <c>equ</c> is not cut short to make an equate of its start, in any case.
    /// </summary>
    /// <param name="line">A line beginning with such a name.</param>
    /// <param name="prefix">The start of the name, which must not be defined.</param>
    [TestMethod]
    [DataRow("Subsequ;comment", "Subs")]
    [DataRow("SUBSEQU;comment", "SUBS")]
    [DataRow("Lequ.b 3", "L")]
    public void NamesEndingInEquAreNotCutShort(string line, string prefix)
    {
        string directory = Directory.CreateTempSubdirectory().FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            File.WriteAllText(main, $".org $6000\nstart:\n    jmp missing\n{line}\n");

            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);

            analysis.Result.Success.Should().BeFalse();
            analysis.Find(prefix).Should().BeEmpty();
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  A procedure remains navigable when its assembly has errors.
    /// </summary>
    /// <param name="error">A line that makes assembly fail.</param>
    [TestMethod]
    [DataRow("jsr missing")]
    [DataRow(".notadirective")]
    public void ProceduresSurviveErrors(string error)
    {
        string directory = Directory.CreateTempSubdirectory().FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            File.WriteAllText(main, $".org $6000\n    {error}\n    .proc InverseCapitalsOn\n    rts\n    .endproc\n");

            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);

            analysis.Result.Success.Should().BeFalse();
            SymbolSite procedure = analysis.Find("InverseCapitalsOn").Should().ContainSingle().Which;
            procedure.Path.Should().Be(main);
            procedure.Line.Should().Be(2);
            procedure.Column.Should().Be(10);
            procedure.Kind.Should().Be(SymbolSiteKind.Label);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  Both names on a ca65 label-and-procedure line remain navigable, even on assembly errors.
    /// </summary>
    /// <param name="error">Whether assembly should fail.</param>
    [TestMethod]
    [DataRow(data: false)]
    [DataRow(data: true)]
    public void ProcedureWithPrecedingLabel(bool error)
    {
        string directory = Directory.CreateTempSubdirectory().FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            string failure = error ? "    jmp missing\n" : "";
            File.WriteAllText(main, $"; retrocore: dialect=ca65\n.org $6000\nAlias: .proc Worker\n    rts\n.endproc\n{failure}");

            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);

            analysis.Result.Success.Should().Be(!error);
            analysis.Find("Alias").Should().ContainSingle().Which.Column.Should().Be(0);
            SymbolSite worker = analysis.Find("Worker").Should().ContainSingle().Which;
            worker.Line.Should().Be(2);
            worker.Column.Should().Be(13);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  A successfully assembled scoped procedure points to its unqualified name.
    /// </summary>
    /// <param name="precedingLabel">Whether a label precedes the procedure on the same line.</param>
    [TestMethod]
    [DataRow(data: false)]
    [DataRow(data: true)]
    public void ScopedProcedureDefinitionRange(bool precedingLabel)
    {
        string directory = Directory.CreateTempSubdirectory().FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            string label = precedingLabel ? "Alias: " : "";
            File.WriteAllText(main, $"; retrocore: dialect=ca65\n.org $6000\n.scope Outer\n{label}.proc Inner\n    rts\n.endproc\n.endscope\n    jsr Outer::Inner\n");

            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);

            analysis.Result.Success.Should().BeTrue();
            SymbolSite procedure = analysis.Find("Outer::Inner").Should().ContainSingle().Which;
            procedure.Line.Should().Be(3);
            procedure.Column.Should().Be(precedingLabel ? 13 : 6);
            procedure.SourceLength.Should().Be("Inner".Length);
            if (precedingLabel)
            {
                SymbolSite alias = analysis.Find("Outer::Alias").Should().ContainSingle().Which;
                alias.Column.Should().Be(0);
                alias.SourceLength.Should().BeNull();
            }
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  Failed assemblies index active procedure statements with their enclosing scopes, not inactive or macro bodies.
    /// </summary>
    [TestMethod]
    public void ProcedureFallbackFollowsPreprocessingAndScopes()
    {
        string directory = Directory.CreateTempSubdirectory().FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            File.WriteAllText(main, """
                .org $6000
                .proc Outer
                .proc Inner
                    rts
                .endproc
                .endproc
                .if 0
                .proc Hidden
                .endproc
                .endif
                .macro Invoke
                .proc Ghost
                .endproc
                .endmacro
                    Invoke
                    jmp missing
                """);

            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);

            analysis.Result.Success.Should().BeFalse();
            analysis.Find("Outer::Inner").Should().ContainSingle().Which.SourceLength.Should().Be("Inner".Length);
            analysis.Find("Hidden").Should().BeEmpty();
            analysis.Find("Ghost").Should().BeEmpty();
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  An address-size annotation does not hide a procedure when assembly fails.
    /// </summary>
    /// <param name="size">The procedure's address-size annotation.</param>
    [TestMethod]
    [DataRow("far")]
    [DataRow("near")]
    public void ProcedureFallbackRecognizesAddressSize(string size)
    {
        string directory = Directory.CreateTempSubdirectory().FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            File.WriteAllText(main, $"; retrocore: dialect=ca65\n.proc Worker: {size}\n    rts\n.endproc\n    jmp missing\n");

            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);

            analysis.Result.Success.Should().BeFalse();
            analysis.Find("Worker").Should().ContainSingle().Which.Column.Should().Be(6);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  A root's companion linker configuration supplies its sections and their addresses.
    /// </summary>
    [TestMethod]
    public void CompanionConfigurationPlacesSections()
    {
        string directory = Directory.CreateTempSubdirectory().FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            string configuration = Path.Join(directory, "main.cfg");
            string bios = Path.Join(directory, "bios.asm");
            File.WriteAllText(main, ".section HIGH\n.include \"bios.asm\"\n    jsr InverseCapitalsOn\n");
            File.WriteAllText(bios, ".proc InverseCapitalsOn\n    rts\n.endproc\n");
            File.WriteAllText(
                configuration,
                "MEMORY { HIGH: start = $FE00, size = $0200, file = %O; }\nSEGMENTS { HIGH: load = HIGH, type = ro; }\n");

            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);

            analysis.Result.Diagnostics.Should().BeEmpty();
            SymbolSite procedure = analysis.Find("InverseCapitalsOn").Should().ContainSingle().Which;
            procedure.Path.Should().Be(bios);
            procedure.Column.Should().Be(6);
            procedure.Value.Should().Be(0xFE00);

            File.WriteAllText(configuration, "MEMORY {");
            SourceAnalysis.Assemble(main, _ => null).Result.Diagnostics.Should().NotBeEmpty(
                "an invalid companion configuration must not be ignored");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  Six-character matching is for MACRO-10, not a native symbol that happens to share a prefix.
    /// </summary>
    [TestMethod]
    public void SixCharacterNamesFollowTheSourceDialect()
    {
        string directory = Directory.CreateTempSubdirectory().FullName;
        try
        {
            string native = Path.Join(directory, "native.asm");
            string macro10 = Path.Join(directory, "macro10.mac");
            File.WriteAllText(native, ".org $6000\nINVERS:\n    rts\n    jmp InverseCapitalsOn\n");
            File.WriteAllText(macro10, "; retrocore: dialect=macro10\n\tORG\t^O10000\nINVERS:\tNOP\n");

            SourceAnalysis nativeAnalysis = SourceAnalysis.Assemble(native, _ => null);
            SourceAnalysis macroAnalysis = SourceAnalysis.Assemble(macro10, _ => null);

            nativeAnalysis.Find("InverseCapitalsOn").Should().BeEmpty();
            macroAnalysis.Find("INVERSE").Should().ContainSingle().Which.Name.Should().Be("INVERS");
            macroAnalysis.Find("InverseCapitalsOn", macro10: false).Should().BeEmpty();
            macroAnalysis.Find("InverseCapitalsOn", macro10: true).Should().ContainSingle().Which.Name.Should().Be("INVERS");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  An included source's explicit dialect, rather than its root's, controls its name matching.
    /// </summary>
    [TestMethod]
    public void IncludedSourceUsesItsOwnDialect()
    {
        string directory = Directory.CreateTempSubdirectory().FullName;
        try
        {
            string native = Path.Join(directory, "native.asm");
            string macro10 = Path.Join(directory, "macro10.mac");
            File.WriteAllText(native, ".org $6000\n.include \"macro10.mac\" dialect=macro10\n    rts\n");
            File.WriteAllText(macro10, "INVERS:\tNOP\n");

            SourceAnalysis analysis = SourceAnalysis.Assemble(native, _ => null);

            analysis.Result.Diagnostics.Should().BeEmpty();
            analysis.UsesMacro10(native).Should().BeFalse();
            analysis.UsesMacro10(macro10).Should().BeTrue();
            analysis.Find("InverseCapitalsOn", analysis.UsesMacro10(native)).Should().BeEmpty();
            analysis.Find("InverseCapitalsOn", analysis.UsesMacro10(macro10)).Should().ContainSingle().Which.Name.Should().Be("INVERS");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  A file with no parsed statements can still declare its own dialect.
    /// </summary>
    [TestMethod]
    public void DialectFallbackUsesTheFileWhenNotParsed()
    {
        string directory = Directory.CreateTempSubdirectory().FullName;
        try
        {
            string root = Path.Join(directory, "main.asm");
            string macro = Path.Join(directory, "unreached.mac");
            string native = Path.Join(directory, "native.mac");
            File.WriteAllText(root, ".org $6000\n    jmp missing\n");
            File.WriteAllText(macro, "; no statements\n");
            File.WriteAllText(native, "; retrocore: dialect=native\n");

            SourceAnalysis analysis = SourceAnalysis.Assemble(root, _ => null);

            analysis.UsesMacro10(macro).Should().BeTrue();
            analysis.UsesMacro10(native).Should().BeFalse();
            SourceText.Macro10Dialect(macro, []).Should().BeTrue();
            SourceText.Macro10Dialect(native, SourceText.Lines(File.ReadAllText(native))).Should().BeFalse();
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  The MACRO-10 overlay and the base it composes both retain six-character name matching.
    /// </summary>
    [TestMethod]
    public void Macro10OverlayAndBaseKeepTheirDialect()
    {
        string folder = Path.GetFullPath(Path.Join(AppContext.BaseDirectory, "Inputs", "AppleSoft"));
        string overlay = Path.Join(folder, "applesoft.mac");
        string basis = Path.GetFullPath(Path.Join(AppContext.BaseDirectory, "Inputs", "Microsoft6502Basic", "m6502.asm"));
        File.Exists(basis).Should().BeTrue("the overlay's base must be where the test inputs keep it");

        SourceAnalysis analysis = SourceAnalysis.Assemble(overlay, _ => null);

        analysis.Result.Diagnostics.Should().BeEmpty();
        analysis.UsesMacro10(overlay).Should().BeTrue();
        analysis.UsesMacro10(basis).Should().BeTrue();
        analysis.Find("INVERSEEXTRA", analysis.UsesMacro10(overlay)).Should().ContainSingle().Which.Name.Should().Be("INVERS");
        analysis.Find("INVERSEEXTRA", analysis.UsesMacro10(basis)).Should().ContainSingle().Which.Name.Should().Be("INVERS");
    }

    /// <summary>
    ///  The editor's documentation knows which branch of an <c>.if</c> the assembly took, as the assembler's does: a
    ///  macro defined after the <c>.ifdef</c> that tests it doesn't select that branch's <c>Entry:</c>.
    /// </summary>
    [TestMethod]
    public void DocumentationFollowsTheBranchTheAssemblyTook()
    {
        string directory = Directory.CreateTempSubdirectory().FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            File.WriteAllText(main, """
                .cpu Mos6502
                .org $6000
                .ifdef WIDE
                ;; Scrolls, wide.
                ;; Entry:
                ;;   Wide = the wide loop
                .proc Scroll
                Wide:
                    rts
                .endproc
                .else
                ;; Scrolls, narrow.
                ;; Entry:
                ;;   Narrow = the narrow loop
                .proc Scroll
                Narrow:
                    rts
                .endproc
                .endif
                .macro WIDE
                .endmacro
                """);

            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);

            analysis.Result.Diagnostics.Should().BeEmpty();
            new DocumentationResolver(analysis.Documentation).Check().Should().BeEmpty();
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  The editor's documentation follows the branch the assembly took even while the assembly has an error, when
    ///  the error comes after the branch was chosen: one in expansion, or one found only when code is laid out.
    /// </summary>
    [TestMethod]
    public void DocumentationFollowsTheBranchTheAssemblyTookDespiteALaterError()
    {
        string directory = Directory.CreateTempSubdirectory().FullName;
        try
        {
            foreach (string error in (string[])[".bogus", "    jmp Nowhere"])
            {
                string main = Path.Join(directory, "main.asm");
                File.WriteAllText(main, $$"""
                    .cpu Mos6502
                    .org $6000
                    .ifdef WIDE
                    ;; Scrolls, wide.
                    ;; Entry:
                    ;;   Wide = the wide loop
                    .proc Scroll
                    Wide:
                        rts
                    .endproc
                    .else
                    ;; Scrolls, narrow.
                    ;; Entry:
                    ;;   Narrow = the narrow loop
                    .proc Scroll
                    Narrow:
                        rts
                    .endproc
                    .endif
                    .macro WIDE
                    .endmacro
                    {{error}}
                    """);

                SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);

                analysis.Result.Success.Should().BeFalse(error);
                DocumentationSet set = analysis.Documentation;
                if (set.Find("Scroll") is not { } scroll) { throw new AssertFailedException("Expected Scroll."); }
                scroll.Sections.Where(section => section.Name == "Entry" && set.InBuild(scroll, section))
                    .Should().ContainSingle(error)
                    .Which.Text.Should().Contain("Narrow", error);
            }
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  A <c>.define</c> in an included file is found from its uses, with its documentation, even when its name
    ///  is also a mnemonic.
    /// </summary>
    [TestMethod]
    public void DefinesAreDefinitions()
    {
        string directory = Directory.CreateTempSubdirectory().FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            string commands = Path.Join(directory, "commands.asm");
            File.WriteAllText(commands, ";; An entry that does nothing.\n.define NOP(state) ((state) << 4 | $8)\n");
            File.WriteAllText(main, ".include \"commands.asm\"\n.org $6000\n    .byte NOP($1)\n");

            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);

            analysis.Result.Diagnostics.Should().BeEmpty();
            SymbolSite nop = analysis.Find("NOP").Single();
            nop.Path.Should().Be(commands);
            nop.Line.Should().Be(1);
            nop.Kind.Should().Be(SymbolSiteKind.Macro);
            analysis.Documentation.Find("NOP")?.Summary.Should().Be("An entry that does nothing.");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  A directive in column 0 is not a local label, so it does not resolve to the line it starts.
    /// </summary>
    [TestMethod]
    public void DirectivesAreNotLocalLabels()
    {
        string[] lines = [";; An entry that does nothing.", ".define NOP(state) ((state) << 4 | $8)", ".loop", "    bne .loop"];

        SourceText.LocalDefinition(lines, ".define", 1).Should().BeNull();
        SourceText.LocalDefinition(lines, ".loop", 3)?.Line.Should().Be(2, "a local label still resolves");
    }

    /// <summary>
    ///  An included file is analyzed through the outermost source that includes it, the later version when two
    ///  do, and a MACRO-10 base through its overlay.
    /// </summary>
    /// <param name="file">The opened file, under the test's inputs.</param>
    /// <param name="root">The root it is analyzed through.</param>
    [TestMethod]
    [DataRow("Dos/BootLoader.asm", "Dos/Dos33.asm")]
    [DataRow("DiskII/Boot.asm", "DiskII/Boot16.asm")]
    [DataRow("DiskII/Sequencer.asm", "DiskII/Sequencer16.asm")]
    [DataRow("Microsoft6502Basic/m6502.asm", "AppleSoft/applesoft.mac")]
    [DataRow("Dos/Dos33.asm", "Dos/Dos33.asm")]
    public void IncludedFilesAreAnalyzedThroughTheirRoot(string file, string root)
    {
        string inputs = Path.Join(AppContext.BaseDirectory, "Inputs");
        SourceIncludes.RootOf(Path.GetFullPath(Path.Join(inputs, file)))
            .Should().Be(Path.GetFullPath(Path.Join(inputs, root)));
    }

    /// <summary>
    ///  A module's part in a folder of its own, included from the module's main file in the folder above, is
    ///  analyzed through that main file.
    /// </summary>
    [TestMethod]
    public void PartsInAModuleFolderAreAnalyzedThroughTheMainFile()
    {
        string folder = Directory.CreateTempSubdirectory("retrocore-parts").FullName;
        try
        {
            string root = Path.Join(folder, "Monitor.asm");
            File.WriteAllText(root, ".include \"Monitor/Screen.asm\"\n");
            string part = Path.Join(Directory.CreateDirectory(Path.Join(folder, "Monitor")).FullName, "Screen.asm");
            File.WriteAllText(part, "    rts\n");

            SourceIncludes.RootOf(part).Should().Be(root);
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    /// <summary>
    ///  A folder beside a source that is deleted, or replaced by a file, after it was listed, as a build or a cleanup
    ///  can do while the language server looks for the source's root, has no sources rather than failing the
    ///  search; the root is still found through the folders that remain.
    /// </summary>
    [TestMethod]
    public void VanishedFoldersDoNotStopTheRootSearch()
    {
        string folder = Directory.CreateTempSubdirectory("retrocore-roots").FullName;
        try
        {
            string library = Directory.CreateDirectory(Path.Join(folder, "lib")).FullName;
            string program = Directory.CreateDirectory(Path.Join(folder, "program")).FullName;
            string gone = Directory.CreateDirectory(Path.Join(folder, "gone")).FullName;
            string included = Path.Join(library, "Library.asm");
            string root = Path.Join(program, "Main.asm");
            File.WriteAllText(included, "    rts\n");
            File.WriteAllText(root, ".include \"../lib/Library.asm\"\n");

            // The folders as they were listed: one is deleted before its files are read, and another is replaced by a
            // file of the same name.
            string replaced = Directory.CreateDirectory(Path.Join(folder, "replaced")).FullName;
            List<string> listed = [library, gone, replaced, program];
            Directory.Delete(gone);
            Directory.Delete(replaced);
            File.WriteAllText(replaced, "");

            SourceIncludes.SourcesIn(gone).Should().BeEmpty();
            SourceIncludes.SourcesIn(replaced).Should().BeEmpty();

            // A source listed and then replaced by a folder of the same name includes nothing.
            string folderNamedLikeASource = Directory.CreateDirectory(Path.Join(folder, "Other.asm")).FullName;
            SourceIncludes.IncludesOf(folderNamedLikeASource).Should().BeEmpty();
            SourceIncludes.RootOf(included, listed).Should().Be(root);
            SourceIncludes.RootOf(included).Should().Be(root);
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    /// <summary>
    ///  The name under the cursor includes scope qualifiers and cheap locals, but not a label's colon.
    /// </summary>
    /// <param name="line">The line.</param>
    /// <param name="column">The cursor's column.</param>
    /// <param name="expected">The name.</param>
    [TestMethod]
    [DataRow("    lda Outer::Value,x", 10, "Outer::Value")]
    [DataRow("start:", 2, "start")]
    [DataRow("    bne @loop", 10, "@loop")]
    [DataRow("    jsr B_FUNC", 12, "B_FUNC")]
    [DataRow("    .org $F800", 6, ".org")]
    public void WordAtFindsTheName(string line, int column, string expected) =>
        SourceText.WordAt(line, column)?.Word.Should().Be(expected);

    /// <summary>
    ///  The operation is the first word after an optional label; a directive's name ends at a parenthesis, as the
    ///  assembler reads it, so what follows <c>.if(</c> is an operand.
    /// </summary>
    /// <param name="before">The line up to the cursor.</param>
    /// <param name="expected">Whether an operation belongs at the cursor.</param>
    [TestMethod]
    [DataRow("    ld", true)]
    [DataRow("start: .i", true)]
    [DataRow("    .if ", false)]
    [DataRow("    .if(", false)]
    [DataRow("start: .byte(", false)]
    public void IsOperationEndsADirectiveAtAParenthesis(string before, bool expected) =>
        SourceText.IsOperation(before).Should().Be(expected);

    /// <summary>
    ///  A definition from an older analysis may no longer have a line in the edited document.
    /// </summary>
    /// <param name="line">The stale definition's line.</param>
    [TestMethod]
    [DataRow(1)]
    [DataRow(3)]
    public void CommentsIgnoreStaleDefinitions(int line) =>
        SourceText.CommentFor(["; Not the stale definition's comment."], line).Should().BeEmpty();

    /// <summary>
    ///  In a file of p-code and 6502 code, a line's help is that of what wrote its bytes: under the <c>.cpu Pcode</c> an
    ///  include sets, <c>LDA</c> expands its macro, so its help is the macro's; under <c>.cpu Mos6502</c> it is the
    ///  6502's instruction. A macro-only CPU has no instruction help or mnemonics of its own.
    /// </summary>
    [TestMethod]
    public void MixedPcodeAndM6502LinesKnowWhatWroteThem()
    {
        string directory = Directory.CreateTempSubdirectory().FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            File.WriteAllText(Path.Join(directory, "pcode.asm"), """
                .cpu Pcode
                ;; Loads an intermediate variable's address.
                .macro LDA level, offset
                .byte 178, level, offset
                .endmacro
                """);

            File.WriteAllText(main, """
                .include "pcode.asm"
                .org $6000
                        LDA 1, 4
                        .cpu Mos6502
                        LDA #1
                """);

            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);

            analysis.Result.Diagnostics.Should().BeEmpty();
            analysis.ExpandsMacro(main, line: 2).Should().BeTrue("the p-code LDA expands Pcode's macro");
            analysis.ExpandsMacro(main, line: 4).Should().BeFalse("under .cpu Mos6502, LDA is the 6502's");
            analysis.Find("LDA").Should().ContainSingle().Which.Kind.Should().Be(SymbolSiteKind.Macro);

            Retrocore.Isa.InstructionSet pcode = Retrocore.Assembler.CpuCatalog.Get("Pcode");
            InstructionDocs.Describe("LDA", pcode).Should().BeNull();
            InstructionDocs.MnemonicsFor(pcode).Should().BeEmpty();
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  Instruction help lists the CPU's encodings, and says when an instruction is not the CPU's.
    /// </summary>
    [TestMethod]
    public void InstructionHelpFollowsTheCpu()
    {
        InstructionDocs.Describe("STZ", ProcessorVariant.Rockwell65C02).Should().Contain("$9C");
        InstructionDocs.Describe("STZ", ProcessorVariant.Mos6502).Should().Contain("Not an instruction");
        InstructionDocs.Describe("LDA", ProcessorVariant.Mos6502).Should().Contain("immediate").And.Contain("$A9");
        InstructionDocs.Describe("KBD", ProcessorVariant.Mos6502).Should().BeNull();
        InstructionDocs.MnemonicsFor(ProcessorVariant.Rockwell65C02).Should().Contain("BBR3");
    }

    /// <summary>
    ///  Z80 help lists canonical encodings with their fields and T-states, and the nearest <c>.cpu</c> selects it.
    /// </summary>
    [TestMethod]
    public void InstructionHelpDescribesTheZ80()
    {
        Retrocore.Isa.InstructionSet z80 = Retrocore.Cpu.Z80.Z80Isa.InstructionSet;
        string? load = InstructionDocs.Describe("LD", z80);
        load.Should().Contain("| `LD A,[IX+d]` | `DD 7E d` | 19 |");
        load.Should().Contain("| `LD IXH,n` (undocumented) | `DD 26 n` | 11 |");
        InstructionDocs.Describe("BIT", z80).Should().Contain("`DD CB d 46+8b`").And.NotContain("DD CB d 40");
        InstructionDocs.Describe("DJNZ", z80).Should().Contain("| 13/8 |");
        InstructionDocs.Describe("RST", z80).Should().Contain("`C7+p`");
        InstructionDocs.Describe("LDA", z80).Should().BeNull();
        InstructionDocs.MnemonicsFor(z80).Should().Contain(["LDIR", "SLL", "DJNZ"]).And.NotContain("LDA");
        InstructionDocs.IsMnemonic("djnz").Should().BeTrue();

        string[] lines = ["    lda #1", ".cpu Z80 ; Model I", "    ld a,b"];
        SourceText.InstructionSetOf(lines, 0).Name.Should().Be("Mos6502");
        SourceText.InstructionSetOf(lines, 2).Should().BeSameAs(z80);
    }

    /// <summary>
    ///  8080 and 8085 help lists canonical encodings with their fields and states, for the CPU <c>.cpu</c> selects,
    ///  and every mnemonic of both has a summary.
    /// </summary>
    [TestMethod]
    public void InstructionHelpDescribesThe8080And8085()
    {
        Retrocore.Isa.InstructionSet i8080 = Retrocore.Cpu.I8080.I8080Isa.InstructionSet;
        Retrocore.Isa.InstructionSet i8085 = Retrocore.Cpu.I8080.I8080Isa.InstructionSet8085;
        InstructionDocs.Describe("MOV", i8080).Should().Contain("| `MOV A,M` | `7E` | 7 |").And.Contain("| `MOV A,B` | `78` | 5 |");
        InstructionDocs.Describe("MOV", i8085).Should().Contain("| `MOV A,B` | `78` | 4 |");
        InstructionDocs.Describe("RST", i8080).Should().Contain("`C7+8n`");
        InstructionDocs.Describe("CC", i8085).Should().Contain("| 18/9 |");
        InstructionDocs.Describe("DSUB", i8085).Should().Contain("(undocumented)");
        InstructionDocs.Describe("DSUB", i8080).Should().NotContain("| `DSUB");
        InstructionDocs.MnemonicsFor(i8085).Should().Contain(["RIM", "SIM", "LDHI"]);
        InstructionDocs.MnemonicsFor(i8080).Should().NotContain("RIM");
        foreach (Retrocore.Isa.InstructionSet set in (Retrocore.Isa.InstructionSet[])[i8080, i8085])
        {
            foreach (string mnemonic in InstructionDocs.MnemonicsFor(set))
            {
                InstructionDocs.Describe(mnemonic, set).Should().NotBeNull(mnemonic);
            }
        }

        string[] lines = [".cpu I8085", "    rim"];
        SourceText.InstructionSetOf(lines, 1).Should().BeSameAs(i8085);
    }

    /// <summary>
    ///  References to a constant, a label and a macro: in code across includes and in documentation links, not in
    ///  strings or ordinary comments, and not another assembly's name spelled the same.
    /// </summary>
    [TestMethod]
    public void ReferencesFollowResolution()
    {
        string directory = Directory.CreateTempSubdirectory().FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            string equates = Path.Join(directory, "equates.asm");
            string other = Path.Join(directory, "other.asm");
            File.WriteAllText(equates, Equates);
            File.WriteAllText(main, ReferencesSource);
            File.WriteAllText(other, ".org $7000\nKBD = $C010\n    lda KBD\n");
            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);
            SourceAnalysis unrelated = SourceAnalysis.Assemble(other, _ => null);
            SourceAnalysis[] analyses = [analysis, unrelated];

            string[] uses = ["main.asm:2:14", "main.asm:4:8", "main.asm:6:8"];
            References(analysis, "KBD", analyses, declarations: true).Should().Equal(["equates.asm:1:0", .. uses]);
            References(analysis, "KBD", analyses, declarations: false).Should().Equal(uses);
            References(analysis, "show", analyses, declarations: false).Should().Equal("main.asm:8:4", "main.asm:9:4");
            References(analysis, "start", analyses, declarations: true).Should().Equal("main.asm:3:0", "main.asm:11:8");
            References(unrelated, "KBD", analyses, declarations: false).Should().Equal("other.asm:2:8");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    // The references to a name an assembly defines, each as file:line:column.
    private static string[] References(SourceAnalysis analysis, string name, SourceAnalysis[] analyses, bool declarations) =>
    [
        .. SymbolReferences.Find(name, analysis.Find(name), analyses, sdk: [], declarations)
            .Select(site => $"{Path.GetFileName(site.Path)}:{site.Line}:{site.Column}")
    ];
}
