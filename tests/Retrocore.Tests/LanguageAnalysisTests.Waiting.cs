// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Debug.Language;

namespace Retrocore.Tests;

// How a request waits for a document's first analysis, and the SDK index the workspaces share.
public sealed partial class LanguageAnalysisTests
{
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
