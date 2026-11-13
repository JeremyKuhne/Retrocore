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
    private readonly Dictionary<string, DocumentationTopic> _topics = new(StringComparer.Ordinal);
    private readonly List<DocumentationTopic> _ordered = [];
    private readonly IReadOnlyDictionary<string, long> _symbols;
    private readonly Dictionary<string, List<(int Line, IsaDescription Cpu)>> _cpus = new(StringComparer.OrdinalIgnoreCase);

    // The CPU every statement was assembled for, unless they were for more than one.
    private IsaDescription? _onlyCpu;
    private bool _mixed;

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
            Dictionary<string, long> moved = new(StringComparer.Ordinal);
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

        DocumentationSet set = Create(files, symbols, module, model, result?.SourceMap);
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
    /// <returns>The set.</returns>
    public static DocumentationSet Create(
        IEnumerable<DocumentationFile> files,
        IReadOnlyDictionary<string, long> symbols,
        string? module = null,
        string? model = null,
        IEnumerable<AssemblySourceMapEntry>? sourceMap = null)
    {
        List<DocumentationFile> list = [.. files];
        DocumentationSet set = new(module, model, symbols, list);
        if (sourceMap is not null) { ReadCpus(set, sourceMap); }
        Dictionary<string, List<DocumentationComment>> byName = new(StringComparer.Ordinal);
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
    ///  Finds the topic of a label documented as an entry into a routine, or the routine itself.
    /// </summary>
    /// <param name="name">The label.</param>
    /// <returns>The routine's topic, or null.</returns>
    public DocumentationTopic? FindRoutine(string name) =>
        Find(name) ?? _ordered.FirstOrDefault(topic => topic.EntryLabels.Contains(name, StringComparer.Ordinal));

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

    private static DocumentationTopic Merge(DocumentationSet set, List<DocumentationComment> comments)
    {
        DocumentationComment first = comments[0];
        string name = first.Name;
        long? value = set._symbols.TryGetValue(name, out long found) ? found : null;
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
                    sections.Add(section.WithCondition(comment.Condition));
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
