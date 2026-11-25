// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.RegularExpressions;
using Retrocore.Debug;
using Retrocore.Debug.Language;

namespace Retrocore.Tests;

/// <summary>
///  Checks a converted ROM source keeps that reviews of the conversions kept finding by hand: code written with
///  the current names, and the historical names of a routine both IIe firmwares, or both DOS versions, have cited
///  alike in each.
/// </summary>
[TestClass]
public sealed partial class ConvertedSourceTests
{
    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    // The Apple II sources' modules, as the editor indexes them.
    private static readonly string[] s_folders = ["DiskII", "Dos", "Mouse", "ProgrammersAid", "System"];

    // Names that mean different routines in the two IIe firmwares, each kept on its own model's definition
    // (docs/conversions/Firmware.md, F1), or that sit on different code in the two.
    private static readonly HashSet<string> s_firmwareOwnNames =
        ["TESTFAIL", "BASCALC", "DIAGS", "STAY80", "X_USRET", "X_DC1B", "QUIT2", "CTLGO"];

    // Definitions both DOS versions have whose historical names name only one version's (docs/conversions/Dos.md,
    // X14): DOS 3.3's NSYNC is a byte DOS 3.2's gap length is not kept in, and its BRETRY the 16-sector ROM's $5C, where
    // the 13-sector ROM's reader is at $5D.
    private static readonly HashSet<string> s_dosOwnSymbols = ["Formatter::GapLength", "Boot::READ_OFFSET"];

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

    /// <summary>
    ///  A definition both DOS versions have gives the same historical names in each, as a routine's lineage cites
    ///  every listing that names it (docs/conversions/Dos.md, X14). A routine the two share is one definition, so
    ///  this checks those that differ throughout, which have one for each version.
    /// </summary>
    [TestMethod]
    public void DosLineagesCiteBothVersions()
    {
        Dictionary<string, SortedSet<string>> dos33 = HistoricalNamesBySymbol("Dos33.asm");
        Dictionary<string, SortedSet<string>> dos32 = HistoricalNamesBySymbol("Dos32.asm");
        List<string> differ = [];
        foreach ((string symbol, SortedSet<string> names) in dos33)
        {
            if (s_dosOwnSymbols.Contains(symbol) || !dos32.TryGetValue(symbol, out SortedSet<string>? other) || names.SetEquals(other))
            {
                continue;
            }

            differ.Add($"{symbol}: DOS 3.3 ({string.Join(", ", names)}), DOS 3.2 ({string.Join(", ", other)})");
        }

        differ.Should().BeEmpty($"both DOS versions cite a shared definition alike:{Environment.NewLine}{string.Join(Environment.NewLine, differ.Order())}");
    }

    // The historical names each symbol of a DOS build has, by the symbol's name.
    private static Dictionary<string, SortedSet<string>> HistoricalNamesBySymbol(string root)
    {
        Retrocore.Assembler.AssemblyResult result = SdkModules.AssembleDos(SdkModules.DosPath(root, s_inputs), master: false, year: 1983);
        Dictionary<string, SortedSet<string>> names = result.Symbols.Keys.ToDictionary(name => name, _ => new SortedSet<string>(StringComparer.Ordinal), StringComparer.Ordinal);
        foreach ((string name, Retrocore.Assembler.AssemblySymbol symbol) in result.HistoricalNames)
        {
            if (!names.TryGetValue(symbol.Name, out SortedSet<string>? set))
            {
                names[symbol.Name] = set = [with(StringComparer.Ordinal)];
            }

            set.Add(name);
        }

        return names;
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
