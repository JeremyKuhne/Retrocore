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

    // The lines the assembly's conditional assembly skipped: which branch of each .if it took.
    private AssemblySkippedLines? _skipped;

    // The symbols each expansion of a macro body line defined, by the line's full path and zero-based line; null
    // when the assembly's definitions are not known.
    private Dictionary<string, Dictionary<int, List<string>>>? _expansions;

    // The topics of the symbols once-expanded macros' bodies define, by symbol, built on first use.
    private Dictionary<string, DocumentationTopic>? _bySymbol;

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

        DocumentationSet set = Create(files, symbols, module, model, result?.SourceMap, result?.SkippedLines, result?.SymbolDefinitions);
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
    /// <param name="skippedLines">
    ///  The lines the assembly's conditional assembly skipped, which tell which branch of each <c>.if</c> it took;
    ///  null when unknown, as for a debug file, which has no source.
    /// </param>
    /// <param name="definitions">
    ///  The assembly's symbol definitions, which count each macro body line's expansions for its historical names;
    ///  null when unknown, as for a debug file. Pass none for an assembly with errors, so no line counts as expanded.
    /// </param>
    /// <returns>The set.</returns>
    public static DocumentationSet Create(
        IEnumerable<DocumentationFile> files,
        IReadOnlyDictionary<string, long> symbols,
        string? module = null,
        string? model = null,
        IEnumerable<AssemblySourceMapEntry>? sourceMap = null,
        AssemblySkippedLines? skippedLines = null,
        IEnumerable<AssemblySymbol>? definitions = null)
    {
        List<DocumentationFile> list = [.. files];
        DocumentationSet set = new(module, model, symbols, list) { _skipped = skippedLines };
        if (sourceMap is not null) { ReadCpus(set, sourceMap); }

        // Each expansion of a macro's body defines its symbols again, at the body's line.
        // Files are compared as the skipped-lines report compares them, so an editor's path matches the assembler's.
        Dictionary<string, Dictionary<int, List<string>>>? expansions = definitions is null ? null : new(AssemblySkippedLines.PathComparer);
        foreach (AssemblySymbol symbol in definitions ?? [])
        {
            bool expanded = symbol.Location is { Path.Length: > 0, IsMacroExpansion: true };
            if (expansions is null || !expanded || symbol.Location is not { } location) { continue; }
            string path = AssemblySkippedLines.FullPath(location.Path);
            if (!expansions.TryGetValue(path, out Dictionary<int, List<string>>? lines))
            {
                expansions[path] = lines = [];
            }

            if (!lines.TryGetValue(location.Line, out List<string>? names)) { lines[location.Line] = names = []; }
            names.Add(symbol.Name);
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
    ///  that the build expands once, the name the expansion gave it (see <see cref="SymbolOf(DocumentationTopic)"/>).
    /// </summary>
    /// <param name="symbol">The symbol's name, as the assembly has it.</param>
    /// <returns>The topic, or null.</returns>
    public DocumentationTopic? FindSymbol(string symbol)
    {
        if (Find(symbol) is { } topic) { return topic; }
        Dictionary<string, DocumentationTopic>? bySymbol = _bySymbol;
        if (bySymbol is null)
        {
            // Built before it is published, as requests can ask from more than one thread.
            bySymbol = [with(StringComparer.Ordinal)];
            foreach (DocumentationTopic candidate in _ordered)
            {
                // Each macro body that defines the topic's name defines its own symbol, as two macros' bodies may.
                foreach (DocumentationComment comment in candidate.Comments.Where(comment => comment.Macro is not null && Reaches(comment)))
                {
                    if (ExpandedName([comment]) is { } expanded && expanded != candidate.Name)
                    {
                        bySymbol[expanded] = candidate;
                    }
                }
            }

            _bySymbol = bySymbol;
        }

        return bySymbol.TryGetValue(symbol, out topic) ? topic : null;
    }

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
    ///   count, nor does an <c>Also:</c> section of such a branch when several branches document the definition, for
    ///   any kind of topic (see <see cref="InBuild"/>). This only chooses among definitions: a name only an omitted
    ///   one gives still finds it, as a plain name of a definition the build leaves out still does. Without the
    ///   assembly's symbols, as after a failed assembly, every definition counts, though its sections still follow
    ///   the assembly's report of the lines it skipped.
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
        topic.Comments.All(comment => comment.Macro is null)
            ? DocumentationAlso.Of(topic.Sections.Where(section => !thisBuild || InBuild(topic, section)))
                .Any(also => also.Name == name)
            : GivesOutsideMacros(topic, name, thisBuild)
                || topic.Comments.Where(comment => comment.Macro is not null && Reaches(comment))
                    .Any(comment => DocumentationAlso.Of(comment.Sections).Any(also => also.Name == name));

    // Whether a topic's definitions outside macros' bodies give a name, judged as if no macro's body shared the topic:
    // the build's own branch gives it, or the build takes a bare Inherit: branch, which shares what the others give.
    private bool GivesOutsideMacros(DocumentationTopic topic, string name, bool thisBuild)
    {
        List<DocumentationComment> outside = [.. topic.Comments.Where(comment => comment.Macro is null)];
        List<DocumentationComment> participants = [.. outside.Where(comment => !BareInherit(comment))];
        if (participants.Count == 0) { participants = outside; }
        bool Gave(DocumentationComment comment) => DocumentationAlso.Of(comment.Sections).Any(also => also.Name == name);
        bool Built(DocumentationComment comment) => !thisBuild || CommentInBuild(comment);
        if (participants.Any(comment => Gave(comment) && Built(comment))) { return true; }

        // As Merge does, a section every branch writes alike, documents and all, is shared with the inheriting branch.
        bool Shared(DocumentationSection section) =>
            participants.All(comment => comment.Sections.Any(candidate => Same(candidate, section)));

        return participants.Count != 0
            && outside.Any(comment => BareInherit(comment) && Built(comment))
            && DocumentationAlso.Of(participants[0].Sections.Where(Shared)).Any(also => also.Name == name);
    }

    /// <summary>
    ///  Gets whether a definition's own old names reach it in this set's build: <see cref="Reaches"/>, for a
    ///  definition outside a macro's body in the branch of conditional assembly the build takes.
    /// </summary>
    /// <param name="comment">The definition's comment.</param>
    /// <returns>Whether they reach it.</returns>
    internal bool ReachesInBuild(DocumentationComment comment) => Reaches(comment) && CommentInBuild(comment);

    /// <summary>
    ///  Gets the symbol one of a topic's definitions is: the name its expansion gave a definition in a macro's body
    ///  that the build expands once, otherwise the topic's name.
    /// </summary>
    /// <param name="topic">The topic.</param>
    /// <param name="comment">One of its comments.</param>
    /// <returns>The symbol's name.</returns>
    public string SymbolOf(DocumentationTopic topic, DocumentationComment comment) =>
        comment.Macro is null ? topic.Name : ExpandedName([comment]) ?? topic.Name;

    // Whether a definition outside a macro's body is in this set's build, as InBuild tells for a merged section: the
    // assembly didn't skip its line, or else its condition holds. A macro body's always counts here: Reaches counts its
    // expansions.
    private bool CommentInBuild(DocumentationComment comment) =>
        comment.Macro is not null
            || comment.Condition is null
            || (_skipped?.InBuild(comment.Path, comment.TargetLine)
                ?? DocumentationConditions.InBuild(comment.Condition, _symbols, IsDefined));

    /// <summary>
    ///  Gets the historical names a topic's <c>Also:</c> sections give it that reach it, as the assembler resolves
    ///  them: in a macro's body, only the sections of definitions that <see cref="Reaches"/> says their names reach.
    /// </summary>
    /// <param name="topic">The topic.</param>
    /// <returns>The names, with the documents that give them.</returns>
    public IEnumerable<DocumentationAlso> AlsoOf(DocumentationTopic topic) =>
        topic.Comments.All(comment => comment.Macro is null)
            ? DocumentationAlso.Of(topic.Sections)
            : topic.Comments.Where(Reaches)
                .SelectMany(comment => DocumentationAlso.Of(comment.Sections))
                .GroupBy(also => also.Name, StringComparer.Ordinal)
                .Select(group => group.First());

    /// <summary>
    ///  Gets the historical names that reach one symbol of a topic: where macros' bodies define the topic's name, only
    ///  those its own definition's <c>Also:</c> gives, as <c>Basic::COMBYT</c>'s, not another expansion's or a
    ///  definition's outside the macro.
    /// </summary>
    /// <param name="topic">The topic.</param>
    /// <param name="symbol">The symbol, as the assembly has it (see <see cref="FindSymbol"/>).</param>
    /// <returns>The names, with the documents that give them.</returns>
    public IEnumerable<DocumentationAlso> AlsoOf(DocumentationTopic topic, string symbol) =>
        topic.Comments.All(comment => comment.Macro is null)
            ? AlsoOf(topic)
            : topic.Comments
                .Where(comment => Reaches(comment) && (comment.Macro is null ? topic.Name : ExpandedName([comment])) == symbol)
                .SelectMany(comment => DocumentationAlso.Of(comment.Sections))
                .GroupBy(also => also.Name, StringComparer.Ordinal)
                .Select(group => group.First());

    /// <summary>
    ///  Gets whether the historical names a definition's own <c>Also:</c> section gives reach it, as the assembler
    ///  resolves them.
    /// </summary>
    /// <param name="comment">The definition's comment.</param>
    /// <returns>
    ///  For a definition in a macro's body, whether this set's build expands it exactly once and its name is the same
    ///  in each expansion: not a parameter's, a <c>.local</c> or a cheap local, nor a <c>.set</c> variable, which
    ///  has a version for each assignment. False when its expansions are not known. True outside a macro's body.
    /// </returns>
    public bool Reaches(DocumentationComment comment) =>
        comment.Macro is null
            || (comment.Kind is not (DocumentationKind.Scope or DocumentationKind.Struct or DocumentationKind.Enum)
                && !comment.NamedByParameter
                && !comment.LocalToExpansion
                && comment.Kind != DocumentationKind.Variable
                && Expansions(comment) == 1);

    /// <summary>
    ///  Gets how many times this set's build defined a definition in a macro's body: once for each expansion.
    /// </summary>
    /// <param name="comment">The definition's comment.</param>
    /// <returns>The count; null outside a macro's body, or when the assembly's definitions are not known.</returns>
    public int? Expansions(DocumentationComment comment) =>
        comment.Macro is null || _expansions is null ? null : ExpansionsAt(comment)?.Count ?? 0;

    // The symbols each expansion of a comment's line defined, or null when none did.
    private List<string>? ExpansionsAt(DocumentationComment comment) =>
        _expansions is not null
            && _expansions.TryGetValue(AssemblySkippedLines.FullPath(comment.Path), out Dictionary<int, List<string>>? lines)
            && lines.TryGetValue(comment.TargetLine, out List<string>? names)
                ? names
                : null;

    /// <summary>
    ///  Gets the symbol a topic's definition is: for a definition in a macro's body that the build expands once, the
    ///  name the expansion gave it (<c>Library::COMBYT</c>, expanded in <c>.scope Library</c>); otherwise its name.
    /// </summary>
    /// <param name="topic">The topic.</param>
    /// <returns>The symbol's name.</returns>
    public string SymbolOf(DocumentationTopic topic) => ExpandedName(topic.Comments) ?? topic.Name;

    /// <summary>
    ///  Gets the symbol a historical name reaches through a topic: for a definition in a macro's body whose own
    ///  <c>Also:</c> gives the name, the name its expansion gave it, though another macro's body defines the same
    ///  name elsewhere (<c>A::COMBYT</c> and <c>B::COMBYT</c> share the topic <c>COMBYT</c>); otherwise
    ///  <see cref="SymbolOf(DocumentationTopic)"/>.
    /// </summary>
    /// <param name="topic">The topic.</param>
    /// <param name="name">The historical name.</param>
    /// <returns>The symbol's name.</returns>
    public string SymbolOf(DocumentationTopic topic, string name)
    {
        foreach (DocumentationComment comment in topic.Comments)
        {
            if (comment.Macro is null || !Reaches(comment)) { continue; }
            if (!DocumentationAlso.Of(comment.Sections).Any(also => also.Name == name)) { continue; }
            if (ExpandedName([comment]) is { } expanded) { return expanded; }
        }

        return SymbolOf(topic);
    }

    // The name a macro body definition's only expansion gave it, or null; null too for a topic that also documents a
    // definition outside a macro's body, which is the symbol of its own name.
    private string? ExpandedName(IEnumerable<DocumentationComment> comments)
    {
        if (_expansions is null) { return null; }
        string? found = null;
        foreach (DocumentationComment comment in comments)
        {
            if (comment.Macro is null) { return null; }
            if (ExpansionsAt(comment) is not { } names) { continue; }
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
    ///   Only a section that differs between branches has a condition; one every branch shares, or the sections of a
    ///   definition documented once, are in every build.
    ///  </para>
    ///  <para>
    ///   When the set was created from an assembly, the assembly answers it for every kind of topic: the branch is in
    ///   the build when the assembly assembled the line the section's comment documents, as the assembler chose it
    ///   with the macros defined before that point and the constants as they were there (see
    ///   <see cref="AssemblyResult.SkippedLines"/>). A file the assembly never opened is not in the build, unless an
    ///   error in expansion may have kept it from opening it.
    ///  </para>
    ///  <para>
    ///   Without that report (documentation from a debug file, which has no source), for a line it leaves undecided
    ///   (after an error in expansion, or a MACRO-10 line its expander didn't pass on), or for a file not opened by
    ///   an assembly with expansion errors, the section's condition is evaluated from the build's symbols and every
    ///   macro the files define, which can differ from the assembler's view where a macro is defined after the
    ///   <c>.ifdef</c> that tests it or in a branch not taken.
    ///  </para>
    /// </remarks>
    public bool InBuild(DocumentationTopic topic, DocumentationSection section)
    {
        if (section.Condition is null) { return true; }
        if (section.OriginPath is not { Length: > 0 } path || _skipped is not { } skipped)
        {
            return DocumentationConditions.InBuild(section.Condition, _symbols, IsDefined);
        }

        // A file the assembly never opened, such as one only a branch it skipped includes, has nothing in the build.
        bool? assembled = skipped.InBuild(path, section.OriginLine);
        return assembled ?? DocumentationConditions.InBuild(section.Condition, _symbols, IsDefined);
    }

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
                if (scope) { continue; }
                foreach (DocumentationAlso item in AlsoOf(topic))
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
    ///  Gets whether a name is defined as an <c>.ifdef</c> sees it, approximately: a symbol of the assembly or a macro
    ///  any of its files defines, wherever and in whichever branch. Only conditions the assembly's report can't
    ///  decide are evaluated with it (see <see cref="InBuild"/>).
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
