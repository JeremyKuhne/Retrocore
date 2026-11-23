// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Documentation;
using Retrocore.Machines.Apple2;
using Retrocore.Machines.Commodore;
using System.Collections.Concurrent;

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
    private static readonly ConcurrentDictionary<string, Lazy<IReadOnlyDictionary<string, string[]>>> s_current =
        new(StringComparer.Ordinal);

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
    /// <returns>The predefined symbols with the current names added.</returns>
    internal static Dictionary<string, long> WithCurrentNames(IReadOnlyDictionary<string, long> symbols)
    {
        Dictionary<string, long> names = new(symbols, StringComparer.Ordinal);
        Dictionary<string, string> added = [with(StringComparer.Ordinal)];
        foreach ((string name, long value) in symbols)
        {
            foreach (string current in CurrentNames(name).Where(current => !symbols.ContainsKey(current)))
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
    ///  Gets the source that defines a label a test's own source gives one of Microsoft's names: the label, and a
    ///  label at the same place under every name the native BASIC builds now define it by, so the modules reach it
    ///  whether they use the old name or the new one.
    /// </summary>
    /// <param name="name">The label, as Microsoft's source has it.</param>
    /// <returns>The label definitions, one per line.</returns>
    internal static string Label(string name) =>
        string.Join('\n', CurrentNames(name).Prepend(name).Select(label => $"{label}:"));

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

                targets.Add(definition.Name);
            }
        }

        return names.ToDictionary(pair => pair.Key, pair => pair.Value.ToArray(), StringComparer.Ordinal);
    }
}
