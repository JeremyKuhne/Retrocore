// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;

namespace Retrocore.Assembler;

/// <summary>
///  Expands MACRO-10 source, the PDP-10 assembler Microsoft used for 6502 BASIC, into native statements.
/// </summary>
/// <remarks>
///  <para>
///   MACRO-10 is bracket structured rather than line structured: a conditional, <c>DEFINE</c> or <c>REPEAT</c>
///   body is a <c>&lt;...&gt;</c> group that may open and close mid-line and span many lines. The expander reads a
///   whole file, evaluates conditionals against the assignments seen so far, expands macros and repeats, and
///   writes flat native lines, each with the location of the source it came from. Lines from a macro body carry
///   the invocation as their expansion, so a debugger can step through them.
///  </para>
///  <para>
///   The 6502 instructions come from Microsoft's unpublished M6502 universal file, which <c>SEARCH M6502</c>
///   names. The expander supplies them as the source uses them: <c>LDA</c> with zero-page or absolute chosen by
///   the native assembler, an <c>I</c> suffix for immediate, <c>DY</c> for <c>(zp),Y</c>, <c>DX</c> for
///   <c>(zp,X)</c>, <c>JMPD</c> for an indirect jump, and <c>,X</c> or <c>,Y</c> for indexing. Each PDP-10 word
///   of data is one 6502 byte, as in Microsoft's 6502 simulator.
///  </para>
///  <para>
///   Symbols are significant to six characters and matched without case. A source name that native syntax
///   cannot spell, such as <c>$Z</c>, is given a generated alias. Pass-dependent <c>IF1</c> code is skipped and
///   <c>IF2</c> code kept, as in MACRO-10's final pass.
///  </para>
/// </remarks>
internal sealed partial class Macro10Expander
{
    // Separates statements on one physical line, such as the copies an IRPC writes.
    private const char StatementBreak = '\u001E';

    private readonly List<Output> _output = [];
    private readonly List<(string Message, AssemblyLocation Location)> _errors = [];
    private readonly Dictionary<string, Macro> _macros = new(StringComparer.Ordinal);
    private readonly Dictionary<string, long?> _values = new(StringComparer.Ordinal);

    // Label addresses as this expander lays code out, for conditionals and instruction sizes only; the native
    // assembler computes the addresses it emits.
    private readonly Dictionary<string, long> _addresses = new(StringComparer.Ordinal);
    private readonly Dictionary<string, int> _assignments = new(StringComparer.Ordinal);
    private readonly Dictionary<string, string> _aliases = new(StringComparer.Ordinal);
    private readonly HashSet<string> _natives = new(StringComparer.OrdinalIgnoreCase);
    private readonly int _maximumStatements;
    private readonly int _maximumDepth;
    private int _statements;
    private int _depth;
    private int _radix = 8;
    private long? _location = 0;
    private bool _ended;

    /// <summary>
    ///  Creates an expander.
    /// </summary>
    /// <param name="maximumStatements">The most statements expansion may produce.</param>
    /// <param name="maximumDepth">The deepest macro nesting.</param>
    /// <param name="predefined">Symbols the build defines, which conditionals and IFDEF see.</param>
    internal Macro10Expander(int maximumStatements, int maximumDepth, IReadOnlyDictionary<string, long>? predefined = null)
    {
        _maximumStatements = maximumStatements;
        _maximumDepth = maximumDepth;
        foreach (KeyValuePair<string, long> symbol in predefined ?? new Dictionary<string, long>())
        {
            _values[Normalize(symbol.Key)] = symbol.Value;
        }
    }

    /// <summary>
    ///  Gets the errors, each at the source it concerns.
    /// </summary>
    internal IReadOnlyList<(string Message, AssemblyLocation Location)> Errors => _errors;

    /// <summary>
    ///  Gets source names mapped to the generated names native syntax uses for them.
    /// </summary>
    internal IReadOnlyDictionary<string, string> Aliases => _aliases;

    /// <summary>
    ///  Expands a source file.
    /// </summary>
    /// <param name="text">The source text.</param>
    /// <param name="path">The source path.</param>
    /// <param name="parent">The including location, if any.</param>
    /// <returns>The native lines, in order, with their locations.</returns>
    internal IReadOnlyList<(string Text, AssemblyLocation Location)> Expand(string text, string path, AssemblyLocation? parent) =>
        Expand(text, line => new(path, line, column: 0, parent));

    /// <summary>
    ///  Expands text whose lines come from different places, such as an overlay composed with its base.
    /// </summary>
    /// <param name="text">The text.</param>
    /// <param name="location">The source location of each line, by line index.</param>
    /// <returns>The native lines, in order, with their locations.</returns>
    internal IReadOnlyList<(string Text, AssemblyLocation Location)> Expand(string text, Func<int, AssemblyLocation> location)
    {
        Process(new(text.Replace("\r\n", "\n"), location));

        // A symbol assigned more than once is a native variable, so each use reads the value assigned before it.
        List<(string Text, AssemblyLocation Location)> lines = new(_output.Count);
        foreach (Output output in _output)
        {
            if (output.Variable is not { } variable)
            {
                lines.Add((output.Text, output.Location));
                continue;
            }

            string assignment = _assignments[variable] > 1 ? $"{variable} .set {output.Text}" : $"{variable} = {output.Text}";
            lines.Add((assignment, output.Location));
        }

        return lines;
    }

    private void Process(Chunk chunk)
    {
        string text = chunk.Text;
        int position = 0;
        int line = 0;
        while (position < text.Length && !_ended)
        {
            char character = text[position];
            if (character == '\n')
            {
                line++;
                position++;
                continue;
            }

            if (character is ' ' or '\t' or '\r' or '\f' or StatementBreak)
            {
                position++;
                continue;
            }

            if (character == ';')
            {
                while (position < text.Length && text[position] != '\n') { position++; }
                continue;
            }

            AssemblyLocation location = chunk.Location(line);
            try
            {
                if (++_statements > _maximumStatements)
                {
                    throw new AssemblyError(0, "Maximum expanded-line count exceeded.");
                }

                Statement(chunk, ref position, ref line, location);
            }
            catch (AssemblyError error)
            {
                _errors.Add((error.Message, location));
                if (_statements > _maximumStatements)
                {
                    _ended = true;
                    return;
                }

                SkipStatement(text, ref position);
            }
        }
    }

    private void Statement(Chunk chunk, ref int position, ref int line, AssemblyLocation location)
    {
        string text = chunk.Text;

        // Labels end in ':', '::' (global) or ':!' (suppressed); an assignment is a name followed by '='.
        while (true)
        {
            int start = position;
            string? name = ReadSymbol(text, ref position);
            if (name is null) { break; }
            int after = position;
            SkipBlanks(text, ref after);
            if (after < text.Length && text[after] == ':')
            {
                position = after + 1;
                if (position < text.Length && text[position] is ':' or '!') { position++; }
                DefineLabel(name, location);
                SkipBlanks(text, ref position);
                continue;
            }

            if (after < text.Length && text[after] == '=')
            {
                position = after + 1;
                if (position < text.Length && text[position] == '=') { position++; }
                if (position < text.Length && text[position] == ':') { position++; }
                Assign(name, ReadOperand(text, ref position), location);
                return;
            }

            position = start;
            break;
        }

        if (AtStatementEnd(text, position)) { return; }
        int wordStart = position;
        string? word = ReadSymbol(text, ref position);
        if (word is null)
        {
            Data(ReadOperand(text, ref position), location);
            return;
        }

        if (PseudoOperation(word.ToUpperInvariant(), chunk, ref position, ref line, location)) { return; }
        if (_macros.TryGetValue(Normalize(word), out Macro? macro))
        {
            Call(macro, text, ref position, location);
            return;
        }

        if (Instruction(word.ToUpperInvariant(), ReadOperand(text, ref position), location)) { return; }

        // Anything else is an expression whose value is one data word.
        position = wordStart;
        Data(ReadOperand(text, ref position), location);
    }

    private bool PseudoOperation(string word, Chunk chunk, ref int position, ref int line, AssemblyLocation location)
    {
        string text = chunk.Text;
        switch (word)
        {
            // Listing, cross-reference and symbol-table controls change nothing a 6502 runs.
            case "TITLE":
            case "SUBTTL":
            case "PRINTX":
            case "SEARCH":
            case "PURGE":
            case "PAGE":
            case "SALL":
            case "XALL":
            case "LALL":
            case "XLIST":
            case "LIST":
            case ".XCREF":
            case ".CREF":
                _ = ReadOperand(text, ref position);
                return true;
            case "END":
                _ = ReadOperand(text, ref position);
                _ended = true;
                return true;
            case "COMMENT":
                SkipComment(text, ref position, ref line);
                return true;
            case "RADIX":
                // The radix operand is always decimal.
                string radix = ReadOperand(text, ref position);
                _radix = int.TryParse(radix, NumberStyles.None, CultureInfo.InvariantCulture, out int value) && value is >= 2 and <= 10
                    ? value
                    : throw new AssemblyError(0, $"Unsupported radix '{radix}'.");

                return true;
            case "ORG":
                string origin = ReadOperand(text, ref position);
                Emit($".org {Expression(origin)}", location, size: 0);
                _location = Evaluate(origin);
                return true;
            case "BLOCK":
                string reserved = ReadOperand(text, ref position);
                Emit($".res {Expression(reserved)}", location, size: 0);
                _location = _location + Evaluate(reserved);
                return true;
            case "EXP":
                foreach (string item in Arguments(ReadOperand(text, ref position))) { Data(item, location); }
                return true;
            case "XWD":
                // Each word is a 6502 byte, so only the right half emits; the M6502 file marks raw opcodes this way.
                List<string> halves = Arguments(ReadOperand(text, ref position));
                if (halves.Count != 2) { throw new AssemblyError(0, "XWD requires a left and right half."); }
                Data(halves[1], location);
                return true;
            case "ADR":
                foreach (string item in Arguments(Unparenthesized(ReadOperand(text, ref position))))
                {
                    Emit($".word {Expression(item)}", location, size: 2);
                }

                return true;
            case "DC":
                Characters(Unparenthesized(ReadOperand(text, ref position)), location);
                return true;
            case "DEFINE":
                Define(chunk, ref position, ref line);
                return true;
            case "REPEAT":
                long count = Constant(ReadCondition(text, ref position));
                (string body, int bodyLine) = ReadBody(text, ref position, ref line);
                if (count < 0) { throw new AssemblyError(0, "REPEAT requires a nonnegative count."); }
                for (long iteration = 0; iteration < count && !_ended; iteration++)
                {
                    Process(Sub(chunk, body, bodyLine));
                }

                return true;
            case "IRP":
            case "IRPC":
                throw new AssemblyError(0, $"{word} is only valid in a macro body over one of its arguments.");
        }

        return Conditional(word, chunk, ref position, ref line);
    }

    private bool Conditional(string word, Chunk chunk, ref int position, ref int line)
    {
        string text = chunk.Text;
        bool include;
        switch (word)
        {
            case "IFE":
            case "IFN":
            case "IFG":
            case "IFGE":
            case "IFL":
            case "IFLE":
                long value = Constant(ReadCondition(text, ref position));
                include = word switch
                {
                    "IFE" => value == 0,
                    "IFN" => value != 0,
                    "IFG" => value > 0,
                    "IFGE" => value >= 0,
                    "IFL" => value < 0,
                    _ => value <= 0
                };

                break;
            case "IFDEF":
            case "IFNDEF":
                string symbol = Normalize(ReadCondition(text, ref position).Trim());
                include = _values.ContainsKey(symbol) == (word == "IFDEF");
                break;
            case "IF1":
            case "IF2":
                // Only the final pass emits code, so pass-two text applies and pass-one text does not.
                SkipBlanks(text, ref position);
                if (position < text.Length && text[position] == ',') { position++; }
                include = word == "IF2";
                break;
            case "IFIDN":
            case "IFDIF":
            case "IFB":
            case "IFNB":
                (string left, string right) = ReadComparison(text, ref position, word is "IFB" or "IFNB");
                bool same = string.Equals(left, right, StringComparison.Ordinal);
                include = word is "IFIDN" or "IFB" ? same : !same;
                break;
            default:
                return false;
        }

        (string body, int bodyLine) = ReadBody(text, ref position, ref line);
        if (include) { Process(Sub(chunk, body, bodyLine)); }
        return true;
    }

    private void Define(Chunk chunk, ref int position, ref int line)
    {
        string text = chunk.Text;
        SkipBlanks(text, ref position);
        string name = ReadSymbol(text, ref position) ?? throw new AssemblyError(0, "DEFINE requires a macro name.");
        SkipBlanks(text, ref position);
        List<string> parameters = [];
        if (position < text.Length && text[position] == '(')
        {
            int close = text.IndexOf(')', position);
            if (close < 0) { throw new AssemblyError(0, "Unterminated DEFINE argument list."); }
            foreach (string parameter in text[(position + 1)..close].Split(','))
            {
                if (parameter.Trim().Length != 0) { parameters.Add(parameter.Trim().ToUpperInvariant()); }
            }

            position = close + 1;
        }

        SkipBlanks(text, ref position);
        if (position < text.Length && text[position] == ',') { position++; }
        (string body, int bodyLine) = ReadBody(text, ref position, ref line);
        _macros[Normalize(name)] = new([.. parameters], body, offset => chunk.Location(bodyLine + offset));
    }

    private void Call(Macro macro, string text, ref int position, AssemblyLocation location)
    {
        // Arguments are in parentheses right after the name, or the rest of the statement split at commas.
        List<string> arguments;
        if (position < text.Length && text[position] == '(')
        {
            int start = position;
            int depth = 0;
            for (; position < text.Length; position++)
            {
                if (text[position] == '(') { depth++; }
                else if (text[position] == ')' && --depth == 0) { break; }
            }

            if (depth != 0) { throw new AssemblyError(0, "Unterminated macro argument list."); }
            arguments = Arguments(text[(start + 1)..position]);
            position++;
            _ = ReadOperand(text, ref position);
        }
        else
        {
            arguments = Arguments(ReadOperand(text, ref position));
        }

        if (_depth >= _maximumDepth) { throw new AssemblyError(0, "Maximum macro recursion depth exceeded."); }
        string body = Substitute(macro.Body, macro.Parameters, arguments);

        // Each invocation is its own expansion, so a debugger can tell repeated calls from one line apart.
        AssemblyLocation call = location.Occurrence();
        _depth++;
        try
        {
            Process(new(body, offset =>
            {
                AssemblyLocation physical = macro.Location(offset);
                return new(physical.Path, physical.Line, physical.Column, call, macro: true);
            }));
        }
        finally
        {
            _depth--;
        }
    }

    /// <summary>
    ///  Replaces a macro's dummy arguments with its call's arguments, expanding each IRPC over one argument's
    ///  characters first.
    /// </summary>
    /// <param name="body">The macro body.</param>
    /// <param name="parameters">The dummy argument names.</param>
    /// <param name="arguments">The call's arguments.</param>
    /// <returns>The expanded text.</returns>
    private static string Substitute(string body, string[] parameters, List<string> arguments)
    {
        List<string> parts = [];
        int copied = 0;
        for (int index = 0; index < body.Length;)
        {
            if (!IsSymbolStart(body[index]))
            {
                index++;
                continue;
            }

            int start = index;
            while (index < body.Length && IsSymbolCharacter(body[index])) { index++; }
            string token = body[start..index].ToUpperInvariant();
            if (token is "IRPC" or "IRP" && Iteration(body, ref index, parameters, arguments) is { } copies)
            {
                parts.Add(body[copied..start]);
                parts.Add(copies);
                copied = index;
                continue;
            }

            int parameter = Array.IndexOf(parameters, token);
            if (parameter < 0) { continue; }
            parts.Add(body[copied..start]);
            parts.Add(parameter < arguments.Count ? arguments[parameter] : "");
            copied = index;
        }

        parts.Add(body[copied..]);
        return string.Concat(parts);
    }

    /// <summary>
    ///  Expands <c>IRPC arg,&lt;body&gt;</c> or <c>IRP arg,&lt;body&gt;</c>: one copy of the body per character
    ///  of the argument, or per comma-separated item, with the dummy argument replaced by it.
    /// </summary>
    /// <param name="body">The macro body.</param>
    /// <param name="index">The position after the keyword, moved past the construct when it is one.</param>
    /// <param name="parameters">The dummy argument names.</param>
    /// <param name="arguments">The call's arguments.</param>
    /// <returns>The copies, separated as statements, or null when the keyword does not start an iteration.</returns>
    private static string? Iteration(string body, ref int index, string[] parameters, List<string> arguments)
    {
        bool characters = body[index - 1] is 'C' or 'c';
        int position = index;
        SkipBlanks(body, ref position);
        int start = position;
        while (position < body.Length && IsSymbolCharacter(body[position])) { position++; }
        int parameter = Array.IndexOf(parameters, body[start..position].ToUpperInvariant());
        SkipBlanks(body, ref position);
        if (parameter < 0 || position >= body.Length || body[position] != ',') { return null; }
        position++;
        SkipBlanks(body, ref position);
        int line = 0;
        (string inner, _) = ReadBody(body, ref position, ref line);
        index = position;

        string value = parameter < arguments.Count ? arguments[parameter] : "";
        IEnumerable<string> items = characters ? value.Select(character => character.ToString()) : Arguments(value);
        List<string> copies = [];
        foreach (string item in items)
        {
            List<string> replaced = [.. arguments];
            while (replaced.Count <= parameter) { replaced.Add(""); }
            replaced[parameter] = item;
            copies.Add(Substitute(inner, parameters, replaced));
        }

        return string.Join(StatementBreak.ToString(), copies);
    }

    private void Assign(string name, string operand, AssemblyLocation location)
    {
        string symbol = Normalize(name);
        (string text, long? value) = Translate(operand);
        _values[symbol] = value;
        if (Evaluate(operand) is { } address) { _addresses[symbol] = address; }
        else { _addresses.Remove(symbol); }

        string native = NativeName(symbol);
        _assignments[native] = _assignments.TryGetValue(native, out int count) ? count + 1 : 1;
        _output.Add(new(text, location, native));
    }

    private void DefineLabel(string name, AssemblyLocation location)
    {
        string symbol = Normalize(name);
        if (!_values.ContainsKey(symbol)) { _values[symbol] = null; }
        if (_location is { } address) { _addresses[symbol] = address; }
        Emit($"{NativeName(symbol)}:", location, size: 0);
    }

    private void Data(string operand, AssemblyLocation location)
    {
        if (operand.Length == 0) { throw new AssemblyError(0, "Expected a data expression."); }
        Emit($".byte <({Expression(operand)})", location, size: 1);
    }

    /// <summary>
    ///  Emits the M6502 file's <c>DC</c>: a quoted string's characters, the last with its high bit set, as in
    ///  BASIC's reserved-word and error tables.
    /// </summary>
    /// <param name="operand">The quoted string.</param>
    /// <param name="location">The source location.</param>
    private void Characters(string operand, AssemblyLocation location)
    {
        string text = operand.Trim();
        if (text.Length < 3 || text[0] != '"' || text[^1] != '"')
        {
            throw new AssemblyError(0, "DC requires a quoted string.");
        }

        string characters = text[1..^1];
        List<string> bytes = [];
        for (int index = 0; index < characters.Length; index++)
        {
            int value = characters[index] & 0x7F;
            if (index == characters.Length - 1) { value |= 0x80; }
            bytes.Add(value.ToString(CultureInfo.InvariantCulture));
        }

        Emit($".byte {string.Join(",", bytes)}", location, bytes.Count);
    }

    private void Emit(string text, AssemblyLocation location, int size)
    {
        _output.Add(new(text, location, Variable: null));
        _location += size;
    }

    private long Constant(string expression)
    {
        string message = $"'{expression.Trim()}' must be a constant defined before it is used here.";
        return Evaluate(expression) ?? throw new AssemblyError(0, message);
    }

    private string Expression(string expression) => Translate(expression).Text;

    private static Chunk Sub(Chunk parent, string body, int bodyLine) => new(body, offset => parent.Location(bodyLine + offset));

    /// <summary>
    ///  Normalizes a symbol as MACRO-10 matches it: without case and to six characters.
    /// </summary>
    /// <param name="name">The source name.</param>
    /// <returns>The normalized name.</returns>
    private static string Normalize(string name)
    {
        string upper = name.ToUpperInvariant();
        return upper.Length > 6 ? upper[..6] : upper;
    }

    /// <summary>
    ///  Gets the native name for a normalized symbol, generating an alias for one native syntax cannot spell or
    ///  reserves.
    /// </summary>
    /// <param name="symbol">The normalized symbol.</param>
    /// <returns>The native name.</returns>
    private string NativeName(string symbol)
    {
        if (_aliases.TryGetValue(symbol, out string? alias)) { return alias; }
        if (AssemblySyntax.IsPlainIdentifier(symbol) && !IsReserved(symbol)) { return symbol; }
        alias = $"__m10_{_aliases.Count}";
        _aliases.Add(symbol, alias);
        return alias;
    }

    private static bool IsSymbolStart(char character) =>
        char.IsAsciiLetter(character) || character is '.' or '$' or '%';

    private static bool IsSymbolCharacter(char character) => IsSymbolStart(character) || char.IsAsciiDigit(character);

    private static string? ReadSymbol(string text, ref int position)
    {
        if (position >= text.Length || !IsSymbolStart(text[position])) { return null; }
        int start = position;
        while (position < text.Length && IsSymbolCharacter(text[position])) { position++; }

        // A lone '.' is the location counter, not a symbol.
        if (position - start == 1 && text[start] == '.')
        {
            position = start;
            return null;
        }

        return text[start..position];
    }

    private static void SkipBlanks(string text, ref int position)
    {
        while (position < text.Length && text[position] is ' ' or '\t' or '\r' or '\f') { position++; }
    }

    private static bool AtStatementEnd(string text, int position) =>
        position >= text.Length || text[position] is '\n' or ';' or StatementBreak;

    private static void SkipStatement(string text, ref int position)
    {
        while (position < text.Length && text[position] is not ('\n' or StatementBreak)) { position++; }
    }

    /// <summary>
    ///  Reads the rest of a statement, without its comment.
    /// </summary>
    /// <param name="text">The text.</param>
    /// <param name="position">The position, moved to the statement's end.</param>
    /// <returns>The trimmed operand.</returns>
    private static string ReadOperand(string text, ref int position)
    {
        int start = position;
        bool quoted = false;
        while (position < text.Length)
        {
            char character = text[position];
            if (character == '"') { quoted = !quoted; }
            if (character is '\n' or StatementBreak || (character == ';' && !quoted)) { break; }
            position++;
        }

        string operand = text[start..position].Trim();
        if (position < text.Length && text[position] == ';')
        {
            while (position < text.Length && text[position] != '\n') { position++; }
        }

        return operand;
    }

    /// <summary>
    ///  Reads a conditional's or repeat's expression up to its comma, outside brackets.
    /// </summary>
    /// <param name="text">The text.</param>
    /// <param name="position">The position, moved past the comma.</param>
    /// <returns>The expression.</returns>
    private static string ReadCondition(string text, ref int position)
    {
        int start = position;
        int depth = 0;
        for (; position < text.Length; position++)
        {
            char character = text[position];
            if (character == '<') { depth++; }
            else if (character == '>') { depth--; }
            else if (character == ',' && depth == 0) { break; }
            else if (character is '\n' or ';') { throw new AssemblyError(0, "Expected ',' and a <body>."); }
        }

        if (position >= text.Length) { throw new AssemblyError(0, "Expected ',' and a <body>."); }
        string condition = text[start..position];
        position++;
        return condition;
    }

    /// <summary>
    ///  Reads <c>IFIDN</c>/<c>IFDIF</c>'s two bracketed strings, or <c>IFB</c>/<c>IFNB</c>'s one, and the comma.
    /// </summary>
    /// <param name="text">The text.</param>
    /// <param name="position">The position, moved past the comma.</param>
    /// <param name="single">Whether there is one string, compared with blank.</param>
    /// <returns>The strings.</returns>
    private static (string Left, string Right) ReadComparison(string text, ref int position, bool single)
    {
        int line = 0;
        SkipBlanks(text, ref position);
        (string left, _) = ReadBody(text, ref position, ref line);
        string right = "";
        if (!single)
        {
            SkipBlanks(text, ref position);
            if (position < text.Length && text[position] == ',') { position++; }
            SkipBlanks(text, ref position);
            (right, _) = ReadBody(text, ref position, ref line);
        }
        else
        {
            left = left.Trim();
        }

        SkipBlanks(text, ref position);
        if (position >= text.Length || text[position] != ',')
        {
            throw new AssemblyError(0, "Expected ',' and a <body>.");
        }

        position++;
        return (left, right);
    }

    /// <summary>
    ///  Reads a <c>&lt;...&gt;</c> body, counting nested brackets everywhere, as MACRO-10 does.
    /// </summary>
    /// <param name="text">The text.</param>
    /// <param name="position">The position of the '&lt;' or blanks before it, moved past the '&gt;'.</param>
    /// <param name="line">The line, advanced past the body's newlines.</param>
    /// <returns>The body text and the line it starts on.</returns>
    private static (string Body, int Line) ReadBody(string text, ref int position, ref int line)
    {
        SkipBlanks(text, ref position);
        if (position >= text.Length || text[position] != '<') { throw new AssemblyError(0, "Expected a <body>."); }
        int bodyLine = line;
        int start = position + 1;
        int depth = 0;
        for (; position < text.Length; position++)
        {
            char character = text[position];
            if (character == '\n') { line++; }
            else if (character == '<') { depth++; }
            else if (character == '>' && --depth == 0) { break; }
        }

        if (depth != 0) { throw new AssemblyError(0, "Unterminated <body>."); }
        string body = text[start..position];
        position++;
        return (body, bodyLine);
    }

    private static void SkipComment(string text, ref int position, ref int line)
    {
        SkipBlanks(text, ref position);
        if (position >= text.Length) { return; }
        char delimiter = text[position++];
        while (position < text.Length && text[position] != delimiter)
        {
            if (text[position] == '\n') { line++; }
            position++;
        }

        if (position < text.Length) { position++; }
    }

    /// <summary>
    ///  Splits an argument list at commas outside brackets and parentheses, removing one level of brackets around
    ///  an argument, as MACRO-10 passes it.
    /// </summary>
    /// <param name="text">The list.</param>
    /// <returns>The arguments.</returns>
    private static List<string> Arguments(string text)
    {
        List<string> items = [];
        if (text.Trim().Length == 0) { return items; }
        int depth = 0;
        int start = 0;
        bool quoted = false;
        for (int index = 0; index <= text.Length; index++)
        {
            char character = index < text.Length ? text[index] : ',';

            // A quoted string's characters are text, such as the parenthesis in DCI"TAB(".
            if (character == '"') { quoted = !quoted; }
            if (quoted) { continue; }
            depth += character switch
            {
                '<' or '(' => 1,
                '>' or ')' => -1,
                _ => 0
            };

            if (character != ',' || depth > 0) { continue; }
            string item = text[start..index].Trim();
            bool bracketed = item.Length >= 2 && item[0] == '<' && item[^1] == '>' && Balanced(item[1..^1]);
            items.Add(bracketed ? item[1..^1] : item);
            start = index + 1;
        }

        return items;
    }

    private static bool Balanced(string text)
    {
        int depth = 0;
        foreach (char character in text)
        {
            if (character == '<') { depth++; }
            else if (character == '>' && --depth < 0) { return false; }
        }

        return depth == 0;
    }

    private static string Unparenthesized(string text)
    {
        string trimmed = text.Trim();
        if (trimmed.Length < 2 || trimmed[0] != '(' || trimmed[^1] != ')') { return trimmed; }
        int depth = 0;
        for (int index = 0; index < trimmed.Length - 1; index++)
        {
            if (trimmed[index] == '(') { depth++; }
            else if (trimmed[index] == ')' && --depth == 0) { return trimmed; }
        }

        return trimmed[1..^1];
    }
}
