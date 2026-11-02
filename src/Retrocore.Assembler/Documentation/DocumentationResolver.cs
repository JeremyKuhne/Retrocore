// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;

namespace Retrocore.Documentation;

/// <summary>
///  Resolves links, <c>Inherit:</c> and <c>Include:</c> for one assembly's documentation, and checks it.
/// </summary>
/// <remarks>
///  <para>
///   A plain name is looked up in the order <c>docs/DocComments.md</c> gives: the assembler's scopes from the
///   topic outward, the rest of the assembly, the other modules, then directives and instructions. A name found
///   more than once at the same step is ambiguous.
///  </para>
/// </remarks>
public sealed partial class DocumentationResolver
{
    private readonly List<DocumentationSet> _others;
    private readonly Func<string, bool> _isDirective;
    private readonly Func<string, bool> _isInstruction;
    private readonly Func<string, string?> _readText;
    private readonly string? _root;

    /// <summary>
    ///  Creates a resolver.
    /// </summary>
    /// <param name="current">The documentation being resolved and checked.</param>
    /// <param name="others">Other modules links may reach, such as the SDK's ROM sources.</param>
    /// <param name="isDirective">Whether a name is an assembler directive.</param>
    /// <param name="isInstruction">Whether a name is an instruction mnemonic.</param>
    /// <param name="readText">Reads a file for <c>Include:</c> and <c>doc:</c> links, or returns null.</param>
    /// <param name="root">The repository root, the second base for relative paths.</param>
    public DocumentationResolver(
        DocumentationSet current,
        IEnumerable<DocumentationSet>? others = null,
        Func<string, bool>? isDirective = null,
        Func<string, bool>? isInstruction = null,
        Func<string, string?>? readText = null,
        string? root = null)
    {
        Current = current;
        _others = [.. (others ?? []).Where(set => !ReferenceEquals(set, current))];
        _isDirective = isDirective ?? (_ => false);
        _isInstruction = isInstruction ?? (_ => false);
        _readText = readText ?? (path => File.Exists(path) ? File.ReadAllText(path) : null);
        _root = root;
    }

    /// <summary>
    ///  Gets the documentation being resolved.
    /// </summary>
    public DocumentationSet Current { get; }

    /// <summary>
    ///  Maps a condition such as <c>ENHANCED</c> or <c>not ENHNCD</c> to the IIe model it selects.
    /// </summary>
    /// <param name="condition">The condition, or null.</param>
    /// <returns><c>Enhanced</c>, <c>Original</c>, or null when the condition is not a model switch.</returns>
    public static string? ModelOf(string? condition)
    {
        if (condition is null) { return null; }
        bool model = condition.Contains("ENHANCED", StringComparison.OrdinalIgnoreCase)
            || condition.Contains("ENHNCD", StringComparison.OrdinalIgnoreCase);

        if (!model) { return null; }
        return condition.StartsWith("not ", StringComparison.OrdinalIgnoreCase) ? "Original" : "Enhanced";
    }

    /// <summary>
    ///  Resolves a link target written in a topic.
    /// </summary>
    /// <param name="from">The topic the link is in.</param>
    /// <param name="target">The target as written.</param>
    /// <returns>What it resolved to.</returns>
    public DocumentationTarget Resolve(DocumentationTopic from, string target)
    {
        string text = target.Trim();
        bool web = text.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
            || text.StartsWith("https://", StringComparison.OrdinalIgnoreCase);

        if (web)
        {
            return new(DocumentationTargetKind.Url, text) { Address = text };
        }

        if (text.StartsWith("doc:", StringComparison.OrdinalIgnoreCase))
        {
            string relative = text[4..];
            int anchor = relative.IndexOf('#');
            string file = anchor < 0 ? relative : relative[..anchor];
            if (FindFile(from.Path, file) is not { } found) { return new(DocumentationTargetKind.Unresolved, text); }
            string address = anchor < 0 ? found : found + relative[anchor..];
            return new(DocumentationTargetKind.Document, text) { Address = address };
        }

        string? section = null;
        int hash = text.IndexOf('#');
        if (hash > 0)
        {
            section = DocumentationSections.Canonical(text[(hash + 1)..]) ?? text[(hash + 1)..];
            text = text[..hash];
        }

        string? model = null;
        int at = text.LastIndexOf('@');
        if (at > 0 && ModelName(text[(at + 1)..]) is { } named)
        {
            model = named;
            text = text[..at];
        }

        string? module = null;
        int colon = text.IndexOf(':');
        if (colon > 0 && (colon + 1 >= text.Length || text[colon + 1] != ':') && text[colon - 1] != ':')
        {
            module = text[..colon];
            text = text[(colon + 1)..];
        }

        DocumentationTarget result = Lookup(from, text, module, model);
        return section is null ? result : result with { Section = section };
    }

    private DocumentationTarget Lookup(DocumentationTopic from, string name, string? module, string? model)
    {
        if (name.Length == 0) { return new(DocumentationTargetKind.Unresolved, name); }
        IEnumerable<DocumentationSet> sets = Sets(module, model);
        if (name[0] == '$'
            && long.TryParse(name[1..], NumberStyles.HexNumber, CultureInfo.InvariantCulture, out long address))
        {
            foreach (DocumentationSet set in sets)
            {
                if (set.FindAt(address) is { } topic) { return Found(topic); }
            }

            return new(DocumentationTargetKind.Unresolved, name);
        }

        if (name[0] == '.' && _isDirective(name)) { return new(DocumentationTargetKind.Directive, name); }
        foreach (DocumentationSet set in sets)
        {
            if (set.Topics.FirstOrDefault(topic => topic.Kind == DocumentationKind.File
                && topic.Name.Equals(name, StringComparison.OrdinalIgnoreCase)) is { } file)
            {
                return Found(file);
            }
        }

        // The assembler's scope rules, from the topic's scope outward.
        if (module is null && SetsFor(model).Contains(Current))
        {
            foreach (string candidate in Scoped(from.Name, name))
            {
                if (Match(Current, candidate) is { } match) { return match; }
            }
        }

        List<DocumentationTarget> matches = [];
        foreach (DocumentationSet set in sets)
        {
            if (module is null && ReferenceEquals(set, Current)) { continue; }
            if (Match(set, name.StartsWith("::", StringComparison.Ordinal) ? name[2..] : name) is { } match)
            {
                matches.Add(match);
            }
        }

        // The same model-dependent source documented in two builds is one definition.
        // An undocumented symbol with the same value in several modules (an equate such as KBD) is one definition.
        List<DocumentationTarget> distinct = [.. matches.GroupBy(Identity).Select(group => group.First())];

        if (distinct.Count == 1) { return distinct[0]; }
        if (distinct.Count > 1) { return new(DocumentationTargetKind.Ambiguous, name); }
        if (_isInstruction(name)) { return new(DocumentationTargetKind.Instruction, name.ToUpperInvariant()); }
        return new(DocumentationTargetKind.Unresolved, name);
    }

    // A definition is the same one when it is at the same line of a file of the same name with the same value, so
    // an SDK source opened from the repository and the SDK's own copy of it count once.
    private static (string File, int Line, long? Value) Identity(DocumentationTarget target) =>
        target.Topic is { } topic
            ? (Path.GetFileName(topic.Path).ToUpperInvariant(), topic.Line, target.Value)
            : ("", -1, target.Value);

    private static DocumentationTarget? Match(DocumentationSet set, string name)
    {
        if (set.Find(name) is { } topic) { return Found(topic); }
        if (set.Symbols.TryGetValue(name, out long value))
        {
            return new(DocumentationTargetKind.Symbol, name) { Set = set, Value = value };
        }

        return null;
    }

    private static DocumentationTarget Found(DocumentationTopic topic) =>
        new(DocumentationTargetKind.Topic, topic.Name) { Topic = topic, Set = topic.Set, Value = topic.Value };

    // Candidates for a name from a topic: scope::name for each enclosing scope, innermost first, then the root.
    private static IEnumerable<string> Scoped(string from, string name)
    {
        if (name.StartsWith("::", StringComparison.Ordinal))
        {
            yield return name[2..];
            yield break;
        }

        string scope = from;
        while (true)
        {
            int separator = scope.LastIndexOf("::", StringComparison.Ordinal);
            if (separator < 0) { break; }
            scope = scope[..separator];
            yield return $"{scope}::{name}";
        }

        yield return name;
    }

    private IEnumerable<DocumentationSet> Sets(string? module, string? model)
    {
        foreach (DocumentationSet set in SetsFor(model))
        {
            if (module is null || string.Equals(set.Module, module, StringComparison.OrdinalIgnoreCase))
            {
                yield return set;
            }
        }
    }

    private IEnumerable<DocumentationSet> SetsFor(string? model)
    {
        foreach (DocumentationSet set in (DocumentationSet[])[Current, .. _others])
        {
            if (model is null || set.Model is null || set.Model.Equals(model, StringComparison.OrdinalIgnoreCase))
            {
                yield return set;
            }
        }
    }

    private static string? ModelName(string text) =>
        text.Equals("Original", StringComparison.OrdinalIgnoreCase) ? "Original"
            : text.Equals("Enhanced", StringComparison.OrdinalIgnoreCase) ? "Enhanced" : null;

    /// <summary>
    ///  Finds a file relative to the source, then to the repository root.
    /// </summary>
    private string? FindFile(string source, string relative)
    {
        string? directory = Path.GetDirectoryName(source);
        foreach (string? baseDirectory in (string?[])[directory, _root])
        {
            if (baseDirectory is null) { continue; }
            string full = Path.GetFullPath(Path.Join(baseDirectory, relative));
            if (_readText(full) is not null) { return full; }
        }

        return null;
    }
}
