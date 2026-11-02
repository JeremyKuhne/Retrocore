// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  Collision-checked names for Merlin's wider label alphabet and global-label-local contexts.
/// </summary>
internal sealed class MerlinNames
{
    private readonly Dictionary<string, string> _reverse = new(StringComparer.Ordinal);
    private readonly HashSet<string> _plain = new(StringComparer.Ordinal);
    private int _next;
    private readonly HashSet<string> _localDefinitions = new(StringComparer.Ordinal);

    /// <summary>
    ///  Allocates a duplicate colon definition without retargeting references already bound to the first.
    /// </summary>
    /// <param name="name">The source-local label.</param>
    /// <returns>The compiler definition name.</returns>
    internal string DefineLocal(string name)
    {
        string key = $"{Anchor}{name}";
        int suffix = _next++;
        string definition = _localDefinitions.Add(key) ? name : $"{name}_duplicate_{suffix}";
        return Resolve(definition);
    }

    /// <summary>
    ///  Gets aliases from original names, including qualified colon locals, to compiler names.
    /// </summary>
    internal Dictionary<string, string> Aliases { get; } = new(StringComparer.Ordinal);

    /// <summary>
    ///  Gets raw textual equates, collected before processing the file's instructions.
    /// </summary>
    internal Dictionary<string, string> Equates { get; } = new(StringComparer.Ordinal);

    /// <summary>
    ///  Gets or sets the expression expansion bound.
    /// </summary>
    internal int MaximumDepth { get; set; } = 64;

    /// <summary>
    ///  Gets or sets the current ordinary address-label anchor.
    /// </summary>
    internal string Anchor { get; set; } = "";

    /// <summary>
    ///  Resolves a source name, honoring invocation-local macro bindings first.
    /// </summary>
    /// <param name="name">The source spelling.</param>
    /// <param name="locals">Optional invocation-local names.</param>
    /// <returns>A plain compiler identifier.</returns>
    internal string Resolve(string name, Dictionary<string, string>? locals = null)
    {
        if (locals?.TryGetValue(name, out string? local) == true) { return local; }
        string key = name.Length != 0 && name[0] == ':' ? Anchor + name : name;
        if (Aliases.TryGetValue(key, out string? alias)) { return alias; }
        if (AssemblySyntax.IsPlainIdentifier(key))
        {
            if (_reverse.ContainsKey(key))
            {
                throw new AssemblyError(0, $"Merlin label '{key}' collides with a generated alias.");
            }

            _plain.Add(key);
            return key;
        }

        do { alias = $"__merlin_{_next++}"; }
        while (_plain.Contains(alias));

        if (_reverse.ContainsKey(alias)) { throw new AssemblyError(0, "Generated Merlin alias collision."); }
        Aliases.Add(key, alias);
        _reverse.Add(alias, key);
        return alias;
    }

    /// <summary>
    ///  Checks ordinary definitions against aliases allocated earlier.
    /// </summary>
    /// <param name="name">The original definition.</param>
    internal void Define(string name)
    {
        if (AssemblySyntax.IsPlainIdentifier(name) && _reverse.ContainsKey(name))
        {
            throw new AssemblyError(0, $"Merlin label '{name}' collides with a generated alias.");
        }
    }
}
