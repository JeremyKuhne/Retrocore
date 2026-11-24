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
    ///  Lints the current documentation: <see cref="Check"/>'s problems and any others found in its files, such as
    ///  the editor's, less what the files' <c>ignore=</c> exclusions turn off (see
    ///  <see cref="DocumentationExclusions"/>).
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   An exclusion that turns nothing off is reported only where the lint could have found something for it: not
    ///   for a rule only the editor runs (<see cref="DocumentationRules.EditorRules"/>) unless its problems are among
    ///   <paramref name="others"/>, and not for a rule of <c>;;</c> blocks (<see cref="DocumentationRules.TopicRules"/>)
    ///   whose range holds a block of a definition another build assembles, which this one doesn't check.
    ///  </para>
    /// </remarks>
    /// <param name="others">More problems in the current documentation's files, filtered with the rest.</param>
    /// <param name="otherRules">The rules that produced <paramref name="others"/>, found or not.</param>
    /// <returns>The problems that remain, with information on each exclusion that turns nothing off.</returns>
    public List<DocumentationDiagnostic> Lint(
        IEnumerable<DocumentationDiagnostic>? others = null,
        IEnumerable<string>? otherRules = null)
    {
        HashSet<string> run = [with(StringComparer.Ordinal), .. otherRules ?? []];
        // Another build's definitions are checked by that build, as are those outside a macro's body that the build has
        // none of, though the macro's expansion makes their topic this build's.
        List<DocumentationComment> skipped = [];
        foreach (DocumentationTopic topic in Current.Topics)
        {
            bool other = OtherBuilds(topic);
            skipped.AddRange(topic.Comments.Where(comment => other || OtherBuildOutside(topic, comment)));
        }

        bool Checked(DocumentationExclusion exclusion) =>
            (!DocumentationRules.EditorRules.Contains(exclusion.Rule) || run.Contains(exclusion.Rule))
                && !(DocumentationRules.TopicRules.Contains(exclusion.Rule) && skipped.Any(comment =>
                    SamePath(comment.Path, exclusion.Path)
                        && comment.Line <= exclusion.LastLine
                        && exclusion.FirstLine <= comment.TargetLine));

        List<DocumentationDiagnostic> diagnostics = others is null ? Check() : [.. Check(), .. others];
        return DocumentationExclusions.Apply(diagnostics, Current.Files, Checked);
    }

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
            // checked by the build that assembles it, where its links and entries are there. An old name in a
            // macro's body that no build could give is reported all the same.
            if (OtherBuilds(topic))
            {
                CheckExpandedAlso(topic, diagnostics);
                continue;
            }

            CheckTopic(topic, diagnostics);
        }

        // An exported symbol is public API: it needs documentation, its own or as an entry of a routine.
        foreach ((string name, string path, int line) in Current.Exports)
        {
            bool parsed = Current.Files.Any(file => SamePath(file.Path, path));
            if (parsed && Current.FindRoutine(name) is null)
            {
                diagnostics.Add(new(
                    $"Exported '{name}' has no ;; documentation.",
                    path,
                    line,
                    DocumentationSeverity.Warning,
                    DocumentationRules.UndocumentedExport));
            }
        }

        return diagnostics;
    }

    // Whether a topic documents a label or equate this assembly does not define: one in an .if branch it left out.
    private bool OtherBuilds(DocumentationTopic topic) => !Current.Assembles(topic);

    private void CheckTopic(DocumentationTopic topic, List<DocumentationDiagnostic> diagnostics)
    {
        void Warn(string rule, string message, int line, string? name = null)
        {
            diagnostics.Add(new(message, topic.Path, line, DocumentationSeverity.Warning, rule) { Name = name });
        }

        void Section(string message, int line) => Warn(DocumentationRules.Sections, message, line);

        // An outside definition the build leaves out, beside a macro's expansion, is checked by the build it's in.
        if (topic.Section("Inherit") is { } inherit && !OtherBuildOutside(topic, inherit))
        {
            List<DocumentationLink> links = DocumentationText.Links(inherit.Text);
            DocumentationTopic? target = InheritTarget(topic, inherit);
            if (target is null)
            {
                string message = links.Count != 0
                    ? $"Inherit: no documented definition named '{links[0].Target}'."
                    : $"Inherit: '{topic.Name}' is not an entry of a documented routine; name the topic to inherit.";

                Section(message, inherit.Line);
            }
            else if (Cycles(topic))
            {
                diagnostics.Add(new(
                    $"Inherit: '{topic.Name}' inherits from itself.",
                    topic.Path,
                    inherit.Line,
                    DocumentationSeverity.Error,
                    DocumentationRules.Sections));
            }

            foreach (string item in inherit.Items.Where(item => !DocumentationSections.IsKnown(item)))
            {
                Section($"Inherit: '{item}' is not a section.", inherit.Line);
            }
        }

        if (topic.Section("Include") is { } include
            && !OtherBuildOutside(topic, include)
            && Included(topic, include) is null)
        {
            Section($"Include: '{include.Text}' names no file or topic that exists.", include.Line);
        }

        DocumentationTopic effective = Effective(topic);
        HashSet<string> entries = new(
            effective.Sections.Where(section => section.Name is "In" or "Out" or "Parameters" or "Flags")
                .SelectMany(section => section.Entries.Select(entry => entry.Name)),
            StringComparer.OrdinalIgnoreCase);

        // In a file that follows the style guide, every documented definition the prose names is a link.
        if (Current.Files.FirstOrDefault(file => SamePath(file.Path, topic.Path)) is { Strict: true })
        {
            CheckUnlinked(topic, entries, (message, line, name) => Warn(DocumentationRules.UnlinkedName, message, line, name));
        }

        // Links and {references} anywhere in the topic's own text.
        foreach ((string text, int line, DocumentationComment comment) in Texts(topic).Where(item => !OtherBuildOutside(topic, item.Comment)))
        {
            foreach (DocumentationLink link in DocumentationText.Links(text))
            {
                DocumentationTarget target = Resolve(topic, link.Target, comment);
                if (target.Kind == DocumentationTargetKind.Unresolved)
                {
                    Warn(DocumentationRules.Link, $"No definition, file or address named '{link.Target}'.", line, link.Target);
                }
                else if (target.Kind == DocumentationTargetKind.Ambiguous)
                {
                    Warn(
                        DocumentationRules.AmbiguousLink,
                        $"'{link.Target}' names definitions in more than one place; qualify it with a module or model.",
                        line,
                        link.Target);
                }
            }

            foreach ((string name, _, _) in DocumentationText.References(text))
            {
                if (!entries.Contains(name))
                {
                    Section($"{{{name}}} is not an entry of this topic's In, Out, Flags or Parameters.", line);
                }
            }
        }

        foreach (DocumentationSection section in topic.Sections.Where(section => !OtherBuildOutside(topic, section)))
        {
            CheckSection(topic, section, Section, (message, line) => Warn(DocumentationRules.Also, message, line));
        }

        CheckExpandedAlso(topic, diagnostics);

        // A macro's body shares the topic of the name it defines with any other definition of that name, though each
        // is its own symbol: an old name two of them give is ambiguous to the assembler, as one two topics give is.
        // Branches of conditional assembly are one symbol, and only the build's branch counts.
        if (topic.Comments.All(comment => comment.Macro is null)) { return; }
        Dictionary<string, string> given = [with(StringComparer.Ordinal)];
        foreach (DocumentationComment comment in topic.Comments.Where(Current.ReachesInBuild))
        {
            if (comment.Section("Also") is not { } also) { continue; }
            string symbol = Current.SymbolOf(topic, comment);
            foreach (DocumentationAlso item in DocumentationAlso.Of(comment.Sections))
            {
                if (given.TryGetValue(item.Name, out string? earlier) && earlier != symbol)
                {
                    // Each comment of the topic may be in a file of its own.
                    diagnostics.Add(new(
                        $"Also: {item.Name} is given by two definitions of {topic.Name}, {earlier} and {symbol}, so code "
                            + "can't tell which it means; give it to one of them.",
                        comment.Path,
                        also.Line,
                        DocumentationSeverity.Warning,
                        DocumentationRules.Also));
                }

                given.TryAdd(item.Name, symbol);
            }
        }
    }

    // Reports each Also: in a macro's body that can't reach its definition, in the comment's own file.
    private void CheckExpandedAlso(DocumentationTopic topic, List<DocumentationDiagnostic> diagnostics)
    {
        foreach (DocumentationComment comment in topic.Comments)
        {
            if (comment.Section("Also") is { } also && ExpandedAlso(topic, comment) is { } expanded)
            {
                diagnostics.Add(new(expanded, comment.Path, also.Line, DocumentationSeverity.Error, DocumentationRules.Also));
            }
        }
    }

    // Why the old names a definition in a macro's body gives itself reach nothing. In no build can they reach a name
    // each expansion takes from an argument or makes its own local, nor a .set variable, which has a version for each
    // assignment; those are reported whether or not this build expands the macro. Otherwise they reach nothing when
    // this build defines the line more than once. Null when they reach it, or outside a macro's body.
    private string? ExpandedAlso(DocumentationTopic topic, DocumentationComment comment)
    {
        if (comment.Macro is not { } macro) { return null; }
        if (comment.NamedByParameter)
        {
            return $"Also: {topic.Name} is named by a parameter of the macro {macro}, so each expansion names it "
                + "after its argument and an old name can't reach it; give the old name in prose.";
        }

        if (comment.LocalToExpansion)
        {
            return $"Also: {topic.Name} is local to each expansion of the macro {macro}, so an old name can't "
                + "reach it; give the old name in prose.";
        }

        if (comment.Kind == DocumentationKind.Variable)
        {
            return $"Also: {topic.Name} is a .set variable in the macro {macro}, which each assignment gives a new "
                + "version, so an old name can't reach it; give the old name in prose.";
        }

        return Current.Expansions(comment) is > 1 and int count
            ? $"Also: {topic.Name} is defined {count} times, by expansions of the macro {macro}, so an old name "
                + "can't reach any of them; give the old name in prose."
            : null;
    }

    private void CheckSection(
        DocumentationTopic topic,
        DocumentationSection section,
        Action<string, int> warn,
        Action<string, int> also)
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
                // A routine written once per build gives each build's old names under its own condition.
                if (!Current.InBuild(topic, section) || OnlyUnreachedMacros(topic, section)) { break; }
                CheckAlso(topic, section, also);
                break;
            case "Entry":
                // A routine written once per build lists each build's entries under its own condition.
                if (!Current.InBuild(topic, section)) { break; }
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
                    else if (DocumentedMember(topic, entry.Name))
                    {
                        // A member with a block or trailing comment of its own is documented there.
                        warn($"{entry.Name} has its own documentation; remove it from Members:", entry.Line);
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


    // Whether an Entry: label is in the routine: from its address up to the next documented routine that is neither
    // one of its entries nor one of its own locals (a .proc's labels may have their own ;; blocks).
    private bool InsideRoutine(DocumentationTopic topic, string label)
    {
        if (!Current.Symbols.TryGetValue(Current.EntrySymbol(topic, label), out long address)) { return false; }
        if (topic.Value is not { } start) { return true; }
        HashSet<string> entries = [.. topic.EntryLabels.Select(entry => Current.EntrySymbol(topic, entry))];
        string local = $"{topic.Name}::";
        long next = long.MaxValue;
        foreach (DocumentationTopic other in Current.Topics)
        {
            bool inside = entries.Contains(other.Name) || other.Name.StartsWith(local, StringComparison.Ordinal);
            if (!inside && other.Kind == DocumentationKind.Routine && other.Value is { } value && value > start && value < next)
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

    // The type's other member of a name, qualified, or null.
    private string? SiblingMember(DocumentationTopic member, string name)
    {
        int separator = member.Name.LastIndexOf("::", StringComparison.Ordinal);
        if (separator <= 0) { return null; }
        string sibling = $"{member.Name[..separator]}::{name}";
        return sibling != member.Name && Current.Defines(sibling) ? sibling : null;
    }

    // Whether a type's member, named in any case, has a topic of its own.
    private bool DocumentedMember(DocumentationTopic topic, string name)
    {
        string? member = topic.Primary.Members.FirstOrDefault(item => item.Equals(name, StringComparison.OrdinalIgnoreCase));
        return member is not null && Current.Find($"{topic.Name}::{member}") is not null;
    }

    private void CheckAlso(DocumentationTopic topic, DocumentationSection section, Action<string, int> warn)
    {
        // A scope or a named type has no address or value for an old name to reach: its members do.
        if (topic.Kind is DocumentationKind.Scope or DocumentationKind.Struct or DocumentationKind.Enum)
        {
            warn($"Also: {topic.Name} is a scope or type, which an old name cannot reach; give old names to its members.", section.Line);
            return;
        }

        foreach (string item in section.Items)
        {
            if (item.Contains("::", StringComparison.Ordinal))
            {
                warn($"Also: a historical name is a plain name, as a listing wrote it, not '{item}'.", section.Line);
                continue;
            }

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

            // A member's own name does not reach it outside its type, so it may be the member's old name too.
            if (also.Name == (topic.Kind == DocumentationKind.Member ? topic.Name : LastName(topic.Name)))
            {
                warn($"Also: {also.Name} is already the definition's name.", section.Line);
            }
            else if (Current.Defines(also.Name))
            {
                warn($"Also: {also.Name} is also a definition, which code reaches instead of {topic.Name}.", section.Line);
            }
            else if (topic.Kind == DocumentationKind.Member && SiblingMember(topic, also.Name) is { } sibling)
            {
                warn($"Also: {also.Name} is also {sibling}, a member of the same type, which it would not mean.", section.Line);
            }
            else if (Current.AlsoOf(topic).Any(item => item.Name == also.Name)
                && Current.Topics.FirstOrDefault(other => Clashes(topic, other, also.Name)) is { } other)
            {
                warn($"Also: {other.Name} has the historical name {also.Name} too.", section.Line);
            }
        }
    }

    // Whether only definitions in macros' bodies whose old names reach nothing write a section, and its checks would
    // say nothing of use: the build defines the line other than once (never, which says nothing about the build's
    // definitions, or more, which CheckExpandedAlso reports), or the name varies, which it reports too. A scope or
    // type is still told so, and where the expansions aren't known the section is checked as any other.
    private bool OnlyUnreachedMacros(DocumentationTopic topic, DocumentationSection section)
    {
        IEnumerable<DocumentationComment> writers = topic.Comments.Where(comment => comment.Sections.Any(candidate =>
            candidate.Name.Equals(section.Name, StringComparison.OrdinalIgnoreCase) && candidate.Text == section.Text));

        return writers.Any() && writers.All(Unreached);
    }

    // Whether a definition in a macro's body has old names no check of its section helps with.
    private bool Unreached(DocumentationComment comment) =>
        comment.Macro is not null
            && comment.Kind is not (DocumentationKind.Scope or DocumentationKind.Struct or DocumentationKind.Enum)
            && (comment.NamedByParameter
                || comment.LocalToExpansion
                || comment.Kind == DocumentationKind.Variable
                || Current.Expansions(comment) is int count && count != 1);

    // Whether a definition outside macros' bodies, in a topic a macro's body shares, is another build's: the build has
    // none of the outside definitions, so without the macro the topic wouldn't be checked, though the macro's
    // expansion makes it this build's. With one of them in the build, every branch is checked, as without the macro.
    private bool OtherBuildOutside(DocumentationTopic topic, DocumentationComment comment) =>
        comment.Macro is null
            && topic.Comments.Any(other => other.Macro is not null)
            && !topic.Comments.Any(other => other.Macro is null && Current.ReachesInBuild(other));

    // Whether a section of a topic a macro's body shares is an outside definition's in a branch the build leaves out.
    private bool OtherBuildOutside(DocumentationTopic topic, DocumentationSection section) =>
        section.OriginPath is { } path
            && topic.Comments.Any(comment => comment.TargetLine == section.OriginLine
                && SamePath(comment.Path, path)
                && OtherBuildOutside(topic, comment));

    // Whether another definition in this build gives a definition's old name too.
    private bool Clashes(DocumentationTopic topic, DocumentationTopic other, string name) =>
        !ReferenceEquals(other, topic)
            && !OtherBuild(topic, other)
            && !OtherBuilds(other)
            && Current.Gives(other, name, thisBuild: true);

    // Whether two definitions are in different builds: in opposite branches of conditional assembly, as one model's
    // routine and another's are (one's condition holds a test the other's negates). Each build has only one of them,
    // so they can share a historical name. Conditions that could both hold are not different builds.
    private static bool OtherBuild(DocumentationTopic topic, DocumentationTopic other)
    {
        if (topic.Condition is not { } condition || other.Condition is not { } otherCondition) { return false; }

        // A condition in a macro's body is each expansion's own, so it never sets a definition apart in another build:
        // two expansions can take opposite branches of one, and an expansion can define what a branch outside leaves
        // in. Which lines the build defines, Reaches and Gives already count.
        if (InMacro(topic) || InMacro(other)) { return false; }

        string[] terms = condition.Split(" and ");
        string[] otherTerms = otherCondition.Split(" and ");
        return terms.Any(term => otherTerms.Contains($"not {term}") || term.StartsWith("not ", StringComparison.Ordinal)
            && otherTerms.Contains(term[4..]));
    }

    private static bool InMacro(DocumentationTopic topic) => topic.Comments.Any(comment => comment.Macro is not null);

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

    private void CheckUnlinked(DocumentationTopic topic, HashSet<string> entries, Action<string, int, string> warn)
    {
        HashSet<string> reported = [with(StringComparer.Ordinal)];
        foreach ((string text, int line, DocumentationComment comment) in Prose(topic).Where(item => !OtherBuildOutside(topic, item.Comment)))
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

                DocumentationTarget resolved = Resolve(topic, name, comment);
                if (resolved.Kind != DocumentationTargetKind.Topic || resolved.Topic is not DocumentationTopic target)
                {
                    continue;
                }

                // A scope's name is often a plain word too ("Pascal's cursor", "Control-E"), so prose may use it
                // without a link.
                if (ReferenceEquals(target, topic)
                    || target.Kind is DocumentationKind.File or DocumentationKind.Topic or DocumentationKind.Scope)
                {
                    continue;
                }

                // A historical name, found through an Also: section, is history or a plain word in prose ("the listing
                // calls it RESET", "starts BASIC"), not the current name left unlinked.
                if (LastName(target.Name) != LastName(name)) { continue; }

                if (reported.Add($"{line}:{name}"))
                {
                    warn($"Link {name} as <{name}>: it names a documented definition.", line, name);
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
    private static IEnumerable<(string Text, int Line, DocumentationComment Comment)> Prose(DocumentationTopic topic)
    {
        foreach (DocumentationComment comment in topic.Comments)
        {
            if (comment.Summary.Length != 0) { yield return (comment.Summary, comment.Line, comment); }
            foreach (string remark in comment.Remarks) { yield return (remark, comment.Line, comment); }
            foreach (DocumentationSection section in comment.Sections)
            {
                if (section.Entries.Count != 0)
                {
                    foreach (DocumentationEntry entry in section.Entries)
                    {
                        yield return (entry.Meaning, entry.Line, comment);
                    }
                }
                else if (section.Name is "Deprecated" || !section.IsKnown)
                {
                    int offset = 0;
                    foreach (string line in section.Lines)
                    {
                        yield return (line, section.Line + offset, comment);
                        offset++;
                    }
                }
            }
        }
    }
}
