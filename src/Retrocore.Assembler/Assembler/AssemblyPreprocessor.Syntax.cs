// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

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

        int end = 0;
        while (end < text.Length && !char.IsWhiteSpace(text[end])) { end++; }
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
    private static ReadOnlyMemory<char> Substitute(ReadOnlyMemory<char> text, Dictionary<string, string>? names, MacroFrame? frame) =>
        names is null && frame is null ? text : Substitute(AssemblySyntax.AsString(text), names, frame).AsMemory();

    private static string Substitute(string text, Dictionary<string, string>? names, MacroFrame? frame)
    {
        if (names is null && frame is null) { return text; }
        StringBuilder? result = null;
        int copied = 0;
        AssemblyNameReferences references = new(text.AsMemory(), qualified: false);
        while (references.MoveNext())
        {
            int index = references.Start;
            int length = references.Current.Length;
            string? replacement = null;
            if (references.Current.Span[0] == '.')
            {
                if (frame is not null
                    && references.Current.Span.Equals(".paramcount", StringComparison.OrdinalIgnoreCase))
                {
                    replacement = frame.ParameterCount.ToString();
                }
            }
            else
            {
                string token = references.Current.ToString();
                if (names?.TryGetValue(token, out replacement) != true)
                {
                    frame?.Locals.TryGetValue(token, out replacement);
                }
            }

            if (replacement is not null)
            {
                result ??= new(text.Length);
                result.Append(text, copied, index - copied).Append(replacement);
                copied = index + length;
            }
        }

        return result is null ? text : result.Append(text, copied, text.Length - copied).ToString();
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

                List<Line> body = new(index - start);
                for (int bodyIndex = start; bodyIndex < index; bodyIndex++) { body.Add(lines[bodyIndex]); }
                return body;
            }
        }

        Error($"Unterminated {opening}.", location);
        return null;
    }
}
