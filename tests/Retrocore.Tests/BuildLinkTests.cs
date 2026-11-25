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
///  In each build of a source that builds several variants with <c>.if</c>, every link in a comment the build
///  assembles reaches a definition the build assembles. The resolver resolves a link only to what its set's build
///  assembles and the lint reports the rest, so each build's lint finds the links only another build can follow;
///  this lints AppleSoft's and PET BASIC's builds, and <see cref="RomBuildLinkTests"/> the Apple II's ROM and DOS
///  builds.
/// </summary>
/// <remarks>
///  <para>
///   The other sources that build several ways, such as the TRS-80's, the CoCo's and the PET's editor, kernal and
///   character generator, are linted only in the build the editor uses.
///  </para>
/// </remarks>
[TestClass]
public sealed class BuildLinkTests
{
    // The SDK's modules for links to reach, read once for every build.
    private static readonly Lazy<List<DocumentationSet>> s_sets = new(SdkDocumentationTests.Sets);

    /// <summary>
    ///  AppleSoft's links reach what the model's build assembles.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus)]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void AppleSoftLinksOnlyWhatItsBuildAssembles(Apple2Model model)
    {
        string inputs = BasicNames.Inputs;
        AssemblyResult result = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(inputs), model);
        AssertLinksAssembled(result, "AppleSoft");
    }

    /// <summary>
    ///  PET BASIC's links reach what the version's build assembles.
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
        AssertLinksAssembled(result, "PetBasic", sdkBuild: false, others: false);
    }

    /// <summary>
    ///  Asserts that a build's lint finds no link it can't follow, and that no link in a comment the build assembles
    ///  reaches a definition of this source the build leaves out. The SDK's other modules are there for links to reach;
    ///  the SDK's set of the module stands aside when it is this build, and one of another build, such as the Enhanced
    ///  IIe's Monitor for the II's, stays for links that name the module or the model.
    /// </summary>
    /// <param name="result">The build's assembly.</param>
    /// <param name="module">The module's name.</param>
    /// <param name="model">The build's model, as links name it, or null.</param>
    /// <param name="sdkBuild">Whether the SDK's set of the module is this build, or one that has no model.</param>
    /// <param name="others">Whether links may reach the SDK's other modules.</param>
    internal static void AssertLinksAssembled(
        AssemblyResult result,
        string module,
        string? model = null,
        bool sdkBuild = true,
        bool others = true)
    {
        result.Success.Should().BeTrue(string.Join(Environment.NewLine, result.Diagnostics.Select(diagnostic => diagnostic.Message)));
        DocumentationSet set = Set(result, module, model);
        bool ThisBuild(DocumentationSet other) => sdkBuild && other.Module == module && (other.Model ?? model) == model;
        List<DocumentationSet> sets = others ? [.. s_sets.Value.Where(other => !ThisBuild(other))] : [];
        DocumentationResolver resolver = new(
            set,
            sets,
            isDirective: name => DirectiveDocs.Describe(name) is not null,
            isInstruction: InstructionDocs.IsMnemonic);

        List<string> broken = [.. resolver.Check()
            .Where(problem => problem.Rule is DocumentationRules.Link or DocumentationRules.AmbiguousLink)
            .Select(problem => $"{Shown(problem.Path)}:{problem.Line + 1}: {problem.Message}")];

        // As the old per-build check did: what each link in a comment the build assembles reaches is in the build.
        foreach (DocumentationTopic topic in set.Topics.Where(set.Assembles))
        {
            foreach (DocumentationComment comment in topic.Comments)
            {
                // A comment in a macro's body is assembled where the build expands its line; any other, a macro's own
                // among them, where the build takes its branch.
                bool assembled = comment.Macro is not null ? set.Expansions(comment) > 0 : set.CommentInBuild(comment);
                if (!assembled) { continue; }

                string[] texts = [comment.Summary, .. comment.Remarks, .. comment.Sections.Select(section => section.Text)];
                foreach (DocumentationLink link in texts.SelectMany(DocumentationText.Links))
                {
                    DocumentationTarget target = resolver.Resolve(topic, link.Target, comment);
                    if (target.Topic is { } linked && ReferenceEquals(target.Set, set) && !set.Assembles(linked))
                    {
                        broken.Add($"{Shown(comment.Path)}:{comment.Line + 1}: <{link.Target}> reaches another build's {linked.Name}");
                    }
                }
            }
        }

        broken = [.. broken.Distinct()];
        broken.Should().BeEmpty(
            $"a comment this build assembles must link only what it can follow:{Environment.NewLine}{string.Join(Environment.NewLine, broken)}");
    }

    // A source's folder and name.
    private static string Shown(string path) =>
        Path.Join(Path.GetFileName(Path.GetDirectoryName(path)), Path.GetFileName(path));

    // The documentation of a build's files.
    private static DocumentationSet Set(AssemblyResult result, string module, string? model)
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

        return DocumentationSet.Create(files, result, module, model);
    }
}
