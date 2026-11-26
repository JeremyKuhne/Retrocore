// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug.Language;
using System.Text.Json.Nodes;

namespace Retrocore.Tests;

/// <summary>
///  The language server analyzes a project's sources through a target, with its headers and defines, takes the
///  active target from the client, and says which lines the target's conditional assembly leaves out.
/// </summary>
[TestClass]
[DoNotParallelize]
public sealed class ProjectLanguageTests
{
    private string _folder = "";

    /// <summary>
    ///  Gets each test a folder of its own.
    /// </summary>
    [TestInitialize]
    public void Initialize()
    {
        _folder = Path.Join(Path.GetTempPath(), "retrocore-language-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_folder);
    }

    /// <summary>
    ///  Removes the test's folder and the active target.
    /// </summary>
    [TestCleanup]
    public void Cleanup()
    {
        ProjectSources.SetActive(project: null, target: null);
        if (Directory.Exists(_folder)) { Directory.Delete(_folder, recursive: true); }
    }

    /// <summary>
    ///  A source two targets assemble is analyzed through the first until the client makes the other active; each
    ///  leaves out the other's branch, and its platform folder's source is a member of the analysis.
    /// </summary>
    /// <returns>A task.</returns>
    [TestMethod]
    public async Task ActiveTargetChoosesTheAnalysis()
    {
        File.WriteAllText(Path.Join(_folder, "retrocore.json"), """
            { "sdk": "1", "cpu": "6502", "sources": ["src/main.s"], "targets": {
                "iiplus": { "machine": "apple2-iiplus", "environment": "bare" },
                "iie": { "machine": "apple2-iie-enhanced", "environment": "bare", "cpu": "65c02" } } }
            """);

        string main = Path.Join(_folder, "src", "main.s");
        Directory.CreateDirectory(Path.Join(_folder, "src", "platform", "apple2"));
        File.WriteAllText(Path.Join(_folder, "src", "platform", "apple2", "screen.s"), ".include <machine.inc>\n");
        string text = """
            .if .defined(RC_CPU_65C02)
                stz CursorColumn
            .else
                lda #0
                sta CursorColumn
            .endif
                rts
            """;

        File.WriteAllText(main, text);
        RecordingLanguageClient client = new();
        LanguageWorkspace workspace = new(client);
        workspace.Update(main, text);

        (await workspace.InactiveLinesAsync(main, CancellationToken.None)).Should().Equal(new AssemblyLineRange(1, 1));
        SourceAnalysis analysis = await workspace.AnalysisOfAsync(main, CancellationToken.None)
            ?? throw new AssertFailedException("The source has no analysis.");

        analysis.Root.Should().EndWith($"{Path.GetFileName(_folder)}.iiplus{ProjectSources.Extension}");
        analysis.Result.Success.Should().BeTrue(string.Join(Environment.NewLine, analysis.Result.Diagnostics.Select(error => error.Message)));
        analysis.Members.Should().Contain(Path.Join(_folder, "src", "platform", "apple2", "screen.s"));

        LanguageHost.ActiveTargetChanged(workspace, new JsonObject
        {
            ["project"] = new Uri(_folder).AbsoluteUri, ["target"] = "iie"
        });

        ProjectSources.Active.Should().Be((Path.Join(_folder, "retrocore.json"), "iie"));
        (await workspace.InactiveLinesAsync(main, CancellationToken.None)).Should().Equal(new AssemblyLineRange(3, 2));
        (await workspace.AnalysisOfAsync(main, CancellationToken.None))?.Root.Should().EndWith($".iie{ProjectSources.Extension}");

        JsonNode? answer = await LanguageHost.InactiveRanges(workspace, new JsonObject
        {
            ["textDocument"] = new JsonObject { ["uri"] = new Uri(main).AbsoluteUri }
        });

        answer?.ToJsonString().Should().Be("""{"ranges":[{"start":{"line":3,"character":0},"end":{"line":5,"character":0}}]}""");

        // The editor fades the lines left out, as an unnecessary hint over them.
        DocumentUri uri = DocumentUri.FromFileSystemPath(main);
        for (int attempt = 0; attempt < 600 && !client.Inactive(uri).Any(hint => hint.Range.Start.Line == 3); attempt++)
        {
            await Task.Delay(50);
        }

        client.Inactive(uri).Should().ContainSingle().Which.Range.Should().Be(new LspRange(3, 0, 5, 0));

        // Clearing it goes back to the first target that assembles the source.
        LanguageHost.ActiveTargetChanged(workspace, new JsonObject
        {
            ["project"] = null, ["target"] = null
        });

        ProjectSources.Active.Should().BeNull();
        (await workspace.InactiveLinesAsync(main, CancellationToken.None)).Should().Equal(new AssemblyLineRange(1, 1));
    }

    /// <summary>
    ///  A folder's roots are its project's targets, one each, in place of the sources they assemble; a source no
    ///  target assembles stays a root of its own.
    /// </summary>
    [TestMethod]
    public void ProjectSourcesAreTheirTargetsRoots()
    {
        File.WriteAllText(Path.Join(_folder, "retrocore.json"), """
            { "sdk": "1", "name": "game", "cpu": "6502", "sources": ["src/*.s"], "targets": {
                "a": { "machine": "apple2-iiplus", "environment": "bare" },
                "b": { "machine": "pet4032", "environment": "bare" } } }
            """);

        Directory.CreateDirectory(Path.Join(_folder, "src"));
        Directory.CreateDirectory(Path.Join(_folder, "tools"));
        File.WriteAllText(Path.Join(_folder, "src", "main.s"), "rts\n");
        File.WriteAllText(Path.Join(_folder, "tools", "alone.s"), "rts\n");
        SourceIncludes.Roots(_folder).Select(Path.GetFileName).Should().BeEquivalentTo(
            $"game.a{ProjectSources.Extension}", $"game.b{ProjectSources.Extension}", "alone.s");

        SourceIncludes.RootOf(Path.Join(_folder, "src", "main.s")).Should().EndWith($"game.a{ProjectSources.Extension}");
        SourceIncludes.RootOf(Path.Join(_folder, "tools", "alone.s")).Should().Be(Path.Join(_folder, "tools", "alone.s"));
    }
}
