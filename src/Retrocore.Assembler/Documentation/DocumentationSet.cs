// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Isa;

namespace Retrocore.Documentation;

/// <summary>
///  The documentation of one assembly: every topic of its source files, with values from the assembly.
/// </summary>
public sealed class DocumentationSet
{
    private readonly Dictionary<string, DocumentationTopic> _topics = [with(StringComparer.Ordinal)];
    private readonly List<DocumentationTopic> _ordered = [];
    private readonly IReadOnlyDictionary<string, long> _symbols;
    private readonly Dictionary<string, List<(int Line, IsaDescription Cpu)>> _cpus = [with(StringComparer.OrdinalIgnoreCase)];

    // The CPU every statement was assembled for, unless they were for more than one.
    private IsaDescription? _onlyCpu;
    private bool _mixed;
    private HashSet<string>? _macros;

    // Where the assembly defined each symbol, by full path and zero-based line: which branch of an .if it took.
    private HashSet<(string Path, int Line)> _definedAt = [];

    // The symbols each expansion of a macro body line defined, by the line's full path and zero-based line; null
    // when the assembly's definitions are not known.
    private Dictionary<(string Path, int Line), List<string>>? _expansions;

    private DocumentationSet(
        string? module,
        string? model,
        IReadOnlyDictionary<string, long> symbols,
        IReadOnlyList<DocumentationFile> files)
    {
        Module = module;
        Model = model;
        _symbols = symbols;
        Files = files;
    }

    /// <summary>
    ///  Gets the module name links can use to qualify names, such as <c>Monitor</c>; null for a user program.
    /// </summary>
    public string? Module { get; }

    /// <summary>
    ///  Gets the model this set's assembly was built for, such as <c>Enhanced</c>; null when it does not depend
    ///  on one.
    /// </summary>
    public string? Model { get; }

    /// <summary>
    ///  Gets the parsed files.
    /// </summary>
    public IReadOnlyList<DocumentationFile> Files { get; }

    /// <summary>
    ///  Gets the topics in source order.
    /// </summary>
    public IReadOnlyList<DocumentationTopic> Topics => _ordered;

    /// <summary>
    ///  Gets the exported symbols and where each is defined, when the set was created from an assembly.
    /// </summary>
    public IReadOnlyList<(string Name, string Path, int Line)> Exports { get; private set; } = [];

    /// <summary>
    ///  Gets the assembly's symbols, by native name.
    /// </summary>
    public IReadOnlyDictionary<string, long> Symbols => _symbols;

    /// <summary>
    ///  Creates the documentation of an assembly.
    /// </summary>
    /// <param name="files">The parsed source files, root first.</param>
    /// <param name="result">The assembly, for values; null when it has none.</param>
    /// <param name="module">The module name links may use, or null.</param>
    /// <param name="model">The model the assembly was built for, or null.</param>
    /// <param name="relocation">
    ///  How far the code runs from where it was assembled, added to its labels but not its constants.
    /// </param>
    /// <returns>The set.</returns>
    public static DocumentationSet Create(
        IEnumerable<DocumentationFile> files,
        AssemblyResult? result,
        string? module = null,
        string? model = null,
        int relocation = 0)
    {
        IReadOnlyDictionary<string, long> symbols = result?.Symbols ?? new Dictionary<string, long>();
        if (result is not null && relocation != 0)
        {
            // Code that runs away from where it was assembled moves its labels; its constants stay.
            Dictionary<string, long> moved = [with(StringComparer.Ordinal)];
            foreach (KeyValuePair<string, long> symbol in symbols) { moved[symbol.Key] = symbol.Value; }
            foreach (AssemblySymbol symbol in result.SymbolDefinitions)
            {
                if (!symbol.IsConstant && moved.ContainsKey(symbol.Name))
                {
                    moved[symbol.Name] = symbol.Value + relocation;
                }
            }

            symbols = moved;
        }

        DocumentationSet set = Create(files, symbols, module, model, result?.SourceMap, result?.SymbolDefinitions);
        if (result is not null)
        {
            List<(string, string, int)> exports = [];
            foreach (AssemblySymbol symbol in result.SymbolDefinitions)
            {
                if (symbol.IsExported && symbol.Location is { Path.Length: > 0 } location)
                {
                    exports.Add((symbol.Name, location.Path, location.Line));
                }
            }

            set.Exports = exports;
        }

        return set;
    }

    // Notes where each file's CPU changes, from the statements' own CPUs, in line order per file.
    private static void ReadCpus(DocumentationSet set, IEnumerable<AssemblySourceMapEntry> sourceMap)
    {
        foreach (AssemblySourceMapEntry entry in sourceMap)
        {
            if (entry.InstructionSet is not { } cpu) { continue; }
            set._onlyCpu ??= cpu.Description;
            set._mixed |= set._onlyCpu != cpu.Description;

            // A macro's statement counts for its definition and for each line that expanded it.
            for (AssemblyLocation? location = entry.Location; location is not null; location = location.ExpandedFrom)
            {
                if (location.Path.Length == 0) { continue; }
                string path = System.IO.Path.GetFullPath(location.Path);
                if (!set._cpus.TryGetValue(path, out List<(int Line, IsaDescription Cpu)>? runs))
                {
                    set._cpus[path] = runs = [];
                }

                runs.Add((location.Line, cpu.Description));
            }
        }

        foreach (List<(int Line, IsaDescription Cpu)> runs in set._cpus.Values)
        {
            runs.Sort((left, right) => left.Line.CompareTo(right.Line));
        }
    }

    /// <summary>
    ///  Gets the CPU code at a source line was assembled for: the nearest statement's at or before it, else the
    ///  file's first. A file that assembled nothing takes the assembly's CPU when it had only one. Null when the
    ///  set was not created from an assembly, or the CPU cannot be told.
    /// </summary>
    /// <param name="path">The source file.</param>
    /// <param name="line">The zero-based line.</param>
    /// <returns>The CPU's description, or null.</returns>
    public IsaDescription? CpuAt(string path, int line)
    {
        if (path.Length == 0 || !_cpus.TryGetValue(System.IO.Path.GetFullPath(path), out List<(int Line, IsaDescription Cpu)>? runs))
        {
            return _mixed ? null : _onlyCpu;
        }

        IsaDescription cpu = runs[0].Cpu;
        foreach ((int at, IsaDescription description) in runs)
        {
            if (at > line) { break; }
            cpu = description;
        }

        return cpu;
    }

    /// <summary>
    ///  Creates documentation with values from a symbol table, such as a debug file's.
    /// </summary>
    /// <param name="files">The parsed source files, root first.</param>
    /// <param name="symbols">Symbol values by name.</param>
    /// <param name="module">The module name links may use, or null.</param>
    /// <param name="model">The model the code was built for, or null.</param>
    /// <param name="sourceMap">The assembly's statements, for each part's CPU; null when unknown.</param>
    /// <param name="definitions">
    ///  The assembly's symbol definitions, which tell which branch of each <c>.if</c> it took; null when unknown.
    /// </param>
    /// <returns>The set.</returns>
    public static DocumentationSet Create(
        IEnumerable<DocumentationFile> files,
        IReadOnlyDictionary<string, long> symbols,
        string? module = null,
        string? model = null,
        IEnumerable<AssemblySourceMapEntry>? sourceMap = null,
        IEnumerable<AssemblySymbol>? definitions = null)
    {
        List<DocumentationFile> list = [.. files];
        DocumentationSet set = new(module, model, symbols, list);
        if (sourceMap is not null) { ReadCpus(set, sourceMap); }
        Dictionary<(string Path, int Line), List<string>>? expansions = definitions is null ? null : [];
        foreach (AssemblySymbol symbol in definitions ?? [])
        {
            if (symbol.Location is { Path.Length: > 0 } location)
            {
                (string, int) at = (System.IO.Path.GetFullPath(location.Path), location.Line);
                set._definedAt.Add(at);
                if (!location.IsMacroExpansion || expansions is null) { continue; }
                if (!expansions.TryGetValue(at, out List<string>? names)) { expansions[at] = names = []; }
                names.Add(symbol.Name);
            }
        }

        set._expansions = expansions;

        Dictionary<string, List<DocumentationComment>> byName = [with(StringComparer.Ordinal)];
        List<string> order = [];
        foreach (DocumentationFile file in list)
        {
            foreach (DocumentationComment comment in file.Comments)
            {
                // A file or free-standing topic is unique to its file.
                string key = comment.Kind is DocumentationKind.File or DocumentationKind.Topic
                    ? $"{comment.Path}|{comment.Kind}|{comment.Line}|{comment.Name}"
                    : comment.Name;

                if (!byName.TryGetValue(key, out List<DocumentationComment>? comments))
                {
                    byName[key] = comments = [];
                    order.Add(key);
                }

                comments.Add(comment);
            }
        }

        foreach (string key in order)
        {
            List<DocumentationComment> comments = byName[key];
            DocumentationTopic topic = Merge(set, comments);
            set._ordered.Add(topic);
            if (comments[0].Kind is not (DocumentationKind.File or DocumentationKind.Topic))
            {
                set._topics[topic.Name] = topic;
            }
        }

        return set;
    }

    /// <summary>
    ///  Finds a topic by its documented name.
    /// </summary>
    /// <param name="name">The name, qualified for a member.</param>
    /// <returns>The topic, or null.</returns>
    public DocumentationTopic? Find(string name) => _topics.TryGetValue(name, out DocumentationTopic? topic) ? topic : null;

    /// <summary>
    ///  Finds a topic by the symbol its definition is: its documented name, or, for a definition in a macro's body
    ///  that the build expands once, the name the expansion gave it (see <see cref="SymbolOf"/>).
    /// </summary>
    /// <param name="symbol">The symbol's name, as the assembly has it.</param>
    /// <returns>The topic, or null.</returns>
    public DocumentationTopic? FindSymbol(string symbol)
    {
        if (Find(symbol) is { } topic) { return topic; }
        if (_bySymbol is null)
        {
            _bySymbol = [with(StringComparer.Ordinal)];
            foreach (DocumentationTopic candidate in _ordered)
            {
                if (ExpandedName(candidate.Comments) is { } expanded && expanded != candidate.Name)
                {
                    _bySymbol[expanded] = candidate;
                }
            }
        }

        return _bySymbol.TryGetValue(symbol, out topic) ? topic : null;
    }

    private Dictionary<string, DocumentationTopic>? _bySymbol;

    /// <summary>
    ///  Finds the topics that give a historical name in their <c>Also:</c> sections.
    /// </summary>
    /// <param name="name">The historical name, such as <c>COUT</c>.</param>
    /// <param name="thisBuild">
    ///  Whether only the definitions this set's assembly assembles count. Two models may give the same old name to
    ///  different code (the original and Enhanced IIe's SLOTRTS), and within its own build a source means its own
    ///  one; a set used as another module, assembled for its default build, says nothing about the caller's build.
    /// </param>
    /// <returns>The topics, in source order; usually none or one.</returns>
    /// <remarks>
    ///  <para>
    ///   With <paramref name="thisBuild"/>, a label or equate in a branch of an <c>.if</c> the build leaves out doesn't
    ///   count, nor does an <c>Also:</c> section of such a branch when both branches document the definition; macros,
    ///   scopes and types, which are no symbols, always count. This only chooses among definitions: a name only an
    ///   omitted one gives still finds it, as a plain name of a definition the build leaves out still does. Without
    ///   the assembly's symbols, every definition counts.
    ///  </para>
    /// </remarks>
    public IReadOnlyList<DocumentationTopic> FindAlso(string name, bool thisBuild = false)
    {
        if (!AlsoIndex().TryGetValue(name, out List<DocumentationTopic>? found)) { return []; }
        if (!thisBuild || found.Count < 2) { return found; }
        List<DocumentationTopic> built = [.. found.Where(topic => Assembles(topic) && Gives(topic, name, thisBuild: true))];
        return built.Count == 0 ? found : built;
    }

    /// <summary>
    ///  Gets whether a topic gives a historical name in an <c>Also:</c> section.
    /// </summary>
    /// <param name="topic">The topic.</param>
    /// <param name="name">The historical name.</param>
    /// <param name="thisBuild">Whether only its sections in this set's build count, as the assembler's do.</param>
    /// <returns>Whether it gives the name.</returns>
    public bool Gives(DocumentationTopic topic, string name, bool thisBuild = false) =>
        Reaches(topic)
            && DocumentationAlso.Of(topic.Sections.Where(section => !thisBuild || InBuild(topic, section)))
                .Any(also => also.Name == name);

    /// <summary>
    ///  Gets the historical names a topic's <c>Also:</c> sections give it that reach it: none for a definition in a
    ///  macro's body that this set's build doesn't expand exactly once.
    /// </summary>
    /// <param name="topic">The topic.</param>
    /// <returns>The names, with the documents that give them.</returns>
    public IEnumerable<DocumentationAlso> AlsoOf(DocumentationTopic topic) =>
        Reaches(topic) ? DocumentationAlso.Of(topic.Sections) : [];

    /// <summary>
    ///  Gets whether the historical names a topic's <c>Also:</c> sections give reach it, as the assembler resolves
    ///  them.
    /// </summary>
    /// <param name="topic">The topic.</param>
    /// <returns>
    ///  False for a definition in a macro's body that this set's build doesn't expand exactly once, whose name a
    ///  parameter or <c>.local</c> gives, or whose expansions are not known; otherwise true.
    /// </returns>
    public bool Reaches(DocumentationTopic topic) =>
        topic.Comments.All(comment => comment.Macro is null
            || (!comment.NamedByParameter && !comment.LocalToExpansion && Expansions(comment) == 1));

    /// <summary>
    ///  Gets how many times this set's build defined a definition in a macro's body: once for each expansion.
    /// </summary>
    /// <param name="comment">The definition's comment.</param>
    /// <returns>The count; null outside a macro's body, or when the assembly's definitions are not known.</returns>
    public int? Expansions(DocumentationComment comment) =>
        comment.Macro is null || _expansions is null ? null
            : _expansions.TryGetValue((System.IO.Path.GetFullPath(comment.Path), comment.TargetLine), out List<string>? names)
                ? names.Count
                : 0;

    /// <summary>
    ///  Gets the symbol a topic's definition is: for a definition in a macro's body that the build expands once, the
    ///  name the expansion gave it (<c>Library::COMBYT</c>, expanded in <c>.scope Library</c>); otherwise its name.
    /// </summary>
    /// <param name="topic">The topic.</param>
    /// <returns>The symbol's name.</returns>
    public string SymbolOf(DocumentationTopic topic) => ExpandedName(topic.Comments) ?? topic.Name;

    // The name a macro body definition's only expansion gave it, or null.
    private string? ExpandedName(IEnumerable<DocumentationComment> comments)
    {
        if (_expansions is null) { return null; }
        string? found = null;
        foreach (DocumentationComment comment in comments)
        {
            if (comment.Macro is null) { continue; }
            (string, int) at = (System.IO.Path.GetFullPath(comment.Path), comment.TargetLine);
            if (!_expansions.TryGetValue(at, out List<string>? names)) { continue; }
            if (names.Count != 1 || (found is not null && found != names[0])) { return null; }
            found = names[0];
        }

        return found;
    }

    /// <summary>
    ///  Gets whether a topic's section, from one branch of an <c>.if</c> when topics from several were merged, is in
    ///  this set's build.
    /// </summary>
    /// <param name="topic">The topic.</param>
    /// <param name="section">One of its sections.</param>
    /// <returns>Whether the section's branch is the one assembled.</returns>
    /// <remarks>
    ///  <para>
    ///   For a label, equate or member, the assembly answers it exactly: the branch is in the build when the assembly
    ///   defined a symbol at the line the section's comment documents, as the assembler gives a definition the
    ///   historical names of the branch it assembled. For anything else, the section's condition is evaluated from
    ///   the build's symbols and the files' macros, which can differ from the assembler's view where a macro is
    ///   defined after the <c>.ifdef</c> that tests it.
    ///  </para>
    /// </remarks>
    public bool InBuild(DocumentationTopic topic, DocumentationSection section)
    {
        return section.Condition is null
            || (IsSymbol(topic.Kind) && _definedAt.Count != 0 && section.OriginPath is { } path
                ? _definedAt.Contains((System.IO.Path.GetFullPath(path), section.OriginLine))
                : DocumentationConditions.InBuild(section.Condition, _symbols, IsDefined));
    }

    // Whether the assembly defines a symbol for a topic of this kind.
    private static bool IsSymbol(DocumentationKind kind) =>
        kind is DocumentationKind.Routine
            or DocumentationKind.Table
            or DocumentationKind.Constant
            or DocumentationKind.Variable
            or DocumentationKind.Member;

    /// <summary>
    ///  Gets whether a topic's definition is in this set's assembly: false only for a label or equate the assembly
    ///  leaves out, in a branch of an <c>.if</c> its build does not take.
    /// </summary>
    /// <param name="topic">The topic.</param>
    /// <returns>Whether it is assembled, or can't be told apart.</returns>
    public bool Assembles(DocumentationTopic topic) =>
        _symbols.Count == 0
            || topic.Kind is not (DocumentationKind.Routine or DocumentationKind.Table or DocumentationKind.Constant or DocumentationKind.Variable)
            || topic.Value is not null
            || Defines(topic.Name)
            || topic.Comments.Any(comment => Expansions(comment) > 0);

    /// <summary>
    ///  Gets every historical name the topics give.
    /// </summary>
    public IEnumerable<string> AlsoNames => AlsoIndex().Keys;

    private Dictionary<string, List<DocumentationTopic>> AlsoIndex()
    {
        if (_also is null)
        {
            Dictionary<string, List<DocumentationTopic>> also = [with(StringComparer.Ordinal)];
            foreach (DocumentationTopic topic in _ordered)
            {
                // A scope or a named type has nothing for an old name to reach, as in the assembler, nor has a
                // definition in a macro's body the build doesn't expand once.
                bool scope = topic.Kind is DocumentationKind.Scope or DocumentationKind.Struct or DocumentationKind.Enum;
                if (scope || !Reaches(topic)) { continue; }
                foreach (DocumentationAlso item in DocumentationAlso.Of(topic.Sections))
                {
                    if (!also.TryGetValue(item.Name, out List<DocumentationTopic>? topics))
                    {
                        topics = [];
                        also[item.Name] = topics;
                    }

                    if (!topics.Contains(topic)) { topics.Add(topic); }
                }
            }

            _also = also;
        }

        return _also;
    }

    /// <summary>
    ///  Gets the symbol an <c>Entry:</c> label names: the routine's own local when the routine is a <c>.proc</c>
    ///  that defines one (<c>Plot::SameRow</c> for <c>SameRow</c> in <c>Plot</c>), otherwise the label as written.
    /// </summary>
    /// <param name="routine">The routine whose comment lists the entry.</param>
    /// <param name="label">The label as written.</param>
    /// <returns>The symbol's name.</returns>
    public string EntrySymbol(DocumentationTopic routine, string label)
    {
        string local = $"{routine.Name}::{label}";
        return _symbols.ContainsKey(local) || _topics.ContainsKey(local) ? local : label;
    }

    /// <summary>
    ///  Finds the topic of a label documented as an entry into a routine, or the routine itself.
    /// </summary>
    /// <param name="name">The label.</param>
    /// <returns>The routine's topic, or null.</returns>
    public DocumentationTopic? FindRoutine(string name) =>
        Find(name) ?? _ordered.FirstOrDefault(topic =>
            topic.EntryLabels.Any(label => label == name || EntrySymbol(topic, label) == name));

    /// <summary>
    ///  Finds the documented label at an address.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>The topic, or null.</returns>
    public DocumentationTopic? FindAt(long address) =>
        _ordered.FirstOrDefault(topic => topic.Kind is DocumentationKind.Routine or DocumentationKind.Table && topic.Value == address);

    /// <summary>
    ///  Gets whether the assembly defines a symbol.
    /// </summary>
    /// <param name="name">The name.</param>
    /// <returns>Whether it is defined.</returns>
    public bool Defines(string name) => _symbols.ContainsKey(name);

    /// <summary>
    ///  Gets whether a name is defined as an <c>.ifdef</c> sees it: a symbol of the assembly or a macro its files define.
    /// </summary>
    /// <param name="name">The name.</param>
    /// <returns>Whether it is defined.</returns>
    public bool IsDefined(string name)
    {
        _macros ??= [.. Files.SelectMany(file => file.Macros)];
        return _symbols.ContainsKey(name) || _macros.Contains(name);
    }

    /// <summary>
    ///  Tests whether a qualified name is a scope: one that a documented or assembled name is qualified by.
    /// </summary>
    /// <param name="name">The qualified scope name, without a leading <c>::</c>.</param>
    /// <returns>Whether some name is in that scope.</returns>
    public bool IsScope(string name) => (_scopes ??= Scopes()).Contains(name);

    private HashSet<string>? _scopes;

    private HashSet<string> Scopes()
    {
        HashSet<string> scopes = [with(StringComparer.Ordinal)];
        foreach (string name in _topics.Keys.Concat(_symbols.Keys))
        {
            for (int end = name.LastIndexOf("::", StringComparison.Ordinal); end > 0; end = name.LastIndexOf("::", end - 1, StringComparison.Ordinal))
            {
                if (!scopes.Add(name[..end])) { break; }
            }
        }

        return scopes;
    }

    private Dictionary<string, List<DocumentationTopic>>? _also;

    private static DocumentationTopic Merge(DocumentationSet set, List<DocumentationComment> comments)
    {
        DocumentationComment first = comments[0];
        string name = first.Name;

        // A definition in a macro's body has the value of the symbol its expansion defined, which a scope around the
        // expansion qualifies.
        string symbol = set.ExpandedName(comments) ?? name;
        long? value = set._symbols.TryGetValue(symbol, out long found) ? found : null;
        if (comments.Count == 1)
        {
            return new DocumentationTopic
            {
                Name = name,
                Kind = first.Kind,
                Set = set,
                Comments = comments,
                Summary = first.Summary,
                Remarks = first.Remarks,
                Sections = first.Sections,
                Value = value
            };
        }

        // The branches of an .if share whatever they say alike; what differs is kept once per branch. A branch
        // whose comment is only a bare "Inherit:" shares the other branches' documentation.
        List<DocumentationComment> participants = [.. comments.Where(comment => !BareInherit(comment))];
        if (participants.Count == 0) { participants = comments; }
        List<DocumentationSection> sections = [];
        foreach (DocumentationComment comment in participants)
        {
            foreach (DocumentationSection section in comment.Sections)
            {
                bool shared = participants.All(other => other.Sections.Any(candidate => Same(candidate, section)));
                if (shared)
                {
                    if (!sections.Any(existing => existing.Condition is null && Same(existing, section)))
                    {
                        sections.Add(section);
                    }
                }
                else
                {
                    sections.Add(section.WithCondition(comment.Condition, comment.Path, comment.TargetLine));
                }
            }
        }

        string summary = participants.Select(comment => comment.Summary).FirstOrDefault(text => text.Length != 0) ?? "";
        IReadOnlyList<string> remarks = participants.Select(comment => comment.Remarks).FirstOrDefault(lines => lines.Count != 0) ?? [];
        DocumentationKind kind = comments.Any(comment => comment.Kind == DocumentationKind.Routine)
            ? DocumentationKind.Routine
            : first.Kind;

        return new DocumentationTopic
        {
            Name = name,
            Kind = kind,
            Set = set,
            Comments = comments,
            Summary = summary,
            Remarks = remarks,
            Sections = sections,
            Value = value
        };
    }

    private static bool BareInherit(DocumentationComment comment) =>
        comment.Summary.Length == 0
            && comment.Sections.Count == 1
            && comment.Sections[0].Name == "Inherit"
            && comment.Sections[0].Text.Length == 0;

    private static bool Same(DocumentationSection a, DocumentationSection b) =>
        a.Name.Equals(b.Name, StringComparison.OrdinalIgnoreCase) && a.Text == b.Text;
}
