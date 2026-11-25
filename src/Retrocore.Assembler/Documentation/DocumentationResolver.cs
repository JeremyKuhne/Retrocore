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
    // The current set, then the others: every set a link may reach, in the order lookups search them.
    private readonly DocumentationSet[] _sets;
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
        _sets = [current, .. (others ?? []).Where(set => !ReferenceEquals(set, current))];
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
    ///  Gets the documents that <c>Also:</c> entries cite, or null to leave their keys unchecked.
    /// </summary>
    public DocumentationBibliography? Bibliography { get; init; }

    /// <summary>
    ///  Gets a predicate for prose names that need no link, given the comment's path and the name.
    /// </summary>
    public Func<string, string, bool>? IgnoreUnlinkedName { get; init; }

    /// <summary>
    ///  Maps a condition such as <c>ENHANCED</c> or <c>not ENHNCD</c> to the IIe model it selects.
    /// </summary>
    /// <param name="condition">The condition, or null.</param>
    /// <returns><c>Enhanced</c>, <c>Original</c>, or null when the condition is not a model switch.</returns>
    public static string? ModelOf(string? condition)
    {
        if (condition is null) { return null; }

        // In a joined condition ("MONITOR = MONITOR_IIE and not ENHANCED") the part that names the switch decides.
        foreach (string part in condition.Split(" and ", StringSplitOptions.TrimEntries))
        {
            bool model = part.Contains("ENHANCED", StringComparison.OrdinalIgnoreCase)
                || part.Contains("ENHNCD", StringComparison.OrdinalIgnoreCase);

            if (model) { return part.StartsWith("not ", StringComparison.OrdinalIgnoreCase) ? "Original" : "Enhanced"; }
        }

        return null;
    }

    /// <summary>
    ///  Gets whether a conditional section applies to a build: one the IIe model switch selects for its model, or one
    ///  whose condition holds for the symbol values the build was assembled with, such as <c>MODEL = 1</c>.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The condition is as the parser records it: tests joined by <c>and</c>, each perhaps after <c>not</c>, and
    ///   each test an <c>.if</c> operand of comparisons (<c>=</c>, <c>==</c>, <c>!=</c>, <c>&lt;</c>, <c>&lt;=</c>,
    ///   <c>&gt;</c>, <c>&gt;=</c>) between symbols, numbers and character literals, joined by <c>&amp;&amp;</c> and
    ///   <c>||</c> and grouped by parentheses. A test that cannot be evaluated, such as one on a symbol the build does
    ///   not define, counts as holding, so the section applies.
    ///  </para>
    /// </remarks>
    /// <param name="condition">The section's condition, or null for one that always applies.</param>
    /// <param name="model">The launched model, such as <c>Enhanced</c>, for the IIe's model switch.</param>
    /// <param name="symbol">The build's value of a symbol, or null when it does not define it.</param>
    /// <returns>Whether the section applies.</returns>
    public static bool Applies(string? condition, string model, Func<string, long?>? symbol = null)
    {
        if (condition is null) { return true; }
        if (ModelOf(condition) is { } only) { return only == model; }
        if (symbol is null) { return true; }
        foreach (string part in condition.Split(" and ", StringSplitOptions.TrimEntries))
        {
            bool not = part.StartsWith("not ", StringComparison.OrdinalIgnoreCase);
            bool? holds = DocumentationConditions.Holds(not ? part[4..].Trim() : part, symbol);
            if (holds is { } value && value == not) { return false; }
        }

        return true;
    }

    /// <summary>
    ///  Resolves a link target written in a topic.
    /// </summary>
    /// <param name="from">The topic the link is in.</param>
    /// <param name="target">The target as written.</param>
    /// <returns>What it resolved to.</returns>
    public DocumentationTarget Resolve(DocumentationTopic from, string target) => Resolve(from, target, comment: null);

    /// <summary>
    ///  Resolves a link target written in one of a topic's comments, by the <c>.using</c> directives in effect at that
    ///  comment; a topic documented in two <c>.if</c> branches has a comment, and directives, for each.
    /// </summary>
    /// <param name="from">The topic the link is in.</param>
    /// <param name="target">The target as written.</param>
    /// <param name="comment">The comment the link is in, or null for the topic's first.</param>
    /// <returns>What it resolved to.</returns>
    public DocumentationTarget Resolve(DocumentationTopic from, string target, DocumentationComment? comment)
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

        DocumentationTarget result = Lookup(from, text, module, model, comment);
        return section is null ? result : result with { Section = section };
    }

    private DocumentationTarget Lookup(DocumentationTopic from, string name, string? module, string? model, DocumentationComment? comment)
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
            if (set.FindFile(name) is { } file) { return Found(file); }
        }

        // The assembler's scope rules, from the topic's scope outward, then the scopes the .using directives in
        // effect at the topic name, then historical names. Only what this build assembles counts: a name the source
        // defines only in another build's branch reaches nothing here, rather than a definition in another module.
        if (module is null && SetsFor(model).Contains(Current))
        {
            DocumentationTarget? elsewhere = null;
            foreach (string candidate in Scoped(from.Name, name))
            {
                if (InBuild(Match(Current, candidate, also: false), ref elsewhere) is { } match) { return match; }
            }

            if (Used(comment ?? (from.Comments.Count == 0 ? null : from.Primary), name, ref elsewhere) is { } used)
            {
                return used;
            }

            string plain = name.StartsWith("::", StringComparison.Ordinal) ? name[2..] : name;
            if (InBuild(Also(Current, plain), ref elsewhere) is { } also) { return also; }
            if (elsewhere is not null) { return elsewhere; }
        }

        List<DocumentationTarget> matches = [];
        DocumentationTarget? otherBuild = null;
        foreach (DocumentationSet set in sets)
        {
            if (module is null && ReferenceEquals(set, Current)) { continue; }
            DocumentationTarget? found = Match(set, name.StartsWith("::", StringComparison.Ordinal) ? name[2..] : name);

            // A link that names this source's own module means this build's definition, as a plain name does, before
            // another build's of the module; one only another build has it reaches only through that build's set.
            if (InBuild(found, ref otherBuild) is { } match)
            {
                if (ReferenceEquals(set, Current)) { return match; }
                matches.Add(match);
            }
        }

        if (matches.Count == 0 && otherBuild is not null) { return otherBuild; }

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

    // A match that only another build of the current source has is noted, the first of them, and passed over.
    private static DocumentationTarget? InBuild(DocumentationTarget? match, ref DocumentationTarget? elsewhere)
    {
        if (match is not { OnlyInOtherBuilds: true }) { return match; }
        elsewhere ??= match;
        return null;
    }

    // In the current set, a definition only another build has is no match; the build doesn't define its name (see
    // InOtherBuild), though an old name the name is may reach a definition it has.
    private DocumentationTarget? Match(DocumentationSet set, string name, bool also = true)
    {
        if (set.Find(name) is { } topic)
        {
            if (!ReferenceEquals(set, Current) || !Current.InOtherBuild(topic)) { return Found(topic); }
            return (also ? Also(set, name) : null) is { OnlyInOtherBuilds: false } old ? old : OtherBuild(name);
        }

        if (set.Symbols.TryGetValue(name, out long value))
        {
            // A symbol a macro's expansion defines is documented by its body's topic.
            return set.FindSymbol(name) is { } expanded
                ? Found(expanded) with { Name = name, Value = value }
                : new(DocumentationTargetKind.Symbol, name) { Set = set, Value = value };
        }

        return also ? Also(set, name) : null;
    }

    private static DocumentationTarget OtherBuild(string name) =>
        new(DocumentationTargetKind.Unresolved, name) { OnlyInOtherBuilds = true };

    // A historical name reaches the definition that gives it in an Also: section: in the set being checked, the one its
    // build assembles; in another module, any of its builds', so a name two of them give is ambiguous. In the set being
    // checked, a name that only another build's definitions or branches give reaches nothing.
    private DocumentationTarget? Also(DocumentationSet set, string name)
    {
        IReadOnlyList<DocumentationTopic> also = set.FindAlso(name, thisBuild: ReferenceEquals(set, Current));
        // A definition both builds have may give the name in a branch the build leaves out.
        bool OnlyElsewhere(DocumentationTopic topic) =>
            Current.InOtherBuild(topic)
                || (Current.KnowsBuild && Current.Gives(topic, name) && !Current.Gives(topic, name, thisBuild: true));

        if (ReferenceEquals(set, Current) && also.Any(OnlyElsewhere))
        {
            also = [.. also.Where(topic => !OnlyElsewhere(topic))];
            if (also.Count == 0) { return OtherBuild(name); }
        }

        if (also.Count == 1)
        {
            // In a topic macros' bodies share with other definitions of the name, the old name reaches one symbol of
            // them, which the target names, with its own value; one that two of them give is ambiguous, as in code.
            DocumentationTopic topic = also[0];
            IReadOnlyList<string> symbols = set.SymbolsOf(topic, name, thisBuild: ReferenceEquals(set, Current));
            if (symbols.Count > 1) { return new(DocumentationTargetKind.Ambiguous, name); }
            string symbol = symbols[0];
            if (symbol == topic.Name) { return Found(topic); }
            long? value = set.Symbols.TryGetValue(symbol, out long found) ? found : null;
            return Found(topic) with { Name = symbol, Value = value };
        }

        return also.Count > 1 ? new(DocumentationTargetKind.Ambiguous, name) : null;
    }

    // A plain name in the scopes the .using directives in effect at the comment name, innermost directive first; a
    // name two scopes of one directive define is ambiguous.
    private DocumentationTarget? Used(DocumentationComment? at, string name, ref DocumentationTarget? elsewhere)
    {
        if (name.Contains("::", StringComparison.Ordinal) || at is null) { return null; }
        foreach (DocumentationUsing directive in at.Usings)
        {
            List<DocumentationTarget> matches = [];
            // As in the assembler, a scope already opened before the directive binds first: one documented earlier in
            // the comment's file. An undocumented scope's opening is not known, so it can only bind second.
            bool OpenedBefore(string scope)
            {
                if (directive.Line < 0 || Current.Find(scope) is not { } opened) { return false; }
                return string.Equals(opened.Path, at.Path, StringComparison.OrdinalIgnoreCase) && opened.Line < directive.Line;
            }

            foreach (string scope in directive.Targets(Current.IsScope, OpenedBefore).Distinct(StringComparer.Ordinal))
            {
                DocumentationTarget? found = Match(Current, $"{scope}::{name}", also: false);
                if (InBuild(found, ref elsewhere) is { } match) { matches.Add(match); }
            }

            if (matches.Count == 1) { return matches[0]; }
            if (matches.Count > 1) { return new(DocumentationTargetKind.Ambiguous, name); }
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
        foreach (DocumentationSet set in _sets)
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
