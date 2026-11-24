// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Documentation;
using Retrocore.Machines.Apple2;
using Retrocore.Machines.Commodore;
using System.Collections.Concurrent;
using System.Globalization;
using System.Text.RegularExpressions;

namespace Retrocore.Tests;

/// <summary>
///  Looks Microsoft 6502 BASIC's names up so that a test keeps working when the native sources rename a definition and
///  keep its old name in a <c>;; Also:</c> section.
/// </summary>
/// <remarks>
///  <para>
///   A name is found as a symbol, or else as a historical name (<see cref="AssemblyResult.HistoricalNames"/>), as code
///   resolves it. A name that is neither is not found, so a lookup that should fail still fails.
///  </para>
/// </remarks>
internal static partial class BasicNames
{
    private static readonly AsyncLocal<string?> s_inputs = new();

    // The names each historical name of the native BASIC builds is defined by now, by inputs folder.
    private static readonly ConcurrentDictionary<string, Lazy<IReadOnlyDictionary<string, string[]>>> s_current =
        new(StringComparer.Ordinal);

    /// <summary>
    ///  Gets the names both vendors' historical-names files give, each for its own definition (Basic.md E4): ANDOP, the
    ///  classic collector's steps, which BASIC 4 gives to its array back-link steps, and the unlinked allocator's room
    ///  check, TRYAG3, which BASIC 4 gives to its step before.
    /// </summary>
    internal static string[] BothVendorsNames { get; } =
    [
        "ANDOP", "ARYVA2", "ARYVA3", "ARYVGO", "ARYGET", "GOGO", "DVARTS", "TRYAG3"
    ];

    /// <summary>
    ///  Gets the names a vendor's alias gives in some builds that other builds still give to a label of a vendor's own
    ///  unconverted code, until its part converts it: BASIC 4's GETRTS, which is the output routine's return in
    ///  AppleSoft and BASIC 1 and 2 (Basic.md E3), and AppleSoft's ON, which is BASIC 4's disk-command parser.
    /// </summary>
    internal static string[] VendorLabelNames { get; } = ["GETRTS", "ON"];

    /// <summary>
    ///  Gets the old names that the two vendors give to neighboring definitions, one step apart: AppleSoft's NTHIS2 is
    ///  the PET's NTHIS1 (<c>Tokenize::SkipWord</c>), and AppleSoft's NTHIS3 the PET's NTHIS2 (Basic.md, C).
    /// </summary>
    internal static string[] ShiftedNames { get; } = ["NTHIS1", "NTHIS2"];

    /// <summary>
    ///  Gets whether a build defines a name as a label of a vendor's own code, in the folder of the vendor's historical
    ///  names but outside them, as it does the <see cref="VendorLabelNames"/>.
    /// </summary>
    /// <param name="result">The build.</param>
    /// <param name="name">The name.</param>
    /// <param name="historicalNames">The vendor's historical-names file.</param>
    /// <returns>Whether the name is one of those and its definition is such a label.</returns>
    internal static bool IsVendorLabel(AssemblyResult result, string name, string historicalNames)
    {
        string folder = Path.GetDirectoryName(Path.GetFullPath(historicalNames)) ?? historicalNames;
        return VendorLabelNames.Contains(name)
            && result.FindDefinition(name)?.Location?.Path is { } path
            && Path.GetFullPath(path).StartsWith(folder, StringComparison.OrdinalIgnoreCase)
            && !path.EndsWith(".HistoricalNames.asm", StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    ///  Gets the folder the BASIC tests read their sources from: the test output's <c>Inputs</c>, unless
    ///  <see cref="WithInputs"/> has replaced it for this flow.
    /// </summary>
    internal static string Inputs => s_inputs.Value ?? Path.Join(AppContext.BaseDirectory, "Inputs");

    /// <summary>
    ///  Runs code with the BASIC tests pointed at another copy of their sources.
    /// </summary>
    /// <param name="directory">The replacement for <see cref="Inputs"/>.</param>
    /// <param name="action">The code.</param>
    internal static void WithInputs(string directory, Action action)
    {
        string? previous = s_inputs.Value;
        s_inputs.Value = directory;
        try
        {
            action();
        }
        finally
        {
            s_inputs.Value = previous;
        }
    }

    /// <summary>
    ///  Gets a name's value, as a symbol or as a historical name.
    /// </summary>
    /// <param name="result">The assembly.</param>
    /// <param name="name">The current or historical name.</param>
    /// <returns>The value.</returns>
    /// <exception cref="KeyNotFoundException">The name is neither a symbol nor a historical name.</exception>
    internal static long Symbol(this AssemblyResult result, string name) =>
        result.SymbolsWithHistoricalNames.TryGetValue(name, out long value)
            ? value
            : throw new KeyNotFoundException($"'{name}' is neither a symbol nor a historical name of the assembly.");

    /// <summary>
    ///  Gets whether a name is a symbol or a historical name.
    /// </summary>
    /// <param name="result">The assembly.</param>
    /// <param name="name">The current or historical name.</param>
    /// <returns>Whether the name is found.</returns>
    internal static bool HasSymbol(this AssemblyResult result, string name) =>
        result.SymbolsWithHistoricalNames.ContainsKey(name);

    /// <summary>
    ///  Gets a name's value, as a symbol or as a historical name, when it has one.
    /// </summary>
    /// <param name="result">The assembly.</param>
    /// <param name="name">The current or historical name.</param>
    /// <param name="value">The value.</param>
    /// <returns>Whether the name is found.</returns>
    internal static bool TryGetSymbol(this AssemblyResult result, string name, out long value) =>
        result.SymbolsWithHistoricalNames.TryGetValue(name, out value);

    /// <summary>
    ///  Gets the definition a name reaches: the symbol it names, or the definition whose <c>;; Also:</c> section gives
    ///  it.
    /// </summary>
    /// <param name="result">The assembly.</param>
    /// <param name="name">The current or historical name.</param>
    /// <returns>The definition.</returns>
    /// <exception cref="KeyNotFoundException">The name is neither a symbol nor a historical name.</exception>
    internal static AssemblySymbol Definition(this AssemblyResult result, string name) =>
        result.FindDefinition(name)
            ?? throw new KeyNotFoundException($"'{name}' is neither a symbol nor a historical name of the assembly.");

    /// <summary>
    ///  Gets the definition a name reaches, when it reaches one.
    /// </summary>
    /// <param name="result">The assembly.</param>
    /// <param name="name">The current or historical name.</param>
    /// <returns>The definition, or null when the name is neither a symbol nor a historical name.</returns>
    internal static AssemblySymbol? FindDefinition(this AssemblyResult result, string name)
    {
        if (result.Symbols.ContainsKey(name)) { return Defined(result, name); }

        // An old name's entry has the definition's name and location with the value the name has, which for a .set
        // variable's old name is the version where it was documented, not the variable's last.
        return result.HistoricalNames.TryGetValue(name, out AssemblySymbol? historical) ? historical : null;
    }

    /// <summary>
    ///  Finds a name's documentation: the topic of the definition it names, or else the one topic whose
    ///  <c>;; Also:</c> section gives it in this build.
    /// </summary>
    /// <param name="set">The documentation.</param>
    /// <param name="name">The current or historical name.</param>
    /// <returns>The topic, or null when no topic has the name or several give it.</returns>
    internal static DocumentationTopic? FindTopic(this DocumentationSet set, string name) =>
        set.Find(name) ?? (set.FindAlso(name, thisBuild: true) is [DocumentationTopic topic] ? topic : null);

    /// <summary>
    ///  Finds the routine a label enters, as <see cref="DocumentationSet.FindRoutine"/> does, or else the topic a
    ///  historical name reaches.
    /// </summary>
    /// <param name="set">The documentation.</param>
    /// <param name="name">The current or historical label.</param>
    /// <returns>The topic, or null.</returns>
    internal static DocumentationTopic? FindRoutineTopic(this DocumentationSet set, string name) =>
        set.FindRoutine(name) ?? set.FindTopic(name);

    /// <summary>
    ///  Gets the value another build, such as the MACRO-10 oracle, gives one of this build's definitions: by the
    ///  definition's name, or else by one of the historical names its <c>;; Also:</c> section gives it.
    /// </summary>
    /// <param name="other">The other build.</param>
    /// <param name="result">The build that has the definition.</param>
    /// <param name="definition">The definition's name in <paramref name="result"/>.</param>
    /// <param name="value">The other build's value.</param>
    /// <returns>Whether the other build has the definition by any of its names.</returns>
    internal static bool TryGetCounterpart(this AssemblyResult other, AssemblyResult result, string definition, out long value)
    {
        // The old names come first: a new name could be another of Microsoft's.
        foreach ((string name, AssemblySymbol target) in result.HistoricalNames.OrderBy(pair => pair.Key, StringComparer.Ordinal))
        {
            if (string.Equals(target.Name, definition, StringComparison.Ordinal) && other.TryGetSymbol(name, out value))
            {
                return true;
            }
        }

        return other.TryGetSymbol(definition, out value);
    }

    private static AssemblySymbol Defined(AssemblyResult result, string name) =>
        result.SymbolDefinitions.Single(symbol => string.Equals(symbol.Name, name, StringComparison.Ordinal));

    /// <summary>
    ///  Gets the name a definition has now, from its current or historical name.
    /// </summary>
    /// <param name="result">The assembly.</param>
    /// <param name="name">The current or historical name.</param>
    /// <returns>The definition's name.</returns>
    internal static string DefinitionName(this AssemblyResult result, string name) => result.Definition(name).Name;

    /// <summary>
    ///  Gets the predefined symbols for a standalone build of shared modules, under the names they have and under
    ///  every name the native BASIC builds now define them by.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   A test takes the values from another build, usually the MACRO-10 oracle, by Microsoft's names. The modules
    ///   reach each value by its old name or by the name a rename gave it. A name given explicitly keeps its value;
    ///   two old names that give one current name different values are an error.
    ///  </para>
    /// </remarks>
    /// <param name="symbols">The predefined symbols, by the names Microsoft's source has.</param>
    /// <returns>
    ///  The predefined symbols with the current names added, except those inside a scope, which
    ///  <see cref="ScopedNames"/> defines.
    /// </returns>
    internal static Dictionary<string, long> WithCurrentNames(IReadOnlyDictionary<string, long> symbols) =>
        new(CurrentNamesOf(symbols).Where(pair => !IsScoped(pair.Key)), StringComparer.Ordinal);

    /// <summary>
    ///  Gets the predefined symbols as <see cref="WithCurrentNames(IReadOnlyDictionary{string, long})"/> does, but
    ///  with only the current names one build has: another build's name for an old one, as ZeroValue is ZERO's where
    ///  BASIC 1 keeps ZERO elsewhere, would be a second definition in a part of that build.
    /// </summary>
    /// <param name="symbols">The predefined symbols, by the names Microsoft's source has.</param>
    /// <param name="build">The build whose names to keep.</param>
    /// <returns>The predefined symbols with the build's current names added.</returns>
    internal static Dictionary<string, long> WithCurrentNames(IReadOnlyDictionary<string, long> symbols, AssemblyResult build) =>
        new(WithCurrentNames(symbols).Where(pair => symbols.ContainsKey(pair.Key) || build.HasSymbol(pair.Key)), StringComparer.Ordinal);

    /// <summary>
    ///  Gets the source that defines, for a standalone build, the current names <see cref="WithCurrentNames(IReadOnlyDictionary{string, long})"/> cannot
    ///  predefine: those inside a scope, such as <c>Float::LoadArg</c>, each a constant in a piece of its scope.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The source declares the families as MsBasic.Families.asm does, under the same guard, unless that file came
    ///   first, so it may go before or after the modules' includes. A scope inside a family, a routine's, is opened
    ///   here, so the build must not define that routine itself.
    ///  </para>
    /// </remarks>
    /// <param name="symbols">The predefined symbols, by the names Microsoft's source has.</param>
    /// <returns>The declarations and definitions, one per line.</returns>
    internal static string ScopedNames(IReadOnlyDictionary<string, long> symbols)
    {
        List<string> source = [".ifndef FAMILIES_DECLARED", "FAMILIES_DECLARED = 1"];
        source.AddRange(s_families.SelectMany(family => (string[])[$".scope {family}", ".endscope"]));
        source.Add(".endif");
        string[] open = [];
        foreach ((string name, long value) in CurrentNamesOf(symbols)
            .Where(pair => IsScoped(pair.Key))
            .OrderBy(pair => pair.Key, StringComparer.Ordinal))
        {
            string[] parts = name.Split("::");
            string[] scopes = parts[..^1];
            int shared = 0;
            while (shared < open.Length && shared < scopes.Length && open[shared] == scopes[shared]) { shared++; }

            for (int depth = open.Length; depth > shared; depth--) { source.Add(".endscope"); }
            for (int depth = shared; depth < scopes.Length; depth++)
            {
                bool family = depth == 0 && s_families.Contains(scopes[0]);
                source.Add(family ? $".scope {scopes[0]} continued" : $".scope {scopes[depth]}");
            }

            source.Add(string.Create(CultureInfo.InvariantCulture, $"{parts[^1]} = ${value:X4}"));
            open = scopes;
        }

        for (int depth = open.Length; depth > 0; depth--) { source.Add(".endscope"); }
        return string.Join('\n', source);
    }

    // The scopes MsBasic.Families.asm declares.
    private static readonly string[] s_families = ["Float", "Functions", "Statements", "Operators", "Strings", "Variables"];

    private static bool IsScoped(string name) => name.Contains("::", StringComparison.Ordinal);

    // The symbols with every current name of each added, as WithCurrentNames describes.
    private static Dictionary<string, long> CurrentNamesOf(IReadOnlyDictionary<string, long> symbols)
    {
        Dictionary<string, long> names = new(symbols, StringComparer.Ordinal);
        Dictionary<string, string> added = [with(StringComparer.Ordinal)];
        HashSet<string> ambiguous = [with(StringComparer.Ordinal)];

        // An old name that names different definitions in different builds (ANDOP: the PET's And, AppleSoft's Or)
        // goes last, and gives way where another old name names only that definition.
        // A name another build's vendor label gives (VendorLabelNames) goes after every other, and gives way.
        foreach ((string name, long value) in symbols
            .OrderBy(pair => VendorLabelNames.Contains(pair.Key) ? 1 : 0)
            .ThenBy(pair => CurrentNames(pair.Key).Count))
        {
            bool perBuild = CurrentNames(name).Count > 1 || VendorLabelNames.Contains(name);
            foreach (string current in CurrentNames(name)
                .Where(current => !symbols.ContainsKey(current) && !ambiguous.Contains(current)))
            {
                if (added.TryGetValue(current, out string? first) && names[current] != value)
                {
                    // The vendors' shifted names (ShiftedNames) cannot tell which build's definition a current name
                    // is, so it is left out, and a source that needs it fails as unresolved rather than taking either.
                    if (ShiftedNames.Contains(first) && ShiftedNames.Contains(name))
                    {
                        names.Remove(current);
                        ambiguous.Add(current);
                        continue;
                    }

                    // Per-build names go last: a name that means another definition in another build gives way to
                    // one that names only this definition, and a vendor label's name gives way to any.
                    bool givesWay = CurrentNames(first).Count == 1 || VendorLabelNames.Contains(name);
                    if (perBuild && givesWay) { continue; }

                    throw new InvalidOperationException(
                        $"{first} and {name} are both old names of {current}, with different values.");
                }

                names[current] = value;
                added[current] = name;
            }
        }

        return names;
    }

    /// <summary>
    ///  Gets predefined symbols exactly as given, without the current names <see cref="WithCurrentNames(IReadOnlyDictionary{string, long})"/> adds: for
    ///  a test of what a build does with an old name predefined by itself.
    /// </summary>
    /// <param name="symbols">The predefined symbols.</param>
    /// <returns>A copy of the symbols.</returns>
    internal static Dictionary<string, long> AsGiven(IReadOnlyDictionary<string, long> symbols) =>
        new(symbols, StringComparer.Ordinal);

    /// <summary>
    ///  Gets the source that defines a label a test's own source gives one of Microsoft's names: the label, and a
    ///  label at the same place under every unscoped name the native BASIC builds now define it by, so the modules
    ///  reach it whether they use the old name or the new one.
    /// </summary>
    /// <param name="name">The label, as Microsoft's source has it.</param>
    /// <returns>The label definitions, one per line.</returns>
    /// <remarks>
    ///  <para>
    ///   A current name inside a scope cannot be a label here; <see cref="ScopedNames"/> defines it.
    ///  </para>
    /// </remarks>
    internal static string Label(string name) =>
        string.Join('\n', CurrentNames(name).Where(current => !IsScoped(current)).Prepend(name).Select(label => $"{label}:"));

    /// <summary>
    ///  Gets the source that defines a label a test's own source gives one of Microsoft's names, under the unscoped
    ///  names the native BASIC builds now define it by, or under the old name where they define none. Unlike
    ///  <see cref="Label(string)"/>, it never defines an old name that an <c>;; Also:</c> in the build's sources gives,
    ///  which the documentation would report as a second definition.
    /// </summary>
    /// <param name="name">The label, as Microsoft's source has it.</param>
    /// <returns>The label definitions, one per line.</returns>
    internal static string CurrentLabel(string name)
    {
        string[] current = [.. CurrentNames(name).Where(current => !IsScoped(current))];
        return string.Join('\n', (current.Length == 0 ? [name] : current).Select(label => $"{label}:"));
    }

    /// <summary>
    ///  Gets the names the native BASIC builds define an old name by now, through their <c>;; Also:</c> sections.
    /// </summary>
    /// <param name="name">The old name.</param>
    /// <returns>The current names; empty when no build gives the name as a historical name.</returns>
    internal static IReadOnlyList<string> CurrentNames(string name) =>
        s_current.GetOrAdd(Inputs, inputs => new(() => CurrentNamesIn(inputs))).Value.TryGetValue(name, out string[]? names)
            ? names
            : [];

    // Every historical name of the three AppleSoft and five PET BASIC native builds, with the definitions it names.
    private static Dictionary<string, string[]> CurrentNamesIn(string inputs)
    {
        Apple2Model[] models = [Apple2Model.IIPlus, Apple2Model.IIe, Apple2Model.IIeEnhanced];
        (PetModel Model, bool Original)[] pets =
        [
            (PetModel.Pet2001, false), (PetModel.Pet2001, true), (PetModel.Pet2001Basic2, false),
            (PetModel.Pet4032, false), (PetModel.Pet4032, true)
        ];

        List<AssemblyResult> builds =
        [
            .. models.Select(model => SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(inputs), model)),
            .. pets.Select(pet => PetSdkModules.AssembleBasic(Path.Join(inputs, "Pet"), pet.Model, pet.Original))
        ];

        Dictionary<string, SortedSet<string>> names = [with(StringComparer.Ordinal)];
        foreach (AssemblyResult build in builds)
        {
            build.Success.Should().BeTrue(string.Join(Environment.NewLine, build.Diagnostics.Select(d => d.Message)));
            foreach ((string name, AssemblySymbol definition) in build.HistoricalNames)
            {
                if (build.Symbols.ContainsKey(name)) { continue; }
                if (!names.TryGetValue(name, out SortedSet<string>? targets))
                {
                    names[name] = targets = [with(StringComparer.Ordinal)];
                }

                // A vendor's alias (AppleSoft::PopFinish = Statements::PopFinish) is how the build reaches the name;
                // the modules define and use its target, so a standalone build predefines that.
                targets.Add(AliasTarget(definition) ?? definition.Name);
            }
        }

        return names.ToDictionary(pair => pair.Key, pair => pair.Value.ToArray(), StringComparer.Ordinal);
    }

    /// <summary>
    ///  Gets whether a vendor's historical names file (AppleSoft's or Commodore's) gives an old name, through an
    ///  alias: a standalone build of a shared module, which does not include that file, does not define it.
    /// </summary>
    /// <param name="name">The old name.</param>
    /// <returns><see langword="true"/> for a vendor's name.</returns>
    internal static bool IsVendorName(string name) =>
        s_vendor.GetOrAdd(Inputs, inputs => new(() => VendorNamesIn(inputs))).Value.Contains(name);

    /// <summary>
    ///  Gets whether a build includes a vendor's historical names file, as the whole AppleSoft and PET builds do and a
    ///  standalone build of a shared module does not.
    /// </summary>
    /// <param name="result">The build.</param>
    /// <returns><see langword="true"/> when one of the build's definitions is in a historical names file.</returns>
    internal static bool IncludesHistoricalNames(AssemblyResult result) =>
        result.SymbolDefinitions.Any(symbol =>
            symbol.Location?.Path.EndsWith(".HistoricalNames.asm", StringComparison.OrdinalIgnoreCase) == true);

    // The vendor's names by inputs folder.
    private static readonly ConcurrentDictionary<string, Lazy<HashSet<string>>> s_vendor = new(StringComparer.Ordinal);

    private static HashSet<string> VendorNamesIn(string inputs)
    {
        HashSet<string> names = [with(StringComparer.Ordinal)];
        foreach (string path in (string[])
            [
                Path.Join(inputs, "AppleSoft", "AppleSoft.HistoricalNames.asm"),
                Path.Join(inputs, "Pet", "Basic", "Commodore.HistoricalNames.asm")
            ])
        {
            DocumentationFile file = DocumentationParser.Parse(File.ReadAllText(path), path);
            names.UnionWith(file.Comments.SelectMany(comment => DocumentationAlso.Of(comment.Sections)).Select(also => also.Name));
        }

        return names;
    }

    /// <summary>
    ///  The labels only the SDK's own MACRO-10 overlays give, which no document names and the rename table gives no
    ///  <c>;; Also:</c> (Basic.md B2), with the definition at each one's address in the native builds that have it.
    /// </summary>
    internal static IReadOnlyDictionary<string, string> OverlayOnlyLabels => s_overlayOnlyLabels;

    private static readonly Dictionary<string, string> s_overlayOnlyLabels = new(StringComparer.Ordinal)
    {
        ["LENFLT"] = "Functions::Len::ToFloat"
    };

    /// <summary>
    ///  Gets the definition a name reaches in a build, following a vendor's alias in its historical names file to the
    ///  definition it names.
    /// </summary>
    /// <param name="result">The build.</param>
    /// <param name="name">The name, current or old.</param>
    /// <returns>The definition the shared or vendor code makes.</returns>
    internal static AssemblySymbol DefiningSymbol(AssemblyResult result, string name)
    {
        AssemblySymbol definition = result.Definition(name);
        return AliasTarget(definition) is { } target ? result.Definition(target) : definition;
    }

    // The target of an alias in a vendor's historical names file, from its line (Name = Target or Name = ::Target).
    private static string? AliasTarget(AssemblySymbol definition)
    {
        if (definition.Location is not { } location
            || !location.Path.EndsWith(".HistoricalNames.asm", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        string line = File.ReadLines(location.Path).ElementAt(location.Line);
        Match match = AliasLine().Match(line);
        return match.Success
            ? match.Groups["target"].Value
            : throw new InvalidOperationException($"{location.Path}:{location.Line + 1} is not an alias line: {line}");
    }

    [GeneratedRegex(@"^\s*\w+\s*=\s*(::)?(?<target>[A-Za-z_]\w*(::\w+)*)\s*$")]
    private static partial Regex AliasLine();
}
