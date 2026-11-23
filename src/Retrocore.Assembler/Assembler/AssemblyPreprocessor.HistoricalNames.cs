// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal sealed partial class AssemblyPreprocessor
{
    // Each source's Also: sections, read once when it is first processed; null for a source with none.
    private readonly Dictionary<string, AssemblyAlsoNames?> _alsoNames = [with(StringComparer.Ordinal)];

    // The definitions each historical name declared so far reaches, by qualified name.
    private Dictionary<string, List<string>>? _historicalNames;

    // A historical name that two definitions give, found while evaluating a condition; reported by TestCondition.
    private string? _nameAmbiguity;

    // An ambiguity found expanding a condition's line, reported where the condition is tested.
    private string? _conditionAmbiguity;

    // The target the first definition of each macro body line with old names declared, or null once a second has:
    // a line expanded more than once gives its old names to none of its definitions.
    private Dictionary<(string Path, int Line), string?>? _expandedTargets;

    /// <summary>
    ///  Reads a source's <c>Also:</c> sections the first time it is processed.
    /// </summary>
    /// <param name="source">The source.</param>
    private void ReadHistoricalNames(AssemblySource source)
    {
        if (!_alsoNames.ContainsKey(source.Path)) { _alsoNames[source.Path] = AssemblyAlsoNames.Collect([source]); }
    }

    /// <summary>
    ///  Records the historical names a just-declared definition gives itself, as the assembler's symbol table will,
    ///  so conditionals see them as code does.
    /// </summary>
    /// <param name="node">The declaring statement.</param>
    /// <param name="qualified">The definition's qualified name.</param>
    /// <returns>For a <c>.set</c> with old names, the private name holding this value; otherwise null.</returns>
    private string? RecordHistoricalNames(AssemblyStatement node, string qualified)
    {
        if (node.Location is not { } location
            || !_alsoNames.TryGetValue(location.Path, out AssemblyAlsoNames? names)
            || names is null
            || names.Of(location) is not { Count: > 0 } historical)
        {
            return null;
        }

        if (location.IsMacroExpansion && !FirstExpansion(location, historical)) { return null; }

        // The assembler aliases a .set variable's version at this line, not the variable.
        string? snapshot = null;
        if (node.Kind == AssemblyStatementKind.Variable)
        {
            snapshot = $"{PrivatePrefix}also_{_project.Statements.Count}";
            _defined.Add(snapshot);
        }

        string target = snapshot ?? qualified;
        (string, int) line = (location.Path, location.Line);
        if (location.IsMacroExpansion && _expandedTargets is not null) { _expandedTargets[line] = target; }
        foreach (string name in historical)
        {
            _historicalNames ??= [with(StringComparer.Ordinal)];
            if (!_historicalNames.TryGetValue(name, out List<string>? targets))
            {
                _historicalNames[name] = targets = [];
            }

            if (!targets.Contains(target)) { targets.Add(target); }
        }

        return snapshot;
    }

    // Whether a macro body line's definition is the first the build declares there. At the second, the first one's
    // old names stop reaching it, so conditionals after that see none, as the assembler, which knows every
    // expansion, gives none; a condition between the two saw them.
    private bool FirstExpansion(AssemblyLocation location, IReadOnlyList<string> historical)
    {
        _expandedTargets ??= [];
        (string, int) line = (location.Path, location.Line);
        if (!_expandedTargets.TryGetValue(line, out string? first))
        {
            _expandedTargets[line] = null;
            return true;
        }

        if (first is null) { return false; }
        _expandedTargets[line] = null;
        foreach (string name in historical)
        {
            List<string>? targets = null;
            if (_historicalNames?.TryGetValue(name, out targets) != true || targets is null) { continue; }
            targets.Remove(first);
            if (targets.Count == 0) { _historicalNames?.Remove(name); }
        }

        return false;
    }

    /// <summary>
    ///  Resolves a plain name no symbol has to the definition whose <c>Also:</c> section gives it.
    /// </summary>
    /// <param name="name">The plain name.</param>
    /// <returns>The definition's qualified name, or null when the name is no definition's historical name.</returns>
    private string? HistoricalTarget(string name)
    {
        if (_historicalNames is null || _defined.Contains(name)) { return null; }
        if (!_historicalNames.TryGetValue(name, out List<string>? targets)) { return null; }
        if (targets.Count == 1) { return targets[0]; }
        _nameAmbiguity = $"'{name}' is a historical name of {string.Join(" and ", targets)}: use one of those.";
        return null;
    }
}
