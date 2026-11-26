// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Documentation;
using Retrocore.Isa;
using Retrocore.Machines.Apple2;

namespace Retrocore.Tests;

/// <summary>
///  The static <c>Keeps:</c> and <c>Uses:</c> check over the SDK's own sources, as a report.
/// </summary>
[TestClass]
public class ContractAnalysisSdkTests
{
    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    /// <summary>
    ///  Checks the documented routines of the Apple II Monitor and firmware, AppleSoft, the BBC Micro's MOS, BASIC
    ///  and DFS, the CoCo 3's ROMs and the Kaypro's MBASIC, and reports what disagrees with the code and what the
    ///  analysis could not follow.
    /// </summary>
    [TestMethod]
    public void SdkSourcesReport()
    {
        string acorn = Path.Join(s_inputs, "Acorn");
        Coco3Assembly coco = CocoSdkModules.AssembleCoco3(Path.Join(s_inputs, "Coco"));
        (string Name, AssemblyResult Result, string Model)[] modules =
        [
            ("Monitor", SdkModules.AssembleSystem(System("Monitor.asm"), SdkModules.MonitorOrigin, SdkModules.MonitorSize, Apple2Model.IIeEnhanced), "Enhanced"),
            ("Firmware (Enhanced)", SdkModules.AssembleSystem(System("Firmware.Enhanced.asm"), SdkModules.FirmwareOrigin, SdkModules.FirmwareSize, Apple2Model.IIeEnhanced), "Enhanced"),
            ("Firmware (Original)", SdkModules.AssembleSystem(System("Firmware.Original.asm"), SdkModules.FirmwareOrigin, SdkModules.FirmwareSize, Apple2Model.IIe), "Original"),
            ("AppleSoft", SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(s_inputs), Apple2Model.IIeEnhanced), "Enhanced"),
            ("BBC MOS", BbcSdkModules.AssembleMos(acorn), ""),
            ("BBC BASIC", BbcSdkModules.AssembleBasic(acorn), ""),
            ("BBC DFS", BbcSdkModules.AssembleDnfs(acorn), ""),
            ("CoCo Color BASIC", coco.ColorBasic, ""),
            ("CoCo Extended BASIC", coco.ExtendedBasic, ""),
            ("CoCo 3", coco.Coco3, ""),
            ("Kaypro MBASIC", KayproSdkModules.AssembleMbasic(Path.Join(s_inputs, "Kaypro", KayproSdkModules.MbasicSource)), "")
        ];

        int findings = 0;
        int checkedRoutines = 0;
        int unverified = 0;
        foreach ((string name, AssemblyResult result, string model) in modules)
        {
            result.Diagnostics.Should().BeEmpty(name);
            DocumentationSet documentation = Set(result, name);
            foreach (InstructionSet set in Sets(documentation))
            {
                AnalysisContractReport report = new AnalysisContracts(result, documentation, set, model).Check();
                IReadOnlyList<AnalysisContractFinding> found = report.Findings;
                int count = report.Checked;
                IReadOnlyList<string> skipped = report.Skipped;
                unverified += report.Unverified;

                findings += found.Count;
                checkedRoutines += count;
                Console.WriteLine($"== {name} ({set.Name}): {count} routines checked, {found.Count} findings, {skipped.Count} not followed");
                foreach (AnalysisContractFinding finding in found)
                {
                    Console.WriteLine($"  {finding}  [{Path.GetFileName(finding.Path)}:{finding.Line}]");
                }

                foreach (string reason in skipped) { Console.WriteLine($"  not followed: {reason}"); }
            }
        }

        Console.WriteLine($"Total: {checkedRoutines} routines checked, {findings} findings, {unverified} Keeps: items not verified.");
        checkedRoutines.Should().BePositive();
    }

    // The instruction sets the documented routines are in.
    private static IEnumerable<InstructionSet> Sets(DocumentationSet documentation) => documentation.Topics
        .Where(topic => topic.Kind == DocumentationKind.Routine && topic.Value is not null)
        .Select(topic => documentation.InstructionSetAt(topic.Path, topic.Line))
        .OfType<InstructionSet>()
        .Distinct();

    private static string System(string file) => Path.GetFullPath(Path.Join(s_inputs, "System", file));

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
