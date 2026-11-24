// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.RegularExpressions;
using Retrocore.Debug.Language;

namespace Retrocore.Tests;

/// <summary>
///  Checks a converted ROM source keeps that reviews of the conversions kept finding by hand: code written with
///  the current names, and the historical names of a routine both IIe firmwares have cited alike in each.
/// </summary>
[TestClass]
public sealed partial class ConvertedSourceTests
{
    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    // The Apple II sources' modules, as the editor indexes them.
    private static readonly string[] s_folders = ["DiskII", "Dos", "System"];

    // Names that mean different routines in the two IIe firmwares, each kept on its own model's definition
    // (docs/conversions/Firmware.md, F1), or that sit on different code in the two.
    private static readonly HashSet<string> s_firmwareOwnNames =
        ["TESTFAIL", "BASCALC", "DIAGS", "STAY80", "X_USRET", "X_DC1B", "QUIT2", "CTLGO"];

    /// <summary>
    ///  A source that follows the style guide writes its code with the current names: a historical name, kept so
    ///  that old code assembles, is never what a converted source itself uses.
    /// </summary>
    [TestMethod]
    public void ConvertedSourcesUseCurrentNames()
    {
        HashSet<string> found = [];
        foreach (string root in s_folders.SelectMany(folder => SourceIncludes.Roots(Path.Join(s_inputs, folder))))
        {
            SourceAnalysis analysis = SourceAnalysis.Assemble(root, _ => null);
            IReadOnlyDictionary<string, Retrocore.Assembler.AssemblySymbol> historical = analysis.Result.HistoricalNames;
            HashSet<string> defined = [.. analysis.Definitions.Select(site => site.Name)];
            foreach (string member in analysis.Members)
            {
                string[] lines = analysis.LinesOf(member);
                bool strict = lines.Any(line => line.StartsWith("; retrocore: style=strict", StringComparison.Ordinal));
                if (!strict) { continue; }
                foreach ((int line, int _, string name) in SourceText.CodeNames(lines))
                {
                    if (!historical.TryGetValue(name, out Retrocore.Assembler.AssemblySymbol? symbol)
                        || defined.Contains(name)
                        || analysis.Bound(name, member, line) is not null)
                    {
                        continue;
                    }

                    found.Add($"{Path.GetFileName(member)}:{line + 1}: {name} is a historical name of {symbol.Name}");
                }
            }
        }

        found.Should().BeEmpty($"converted code uses the current names:{Environment.NewLine}{string.Join(Environment.NewLine, found.Order())}");
    }

    /// <summary>
    ///  A historical name both IIe firmwares give a definition cites the same documents in each, as one routine's
    ///  lineage cites every listing that names it (docs/ConvertingSources.md).
    /// </summary>
    [TestMethod]
    public void FirmwareLineagesCiteBothListings()
    {
        Dictionary<string, HashSet<string>> original = AlsoKeys("Firmware.Original");
        Dictionary<string, HashSet<string>> enhanced = AlsoKeys("Firmware.Enhanced");
        List<string> differ = [];
        foreach ((string name, HashSet<string> keys) in original)
        {
            if (s_firmwareOwnNames.Contains(name) || !enhanced.TryGetValue(name, out HashSet<string>? other))
            {
                continue;
            }

            if (!keys.SetEquals(other))
            {
                differ.Add($"{name}: original ({string.Join(", ", keys.Order())}), Enhanced ({string.Join(", ", other.Order())})");
            }
        }

        differ.Should().BeEmpty($"both firmwares cite a shared name alike:{Environment.NewLine}{string.Join(Environment.NewLine, differ)}");
    }

    // Each historical name a model's firmware gives, with the documents its definitions cite for it.
    private static Dictionary<string, HashSet<string>> AlsoKeys(string model)
    {
        string system = Path.Join(s_inputs, "System");
        Dictionary<string, HashSet<string>> names = [with(StringComparer.Ordinal)];
        IEnumerable<string> files = Directory.EnumerateFiles(Path.Join(system, model), "*.asm")
            .Append(Path.Join(system, $"{model}.asm"));

        foreach (string line in files.SelectMany(File.ReadLines).Where(line => line.StartsWith(";; Also:", StringComparison.Ordinal)))
        {
            foreach (Match match in AlsoName().Matches(line))
            {
                if (!names.TryGetValue(match.Groups[1].Value, out HashSet<string>? keys))
                {
                    names[match.Groups[1].Value] = keys = [with(StringComparer.Ordinal)];
                }

                keys.UnionWith(match.Groups[2].Value.Split(',', StringSplitOptions.TrimEntries));
            }
        }

        return names;
    }

    // A historical name and its document keys in an Also: line, as NAME (KEY1, KEY2).
    [GeneratedRegex(@"([A-Za-z_0-9]+) \(([^)]*)\)")]
    private static partial Regex AlsoName();
}
