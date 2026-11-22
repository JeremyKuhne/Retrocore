// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  Content-keyed symbol slices, allowing allocation-free lookups on .NET and .NET Standard.
/// </summary>
/// <remarks>
///  <para>
///   Stored keys borrow immutable model strings, while lookup keys may be slices of other expression strings.
///   Equality and hashing therefore use character contents, not memory-owner identity or slice offsets.
///   This supplies the same allocation-free lookup behavior on both supported build targets.
///  </para>
///  <para>
///   Each name also has a dense ID, so recorded expressions read values by index instead of hashing names.
///  </para>
/// </remarks>
internal sealed class AssemblySymbols : IEqualityComparer<ReadOnlyMemory<char>>
{
    private const uint FnvOffsetBasis = 2166136261;
    private const uint FnvPrime = 16777619;

    /// <summary>
    ///  The ID of a name that was never declared, which never resolves.
    /// </summary>
    internal const int Undeclared = -1;

    /// <summary>
    ///  The ID a .set variable resolves to before its first assignment in source order.
    /// </summary>
    internal const int UnassignedVariable = -2;

    /// <summary>
    ///  The ID of a historical name that two definitions give, which never resolves.
    /// </summary>
    internal const int AmbiguousAlias = -3;

    // Version names contain a character no identifier can, so source text never names a version directly.
    private const char VersionSeparator = '#';

    private readonly Dictionary<ReadOnlyMemory<char>, int> _ids;
    private readonly List<string> _names;

    // Symbols in the order they first resolved, which orders the result snapshot.
    private readonly List<int> _resolved;
    private long[] _values;
    private bool[] _known;

    // Created only for sources that use .set: each variable's current version and each version's variable.
    private Dictionary<int, int>? _bindings;
    private Dictionary<int, int>? _versions;
    private List<int>? _variables;
    private Dictionary<int, int>? _versionCounts;

    // Created only for sources with Also: sections: each historical name's definition, or AmbiguousAlias.
    private Dictionary<ReadOnlyMemory<char>, int>? _aliases;
    private Dictionary<string, List<string>>? _ambiguous;

    /// <summary>
    ///  Gets the expression programs recorded against these symbols' IDs.
    /// </summary>
    internal ExpressionPrograms Programs { get; } = new();

    /// <summary>
    ///  Gets whether any .set variable was declared.
    /// </summary>
    internal bool HasVariables => _versions is not null;

    /// <summary>
    ///  Creates an ordinal content-keyed symbol table.
    /// </summary>
    /// <param name="capacity">The known number of declarations, when available.</param>
    internal AssemblySymbols(int capacity = 0)
    {
        _ids = new(capacity, this);
        _names = [with(capacity)];
        _resolved = [with(capacity)];
        _values = new long[capacity];
        _known = new bool[capacity];
    }

    /// <summary>
    ///  Assigns a name its dense ID, or returns the ID it already has.
    /// </summary>
    /// <param name="name">The owned model identifier.</param>
    /// <returns>The name's ID.</returns>
    internal int Declare(string name)
    {
        ReadOnlyMemory<char> key = name.AsMemory();
        if (_ids.TryGetValue(key, out int id)) { return id; }
        id = _names.Count;
        _names.Add(name);
        _ids.Add(key, id);
        if (id == _values.Length)
        {
            Array.Resize(ref _values, Math.Max(id * 2, 4));
            Array.Resize(ref _known, _values.Length);
        }

        return id;
    }

    /// <summary>
    ///  Finds a name's ID without allocating a temporary identifier string.
    /// </summary>
    /// <param name="name">The identifier slice.</param>
    /// <returns>The ID, or <see cref="Undeclared"/>.</returns>
    /// <remarks>A .set variable resolves to the version bound at this point of a source-order walk.</remarks>
    internal int GetId(ReadOnlyMemory<char> name)
    {
        return !_ids.TryGetValue(name, out int id) ? Alias(name)
            : _bindings is not null && _bindings.TryGetValue(id, out int version) ? version : id;
    }

    /// <summary>
    ///  Gives a definition a historical name, from its <c>Also:</c> section, that resolves to it wherever no
    ///  symbol has that name.
    /// </summary>
    /// <param name="name">The historical name.</param>
    /// <param name="id">The definition's ID.</param>
    internal void AddAlias(string name, int id)
    {
        _aliases ??= [with(this)];
        ReadOnlyMemory<char> key = name.AsMemory();
        if (!_aliases.TryGetValue(key, out int existing))
        {
            _aliases.Add(key, id);
            return;
        }

        if (existing == id) { return; }
        _ambiguous ??= [with(StringComparer.Ordinal)];
        if (!_ambiguous.TryGetValue(name, out List<string>? targets))
        {
            targets = [_names[existing]];
            _ambiguous.Add(name, targets);
            _aliases[key] = AmbiguousAlias;
        }

        if (!targets.Contains(_names[id])) { targets.Add(_names[id]); }
    }

    /// <summary>
    ///  Gets the definitions that share a historical name.
    /// </summary>
    /// <param name="name">The historical name.</param>
    /// <returns>The definitions' names, in the order they were given it.</returns>
    internal IReadOnlyList<string> AliasTargets(ReadOnlyMemory<char> name) =>
        _ambiguous is not null && _ambiguous.TryGetValue(name.ToString(), out List<string>? targets) ? targets : [];

    private int Alias(ReadOnlyMemory<char> name) =>
        _aliases is not null && _aliases.TryGetValue(name, out int id) ? id : Undeclared;

    /// <summary>
    ///  Declares the next immutable version of a .set variable.
    /// </summary>
    /// <param name="name">The variable's source name.</param>
    /// <returns>The private version name, which the assignment defines.</returns>
    internal string DeclareVersion(string name)
    {
        int variable = Declare(name);
        _bindings ??= [];
        _versions ??= [];
        _variables ??= [];
        if (!_bindings.ContainsKey(variable))
        {
            _bindings.Add(variable, UnassignedVariable);
            _variables.Add(variable);
        }

        _versionCounts ??= [];
        _versionCounts.TryGetValue(variable, out int count);
        _versionCounts[variable] = ++count;

        string version = $"{name}{VersionSeparator}{count}";
        _versions.Add(Declare(version), variable);
        return version;
    }

    /// <summary>
    ///  Makes later lookups of a variable read the given version, as its assignment is walked.
    /// </summary>
    /// <param name="version">The assigned version's ID.</param>
    internal void Bind(int version)
    {
        if (_versions is not null && _bindings is not null && _versions.TryGetValue(version, out int variable))
        {
            _bindings[variable] = version;
        }
    }

    /// <summary>
    ///  Unbinds every variable at the start of a source-order walk.
    /// </summary>
    internal void ResetBindings()
    {
        if (_variables is null || _bindings is null) { return; }
        foreach (int variable in _variables) { _bindings[variable] = UnassignedVariable; }
    }

    /// <summary>
    ///  Updates a symbol and reports whether layout state changed.
    /// </summary>
    /// <param name="name">The owned model identifier, declared on first use.</param>
    /// <param name="value">The resolved value.</param>
    /// <returns>Whether this symbol was added or changed.</returns>
    internal bool SetValue(string name, long value)
    {
        int id = Declare(name);
        return SetValue(id, value);
    }

    /// <summary>
    ///  Updates an already declared compiler symbol without hashing its name again.
    /// </summary>
    /// <param name="id">The declared symbol ID.</param>
    /// <param name="value">The current value.</param>
    /// <returns>Whether the value became known or changed.</returns>
    internal bool SetValue(int id, long value)
    {
        if (_known[id])
        {
            if (_values[id] == value) { return false; }
        }
        else
        {
            _known[id] = true;
            _resolved.Add(id);
        }

        _values[id] = value;
        return true;
    }

    /// <summary>
    ///  Reads a symbol by ID.
    /// </summary>
    /// <param name="id">The ID; <see cref="Undeclared"/> never resolves.</param>
    /// <param name="value">The resolved value, or zero.</param>
    /// <returns>Whether the symbol has been resolved.</returns>
    internal bool TryGetValue(int id, out long value)
    {
        if ((uint)id < (uint)_names.Count && _known[id])
        {
            value = _values[id];
            return true;
        }

        value = 0;
        return false;
    }

    /// <summary>
    ///  Resolves a source slice without allocating a temporary identifier string.
    /// </summary>
    /// <param name="name">The identifier slice.</param>
    /// <param name="value">The resolved value.</param>
    /// <returns>Whether the symbol has been resolved.</returns>
    internal bool TryGetValue(ReadOnlyMemory<char> name, out long value) => TryGetValue(GetId(name), out value);

    /// <summary>
    ///  Invalidates a preprocessing value without losing its symbol identity.
    /// </summary>
    /// <param name="name">The source-order name whose latest value is unknown.</param>
    internal void Unset(string name)
    {
        int id = Declare(name);
        if (_known[id]) { _resolved.Remove(id); }
        _known[id] = false;
    }

    /// <summary>
    ///  Lists the historical names that reach one resolved definition each.
    /// </summary>
    /// <returns>
    ///  Each name, the definition's name (a <c>.set</c> variable's own, for the version an old name holds), the
    ///  name of the symbol it reaches (the version's, for a variable) and the value the name has.
    /// </returns>
    internal IEnumerable<(string Name, string Target, string Version, long Value)> HistoricalSnapshot()
    {
        if (_aliases is null) { yield break; }
        foreach (KeyValuePair<ReadOnlyMemory<char>, int> alias in _aliases)
        {
            int id = alias.Value;
            if (id < 0 || id >= _known.Length || !_known[id]) { continue; }
            int target = _versions is not null && _versions.TryGetValue(id, out int variable) ? variable : id;
            yield return (alias.Key.ToString(), _names[target], _names[id], _values[id]);
        }
    }

    /// <summary>
    ///  Creates the owned, ordinal-keyed public result dictionary once layout is complete.
    /// </summary>
    /// <returns>The resolved symbols, in the order they first resolved.</returns>
    internal Dictionary<string, long> Snapshot()
    {
        Dictionary<string, long> result = new(_resolved.Count, StringComparer.Ordinal);
        foreach (int id in _resolved)
        {
            if (_versions is not null && _bindings is not null && _versions.TryGetValue(id, out int variable))
            {
                // Only the final version is public, under the variable's own name.
                if (_bindings[variable] == id) { result.Add(_names[variable], _values[id]); }
                continue;
            }

            result.Add(_names[id], _values[id]);
        }

        return result;
    }

    /// <inheritdoc/>
    bool IEqualityComparer<ReadOnlyMemory<char>>.Equals(ReadOnlyMemory<char> x, ReadOnlyMemory<char> y) =>
        x.Span.SequenceEqual(y.Span);

    /// <inheritdoc/>
    int IEqualityComparer<ReadOnlyMemory<char>>.GetHashCode(ReadOnlyMemory<char> obj)
    {
        unchecked
        {
            // FNV-1a over UTF-16 code units matches the ordinal, case-sensitive equality above.
            uint hash = FnvOffsetBasis;
            foreach (char character in obj.Span) { hash = (hash ^ character) * FnvPrime; }
            return (int)hash;
        }
    }
}
