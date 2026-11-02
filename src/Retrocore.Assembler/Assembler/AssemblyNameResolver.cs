// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Isa;

namespace Retrocore.Assembler;

/// <summary>
///  Collects lexical definitions before translating references into one compiler namespace.
/// </summary>
internal sealed partial class AssemblyNameResolver
{
    private readonly AssemblyProject _source;
    private readonly List<AssemblyError> _errors;
    private readonly Site[] _sites;
    private readonly string?[] _definitions;
    private readonly Scope _root = new(parent: null, name: "", opening: -1, procedure: false);
    private readonly string _privatePrefix;
    private readonly Dictionary<string, string> _sizes = new(StringComparer.Ordinal);

    // Statements that define each label, for .sizeof on a label: the size of the statement on its line.
    private readonly Dictionary<string, int> _labelLines = new(StringComparer.Ordinal);
    private Dictionary<string, int>? _labelSizes;
    private CancellationToken _cancellation;

    private AssemblyNameResolver(AssemblyProject source, List<AssemblyError> errors, CancellationToken cancellation)
    {
        _source = source;
        _errors = errors;
        _cancellation = cancellation;
        _sites = new Site[source.Statements.Count];
        _definitions = new string?[source.Statements.Count];
        _privatePrefix = "__retro_scope_";
        while (Mentions(source, _privatePrefix)) { _privatePrefix += "_"; }
    }

    /// <summary>
    ///  Gets the lowered project without changing caller-owned nodes.
    /// </summary>
    internal AssemblyProject Project { get; private set; } = new();

    /// <summary>
    ///  Gets bindings from plain export names to resolved compiler symbol names.
    /// </summary>
    internal Dictionary<string, string> Exports { get; } = new(StringComparer.Ordinal);

    /// <summary>
    ///  Detects name-resolution syntax during the compiler's existing declaration-count scan.
    /// </summary>
    /// <param name="node">The original statement.</param>
    /// <returns>Whether a resolution pass is necessary.</returns>
    internal static bool RequiresResolution(AssemblyStatement node)
    {
        return IsScopeDirective(node.Kind)
            || (node.Label is { Length: > 0 } name && name[0] is '@' or ':')
            || (node.Operand.MayReferenceScopes && HasScopedReference(node.Operand.Memory));
    }

    private static readonly AssemblyOperand s_emptyOperand = new("");

    private static bool HasScopedReference(ReadOnlyMemory<char> text)
    {
        AssemblyNameReferences references = new(text);
        while (references.MoveNext())
        {
            ReadOnlySpan<char> token = references.Current.Span;
            if (token[0] is '@' or ':' || token.IndexOf("::") >= 0) { return true; }
            if (token.Equals(".sizeof", StringComparison.OrdinalIgnoreCase)) { return true; }
        }

        return false;
    }

    /// <summary>
    ///  Collects all definitions, then resolves the source-ordered stream.
    /// </summary>
    /// <param name="source">The original editable model.</param>
    /// <param name="options">CPU defaults.</param>
    /// <param name="sets">The existing opcode maps.</param>
    /// <param name="errors">Receives structural and reference errors.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>The lowered stream and public-name mappings.</returns>
    internal static AssemblyNameResolver Resolve(
        AssemblyProject source,
        AssemblyOptions options,
        IReadOnlyDictionary<string, InstructionSet> sets,
        List<AssemblyError> errors,
        CancellationToken cancellationToken)
    {
        AssemblyNameResolver resolver = new(source, errors, cancellationToken);
        resolver.Collect();
        resolver.Lower(options, sets);
        return resolver;
    }

    /// <summary>
    ///  Removes symbols named through private unnamed labels, anonymous scopes or anonymous cheap-local contexts,
    ///  and restores original syntax for immutable source mappings.
    /// </summary>
    /// <param name="image">Successful transient compiler output.</param>
    internal void Publish(AssemblyImage image)
    {
        List<string>? hidden = null;
        foreach (string name in image.Symbols.Keys)
        {
            if (name.Contains(_privatePrefix, StringComparison.Ordinal))
            {
                (hidden ??= []).Add(name);
            }
        }

        if (hidden is not null)
        {
            foreach (string name in hidden) { image.Symbols.Remove(name); }
        }

        image.Project = _source;
        image.SymbolExports = new(Exports.Values, StringComparer.Ordinal);
    }

    private static bool Mentions(AssemblyProject source, string prefix)
    {
        foreach (AssemblyStatement node in source.Statements)
        {
            if (node.Label?.StartsWith(prefix, StringComparison.Ordinal) == true
                || node.Operand.Memory.Span.IndexOf(prefix.AsSpan(), StringComparison.Ordinal) >= 0)
            {
                return true;
            }
        }

        return false;
    }

    private void Collect()
    {
        Scope scope = _root;
        AssemblyDialect dialect = AssemblyDialect.Native;
        int anonymous = 0;
        int contexts = 0;
        List<(int Index, string Name)> unnamed = [];
        HashSet<string> defined = new(StringComparer.Ordinal);

        // As in ca65, one cheap-local context spans scopes: the first definition of an ordinary symbol starts a
        // context, entering a scope keeps it, and leaving a scope or switching dialect starts an anonymous one.
        string cheap = "";
        string FreshContext() => $"{_privatePrefix}cheap_{++contexts}";

        for (int index = 0; index < _source.Statements.Count; index++)
        {
            _cancellation.ThrowIfCancellationRequested();
            AssemblyStatement node = _source.Statements[index];
            if (node.Kind is AssemblyStatementKind.Section or AssemblyStatementKind.LogicalOrigin)
            {
                for (Scope? enclosing = scope; enclosing is not null; enclosing = enclosing.Parent)
                {
                    enclosing.Contiguous = false;
                }
            }

            if (index != 0 && node.Dialect != dialect)
            {
                unnamed = [];
                cheap = FreshContext();
            }

            dialect = node.Dialect;
            if (node.Kind is AssemblyStatementKind.Procedure or AssemblyStatementKind.Scope)
            {
                bool procedure = node.Kind == AssemblyStatementKind.Procedure;
                string name = node.Operand.Text.Trim();
                if (node.Label is not null || (name.Length == 0 ? procedure : !AssemblySyntax.IsPlainIdentifier(name)))
                {
                    _errors.Add(new(index, "A scope requires an unqualified name; .proc requires a name and neither takes a label."));
                }
                else
                {
                    if (name.Length == 0)
                    {
                        name = $"{_privatePrefix}anonymous_{index}";
                    }
                    else if (scope.Children.ContainsKey(name))
                    {
                        _errors.Add(new(index, $"Duplicate scope '{name}'."));
                    }

                    if (procedure)
                    {
                        scope.Definitions.Add(name);
                        string entry = scope.Qualify(name);
                        _definitions[index] = entry;
                        if (defined.Add(entry)) { cheap = entry; }
                    }
                    else
                    {
                        _definitions[index] = scope.Qualify($"{name}::{_privatePrefix}start");
                    }

                    _sites[index] = new(scope, cheap, unnamed);
                    Scope child = new(scope, name, index, procedure);
                    scope.Children[name] = child;
                    scope = child;
                    continue;
                }
            }
            else if (node.Kind is AssemblyStatementKind.EndProcedure or AssemblyStatementKind.EndScope)
            {
                _sites[index] = new(scope, cheap, unnamed);
                if (scope.Parent is null || scope.Procedure != (node.Kind == AssemblyStatementKind.EndProcedure))
                {
                    _errors.Add(new(index, "Scope terminator does not match an open .proc or .scope."));
                }
                else
                {
                    if (node.Operand.Memory.Length != 0 || node.Label is not null)
                    {
                        _errors.Add(new(index, "A scope terminator takes no operand or label."));
                    }

                    string end = scope.Qualify($"{_privatePrefix}end");
                    string start = scope.Procedure ? scope.Prefix : scope.Qualify($"{_privatePrefix}start");
                    _definitions[index] = end;
                    _sizes[scope.Prefix] = scope.Contiguous ? $"({end}-{start})" : "";

                    scope = scope.Parent;
                    cheap = FreshContext();
                }

                continue;
            }
            else if (node.Label is { } label)
            {
                if (label == ":")
                {
                    string name = scope.Qualify($"{_privatePrefix}label_{++anonymous}");
                    _definitions[index] = name;
                    unnamed.Add((index, name));
                }
                else if (label[0] == '@')
                {
                    _definitions[index] = QualifyCheap(cheap, label);
                }
                else
                {
                    // Symbols and scopes occupy separate namespaces, so a scope may share a symbol's name.
                    scope.Definitions.Add(label);
                    string qualified = scope.Qualify(label);
                    _definitions[index] = qualified;
                    if (defined.Add(qualified)) { cheap = qualified; }
                }
            }

            _sites[index] = new(scope, cheap, unnamed);
            if (_definitions[index] is { } sized && node.Label is not (null or ":") && HasSize(node.Kind))
            {
                _labelLines.TryAdd(sized, index);
            }
        }

        while (scope.Parent is not null)
        {
            _errors.Add(new(scope.Opening, "Unterminated .proc or .scope."));
            scope = scope.Parent;
        }
    }

    private void Lower(AssemblyOptions options, IReadOnlyDictionary<string, InstructionSet> sets)
    {
        AssemblyProject project = new(_source.Statements.Count)
        {
            InitialSection = _source.InitialSection,
            SymbolAliases = _source.SymbolAliases,
            MerlinOutput = _source.MerlinOutput,
            MemoryRegions = _source.MemoryRegions,
            LinkerSymbols = _source.LinkerSymbols
        };

        foreach (AssemblySource source in _source.Sources) { project.Sources.Add(source); }
        if (_source.DeclaredSections is { } sections)
        {
            foreach (AssemblySectionDefinition section in sections) { project.SectionDefinitions.Add(section); }
        }

        sets.TryGetValue(options.Cpu, out InstructionSet? codes);
        foreach (AssemblyStatement node in _source.Statements)
        {
            if (node.Kind == AssemblyStatementKind.Cpu
                && node.Label is null
                && AssemblyCompiler.TryCpu(node.Operand.Text, sets, out InstructionSet? first))
            {
                codes = first;
                break;
            }
        }

        for (int index = 0; index < _source.Statements.Count; index++)
        {
            _cancellation.ThrowIfCancellationRequested();
            AssemblyStatement node = _source.Statements[index];
            AssemblyStatementKind kind = node.Kind;
            ReadOnlyMemory<char> operation = node.OperationMemory;
            AssemblyOperand operand = node.Operand;
            if (kind == AssemblyStatementKind.Cpu)
            {
                if (AssemblyCompiler.TryCpu(operand.Text, sets, out InstructionSet? selected))
                {
                    codes = selected;
                }
            }
            else if (IsScopeDirective(kind))
            {
                kind = AssemblyStatementKind.Label;
                operation = default;
                operand = s_emptyOperand;
            }
            else if (kind == AssemblyStatementKind.Export)
            {
                try
                {
                    foreach (ReadOnlyMemory<char> name in new AssemblyOperands(operand.Memory, index))
                    {
                        if (!AssemblySyntax.IsPlainIdentifier(name.Span)) { continue; }
                        string exported = name.ToString();
                        Exports.TryAdd(exported, ResolveName(exported, _sites[index], index));
                    }
                }
                catch (AssemblyError error)
                {
                    _errors.Add(error);
                }
            }
            else
            {
                operand = Rewrite(node, _sites[index], index, codes);
            }

            project.Statements.Add(new(kind, operation, operand, _definitions[index])
            {
                Location = node.Location,
                WidthPolicy = node.WidthPolicy,
                Dialect = node.Dialect
            });
        }

        if (_labelSizes is not null)
        {
            project.LabelSizes ??= new(StringComparer.Ordinal);
            foreach (KeyValuePair<string, int> pair in _labelSizes) { project.LabelSizes[pair.Key] = pair.Value; }
        }

        Project = project;
    }

    private static bool HasSize(AssemblyStatementKind kind) => kind switch
    {
        AssemblyStatementKind.Label => true,
        AssemblyStatementKind.Instruction => true,
        AssemblyStatementKind.Data => true,
        AssemblyStatementKind.Reserve => true,
        AssemblyStatementKind.Align => true,
        AssemblyStatementKind.Checksum => true,
        _ => false
    };

    private static string QualifyCheap(string prefix, string name) => prefix.Length == 0 ? name : $"{prefix}::{name}";

    private static bool IsScopeDirective(AssemblyStatementKind kind) => kind switch
    {
        AssemblyStatementKind.Procedure => true,
        AssemblyStatementKind.EndProcedure => true,
        AssemblyStatementKind.Scope => true,
        AssemblyStatementKind.EndScope => true,
        _ => false
    };

    private static string ResolveName(string name, Site site, int index)
    {
        if (name.StartsWith("::", StringComparison.Ordinal)) { return name[2..]; }
        if (name[0] == '@') { return QualifyCheap(site.CheapPrefix, name); }
        int separator = name.IndexOf("::", StringComparison.Ordinal);
        if (separator < 0)
        {
            // Symbols resolve to the innermost scope that defines them anywhere, even later in source.
            for (Scope? scope = site.Scope; scope is not null; scope = scope.Parent)
            {
                if (scope.Definitions.Contains(name)) { return scope.Qualify(name); }
            }

            return name;
        }

        // As in ca65, a qualifying scope binds to one already opened at this point, so a later inner namespace
        // does not capture an earlier reference. Only without such a scope does a later one apply.
        string first = name[..separator];
        for (Scope? scope = site.Scope; scope is not null; scope = scope.Parent)
        {
            if (scope.Children.TryGetValue(first, out Scope? child) && child.Opening < index)
            {
                return scope.Qualify(name);
            }
        }

        for (Scope? scope = site.Scope; scope is not null; scope = scope.Parent)
        {
            if (scope.Children.ContainsKey(first)) { return scope.Qualify(name); }
        }

        return name;
    }

    /// <summary>
    ///  Qualifies the names in an operand.
    /// </summary>
    /// <param name="node">The statement.</param>
    /// <param name="site">The statement's scope context.</param>
    /// <param name="index">The statement index.</param>
    /// <param name="codes">The CPU's opcodes, if known.</param>
    /// <returns>The statement's own operand when no name changes, otherwise the rewritten operand.</returns>
    private AssemblyOperand Rewrite(AssemblyStatement node, Site site, int index, InstructionSet? codes)
    {
        ReadOnlySpan<char> text = node.Operand.Memory.Span;
        bool instruction = node.Kind == AssemblyStatementKind.Instruction;
        bool bitBranch = false;
        OperandFormMatcher? matcher = null;
        if (instruction && codes is not null)
        {
            ReadOnlySpan<char> mnemonic = node.OperationMemory.Span;
            if (mnemonic.EndsWith(".W", StringComparison.OrdinalIgnoreCase)) { mnemonic = mnemonic[..^2]; }
            int id = codes.GetMnemonic(mnemonic);
            matcher = OperandFormMatcher.Get(codes.Description);
            if (matcher.IsLiteral(codes, id, text.Trim())) { return node.Operand; }
            bitBranch = matcher.HasFieldList(codes, id);
        }

        // Unchanged text is copied into the result only once a name actually changes.
        List<string>? result = null;
        int copied = 0;
        AssemblyNameReferences references = new(node.Operand.Memory);
        while (references.MoveNext())
        {
            ReadOnlySpan<char> token = references.Current.Span;
            if (references.Start < copied) { continue; }
            if (token.Equals(".sizeof", StringComparison.OrdinalIgnoreCase))
            {
                int nameStart = references.Start + token.Length;
                while (nameStart < text.Length && char.IsWhiteSpace(text[nameStart])) { nameStart++; }
                if (nameStart < text.Length && text[nameStart] == '(')
                {
                    nameStart++;
                }
                else
                {
                    _errors.Add(new(index, ".sizeof requires a parenthesized procedure name."));
                    continue;
                }

                while (nameStart < text.Length && char.IsWhiteSpace(text[nameStart])) { nameStart++; }
                int length = AssemblySyntax.IdentifierLength(text[nameStart..]);
                string sizeName = text.Slice(nameStart, length).ToString();
                int end = nameStart + length;
                while (end < text.Length && char.IsWhiteSpace(text[end])) { end++; }
                bool closed = length > 0 && end < text.Length && text[end] == ')';
                if (!closed)
                {
                    _errors.Add(new(index, ".sizeof requires a parenthesized scope or procedure name."));
                    continue;
                }

                const string SizeSuffix = "::__retro_size";
                string scopedName = ResolveName(sizeName + SizeSuffix, site, index);
                scopedName = scopedName[..^SizeSuffix.Length];
                if (!_sizes.TryGetValue(scopedName, out string? size))
                {
                    // As in ca65, a label's size is that of the statement on its own line.
                    string label = ResolveName(sizeName, site, index);
                    if (!_labelLines.TryGetValue(label, out int line))
                    {
                        _errors.Add(new(index, $"Unknown size of '{sizeName}' in .sizeof."));
                        continue;
                    }

                    size = $"{label}::{_privatePrefix}size";
                    (_labelSizes ??= new(StringComparer.Ordinal))[size] = line;
                }

                if (size.Length == 0)
                {
                    _errors.Add(new(index, ".sizeof currently requires a contiguous procedure without section or origin changes."));
                    continue;
                }

                result ??= [];
                result.Add(text[copied..references.Start].ToString());
                result.Add(size);
                copied = end + 1;
                continue;
            }

            if (token[0] == '.') { continue; }
            int start = references.Start;
            if (node.Kind == AssemblyStatementKind.Section && text[..start].IndexOf(',') < 0) { continue; }
            // A register in its place in some operand pattern, such as X in addr,X or IX in [IX+d], is no symbol.
            if (instruction && (IsWidthPrefix(text, start, token.Length)
                || (!bitBranch && (matcher?.IsPatternWord(text, start, token.Length) ?? IsIndex(text, start, token.Length)))))
            {
                continue;
            }

            string name = references.Current.ToString();
            string replacement;
            if (token.Length >= 2 && token[0] == ':' && token[1] is '+' or '-')
            {
                bool forward = token[1] == '+';
                int distance = token.Length - 1;
                int low = 0;
                int high = site.Anonymous.Count;
                while (low < high)
                {
                    int middle = low + ((high - low) / 2);
                    if (site.Anonymous[middle].Index <= index) { low = middle + 1; }
                    else { high = middle; }
                }

                int at = forward ? low + distance - 1 : low - distance;
                replacement = name;
                if ((uint)at < (uint)site.Anonymous.Count) { replacement = site.Anonymous[at].Name; }
                else { _errors.Add(new(index, $"No matching unnamed label for '{name}'.")); }
            }
            else if (token.IndexOf("::@") >= 0)
            {
                _errors.Add(new(index, $"Cheap local '{name}' cannot be qualified."));
                continue;
            }
            else
            {
                replacement = ResolveName(name, site, index);
            }

            if (replacement == name) { continue; }
            result ??= [];
            result.Add(text[copied..start].ToString());
            result.Add(replacement);
            copied = start + token.Length;
        }

        if (result is null) { return node.Operand; }
        result.Add(text[copied..].ToString());
        return new(string.Concat(result));
    }

    private static bool IsIndex(ReadOnlySpan<char> text, int start, int length)
    {
        if (length != 1 || text[start] is not ('x' or 'X' or 'y' or 'Y')) { return false; }
        int before = start - 1;
        while (before >= 0 && char.IsWhiteSpace(text[before])) { before--; }
        int after = start + length;
        while (after < text.Length && char.IsWhiteSpace(text[after])) { after++; }
        return before >= 0 && text[before] == ',' && (after == text.Length || text[after] == ')');
    }

    private static bool IsWidthPrefix(ReadOnlySpan<char> text, int start, int length)
    {
        if (length != 1 || text[start] is not ('a' or 'A' or 'z' or 'Z')) { return false; }
        if (!text[..start].Trim().IsEmpty) { return false; }
        int end = start + length;
        while (end < text.Length && char.IsWhiteSpace(text[end])) { end++; }
        return end < text.Length && text[end] == ':' && (end + 1 == text.Length || text[end + 1] != ':');
    }
}
