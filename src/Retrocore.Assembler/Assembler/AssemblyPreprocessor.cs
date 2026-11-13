// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  Bounded, source-ordered expansion shared by dialect front ends.
/// </summary>
/// <remarks>Each active expanded line is parsed exactly once, directly into the resulting project.</remarks>
internal sealed partial class AssemblyPreprocessor
{
    private readonly AssemblyOptions _options;
    private CancellationToken _cancellation;
    private readonly List<(int Order, AssemblyDiagnostic Diagnostic)> _diagnostics = [];
    private readonly List<AssemblySource> _sources = [];
    private readonly AssemblyProject _project = new();
    private readonly List<Conditional> _conditions = [];
    private readonly Dictionary<string, Macro> _macros = new(StringComparer.Ordinal);

    // Created once so translating each ca65 line does not allocate a delegate.
    private readonly Func<string, bool> _isMacro;
    private readonly AssemblySymbols _constants = new();
    private readonly HashSet<string> _defined = new(StringComparer.Ordinal);
    private readonly HashSet<string> _activeIncludes = new(
        Path.DirectorySeparatorChar == '\\' ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal);
    private int _visited;
    private int _invocation;
    private bool _stopped;

    // The latest .cpu name in source order, or null before the first.
    private string? _cpu;

    // Whether the line being expanded is native, so shared ca65 features evaluate native expression syntax.
    private bool _nativeSyntax;

    private AssemblyPreprocessor(AssemblyOptions options, CancellationToken cancellation)
    {
        _options = options;
        _cancellation = cancellation;
        _isMacro = _macros.ContainsKey;
    }

    /// <summary>
    ///  Expands all roots in one environment and parses only the resulting active statements.
    /// </summary>
    /// <param name="sources">The ordered root documents.</param>
    /// <param name="options">Expansion limits, source resolution and inherited settings.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Expanded syntax and physical source diagnostics.</returns>
    internal static AssemblyParseResult Parse(
        IEnumerable<AssemblySource> sources,
        AssemblyOptions options,
        CancellationToken cancellationToken)
    {
        AssemblyPreprocessor processor = new(options, cancellationToken);
        processor.Predefine();
        foreach (AssemblySource source in sources)
        {
            ArgumentNullException.ThrowIfNull(source);
            processor.ProcessSource(
                source,
                options.Dialect,
                parent: null,
                explicitDialect: null,
                depth: 1,
                macroDepth: 0);

            if (processor._stopped) { break; }
        }

        processor.CloseConditions(depth: 0);
        processor.FinishMerlin();
        processor.FinishMacro10();
        if (processor._ca65State is { } ca65)
        {
            foreach (TypeFrame type in ca65.Types) { processor.Error("Unterminated ca65 type.", type.Opening); }
        }

        AssemblyProject project = processor._project;
        foreach (AssemblySource source in processor._sources) { project.Sources.Add(source); }
        return new(project, [.. processor._diagnostics.OrderBy(item => item.Order).Select(item => item.Diagnostic)]);
    }

    /// <summary>
    ///  Recognizes a file-level dialect selection without scanning the document's body.
    /// </summary>
    /// <param name="source">The document.</param>
    /// <param name="options">Optional inherited settings.</param>
    /// <returns>Whether dialect dispatch is needed.</returns>
    internal static bool HasDialectSelection(AssemblySource source, AssemblyOptions? options)
    {
        if (HasPragma(source.Text))
        {
            ReadOnlySpan<char> first = source.Text;
            int end = first.IndexOfAny('\r', '\n');
            first = (end < 0 ? first : first[..end]).Trim();
            return !string.Equals(PragmaValue(source.Text, "dialect"), "native", StringComparison.OrdinalIgnoreCase);
        }

        return (source.Dialect ?? options?.Dialect ?? AssemblyDialect.Native) != AssemblyDialect.Native;
    }

    /// <summary>
    ///  Recognizes directives requiring expansion.
    /// </summary>
    /// <param name="operation">The original operation.</param>
    /// <returns>Whether this is a preprocessing directive.</returns>
    internal static bool IsDirective(ReadOnlySpan<char> operation) =>
        operation.Length > 2
            && operation[0] == '.'
            && (operation.Equals(".include", StringComparison.OrdinalIgnoreCase)
                || operation.Equals(".macro", StringComparison.OrdinalIgnoreCase)
                || operation.Equals(".endmacro", StringComparison.OrdinalIgnoreCase)
                || operation.Equals(".repeat", StringComparison.OrdinalIgnoreCase)
                || operation.Equals(".endrepeat", StringComparison.OrdinalIgnoreCase)
                || operation.Equals(".if", StringComparison.OrdinalIgnoreCase)
                || operation.Equals(".ifdef", StringComparison.OrdinalIgnoreCase)
                || operation.Equals(".ifndef", StringComparison.OrdinalIgnoreCase)
                || operation.Equals(".ifblank", StringComparison.OrdinalIgnoreCase)
                || operation.Equals(".elseif", StringComparison.OrdinalIgnoreCase)
                || operation.Equals(".else", StringComparison.OrdinalIgnoreCase)
                || operation.Equals(".endif", StringComparison.OrdinalIgnoreCase)
                || operation.Equals(".local", StringComparison.OrdinalIgnoreCase)
                || operation.Equals(".exitmacro", StringComparison.OrdinalIgnoreCase)
                || operation.Equals(".incbin", StringComparison.OrdinalIgnoreCase)
                || IsCa65Condition(operation));

    /// <summary>
    ///  Recognizes directives that only the preprocessor implements, including the ca65 features native shares.
    /// </summary>
    /// <param name="operation">The unrecognized operation.</param>
    /// <returns>Whether parsing must restart through preprocessing.</returns>
    internal static bool IsExpansion(ReadOnlySpan<char> operation) =>
        IsDirective(operation) || IsCa65Metadata(operation);

    /// <summary>
    ///  Finds a <c>.name(</c> function call outside strings and comments, which only preprocessing may expand.
    /// </summary>
    /// <param name="line">The physical line.</param>
    /// <returns>Whether the line calls a dotted function.</returns>
    internal static bool HasFunctionCall(ReadOnlySpan<char> line)
    {
        for (int index = 0; index < line.Length; index++)
        {
            char character = line[index];
            if (character == ';') { return false; }
            if (character is '"' or '\'')
            {
                int close = line[(index + 1)..].IndexOf(character);
                if (close < 0) { return false; }
                index += close + 1;
                continue;
            }

            if (character != '.' || index + 1 >= line.Length || !char.IsAsciiLetter(line[index + 1])) { continue; }
            int end = index + 1;
            while (end < line.Length && AssemblySyntax.IsWord(line[end])) { end++; }
            while (end < line.Length && line[end] is ' ' or '\t') { end++; }
            if (end < line.Length && line[end] == '(' && IsPreprocessorFunction(line[(index + 1)..end].TrimEnd()))
            {
                return true;
            }

            index = end - 1;
        }

        return false;
    }

    // Functions the preprocessor evaluates; native expressions handle .lobyte and the other operator words.
    private static bool IsPreprocessorFunction(ReadOnlySpan<char> name) =>
        name.Length switch
        {
            3 => name.Equals("def", StringComparison.OrdinalIgnoreCase)
                || name.Equals("max", StringComparison.OrdinalIgnoreCase)
                || name.Equals("min", StringComparison.OrdinalIgnoreCase)
                || name.Equals("ref", StringComparison.OrdinalIgnoreCase)
                || name.Equals("mid", StringComparison.OrdinalIgnoreCase),
            _ => name.Equals("defined", StringComparison.OrdinalIgnoreCase)
                || name.Equals("definedmacro", StringComparison.OrdinalIgnoreCase)
                || name.Equals("sizeof", StringComparison.OrdinalIgnoreCase)
                || name.Equals("concat", StringComparison.OrdinalIgnoreCase)
                || name.Equals("ident", StringComparison.OrdinalIgnoreCase)
                || name.Equals("strlen", StringComparison.OrdinalIgnoreCase)
                || name.Equals("string", StringComparison.OrdinalIgnoreCase)
                || name.Equals("sprintf", StringComparison.OrdinalIgnoreCase)
                || name.Equals("loword", StringComparison.OrdinalIgnoreCase)
                || name.Equals("hiword", StringComparison.OrdinalIgnoreCase)
                || name.Equals("referenced", StringComparison.OrdinalIgnoreCase)
                || name.Equals("match", StringComparison.OrdinalIgnoreCase)
                || name.Equals("xmatch", StringComparison.OrdinalIgnoreCase)
                || name.Equals("tcount", StringComparison.OrdinalIgnoreCase)
                || name.Equals("blank", StringComparison.OrdinalIgnoreCase)
                || name.Equals("left", StringComparison.OrdinalIgnoreCase)
                || name.Equals("right", StringComparison.OrdinalIgnoreCase)
                || name.Equals("const", StringComparison.OrdinalIgnoreCase)
                || name.Equals("strat", StringComparison.OrdinalIgnoreCase)
        };

    /// <summary>
    ///  Gets one <c>key=value</c> word of a first-line <c>; retrocore:</c> pragma, such as a MACRO-10 overlay's base.
    /// </summary>
    /// <param name="text">The source text.</param>
    /// <param name="key">The key.</param>
    /// <returns>The value, or null when the pragma or key is absent.</returns>
    internal static string? PragmaValue(string text, string key)
    {
        if (!HasPragma(text)) { return null; }
        int end = text.IndexOfAny(['\r', '\n']);
        string first = (end < 0 ? text : text[..end]).Trim();
        foreach (string word in first["; retrocore:".Length..].Split([' ', '\t'], StringSplitOptions.RemoveEmptyEntries))
        {
            int separator = word.IndexOf('=');
            if (separator > 0 && word[..separator].Equals(key, StringComparison.OrdinalIgnoreCase))
            {
                return word[(separator + 1)..];
            }
        }

        return null;
    }

    private static bool HasPragma(string text)
    {
        ReadOnlySpan<char> first = text;
        int end = first.IndexOfAny('\r', '\n');
        first = (end < 0 ? first : first[..end]).TrimStart();
        return first.StartsWith("; retrocore:", StringComparison.OrdinalIgnoreCase);
    }

    private AssemblyDialect? Pragma(AssemblySource source)
    {
        if (!HasPragma(source.Text)) { return null; }
        ReadOnlySpan<char> first = source.Text;
        int end = first.IndexOfAny('\r', '\n');
        first = (end < 0 ? first : first[..end]).Trim();
        if (PragmaValue(source.Text, "dialect") is { } name
            && Enum.TryParse(name, ignoreCase: true, out AssemblyDialect dialect)
            && Enum.IsDefined(dialect))
        {
            return dialect;
        }

        Error("Expected '; retrocore: dialect=native|ca65|merlin|macro10'.", new(source.Path, line: 0));
        return null;
    }

    private bool ProcessSource(
        AssemblySource source,
        AssemblyDialect inherited,
        AssemblyLocation? parent,
        AssemblyDialect? explicitDialect,
        int depth,
        int macroDepth)
    {
        _cancellation.ThrowIfCancellationRequested();
        AssemblyDialect dialect = explicitDialect ?? Pragma(source) ?? source.Dialect ?? inherited;
        if (dialect == AssemblyDialect.Merlin) { CollectMerlinEquates(source); }

        if (dialect is not (AssemblyDialect.Native or AssemblyDialect.Ca65 or AssemblyDialect.Merlin or AssemblyDialect.Macro10))
        {
            Error($"The {dialect} dialect front end is not implemented yet.", new(source.Path, 0, expandedFrom: parent));
            return false;
        }

        if (depth > _options.MaximumIncludeDepth)
        {
            Error("Maximum include depth exceeded.", parent ?? new(source.Path, line: 0));
            return false;
        }

        string identity = source.Path;
        if (identity.Length != 0 && !_activeIncludes.Add(identity))
        {
            Error($"Include cycle involving '{identity}'.", parent ?? new(identity, line: 0));
            return false;
        }

        _sources.Add(source);
        if (dialect == AssemblyDialect.Macro10)
        {
            ProcessMacro10(source, parent);
            if (identity.Length != 0) { _activeIncludes.Remove(identity); }
            return false;
        }

        List<Line> lines = [];
        int number = 0;
        foreach (ReadOnlyMemory<char> line in new AssemblyLines(source.Text.AsMemory()))
        {
            lines.Add(new(line, new(source.Path, number++, expandedFrom: parent), dialect));
        }

        // As in ca65, conditionals are balanced per file: an include cannot close its includer's block.
        int floor = _conditions.Count;
        bool exit = Process(lines, substitutions: null, depth, macroDepth, floor, frame: null);
        CloseConditions(floor, report: !exit);
        if (identity.Length != 0) { _activeIncludes.Remove(identity); }
        return exit;
    }

    private bool Process(
        IReadOnlyList<Line> lines,
        Dictionary<string, string>? substitutions,
        int includeDepth,
        int macroDepth,
        int conditionFloor,
        MacroFrame? frame)
    {
        for (int index = 0; index < lines.Count && !_stopped; index++)
        {
            _cancellation.ThrowIfCancellationRequested();
            Line original = lines[index];
            if (++_visited > _options.MaximumExpandedLines)
            {
                Error("Maximum expanded-line count exceeded.", original.Location);
                _stopped = true;
                break;
            }

            ReadOnlyMemory<char> text = original.Dialect == AssemblyDialect.Merlin
                ? original.Text
                : Substitute(original.Text, substitutions, frame);

            _nativeSyntax = original.Dialect == AssemblyDialect.Native;
            if (_nativeSyntax)
            {
                DirectiveLabel(ref original, ref text);

                // Native sources share ca65's text definitions, types, character map and functions, but keep
                // native expression syntax.
                try
                {
                    if (PrepareCa65(ref original, ref text)) { continue; }
                    if (_ca65State is { CharactersChanged: true })
                    {
                        original = new(Ca65LineCharacters(AssemblySyntax.AsString(text)), original.Location, original.Dialect);
                        text = original.Text;
                    }
                }
                catch (AssemblyError failure)
                {
                    if (_conditions.Count == 0 || _conditions[^1].Active) { Error(failure.Message, original.Location); }
                    continue;
                }
                catch (OverflowException)
                {
                    if (_conditions.Count == 0 || _conditions[^1].Active)
                    {
                        Error("Expansion overflow.", original.Location);
                    }

                    continue;
                }
            }

            if (original.Dialect == AssemblyDialect.Merlin)
            {
                try
                {
                    string translated = TranslateMerlin(original, substitutions, frame, master: includeDepth == 1);
                    original = new(translated, original.Location, original.Dialect);
                    text = original.Text;
                }
                catch (AssemblyError failure)
                {
                    Error(failure.Message, original.Location);
                    continue;
                }
            }

            if (original.Dialect == AssemblyDialect.Ca65)
            {
                DirectiveLabel(ref original, ref text);
                try
                {
                    if (PrepareCa65(ref original, ref text)) { continue; }
                    string translated = Ca65LineCharacters(Ca65Frontend.Translate(text.Span, _options.BuildTime, _isMacro));
                    original = new(translated, original.Location, original.Dialect);
                    text = original.Text;
                }
                catch (AssemblyError failure)
                {
                    if (_conditions.Count == 0 || _conditions[^1].Active) { Error(failure.Message, original.Location); }
                    continue;
                }
                catch (OverflowException)
                {
                    if (_conditions.Count == 0 || _conditions[^1].Active)
                    {
                        Error("ca65 expansion overflow.", original.Location);
                    }

                    continue;
                }
            }

            Split(text.Span, out ReadOnlySpan<char> labelText, out ReadOnlySpan<char> operationText, out ReadOnlySpan<char> operandText);
            if (!IsDirective(operationText))
            {
                // Ordinary lines allocate nothing here unless a macro could match their operation.
                if (_conditions.Count != 0 && !_conditions[^1].Active) { continue; }
                if (_macros.Count != 0
                    && !operationText.IsEmpty
                    && _macros.TryGetValue(operationText.ToString(), out Macro? macro)
                    && (macro.Cpu is null || string.Equals(macro.Cpu, _cpu, StringComparison.OrdinalIgnoreCase)))
                {
                    if (!labelText.IsEmpty) { Emit(original, labelText is ":" ? ":" : $"{labelText}:"); }
                    ExpandMacro(
                        macro,
                        operandText.ToString(),
                        original,
                        includeDepth,
                        macroDepth,
                        merlin: original.Dialect == AssemblyDialect.Merlin);

                    continue;
                }

                Emit(original, text);
                continue;
            }

            string operation = operationText.ToString();
            string directive = operation.ToUpperInvariant();
            string operand = operandText.ToString();
            if (ConditionalDirective(directive, operand, original.Location, conditionFloor, original.Dialect))
            {
                continue;
            }

            if (_conditions.Count != 0 && !_conditions[^1].Active) { continue; }
            if (directive == ".MACRO")
            {
                IReadOnlyList<Line>? body = Capture(lines, ref index, ".MACRO", ".ENDMACRO", original.Location);
                if (body is not null)
                {
                    DefineMacro(operand, body, original.Location, substitutions, frame);
                    if (original.Dialect == AssemblyDialect.Merlin)
                    {
                        // Labels in a Merlin macro body are local to each expansion, as in Merlin 32.
                        string name = operand.Split(' ')[0];
                        if (_macros.TryGetValue(name, out Macro? macro))
                        {
                            HashSet<string> labels = new(StringComparer.Ordinal);
                            foreach (Line member in body)
                            {
                                MerlinFrontend.Split(member.Text.Span, out string local, out _, out _);
                                if (local.Length != 0 && local[0] != ']') { labels.Add(local); }
                            }

                            macro.MerlinLocals = [.. labels];
                        }
                    }
                }

                continue;
            }

            if (directive == ".REPEAT")
            {
                IReadOnlyList<Line>? body = Capture(lines, ref index, ".REPEAT", ".ENDREPEAT", original.Location);
                if (body is not null && Repeat(original, body, substitutions, includeDepth, macroDepth, frame))
                {
                    return true;
                }

                continue;
            }

            if (directive == ".INCLUDE")
            {
                if (Include(operand, original, includeDepth, macroDepth)) { return true; }
                continue;
            }

            if (directive == ".EXITMACRO")
            {
                if (operand.Length != 0) { Error(".exitmacro takes no operand.", original.Location); }
                else if (macroDepth == 0) { Error(".exitmacro requires a macro invocation.", original.Location); }
                else { return true; }
                continue;
            }

            if (directive == ".LOCAL")
            {
                DeclareLocals(original, frame, substitutions);
                continue;
            }

            if (directive is ".ENDMACRO" or ".ENDREPEAT")
            {
                Error($"Unexpected {operation}.", original.Location);
                continue;
            }

            if (directive == ".INCBIN")
            {
                IncludeBinary(operand, original);
                continue;
            }

            Error($"Unsupported preprocessing directive '{operation}'.", original.Location);
        }

        return false;
    }

    private bool Repeat(
        Line original,
        IReadOnlyList<Line> body,
        Dictionary<string, string>? substitutions,
        int includeDepth,
        int macroDepth,
        MacroFrame? frame)
    {
        Split(original.Text.Span, out _, out _, out ReadOnlySpan<char> repeatOperand);
        List<string> args = Arguments(repeatOperand.ToString());
        if (args.Count is < 1 or > 2)
        {
            Error(".repeat requires a count and optional counter.", original.Location);
            return false;
        }

        if (!Constant(Substitute(args[0], substitutions, frame), original.Location, out long count)) { return false; }
        if (count < 0 || count > _options.MaximumRepeatCount)
        {
            Error("Repeat count exceeds the configured limit.", original.Location);
            return false;
        }

        string? counter = args.Count == 2 ? args[1].Trim() : null;
        if (counter is not null && !AssemblySyntax.IsPlainIdentifier(counter))
        {
            Error("Invalid repeat counter name.", original.Location);
            return false;
        }

        // The counter is visible only in this body's own lines, not in macros it invokes, as in ca65.
        Dictionary<string, string>? names = substitutions;
        if (counter is not null)
        {
            names = substitutions is null ? new(StringComparer.Ordinal) : new(substitutions, StringComparer.Ordinal);
        }

        for (long iteration = 0; iteration < count && !_stopped; iteration++)
        {
            if (counter is not null && names is not null)
            {
                names[counter] = $"{iteration}";
            }

            int floor = _conditions.Count;
            bool exit = Process(body, names, includeDepth, macroDepth, floor, frame);
            CloseConditions(floor, report: !exit);
            if (exit) { return true; }
        }

        return false;
    }

    /// <summary>
    ///  Defines a label written on a preprocessing directive's line, then removes it from the line.
    /// </summary>
    /// <param name="original">The line, whose label is removed.</param>
    /// <param name="text">The line after substitution, whose label is removed.</param>
    /// <remarks>
    ///  As in ca65, the label names the address where the directive appears and is defined only when the code just
    ///  before the directive is assembled, so one on <c>.else</c> or <c>.endif</c> follows the block it closes.
    /// </remarks>
    private void DirectiveLabel(ref Line original, ref ReadOnlyMemory<char> text)
    {
        Split(text.Span, out ReadOnlySpan<char> label, out ReadOnlySpan<char> operation, out _);
        if (label.IsEmpty || !ConsumesLine(operation)) { return; }

        bool active = _conditions.Count == 0 || _conditions[^1].Active;
        if (active) { Emit(original, label is ":" ? ":" : $"{label}:"); }
        text = WithoutLabel(text);
        original = new(WithoutLabel(original.Text), original.Location, original.Dialect);
    }

    // The line after its leading label and the label's colon.
    private static ReadOnlyMemory<char> WithoutLabel(ReadOnlyMemory<char> line)
    {
        ReadOnlySpan<char> span = line.Span;
        int start = span.Length - span.TrimStart().Length;
        int length = span[start] == ':' ? 0 : AssemblySyntax.IdentifierLength(span[start..]);
        return line[(start + length + 1)..];
    }

    // Directives that the preprocessor consumes, so the statement parser never sees their line's label.
    private static bool ConsumesLine(ReadOnlySpan<char> operation) =>
        IsDirective(operation)
            || operation.Equals(".define", StringComparison.OrdinalIgnoreCase)
            || operation.Equals(".undefine", StringComparison.OrdinalIgnoreCase)
            || operation.Equals(".charmap", StringComparison.OrdinalIgnoreCase)
            || operation.Equals(".out", StringComparison.OrdinalIgnoreCase)
            || operation.Equals(".warning", StringComparison.OrdinalIgnoreCase)
            || operation.Equals(".error", StringComparison.OrdinalIgnoreCase)
            || operation.Equals(".fatal", StringComparison.OrdinalIgnoreCase)
            || operation.Equals(".feature", StringComparison.OrdinalIgnoreCase)
            || operation.Equals(".debuginfo", StringComparison.OrdinalIgnoreCase)
            || operation.Equals(".list", StringComparison.OrdinalIgnoreCase)
            || operation.Equals(".smart", StringComparison.OrdinalIgnoreCase);

    private void Emit(Line original, string text) => Emit(original, text.AsMemory());

    private void Emit(Line original, ReadOnlyMemory<char> text)
    {
        AssemblyStatement? node = Assembler.ParseLine(text, original.Location.Line, out _, out string? error);
        if (error is not null)
        {
            Error(error, original.Location);
            return;
        }

        if (node is null) { return; }
        node.Location = original.Location;
        node.Dialect = original.Dialect;
        if (node.Kind == AssemblyStatementKind.Cpu)
        {
            // The .ifp* conditions and .cpu's value follow the latest .cpu in source order. The shared ca65
            // state is made only once a line needs it, so a plain native source stays on its fast path.
            _cpu = node.Operand.Text;
            if (_ca65State is { } state) { state.Cpu = Ca65CpuNumber(_cpu); }
        }

        if (original.Dialect != AssemblyDialect.Native) { node.WidthPolicy = AssemblyWidthPolicy.SourceOrder; }
        _project.Statements.Add(node);
        if (TrackScope(node)) { return; }
        if (node.Label is not { } name) { return; }
        if (name == ":") { return; }
        bool cheap = name[0] == '@';
        name = cheap ? ConstantQualified(_constantCheap, name) : ConstantQualified(_constantScope, name);

        // As in ca65, the first definition of an ordinary symbol starts a cheap-local context.
        if (_defined.Add(name) && !cheap) { _constantCheap = name; }
        if (node.Kind is not (AssemblyStatementKind.Constant or AssemblyStatementKind.Variable))
        {
            _constants.Unset(name);
            return;
        }

        try
        {
            // Without scopes or local names the operand's own characters are the expression.
            ReadOnlyMemory<char> operand = node.Operand.Memory;
            ReadOnlyMemory<char> expression = _constantScope.Length == 0 && operand.Span.IndexOfAny('@', ':') < 0
                ? operand
                : ConstantExpression(node.Operand.Text).AsMemory();

            ExpressionEvaluator evaluator = new(expression, _constants, address: 0, line: 0);
            if (evaluator.TryEvaluate(out long value) && !evaluator.ReadsAddress)
            {
                _constants.SetValue(name, value);
            }
            else
            {
                _constants.Unset(name);
            }
        }
        catch (AssemblyError failure)
        {
            // Merlin EQU bodies are textual until used; an unused body need not be a numeric expression.
            if (original.Dialect != AssemblyDialect.Merlin || node.Kind != AssemblyStatementKind.Constant)
            {
                Error(failure.Message, original.Location);
            }

            _constants.Unset(name);
        }
        catch (OverflowException)
        {
            Error("Expression overflow.", original.Location);
            _constants.Unset(name);
        }
    }

    private bool Constant(string text, AssemblyLocation location, out long value, string purpose = "Conditional")
    {
        value = 0;
        try
        {
            ExpressionEvaluator evaluator = new(ConstantExpression(text).AsMemory(), _constants, address: 0, line: 0);
            if (evaluator.TryEvaluate(out value) && !evaluator.ReadsAddress) { return true; }
            Error($"{purpose} requires a constant known at this point in source order.", location);
        }
        catch (AssemblyError error)
        {
            Error(error.Message, location);
        }
        catch (OverflowException)
        {
            Error("Expression overflow.", location);
        }

        return false;
    }

    private void Error(string message, AssemblyLocation location, int? order = null) =>
        _diagnostics.Add((order ?? _visited, new(message, location)));
}
