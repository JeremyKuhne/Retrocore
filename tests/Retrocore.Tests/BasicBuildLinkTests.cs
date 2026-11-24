// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Debug.Language;
using Retrocore.Documentation;
using Retrocore.Machines.Apple2;
using Retrocore.Machines.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  In each native BASIC build, every link in a comment the build assembles names a definition the build assembles.
///  The lint resolves a link against the definitions of every build of a conditional source, so a comment that all
///  builds assemble can link a definition that only some builds have; this checks each build for it.
/// </summary>
[TestClass]
public sealed class BasicBuildLinkTests
{
    // The folders of the BASIC sources: the shared Microsoft modules and the two vendors' files.
    private static readonly string[] s_folders =
    [
        Path.Join("Microsoft6502Basic", ""), Path.Join("AppleSoft", ""), Path.Join("Pet", "Basic", "")
    ];

    /// <summary>
    ///  AppleSoft's comments link only what the model's build assembles.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus)]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void AppleSoftLinksOnlyWhatItsBuildAssembles(Apple2Model model)
    {
        string inputs = BasicNames.Inputs;
        AssertLinksAssembled(SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(inputs), model), "AppleSoft");
    }

    /// <summary>
    ///  PET BASIC's comments link only what the version's build assembles.
    /// </summary>
    /// <param name="model">The PET BASIC version.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void PetBasicLinksOnlyWhatItsBuildAssembles(PetModel model, bool original)
    {
        string inputs = BasicNames.Inputs;
        AssemblyResult result = PetSdkModules.AssembleBasic(Path.Join(inputs, "Pet"), model, original, BasicSourceKind.Native);
        AssertLinksAssembled(result, "PetBasic");
    }

    // Asserts that each link in a BASIC comment the build assembles resolves to a definition the build assembles.
    private static void AssertLinksAssembled(AssemblyResult result, string module)
    {
        result.Success.Should().BeTrue(string.Join(Environment.NewLine, result.Diagnostics.Select(diagnostic => diagnostic.Message)));
        DocumentationSet set = Set(result, module);
        DocumentationResolver resolver = new(
            set,
            isDirective: name => DirectiveDocs.Describe(name) is not null,
            isInstruction: InstructionDocs.IsMnemonic);

        List<string> broken = [];
        foreach (DocumentationTopic topic in set.Topics.Where(set.Assembles))
        {
            foreach (DocumentationComment comment in topic.Comments.Where(comment => IsBasic(comment.Path)))
            {
                // A macro's own comment is in every build that includes its file; a comment in its body only where the
                // build expands that line; any other only where the build takes its branch.
                bool inBody = comment.Macro is not null;
                bool assembled = inBody ? set.Expansions(comment) > 0 : set.CommentInBuild(comment);
                if (topic.Kind != DocumentationKind.Macro && !assembled) { continue; }

                string[] texts = [comment.Summary, .. comment.Remarks, .. comment.Sections.Select(section => section.Text)];
                foreach (DocumentationLink link in texts.SelectMany(DocumentationText.Links))
                {
                    DocumentationTarget target = resolver.Resolve(topic, link.Target, comment);
                    if (target.Topic is { } linked && ReferenceEquals(target.Set, set) && !set.Assembles(linked))
                    {
                        broken.Add($"{Path.GetFileName(comment.Path)}:{comment.Line + 1}: <{link.Target}> ({topic.Name})");
                    }
                }
            }
        }

        broken = [.. broken.Distinct()];
        broken.Should().BeEmpty(
            $"a comment this build assembles must link only definitions it assembles:{Environment.NewLine}{string.Join(Environment.NewLine, broken)}");
    }

    // Whether a file is one of the BASIC sources.
    private static bool IsBasic(string? path) =>
        path is not null && s_folders.Any(folder => path.Contains(folder, StringComparison.OrdinalIgnoreCase));

    // The documentation of a build's files.
    private static DocumentationSet Set(AssemblyResult result, string module)
    {
        IEnumerable<string?> paths = result.SourceMap
            .Select(entry => entry.Location?.Path)
            .Concat(result.SymbolDefinitions.Select(symbol => symbol.Location?.Path));

        List<DocumentationFile> files = [.. paths
            .OfType<string>()
            .Where(File.Exists)
            .Select(Path.GetFullPath)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Select(path => DocumentationParser.Parse(File.ReadAllText(path), path))];

        return DocumentationSet.Create(files, result, module);
    }
}
