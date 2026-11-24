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
internal static class BasicNames
{
    private static readonly AsyncLocal<string?> s_inputs = new();

    // The names each historical name of the native BASIC builds is defined by now, by inputs folder.
    private static readonly ConcurrentDictionary<string, Lazy<IReadOnlyDictionary<string, IReadOnlyDictionary<string, string[]>>>>
        s_current = new(StringComparer.Ordinal);

    // The three AppleSoft and five PET BASIC native builds, by the key each build's names are kept under.
    private static readonly (string Key, Apple2Model? Apple, PetModel Pet, bool Original)[] s_builds =
    [
        (Build(Apple2Model.IIPlus), Apple2Model.IIPlus, default, false),
        (Build(Apple2Model.IIe), Apple2Model.IIe, default, false),
        (Build(Apple2Model.IIeEnhanced), Apple2Model.IIeEnhanced, default, false),
        (Build(PetModel.Pet2001, original: false), null, PetModel.Pet2001, false),
        (Build(PetModel.Pet2001, original: true), null, PetModel.Pet2001, true),
        (Build(PetModel.Pet2001Basic2, original: false), null, PetModel.Pet2001Basic2, false),
        (Build(PetModel.Pet4032, original: false), null, PetModel.Pet4032, false),
        (Build(PetModel.Pet4032, original: true), null, PetModel.Pet4032, true),
    ];

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
    ///  <para>
    ///   An old name that the builds give to different definitions would add every build's name, so another build's
    ///   name could reach the assembly; it is an error here, and a test that predefines it names the build it
    ///   assembles with an overload that takes the build. An old name only some builds give, such as AppleSoft's
    ///   TEXTAB, adds those builds' name in any build's assembly.
    ///  </para>
    /// </remarks>
    /// <param name="symbols">The predefined symbols, by the names Microsoft's source has.</param>
    /// <returns>
    ///  The predefined symbols with the current names added, except those inside a scope, which
    ///  <see cref="ScopedNames"/> defines.
    /// </returns>
    /// <exception cref="InvalidOperationException">The builds give an old name to different definitions.</exception>
    internal static Dictionary<string, long> WithCurrentNames(IReadOnlyDictionary<string, long> symbols) =>
        WithCurrentNames(symbols, Tables(), build: null);

    /// <summary>
    ///  Gets the predefined symbols for a standalone build of shared modules, under the names they have and under the
    ///  names one native BASIC build now defines them by, except those inside a scope.
    /// </summary>
    /// <param name="symbols">The predefined symbols, by the names Microsoft's source has.</param>
    /// <param name="build">The build whose names to add, from a <c>Build</c> overload.</param>
    /// <returns>The predefined symbols with the build's current names added.</returns>
    /// <exception cref="ArgumentException">The build is not a native BASIC build.</exception>
    internal static Dictionary<string, long> WithCurrentNames(IReadOnlyDictionary<string, long> symbols, string build) =>
        WithCurrentNames(symbols, Tables(), build);

    /// <summary>
    ///  Adds current names, except those inside a scope, to predefined symbols from given tables of each build's
    ///  historical names: the names one build defines them by, or with no build the names the builds that give an
    ///  old name agree on, failing on a name they give to different definitions.
    /// </summary>
    /// <param name="symbols">The predefined symbols, by their old names.</param>
    /// <param name="byBuild">Each build's current names for its historical names, by build key.</param>
    /// <param name="build">The build whose names to add; null for all of them.</param>
    /// <returns>The predefined symbols with the current names added.</returns>
    internal static Dictionary<string, long> WithCurrentNames(
        IReadOnlyDictionary<string, long> symbols,
        IReadOnlyDictionary<string, IReadOnlyDictionary<string, string[]>> byBuild,
        string? build)
    {
        return new(CurrentNamesOf(symbols, byBuild, build).Where(pair => !IsScoped(pair.Key)), StringComparer.Ordinal);
    }

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
        foreach ((string name, long value) in CurrentNamesOf(symbols, Tables(), build: null)
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
    private static readonly string[] s_families = ["Float", "Functions"];

    private static bool IsScoped(string name) => name.Contains("::", StringComparison.Ordinal);

    // The symbols with every current name of each added, as WithCurrentNames describes.
    private static Dictionary<string, long> CurrentNamesOf(
        IReadOnlyDictionary<string, long> symbols,
        IReadOnlyDictionary<string, IReadOnlyDictionary<string, string[]>> byBuild,
        string? build)
    {
        Dictionary<string, long> names = new(symbols, StringComparer.Ordinal);
        Dictionary<string, string> added = [with(StringComparer.Ordinal)];
        foreach ((string name, long value) in symbols)
        {
            foreach (string current in CurrentNames(name, byBuild, build).Where(current => !symbols.ContainsKey(current)))
            {
                if (added.TryGetValue(current, out string? first) && names[current] != value)
                {
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
    ///  label at the same place under every name the native BASIC builds now define it by, so the modules reach it
    ///  whether they use the old name or the new one.
    /// </summary>
    /// <param name="name">The label, as Microsoft's source has it.</param>
    /// <returns>The label definitions, one per line.</returns>
    /// <exception cref="InvalidOperationException">The builds give the name to different definitions.</exception>
    internal static string Label(string name) =>
        string.Join('\n', CurrentNames(name).Prepend(name).Select(label => $"{label}:"));

    /// <summary>
    ///  Gets the names the native BASIC builds define an old name by now, through their <c>;; Also:</c> sections.
    /// </summary>
    /// <param name="name">The old name.</param>
    /// <returns>The current names; empty when no build gives the name as a historical name.</returns>
    /// <exception cref="InvalidOperationException">The builds give the name to different definitions.</exception>
    internal static IReadOnlyList<string> CurrentNames(string name) => CurrentNames(name, Tables(), build: null);

    /// <summary>
    ///  Gets the key of an AppleSoft native build, for <see cref="WithCurrentNames(IReadOnlyDictionary{string, long}, string)"/>.
    /// </summary>
    /// <param name="model">The Apple II model whose AppleSoft the build is.</param>
    /// <returns>The key.</returns>
    internal static string Build(Apple2Model model) => $"AppleSoft {model}";

    /// <summary>
    ///  Gets the key of a PET BASIC native build, for <see cref="WithCurrentNames(IReadOnlyDictionary{string, long}, string)"/>.
    /// </summary>
    /// <param name="model">The PET model whose BASIC the build is.</param>
    /// <param name="original">Whether it is the original rather than the revised ROM.</param>
    /// <returns>The key.</returns>
    internal static string Build(PetModel model, bool original) => original ? $"PET {model} original" : $"PET {model}";

    /// <summary>
    ///  Gets each native BASIC build's current names for its historical names, by build key.
    /// </summary>
    /// <returns>The tables.</returns>
    internal static IReadOnlyDictionary<string, IReadOnlyDictionary<string, string[]>> CurrentNamesByBuild() => Tables();

    private static IReadOnlyDictionary<string, IReadOnlyDictionary<string, string[]>> Tables() =>
        s_current.GetOrAdd(Inputs, inputs => new(() => CurrentNamesIn(inputs))).Value;

    // The current names one build, or with no build every build, gives an old name; an old name the builds give to
    // different definitions has no names for all builds, only an error.
    private static string[] CurrentNames(
        string name,
        IReadOnlyDictionary<string, IReadOnlyDictionary<string, string[]>> byBuild,
        string? build)
    {
        if (build is not null)
        {
            if (!byBuild.TryGetValue(build, out IReadOnlyDictionary<string, string[]>? table))
            {
                throw new ArgumentException($"{build} is not a native BASIC build.", nameof(build));
            }

            return table.TryGetValue(name, out string[]? own) ? own : [];
        }

        List<string[]> given = [.. byBuild.Values.Where(table => table.ContainsKey(name)).Select(table => table[name])];
        if (given.Count == 0)
        {
            return [];
        }

        if (given.Any(names => !names.SequenceEqual(given[0], StringComparer.Ordinal)))
        {
            List<string> builds = [];
            foreach ((string key, IReadOnlyDictionary<string, string[]> table) in byBuild)
            {
                if (table.TryGetValue(name, out string[]? targets))
                {
                    builds.Add(key + ": " + string.Join(' ', targets));
                }
            }

            string each = string.Join(", ", builds);
            throw new InvalidOperationException($"{name} names different definitions in different builds ({each}); predefine it for one build.");
        }

        return given[0];
    }

    // Every historical name of the three AppleSoft and five PET BASIC native builds, with the definitions it names in
    // each build.
    private static Dictionary<string, IReadOnlyDictionary<string, string[]>> CurrentNamesIn(string inputs)
    {
        Dictionary<string, IReadOnlyDictionary<string, string[]>> byBuild = [with(StringComparer.Ordinal)];
        foreach ((string key, Apple2Model? apple, PetModel pet, bool original) in s_builds)
        {
            AssemblyResult build;
            if (apple is Apple2Model model)
            {
                build = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(inputs), model);
            }
            else
            {
                build = PetSdkModules.AssembleBasic(Path.Join(inputs, "Pet"), pet, original);
            }

            build.Success.Should().BeTrue(string.Join(Environment.NewLine, build.Diagnostics.Select(d => d.Message)));

            Dictionary<string, SortedSet<string>> own = [with(StringComparer.Ordinal)];
            foreach ((string name, AssemblySymbol definition) in build.HistoricalNames)
            {
                if (build.Symbols.ContainsKey(name)) { continue; }
                if (!own.TryGetValue(name, out SortedSet<string>? targets))
                {
                    own[name] = targets = [with(StringComparer.Ordinal)];
                }

                targets.Add(definition.Name);
            }

            byBuild[key] = own.ToDictionary(pair => pair.Key, pair => pair.Value.ToArray(), StringComparer.Ordinal);
        }

        return byBuild;
    }
}
