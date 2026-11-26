// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Documentation;
using Retrocore.Isa;
using Retrocore.Machines;
using Retrocore.Machines.Acorn;
using Retrocore.Machines.Apple2;
using Retrocore.Machines.Coco;

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
        // Each map is the machine's in the state the module runs in.
        MemoryMap enhanced = AppleMap(Apple2Model.IIeEnhanced, internalSlotRom: false);
        MemoryMap enhancedFirmware = AppleMap(Apple2Model.IIeEnhanced, internalSlotRom: true);
        MemoryMap originalFirmware = AppleMap(Apple2Model.IIe, internalSlotRom: true);
        MemoryMap bbc = BbcMap();
        MemoryMap coco3 = Coco3Map();
        (string Name, AssemblyResult Result, string Model, MemoryMap Map)[] modules =
        [
            ("Monitor", SdkModules.AssembleSystem(System("Monitor.asm"), SdkModules.MonitorOrigin, SdkModules.MonitorSize, Apple2Model.IIeEnhanced), "Enhanced", enhanced),
            ("Firmware (Enhanced)", SdkModules.AssembleSystem(System("Firmware.Enhanced.asm"), SdkModules.FirmwareOrigin, SdkModules.FirmwareSize, Apple2Model.IIeEnhanced), "Enhanced", enhancedFirmware),
            ("Firmware (Original)", SdkModules.AssembleSystem(System("Firmware.Original.asm"), SdkModules.FirmwareOrigin, SdkModules.FirmwareSize, Apple2Model.IIe), "Original", originalFirmware),
            ("AppleSoft", SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(s_inputs), Apple2Model.IIeEnhanced), "Enhanced", enhanced),
            ("BBC MOS", BbcSdkModules.AssembleMos(acorn), "", bbc),
            ("BBC BASIC", BbcSdkModules.AssembleBasic(acorn), "", bbc),
            ("BBC DFS", BbcSdkModules.AssembleDnfs(acorn), "", bbc),
            ("CoCo Color BASIC", coco.ColorBasic, "", coco3),
            ("CoCo Extended BASIC", coco.ExtendedBasic, "", coco3),
            ("CoCo 3", coco.Coco3, "", coco3),
            ("Kaypro MBASIC", KayproSdkModules.AssembleMbasic(Path.Join(s_inputs, "Kaypro", KayproSdkModules.MbasicSource)), "", MemoryMap.AllRam)
        ];

        int findings = 0;
        int provedMarked = 0, provedUnmarked = 0, unprovedMarked = 0;
        int checkedRoutines = 0;
        int unverified = 0;
        foreach ((string name, AssemblyResult result, string model, MemoryMap map) in modules)
        {
            result.Diagnostics.Should().BeEmpty(name);
            DocumentationSet documentation = Set(result, name);
            foreach (InstructionSet set in Sets(documentation))
            {
                AnalysisContractReport report = new AnalysisContracts(result, documentation, set, model, map: map).Check();
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
                (int marked, int unmarked, int unproved) = ReportConditions(result, report);
                provedMarked += marked;
                provedUnmarked += unmarked;
                unprovedMarked += unproved;
            }
        }

        Console.WriteLine($"Total: {checkedRoutines} routines checked, {findings} findings, {unverified} Keeps: items not verified.");
        Console.WriteLine($"Conditions: {provedMarked} marked 'always' and proved fixed, {provedUnmarked} fixed without it.");
        Console.WriteLine($"Conditions: {unprovedMarked} marked 'always' but not proved.");
        checkedRoutines.Should().BePositive();
    }

    // The conditions the analysis reached, against the source's own "always" comments: those it proved go one way,
    // marked or not, and those marked that it did not prove.
    private static (int Marked, int Unmarked, int Unproved) ReportConditions(AssemblyResult result, AnalysisContractReport report)
    {
        Dictionary<int, AssemblyLocation> locations = [];
        foreach (AssemblySourceMapEntry entry in result.SourceMap)
        {
            if (entry.Size != 0 && entry.Location is { } location)
            {
                locations.TryAdd(entry.Address, location);
            }

        }

        int marked = 0, unmarked = 0, unproved = 0;
        foreach ((ushort at, int ways) in report.Conditions.OrderBy(pair => pair.Key))
        {
            if (!locations.TryGetValue(at, out AssemblyLocation? location) || !File.Exists(location.Path)) { continue; }
            string line = File.ReadLines(location.Path).ElementAtOrDefault(location.Line) ?? "";
            int comment = line.IndexOf(';', StringComparison.Ordinal);
            bool always = comment >= 0 && line[comment..].Contains("always", StringComparison.OrdinalIgnoreCase);
            string where = $"{Path.GetFileName(location.Path)}:{location.Line + 1}";
            if (ways != 3 && always)
            {
                marked++;
            }
            else if (ways != 3)
            {
                unmarked++;
                Console.WriteLine($"  fixed (${at:X4}, {(ways == 2 ? "always taken" : "never taken")}): {line.Trim()}  [{where}]");
            }
            else if (always)
            {
                unproved++;
                Console.WriteLine($"  marked, not proved (${at:X4}): {line.Trim()}  [{where}]");
            }
        }

        return (marked, unmarked, unproved);
    }

    // An Apple IIe after reset: the Monitor and AppleSoft run there. The firmware's $C100-$CFFF runs with the
    // internal ROM switched in over the slots, as SETINTCXROM does.
    private static MemoryMap AppleMap(Apple2Model model, bool internalSlotRom)
    {
        Apple2Machine machine = new(model, new Apple2Roms(new byte[16384], new byte[4096]));
        if (internalSlotRom) { machine.Bus.Write(0xC007, 0); }
        return MemoryMap.Capture(machine);
    }

    // A Model B with ROMs in the sockets BASIC and the DFS use.
    private static MemoryMap BbcMap()
    {
        BbcRoms roms = new(new byte[16384], new byte[960]);
        roms.Fit(0, new byte[16384]);
        roms.Fit(3, new byte[16384]);
        return MemoryMap.Capture(new BbcMachine(roms));
    }

    // A CoCo 3 as its reset leaves it to run BASIC: copied into RAM, with the MMU on, 32K internal ROM mapped
    // (INIT0 = COCO+MMUEN+MC3+MC1) and the SAM in all-RAM mode.
    private static MemoryMap Coco3Map()
    {
        CocoConfiguration configuration = new() { Model = CocoModel.Coco3 };
        CocoMachine machine = new(configuration, CocoRoms.ForCoco3(new byte[32768]));
        machine.Bus.Write(0xFF90, 0xCA);
        machine.Bus.Write(0xFFDF, 0);
        return MemoryMap.Capture(machine);
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
