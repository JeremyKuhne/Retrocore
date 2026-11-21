// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using System.Globalization;
using System.Text.RegularExpressions;

namespace Retrocore.Documentation;

public sealed partial class DocumentationResolver
{
    private static readonly string[] s_nothing = ["none", "nothing", "all"];

    // Every CPU the assembler knows, for documentation whose own CPU is unknown.
    private static readonly DocumentationCpu[] s_anyCpu =
        [.. CpuCatalog.InstructionSets.Values.Select(set => set.Description).Distinct().Select(DocumentationCpu.For)];

    /// <summary>
    ///  Checks the current documentation: placement, sections, references, links, inheritance and includes.
    /// </summary>
    /// <returns>The problems, the parser's included.</returns>
    public List<DocumentationDiagnostic> Check()
    {
        List<DocumentationDiagnostic> diagnostics = [.. Current.Files.SelectMany(file => file.Diagnostics)];
        foreach (DocumentationTopic topic in Current.Topics)
        {
            // A definition in another build of a conditional source, such as a routine only one model has, is
            // checked by the build that assembles it, where its links and entries are there.
            if (OtherBuilds(topic)) { continue; }
            CheckTopic(topic, diagnostics);
        }

        // An exported symbol is public API: it needs documentation, its own or as an entry of a routine.
        foreach ((string name, string path, int line) in Current.Exports)
        {
            bool parsed = Current.Files.Any(file => SamePath(file.Path, path));
            if (parsed && Current.FindRoutine(name) is null)
            {
                diagnostics.Add(new($"Exported '{name}' has no ;; documentation.", path, line, DocumentationSeverity.Warning));
            }
        }

        return diagnostics;
    }

    // Whether a topic documents a label or equate this assembly does not define: one in an .if branch it left out.
    private bool OtherBuilds(DocumentationTopic topic) =>
        topic.Kind is DocumentationKind.Routine or DocumentationKind.Table or DocumentationKind.Constant or DocumentationKind.Variable
            && Current.Symbols.Count != 0
            && topic.Value is null
            && !Current.Defines(topic.Name);

    private void CheckTopic(DocumentationTopic topic, List<DocumentationDiagnostic> diagnostics)
    {
        void Warn(string message, int line) =>
            diagnostics.Add(new(message, topic.Path, line, DocumentationSeverity.Warning));

        if (topic.Section("Inherit") is { } inherit)
        {
            List<DocumentationLink> links = DocumentationText.Links(inherit.Text);
            DocumentationTopic? target = InheritTarget(topic, inherit);
            if (target is null)
            {
                string message = links.Count != 0
                    ? $"Inherit: no documented definition named '{links[0].Target}'."
                    : $"Inherit: '{topic.Name}' is not an entry of a documented routine; name the topic to inherit.";

                Warn(message, inherit.Line);
            }
            else if (Cycles(topic))
            {
                diagnostics.Add(new(
                    $"Inherit: '{topic.Name}' inherits from itself.",
                    topic.Path,
                    inherit.Line,
                    DocumentationSeverity.Error));
            }

            foreach (string item in inherit.Items.Where(item => !DocumentationSections.IsKnown(item)))
            {
                Warn($"Inherit: '{item}' is not a section.", inherit.Line);
            }
        }

        if (topic.Section("Include") is { } include && Included(topic, include) is null)
        {
            Warn($"Include: '{include.Text}' names no file or topic that exists.", include.Line);
        }

        DocumentationTopic effective = Effective(topic);
        HashSet<string> entries = new(
            effective.Sections.Where(section => section.Name is "In" or "Out" or "Parameters" or "Flags")
                .SelectMany(section => section.Entries.Select(entry => entry.Name)),
            StringComparer.OrdinalIgnoreCase);

        // In a file that follows the style guide, every documented definition the prose names is a link.
        if (Current.Files.FirstOrDefault(file => SamePath(file.Path, topic.Path)) is { Strict: true })
        {
            CheckUnlinked(topic, entries, Warn);
        }

        // Links and {references} anywhere in the topic's own text.
        foreach ((string text, int line, DocumentationComment comment) in Texts(topic))
        {
            foreach (DocumentationLink link in DocumentationText.Links(text))
            {
                DocumentationTarget target = Resolve(topic, link.Target, comment);
                if (target.Kind == DocumentationTargetKind.Unresolved)
                {
                    Warn($"No definition, file or address named '{link.Target}'.", line);
                }
                else if (target.Kind == DocumentationTargetKind.Ambiguous)
                {
                    Warn($"'{link.Target}' names definitions in more than one place; qualify it with a module or model.", line);
                }
            }

            foreach ((string name, _, _) in DocumentationText.References(text))
            {
                if (!entries.Contains(name))
                {
                    Warn($"{{{name}}} is not an entry of this topic's In, Out, Flags or Parameters.", line);
                }
            }
        }

        foreach (DocumentationSection section in topic.Sections)
        {
            CheckSection(topic, section, Warn);
        }
    }

    private void CheckSection(DocumentationTopic topic, DocumentationSection section, Action<string, int> warn)
    {
        switch (section.Name)
        {
            case "In":
            case "Out":
                foreach (DocumentationEntry entry in section.Entries)
                {
                    if (Unknown(topic, entry.Name) is { } unknown)
                    {
                        warn(NotKnown(topic, section.Name, unknown), entry.Line);
                    }
                }

                // A bare list ("Out: BASL/BASH") must hold only names; anything else needs "name = meaning".
                bool bare = !section.Text.Contains('=') && section.Text.IndexOf(" - ", StringComparison.Ordinal) < 0;
                bool partial = bare && DocumentationText.SplitList(section.Text).Count != section.Entries.Count;
                if ((section.Entries.Count == 0 && section.Text.Length != 0) || partial)
                {
                    warn($"{section.Name}: write entries as 'name = meaning'.", section.Line);
                }

                break;
            case "Flags":
                warn("Flags: name flags in In or Out by word, as 'Out: carry = found'.", section.Line);
                break;
            case "Uses":
            case "Keeps":
                foreach (string written in section.Items)
                {
                    // A note in parentheses may follow an item: "BAS2L (scroll)".
                    int note = written.IndexOf(" (", StringComparison.Ordinal);
                    string item = note > 0 && written.EndsWith(')') ? written[..note] : written;
                    if (Array.IndexOf(s_nothing, item.ToLowerInvariant()) >= 0) { continue; }
                    if (item.Contains(' ', StringComparison.Ordinal))
                    {
                        warn($"{section.Name}: list registers and memory separated by commas, not '{item}'.", section.Line);
                    }
                    else if (Unknown(topic, item) is { } unknown)
                    {
                        warn(NotKnown(topic, section.Name, unknown), section.Line);
                    }
                }

                break;
            case "Also":
                CheckAlso(topic, section, warn);
                break;
            case "Entry":
                foreach (DocumentationEntry entry in section.Entries)
                {
                    if (!InsideRoutine(topic, entry.Name))
                    {
                        warn($"Entry: '{entry.Name}' is not a label inside {topic.Name}.", entry.Line);
                    }
                }

                break;
            case "Parameters":
                IReadOnlyList<string> declared = topic.Primary.Parameters;
                foreach (DocumentationEntry entry in section.Entries)
                {
                    if (declared.Count != 0 && !declared.Contains(entry.Name, StringComparer.OrdinalIgnoreCase))
                    {
                        warn($"Parameters: '{entry.Name}' is not a parameter of {topic.Name}.", entry.Line);
                    }
                }

                break;
            case "Members":
                foreach (DocumentationEntry entry in section.Entries)
                {
                    if (!topic.Primary.Members.Contains(entry.Name, StringComparer.OrdinalIgnoreCase))
                    {
                        warn($"Members: '{entry.Name}' is not a member of {topic.Name}.", entry.Line);
                    }
                }

                break;
        }
    }

    /// <summary>
    ///  Finds the first part of an entry name that is not a register, flag, number or known symbol. Names may
    ///  combine parts, as in <c>A1L/A1H</c>, <c>IN,X</c>, <c>SOFTEV+1</c> or <c>IN..IN+$FF</c>.
    /// </summary>
    private string? Unknown(DocumentationTopic topic, string name)
    {
        DocumentationCpu[] cpus = CpusOf(topic);

        // A flag's word may hold a hyphen (half-carry), which otherwise joins a range's parts.
        List<string> parts = [];
        foreach (string word in name.Split(['/', ',', '+', '(', ')', '.', '*', ' '], StringSplitOptions.RemoveEmptyEntries))
        {
            if (cpus.Any(cpu => cpu.Flag(word) is not null)) { continue; }
            parts.AddRange(word.Split('-', StringSplitOptions.RemoveEmptyEntries));
        }

        foreach (string part in parts)
        {
            if (cpus.Any(cpu => cpu.IsRegister(part) || cpu.Flag(part) is not null)) { continue; }
            bool hex = part[0] == '$' && long.TryParse(part[1..], NumberStyles.HexNumber, CultureInfo.InvariantCulture, out _);
            if (hex) { continue; }
            if (char.IsDigit(part[0]) || part[0] == '%') { continue; }
            if (part.Equals("Cn", StringComparison.Ordinal) || part.Equals("n", StringComparison.Ordinal)) { continue; }
            // A flag's letter is a symbol only where the routine's own assembly defines it: another module's (DOS's
            // option bit V) or a pair (CL and CH) is not what a flag's letter means.
            if (cpus.Any(cpu => cpu.FlagByLetter(part) is not null) && !Current.Symbols.ContainsKey(part))
            {
                return part;
            }

            if (Resolve(topic, part).IsResolved) { continue; }

            // Apple's A1 names the pair A1L/A1H.
            if (Resolve(topic, part + "L").IsResolved && Resolve(topic, part + "H").IsResolved) { continue; }
            return part;
        }

        return null;
    }

    /// <summary>
    ///  Gets the CPUs whose registers and flags a topic may name: the one its routine was assembled for, or
    ///  every CPU when that is unknown.
    /// </summary>
    private DocumentationCpu[] CpusOf(DocumentationTopic topic) =>
        Current.CpuAt(topic.Path, topic.Line) is { } cpu ? [DocumentationCpu.For(cpu)] : s_anyCpu;

    // The warning for a name the topic's CPU does not know, suggesting the word when it is a flag's letter.
    private string NotKnown(DocumentationTopic topic, string section, string name)
    {
        foreach (DocumentationCpu cpu in CpusOf(topic))
        {
            if (cpu.FlagByLetter(name) is { } flag)
            {
                return $"{section}: name the {flag.Name} flag by its word, '{flag.Words[0]}'; letters are only for registers.";
            }
        }

        return $"{section}: '{name}' is not a register, flag or symbol.";
    }

    // An entry label must lie between the routine's address and the next documented routine.
    private bool InsideRoutine(DocumentationTopic topic, string label)
    {
        if (!Current.Symbols.TryGetValue(label, out long address)) { return false; }
        if (topic.Value is not { } start) { return true; }
        long next = long.MaxValue;
        foreach (DocumentationTopic other in Current.Topics)
        {
            bool entry = topic.EntryLabels.Contains(other.Name, StringComparer.Ordinal);
            if (!entry && other.Kind == DocumentationKind.Routine && other.Value is { } value && value > start && value < next)
            {
                next = value;
            }
        }

        return address >= start && address < next;
    }

    private bool Cycles(DocumentationTopic topic)
    {
        HashSet<DocumentationTopic> seen = [topic];
        DocumentationTopic current = topic;
        while (current.Section("Inherit") is { } inherit && InheritTarget(current, inherit) is { } next)
        {
            if (!seen.Add(next)) { return true; }
            current = next;
        }

        return false;
    }

    private static bool SamePath(string a, string b) =>
        string.Equals(Path.GetFullPath(a), Path.GetFullPath(b), StringComparison.OrdinalIgnoreCase);

    // Every piece of a topic's own text, with the line it is on.
    private static IEnumerable<(string Text, int Line, DocumentationComment Comment)> Texts(DocumentationTopic topic)
    {
        foreach (DocumentationComment comment in topic.Comments)
        {
            if (comment.Summary.Length != 0) { yield return (comment.Summary, comment.Line, comment); }
            foreach (string remark in comment.Remarks) { yield return (remark, comment.Line, comment); }
            foreach (DocumentationSection section in comment.Sections)
            {
                if (section.Name is "Inherit" or "Include") { continue; }
                int offset = 0;
                foreach (string line in section.Lines)
                {
                    yield return (line, section.Line + offset, comment);
                    offset++;
                }
            }
        }
    }

    private void CheckAlso(DocumentationTopic topic, DocumentationSection section, Action<string, int> warn)
    {
        foreach (string item in section.Items)
        {
            if (DocumentationAlso.Parse(item) is not { } also)
            {
                warn($"Also: write a historical name and the documents that give it, as 'COUT (A2RM)', not '{item}'.", section.Line);
                continue;
            }

            if (also.Sources.Count == 0)
            {
                warn($"Also: say which document {also.Name} comes from, as '{also.Name} (A2RM)'.", section.Line);
            }

            foreach (string key in also.Sources)
            {
                if (Bibliography is not null && Bibliography.Find(key) is null)
                {
                    warn($"Also: no document '{key}' in the bibliography.", section.Line);
                }
            }

            if (also.Name == LastName(topic.Name))
            {
                warn($"Also: {also.Name} is already the definition's name.", section.Line);
            }
            else if (Current.Defines(also.Name))
            {
                warn($"Also: {also.Name} is also a definition, which code reaches instead of {topic.Name}.", section.Line);
            }
            else if (Current.Topics.FirstOrDefault(other => !ReferenceEquals(other, topic)
                && DocumentationAlso.Of(other.Sections).Any(name => name.Name == also.Name)) is { } other)
            {
                warn($"Also: {other.Name} has the historical name {also.Name} too.", section.Line);
            }
        }
    }

    private static string LastName(string name)
    {
        int separator = name.LastIndexOf("::", StringComparison.Ordinal);
        return separator < 0 ? name : name[(separator + 2)..];
    }

    // A name in prose, which may be qualified: not part of a longer word, an address or a call, and not an entry's
    // name before its "=".
    [GeneratedRegex(
        @"(?<![\w:$#.'])[A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)*(?![\w(]|\s*=(?!=))",
        RegexOptions.CultureInvariant)]
    private static partial Regex ProseName();

    // What a link, code span, reference or quotation holds, which is not prose to look for names in.
    [GeneratedRegex("<[^>]*>|`[^`]*`|\\{[^}]*\\}|\"[^\"]*\"", RegexOptions.CultureInvariant)]
    private static partial Regex NotProse();

    private void CheckUnlinked(DocumentationTopic topic, HashSet<string> entries, Action<string, int> warn)
    {
        HashSet<string> reported = [with(StringComparer.Ordinal)];
        foreach ((string text, int line) in Prose(topic))
        {
            string prose = NotProse().Replace(text, " ");
            foreach (Match word in ProseName().Matches(prose))
            {
                string name = word.Value;
                if (name.Length < 2 || entries.Contains(name) || name == topic.Name || name == LastName(topic.Name))
                {
                    continue;
                }

                // An instruction is not a definition to link, and a plain capitalized word that starts a sentence
                // is more likely English than a name.
                if (_isInstruction(name) || (StartsSentence(prose, word.Index) && IsPlainWord(name))) { continue; }

                DocumentationTarget resolved = Resolve(topic, name);
                if (resolved.Kind != DocumentationTargetKind.Topic || resolved.Topic is not DocumentationTopic target)
                {
                    continue;
                }

                if (ReferenceEquals(target, topic) || target.Kind is DocumentationKind.File or DocumentationKind.Topic)
                {
                    continue;
                }

                // A historical name, found through an Also: section, is history or a plain word in prose ("the listing
                // calls it RESET", "starts BASIC"), not the current name left unlinked.
                if (LastName(target.Name) != LastName(name)) { continue; }

                if (reported.Add($"{line}:{name}"))
                {
                    warn($"Link {name} as <{name}>: it names a documented definition.", line);
                }
            }
        }
    }

    private static bool StartsSentence(string text, int index)
    {
        string before = text[..index].TrimEnd();
        return before.Length == 0 || before[^1] is '.' or '!' or '?' or ';';
    }

    // A word with one capital, at its start, and no digits or underscores: "Procedure", not "SysDirectory".
    private static bool IsPlainWord(string name) =>
        char.IsAsciiLetterUpper(name[0]) && name.Skip(1).All(char.IsAsciiLetterLower);

    // A topic's prose: its summary, remarks, entries' meanings and free-text sections, not names in lists.
    private static IEnumerable<(string Text, int Line)> Prose(DocumentationTopic topic)
    {
        foreach (DocumentationComment comment in topic.Comments)
        {
            if (comment.Summary.Length != 0) { yield return (comment.Summary, comment.Line); }
            foreach (string remark in comment.Remarks) { yield return (remark, comment.Line); }
            foreach (DocumentationSection section in comment.Sections)
            {
                if (section.Entries.Count != 0)
                {
                    foreach (DocumentationEntry entry in section.Entries) { yield return (entry.Meaning, entry.Line); }
                }
                else if (section.Name is "Deprecated" || !section.IsKnown)
                {
                    int offset = 0;
                    foreach (string line in section.Lines)
                    {
                        yield return (line, section.Line + offset);
                        offset++;
                    }
                }
            }
        }
    }
}
