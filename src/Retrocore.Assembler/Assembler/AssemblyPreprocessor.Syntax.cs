// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Runtime.InteropServices;
using System.Text;

namespace Retrocore.Assembler;

internal sealed partial class AssemblyPreprocessor
{
    /// <summary>
    ///  Splits a line into label, operation and operand slices without allocating.
    /// </summary>
    /// <param name="line">The line, including any comment.</param>
    /// <param name="label">The label before a colon, or empty.</param>
    /// <param name="operation">The first word after the label.</param>
    /// <param name="operand">The remaining text without its comment.</param>
    private static void Split(
        ReadOnlySpan<char> line,
        out ReadOnlySpan<char> label,
        out ReadOnlySpan<char> operation,
        out ReadOnlySpan<char> operand)
    {
        ReadOnlySpan<char> text = AssemblySyntax.WithoutComment(line).Trim();
        label = default;
        int identifier = AssemblySyntax.IdentifierLength(text);
        if (!text.IsEmpty && text[0] == ':' && (text.Length == 1 || text[1] != ':'))
        {
            label = text[..1];
            text = text[1..].TrimStart();
        }
        else if (identifier > 0 && identifier < text.Length && text[identifier] == ':')
        {
            label = text[..identifier];
            text = text[(identifier + 1)..].TrimStart();
        }

        int end = AssemblySyntax.OperationLength(text);
        operation = text[..end];
        operand = text[end..].Trim();
    }

    private static List<string> MerlinArguments(string operand)
    {
        List<string> result = [];
        if (string.IsNullOrWhiteSpace(operand)) { return result; }
        foreach (string argument in operand.Split(MerlinArgumentSeparator)) { result.Add(argument.Trim()); }
        return result;
    }

    private static List<string> Arguments(string operand)
    {
        List<string> result = [];
        if (string.IsNullOrWhiteSpace(operand)) { return result; }
        int start = 0;
        int depth = 0;
        char quote = '\0';
        for (int index = 0; index < operand.Length; index++)
        {
            char character = operand[index];
            if (AssemblySyntax.TogglesQuote(operand, index, quote)) { quote = quote == '\0' ? character : '\0'; }
            if (quote != '\0') { continue; }
            if (character == '(') { depth++; }
            if (character == ')') { depth--; }
            if (character == ',' && depth == 0)
            {
                result.Add(operand[start..index].Trim());
                start = index + 1;
            }
        }

        result.Add(operand[start..].Trim());
        return result;
    }

    private bool ValidateArguments(string operand, AssemblyLocation location)
    {
        int depth = 0;
        char quote = '\0';
        for (int index = 0; index < operand.Length; index++)
        {
            char character = operand[index];
            if (AssemblySyntax.TogglesQuote(operand, index, quote)) { quote = quote == '\0' ? character : '\0'; }
            if (quote != '\0') { continue; }
            if (character == '(') { depth++; }
            if (character == ')' && --depth < 0)
            {
                Error("Unbalanced macro argument parentheses.", location);
                return false;
            }
        }

        if (depth == 0 && quote == '\0') { return true; }
        Error("Unterminated macro argument string or parentheses.", location);
        return false;
    }

    /// <summary>
    ///  Replaces whole-token parameter, counter and local names outside strings and comments.
    /// </summary>
    /// <param name="text">The line.</param>
    /// <param name="names">Macro parameters and repeat counters visible to this line.</param>
    /// <param name="frame">The enclosing macro invocation, supplying locals and .paramcount.</param>
    /// <returns>The substituted line, or the original instance when nothing changed.</returns>
    private static string Substitute(string text, Dictionary<string, string>? names, MacroFrame? frame) =>
        names is null && frame is null ? text : AssemblySyntax.AsString(Substitute(text.AsMemory(), names, frame));

    // Reads the line in place: a name is looked up by its text, and the line is copied only when one is replaced.
    private static ReadOnlyMemory<char> Substitute(ReadOnlyMemory<char> text, Dictionary<string, string>? names, MacroFrame? frame)
    {
        if (names is null && frame is null) { return text; }

        // StringBuilder takes a part of a string on every runtime, so a line that is a slice of one is read from it.
        if (!MemoryMarshal.TryGetString(text, out string? owner, out int offset, out _) || owner is null)
        {
            owner = text.ToString();
            offset = 0;
        }

        StringBuilder? result = null;
        int copied = 0;
        AssemblyNameReferences references = new(text, qualified: false);
        while (references.MoveNext())
        {
            int index = references.Start;
            ReadOnlySpan<char> token = references.Current.Span;
            string? replacement = null;
            if (token[0] == '.')
            {
                if (frame is not null && token.Equals(".paramcount", StringComparison.OrdinalIgnoreCase))
                {
                    replacement = frame.ParameterCount.ToString();
                }
            }
            else if (names is null || !TryGetByText(names, token, out replacement))
            {
                if (frame is not null) { TryGetByText(frame.Locals, token, out replacement); }
            }

            if (replacement is not null)
            {
                result ??= new(text.Length);
                result.Append(owner, offset + copied, index - copied).Append(replacement);
                copied = index + token.Length;
            }
        }

        return result is null ? text : result.Append(owner, offset + copied, text.Length - copied).ToString().AsMemory();
    }

    /// <summary>
    ///  Looks a name up by its text, without copying it where the runtime allows; the source generator's copies it.
    /// </summary>
    /// <typeparam name="T">The values' type.</typeparam>
    /// <param name="dictionary">A dictionary keyed with <see cref="StringComparer.Ordinal"/>.</param>
    /// <param name="name">The name.</param>
    /// <param name="value">The value, when found.</param>
    /// <returns>Whether the name is a key.</returns>
    private static bool TryGetByText<T>(Dictionary<string, T> dictionary, ReadOnlySpan<char> name, [MaybeNullWhen(returnValue: false)] out T value)
    {
#if NET
        return dictionary.GetAlternateLookup<ReadOnlySpan<char>>().TryGetValue(name, out value);
#else
        return dictionary.TryGetValue(name.ToString(), out value);
#endif
    }

    private List<Line>? Capture(
        IReadOnlyList<Line> lines,
        ref int index,
        string opening,
        string closing,
        AssemblyLocation location)
    {
        int start = index + 1;
        int depth = 1;
        for (index++; index < lines.Count; index++)
        {
            _cancellation.ThrowIfCancellationRequested();
            Split(lines[index].Text.Span, out ReadOnlySpan<char> label, out ReadOnlySpan<char> operation, out ReadOnlySpan<char> operand);
            if (lines[index].Dialect == AssemblyDialect.Merlin)
            {
                MerlinFrontend.Split(lines[index].Text.Span, out _, out string merlinOperation, out string merlinOperand);
                operation = merlinOperation.ToUpperInvariant() switch
                {
                    "MAC" => ".macro",
                    "EOM" or "<<<" => ".endmacro",
                    "LUP" => ".repeat",
                    "--^" => ".endrepeat",
                    _ => merlinOperation
                };

                operand = merlinOperand;
            }

            if (lines[index].Dialect == AssemblyDialect.Ca65)
            {
                if (operation.Equals(".endmac", StringComparison.OrdinalIgnoreCase))
                {
                    operation = ".endmacro";
                }
                else if (operation.Equals(".mac", StringComparison.OrdinalIgnoreCase))
                {
                    operation = ".macro";
                }
                else if (operation.Equals(".endrep", StringComparison.OrdinalIgnoreCase))
                {
                    operation = ".endrepeat";
                }
            }

            if (operation.Equals(opening, StringComparison.OrdinalIgnoreCase)) { depth++; }
            if (operation.Equals(closing, StringComparison.OrdinalIgnoreCase) && --depth == 0)
            {
                if (!operand.IsEmpty) { Error($"{closing} takes no operand.", lines[index].Location); }
                if (!label.IsEmpty && lines[index].Dialect == AssemblyDialect.Native)
                {
                    // The closing line has no single address: it ends every expansion of the body.
                    Error($"A label cannot be on a {closing.ToLowerInvariant()} line.", lines[index].Location);
                }

                List<Line> body = [with(index - start)];
                for (int bodyIndex = start; bodyIndex < index; bodyIndex++) { body.Add(lines[bodyIndex]); }
                return body;
            }
        }

        Error($"Unterminated {opening}.", location);
        return null;
    }
}
