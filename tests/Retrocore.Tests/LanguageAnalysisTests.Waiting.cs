// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Debug.Language;
using Retrocore.Documentation;
using System.Text.Json.Nodes;

namespace Retrocore.Tests;

// How a request waits for a document's first analysis, and the SDK index the workspaces share.
public sealed partial class LanguageAnalysisTests
{
    /// <summary>
    ///  The comment's folder selects its words, even in an include: a nested folder wins over its parent, and a
    ///  similarly named sibling is not part of that parent.
    /// </summary>
    [TestMethod]
    public void UnlinkedWordsFollowTheCommentsWorkspaceFolder()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-words").FullName;
        try
        {
            string outer = Directory.CreateDirectory(Path.Join(directory, "outer")).FullName;
            string inner = Directory.CreateDirectory(Path.Join(outer, "inner")).FullName;
            string sibling = Directory.CreateDirectory(Path.Join(directory, "outer-other")).FullName;
            string root = Path.Join(outer, "root.asm");
            string innerFile = Path.Join(inner, "inner.asm");
            string siblingFile = Path.Join(sibling, "sibling.asm");
            File.WriteAllText(root, """
                ; retrocore: style=strict
                .org $6000
                ;; A flag.
                CommonTerm = 1
                ;; A flag.
                OuterTerm = 2
                ;; A flag.
                InnerTerm = 3
                ;; Reads CommonTerm and OuterTerm and InnerTerm.
                OuterEntry:
                    rts
                .include "inner/inner.asm"
                .include "../outer-other/sibling.asm"
                """);

            File.WriteAllText(innerFile, "; retrocore: style=strict\n;; Reads CommonTerm and OuterTerm and InnerTerm.\nInnerEntry:\n    rts\n");
            File.WriteAllText(siblingFile, "; retrocore: style=strict\n;; Reads CommonTerm and OuterTerm and InnerTerm.\nSiblingEntry:\n    rts\n");
            SourceAnalysis analysis = SourceAnalysis.Assemble(root, _ => null);
            analysis.Result.Success.Should().BeTrue();
            LanguageWorkspace workspace = new(new RecordingLanguageClient());

            List<string?> Names(string file) => [.. workspace.ResolverFor(analysis).Lint()
                .Where(diagnostic => diagnostic.Rule == DocumentationRules.UnlinkedName && diagnostic.Path == file)
                .Select(diagnostic => diagnostic.Name)];

            Names(root).Should().BeEquivalentTo("CommonTerm", "OuterTerm", "InnerTerm");
            Names(innerFile).Should().BeEquivalentTo("CommonTerm", "OuterTerm", "InnerTerm");
            Names(siblingFile).Should().BeEquivalentTo("CommonTerm", "OuterTerm", "InnerTerm");
            LanguageHost.UnlinkedNameWordsChanged(workspace, new JsonObject
            {
                ["words"] = new JsonArray("CommonTerm"),
                ["folders"] = new JsonArray
                {
                    new JsonObject
                    {
                        ["uri"] = "vscode-vfs:/virtual", ["words"] = new JsonArray("VirtualTerm")
                    },
                    new JsonObject
                    {
                        ["uri"] = new Uri(inner).AbsoluteUri, ["words"] = new JsonArray("CommonTerm", "InnerTerm")
                    },
                    new JsonObject
                    {
                        ["uri"] = new Uri(outer).AbsoluteUri, ["words"] = new JsonArray("CommonTerm", "OuterTerm")
                    }
                }
            });

            Names(root).Should().BeEquivalentTo("InnerTerm");
            Names(innerFile).Should().BeEquivalentTo("OuterTerm");
            Names(siblingFile).Should().BeEquivalentTo("OuterTerm", "InnerTerm");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  A request about a file that nothing is analyzing answers at once, rather than waiting for an analysis that
    ///  never comes.
    /// </summary>
    /// <returns>The test.</returns>
    [TestMethod]
    public async Task RequestForAFileNotBeingAnalyzedAnswersAtOnce()
    {
        string folder = Directory.CreateTempSubdirectory("retrocore-waiting").FullName;
        try
        {
            // A folder of its own, away from other tests' temporary folders, as the editor reads the folders beside it.
            string probe = Directory.CreateDirectory(Path.Join(folder, "probe")).FullName;
            string path = Path.GetFullPath(Path.Join(probe, "Probe.asm"));
            File.WriteAllText(path, ".org $0300\n    rts\n");
            LanguageWorkspace workspace = new(new RecordingLanguageClient());

            Task<SourceAnalysis?> answer = workspace.AnalysisOfAsync(path, CancellationToken.None);

            answer.IsCompleted.Should().BeTrue();
            (await answer).Should().BeNull();
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    /// <summary>
    ///  A request waiting for a document's first analysis goes on when the analysis ends without one: here a document
    ///  whose file is not on disk closes, so the attempt it schedules has nothing to read.
    /// </summary>
    /// <returns>The test.</returns>
    [TestMethod]
    public async Task WaitEndsWhenTheAnalysisEndsWithoutOne()
    {
        string folder = Directory.CreateTempSubdirectory("retrocore-waiting").FullName;
        try
        {
            string probe = Directory.CreateDirectory(Path.Join(folder, "probe")).FullName;
            string path = Path.GetFullPath(Path.Join(probe, "Unsaved.asm"));
            LanguageWorkspace workspace = new(new RecordingLanguageClient());
            workspace.Close(path);

            (await workspace.AnalysisOfAsync(path, CancellationToken.None)).Should().BeNull();
            await workspace.IdleAsync(path, CancellationToken.None);
            workspace.AnalysisOf(path).Should().BeNull();
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    /// <summary>
    ///  Workspaces in one process share the SDK's index rather than each assembling every ROM source again.
    /// </summary>
    /// <returns>The test.</returns>
    [TestMethod]
    public async Task WorkspacesShareTheSdkIndex()
    {
        LanguageWorkspace first = new(new RecordingLanguageClient());
        LanguageWorkspace second = new(new RecordingLanguageClient());
        await SdkIndex.For(SdkModules.RomDirectory).Completion;

        List<SourceAnalysis> sdk = [.. first.SdkAnalyses()];
        sdk.Should().NotBeEmpty();
        second.SdkAnalyses().Should().Equal(sdk, (one, other) => ReferenceEquals(one, other));
    }
}
