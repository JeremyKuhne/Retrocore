// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Isa;

namespace Retrocore.Assembler;

/// <summary>
///  Matches operand text against an instruction-set description's operand forms.
/// </summary>
/// <remarks>
///  <para>
///   The empty operand selects the first empty-pattern form the mnemonic has. A literal pattern, such as
///   <c>A</c> or <c>A,[HL]</c>, matches first, but only when the mnemonic has its form. The other forms are
///   then tried in declaration order. An exclusive form, such as a relative branch, matches only when the
///   mnemonic has it. Any other pattern matches by syntax alone, so an operand the mnemonic lacks reports an
///   unsupported form rather than trying a later pattern. Its group, the forms sharing the pattern, then
///   supplies a wide form and its narrow alternative, or the first form the mnemonic has.
///  </para>
///  <para>
///   Each hole of a pattern holds one expression. Between holes, a pattern's literal text is found outside
///   quotes and outside the expression's own parentheses and brackets. When a pattern has a parenthesis or
///   bracket, each expression must balance its own, so <c>(1)+(2)</c> is an expression rather than an
///   indirect operand. A displacement's hole, as in <c>[IX{}]</c>, is empty or starts with <c>+</c> or
///   <c>-</c>.
///  </para>
/// </remarks>
internal sealed partial class OperandFormMatcher
{
    /// <summary>
    ///  The form value of an operand that matches no form.
    /// </summary>
    internal const ushort NoForm = ushort.MaxValue;

    /// <summary>
    ///  The most holes a pattern may have.
    /// </summary>
    internal const int MaximumHoles = 4;

    // Context markers for a pattern word next to a hole or the operand's ends.
    private const char Edge = '\0';
    private const char Hole = '\u0001';

    // Weak, so descriptions parsed by a long-lived compiler host can be collected.
    // A collection expression needs the table to be enumerable, which it is not on .NET Standard 2.0.
#pragma warning disable IDE0028 // Collection initialization can be simplified
    private static readonly System.Runtime.CompilerServices.ConditionalWeakTable<IsaDescription, OperandFormMatcher> s_matchers =
        new();
#pragma warning restore IDE0028

    private static readonly ReadOnlyMemory<char> s_zero = "0".AsMemory();

    private readonly Entry[] _literals;
    private readonly Entry[] _entries;
    private readonly ushort[] _empty;
    private readonly Pattern[][] _patterns;
    private readonly bool[] _simple;
    private readonly string[] _prefixes;
    private readonly string[] _suffixes;
    private readonly HashSet<(string Word, char Before, char After)> _words = [];
    private readonly HashSet<string> _names = new(StringComparer.OrdinalIgnoreCase);

    // Bit n is set when some literal pattern, or some pattern word, is n characters long (n below 64), so most
    // operands and names are rejected without a comparison or a string.
    private readonly ulong _literalLengths;
    private ulong _wordLengths;

    private OperandFormMatcher(IsaDescription description)
    {
        IReadOnlyList<OperandForm> forms = description.Forms;
        _prefixes = new string[forms.Count];
        _suffixes = new string[forms.Count];
        _patterns = new Pattern[forms.Count][];
        _simple = new bool[forms.Count];
        List<ushort> empty = [];
        List<Entry> literals = [];
        List<Entry> entries = [];
        Dictionary<string, Entry> groups = new(StringComparer.Ordinal);
        foreach (OperandForm form in forms)
        {
            _prefixes[form.Id] = "";
            _suffixes[form.Id] = "";
            List<Pattern> holed = [];
            foreach (string text in form.Patterns)
            {
                if (text.Length == 0)
                {
                    empty.Add(form.Id);
                    continue;
                }

                if (OperandForm.IsLiteral(text))
                {
                    literals.Add(new(EntryKind.Literal, form.Id, new(text, form)));
                    continue;
                }

                Pattern pattern = new(text, form);
                if (holed.Count == 0)
                {
                    _prefixes[form.Id] = pattern.Literals[0];
                    _suffixes[form.Id] = pattern.Literals[^1];
                }

                holed.Add(pattern);
                AddWords(pattern);
                if (form.Exclusive)
                {
                    entries.Add(new(EntryKind.Exclusive, form.Id, pattern));
                }
                else if (groups.TryGetValue(text, out Entry? group))
                {
                    group.Group.Add(form.Id);
                }
                else
                {
                    Entry entry = new(EntryKind.Syntax, form.Id, pattern);
                    entry.Group.Add(form.Id);
                    groups.Add(text, entry);
                    entries.Add(entry);
                }
            }

            _patterns[form.Id] = [.. holed];

            // One pattern with one plain hole slices its expression without a search.
            _simple[form.Id] = holed.Count == 1 && holed[0].Holes == 1 && !holed[0].Displacement[0];
        }

        foreach (Entry entry in entries)
        {
            foreach (ushort id in entry.Group)
            {
                OperandForm narrow = forms[id];
                if (narrow.NarrowOf >= 0 && entry.Group.Contains((ushort)narrow.NarrowOf))
                {
                    entry.Wide = narrow.NarrowOf;
                    entry.Narrow = id;
                    break;
                }
            }
        }

        _literals = [.. literals];
        foreach (Entry entry in _literals) { _literalLengths |= LengthBit(entry.Pattern.Text.Length); }
        _entries = [.. entries];
        _empty = [.. empty];
    }

    /// <summary>
    ///  Gets the matcher for a description's forms.
    /// </summary>
    /// <param name="description">The description.</param>
    /// <returns>Its matcher, built once.</returns>
    internal static OperandFormMatcher Get(IsaDescription description) =>
        s_matchers.GetValue(description, static value => new(value));

    /// <summary>
    ///  Classifies an operand.
    /// </summary>
    /// <param name="set">The instruction set, for the forms a mnemonic has.</param>
    /// <param name="mnemonic">The dense mnemonic ID.</param>
    /// <param name="text">The compact operand, without width prefixes.</param>
    /// <param name="narrow">The narrow alternative of the returned wide form, or <see cref="NoForm"/>.</param>
    /// <returns>The form, or <see cref="NoForm"/> when the operand fits none.</returns>
    internal ushort Classify(InstructionSet set, int mnemonic, ReadOnlySpan<char> text, out ushort narrow)
    {
        narrow = NoForm;
        if (text.Length == 0)
        {
            foreach (ushort id in _empty)
            {
                if (set.Has(mnemonic, id)) { return id; }
            }

            return _empty.Length == 0 ? NoForm : _empty[^1];
        }

        if (LiteralForm(set, mnemonic, text) is { } literal) { return literal; }
        foreach (Entry entry in _entries)
        {
            if (entry.Kind == EntryKind.Exclusive)
            {
                // The table lookup is cheaper than the syntax test.
                if (set.Has(mnemonic, entry.Form) && entry.Pattern.Matches(text)) { return entry.Form; }
                continue;
            }

            if (!entry.Pattern.Matches(text)) { continue; }
            if (entry.Wide >= 0)
            {
                narrow = (ushort)entry.Narrow;
                return (ushort)entry.Wide;
            }

            foreach (ushort id in entry.Group)
            {
                if (set.Has(mnemonic, id)) { return id; }
            }

            return entry.Group[0];
        }

        return NoForm;
    }

    /// <summary>
    ///  Gets whether an operand is a literal form the mnemonic has, such as <c>A</c>, so it names no symbol.
    /// </summary>
    /// <param name="set">The instruction set.</param>
    /// <param name="mnemonic">The dense mnemonic ID.</param>
    /// <param name="text">The operand.</param>
    /// <returns>Whether it is.</returns>
    internal bool IsLiteral(InstructionSet set, int mnemonic, ReadOnlySpan<char> text) =>
        LiteralForm(set, mnemonic, text) is not null;

    /// <summary>
    ///  Gets whether the mnemonic takes an exclusive form with several fields in one hole, such as a bit
    ///  branch's address and target, so its operand is a list of expressions.
    /// </summary>
    /// <param name="set">The instruction set.</param>
    /// <param name="mnemonic">The dense mnemonic ID.</param>
    /// <returns>Whether it does.</returns>
    internal bool HasFieldList(InstructionSet set, int mnemonic)
    {
        foreach (Entry entry in _entries)
        {
            if (entry.Kind == EntryKind.Exclusive
                && entry.Pattern.Holes == 1
                && set.Forms[entry.Form].Fields.Count > 1
                && set.Has(mnemonic, entry.Form))
            {
                return true;
            }
        }

        return false;
    }

    /// <summary>
    ///  Gets whether a name in an operand is a word of some pattern in its place, such as <c>X</c> after a
    ///  comma at the end or <c>IX</c> after a bracket, so it names a register rather than a symbol.
    /// </summary>
    /// <param name="text">The operand, which may hold whitespace.</param>
    /// <param name="start">Where the name starts.</param>
    /// <param name="length">The name's length.</param>
    /// <returns>Whether it is a pattern word.</returns>
    internal bool IsPatternWord(ReadOnlySpan<char> text, int start, int length)
    {
        if ((_wordLengths & LengthBit(length)) == 0) { return false; }
        int before = start - 1;
        while (before >= 0 && char.IsWhiteSpace(text[before])) { before--; }
        int after = start + length;
        while (after < text.Length && char.IsWhiteSpace(text[after])) { after++; }
        string word = text.Slice(start, length).ToString().ToUpperInvariant();
        char previous = before < 0 ? Edge : text[before];
        char next = after >= text.Length ? Edge : text[after];
        return _words.Contains((word, previous, next))
            || _words.Contains((word, Hole, next))
            || _words.Contains((word, previous, Hole))
            || _words.Contains((word, Hole, Hole));
    }

    /// <summary>
    ///  Gets whether a name is a word of some operand pattern, such as the register <c>HL</c>, so a symbol of
    ///  that name could read as the register.
    /// </summary>
    /// <param name="name">The name.</param>
    /// <returns>Whether a pattern uses it.</returns>
    internal bool IsPatternName(string name) => (_wordLengths & LengthBit(name.Length)) != 0 && _names.Contains(name);

    /// <summary>
    ///  Removes a form's syntax from an operand that matched it, leaving the expression.
    /// </summary>
    /// <param name="operand">The compact operand.</param>
    /// <param name="form">The form.</param>
    /// <returns>The expression, or for a form with several fields, the comma-separated expressions.</returns>
    internal ReadOnlyMemory<char> Expression(ReadOnlyMemory<char> operand, int form)
    {
        if (!_simple[form])
        {
            Span<ReadOnlyMemory<char>> expressions = new ReadOnlyMemory<char>[MaximumHoles];
            return Expressions(operand, form, expressions) > 0 ? expressions[0] : operand;
        }

        int prefix = _prefixes[form].Length;
        int suffix = _suffixes[form].Length;
        return operand.Length < prefix + suffix ? operand : operand.Slice(prefix, operand.Length - prefix - suffix);
    }

    /// <summary>
    ///  Gets whether a form's pattern holds one expression per field, so <see cref="Expressions"/> applies.
    /// </summary>
    /// <param name="form">The form.</param>
    /// <returns>Whether its pattern has several holes or a displacement.</returns>
    internal bool HasHoles(int form)
    {
        Pattern[] patterns = _patterns[form];
        return !_simple[form] && patterns.Length > 0 && (patterns[0].Holes > 1 || patterns[0].Displacement[0]);
    }

    /// <summary>
    ///  Splits an operand that matched a form into the expression of each hole.
    /// </summary>
    /// <param name="operand">The compact operand.</param>
    /// <param name="form">The form.</param>
    /// <param name="expressions">Receives the expressions; a displacement's is its signed value.</param>
    /// <returns>The number of expressions, or 0 when no pattern of the form matches.</returns>
    internal int Expressions(ReadOnlyMemory<char> operand, int form, Span<ReadOnlyMemory<char>> expressions)
    {
        Span<Range> holes = stackalloc Range[MaximumHoles];
        foreach (Pattern pattern in _patterns[form])
        {
            if (!pattern.Match(operand.Span, holes)) { continue; }
            for (int index = 0; index < pattern.Holes; index++)
            {
                ReadOnlyMemory<char> expression = operand[holes[index]];
                if (pattern.Displacement[index])
                {
                    // [IX] is [IX+0]; a leading plus is dropped, since the native evaluator has no unary plus.
                    expression = expression.IsEmpty ? s_zero : expression.Span[0] == '+' ? expression[1..] : expression;
                }

                expressions[index] = expression;
            }

            return pattern.Holes;
        }

        return 0;
    }

    private static ulong LengthBit(int length) => length < 64 ? 1UL << length : 0;

    private ushort? LiteralForm(InstructionSet set, int mnemonic, ReadOnlySpan<char> text)
    {
        if ((_literalLengths & LengthBit(text.Length)) == 0) { return null; }
        foreach (Entry entry in _literals)
        {
            if (text.Equals(entry.Pattern.Text.AsSpan(), StringComparison.OrdinalIgnoreCase) && set.Has(mnemonic, entry.Form))
            {
                return entry.Form;
            }
        }

        return null;
    }

    // Records each identifier in a pattern's literal text with the characters around it.
    private void AddWords(Pattern pattern)
    {
        for (int segment = 0; segment < pattern.Literals.Length; segment++)
        {
            string literal = pattern.Literals[segment];
            int index = 0;
            while (index < literal.Length)
            {
                if (!char.IsAsciiLetter(literal[index]))
                {
                    index++;
                    continue;
                }

                int start = index;
                while (index < literal.Length && AssemblySyntax.IsWord(literal[index])) { index++; }
                char before = start > 0 ? literal[start - 1] : segment == 0 ? Edge : Hole;
                char after = index < literal.Length ? literal[index]
                    : segment == pattern.Literals.Length - 1 ? Edge : Hole;

                _words.Add((literal[start..index].ToUpperInvariant(), before, after));
                _names.Add(literal[start..index]);
                _wordLengths |= LengthBit(index - start);
            }
        }
    }

    // Finds where a hole's expression ends: the next literal outside quotes and the expression's own groups.
    private static int FindLiteral(ReadOnlySpan<char> text, int start, int end, string literal)
    {
        int depth = 0;
        char quote = '\0';
        for (int index = start; index <= end - literal.Length; index++)
        {
            char value = text[index];
            if (quote == '\0'
                && depth == 0
                && text.Slice(index, literal.Length).Equals(literal.AsSpan(), StringComparison.OrdinalIgnoreCase))
            {
                return index;
            }

            if (AssemblySyntax.TogglesQuote(text, index, quote)) { quote = quote == '\0' ? value : '\0'; }
            if (quote != '\0') { continue; }
            if (value is '(' or '[') { depth++; }
            else if (value is ')' or ']') { depth--; }
        }

        return -1;
    }

    // Whether an expression closes each parenthesis and bracket it opens, and no others.
    private static bool IsBalanced(ReadOnlySpan<char> text)
    {
        int depth = 0;
        char quote = '\0';
        for (int index = 0; index < text.Length; index++)
        {
            char value = text[index];
            if (AssemblySyntax.TogglesQuote(text, index, quote)) { quote = quote == '\0' ? value : '\0'; }
            if (quote != '\0') { continue; }
            if (value is '(' or '[') { depth++; }
            else if (value is ')' or ']' && --depth < 0) { return false; }
        }

        return depth == 0;
    }
}
