// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  Translates ca65 spelling without evaluating expressions or parsing inactive source.
/// </summary>
/// <remarks>
///  <para>
///   Expressions are rewritten only where ca65 expects them, using ca65 precedence (see
///   <see cref="Ca65Expression"/>). Macro invocations keep their arguments as written: ca65 substitutes tokens,
///   so grouping an argument before substitution could change the expanded expression.
///  </para>
/// </remarks>
internal static class Ca65Frontend
{
    /// <summary>
    ///  Normalizes one line while preserving its physical location and quoted text.
    /// </summary>
    /// <param name="text">The original line.</param>
    /// <param name="time">The reproducible build timestamp.</param>
    /// <param name="isMacro">Whether an operation names a macro defined so far.</param>
    /// <returns>Native syntax for the shared preprocessor and compiler.</returns>
    internal static string Translate(ReadOnlySpan<char> text, DateTimeOffset time, Func<string, bool> isMacro)
    {
        ReadOnlySpan<char> source = AssemblySyntax.WithoutComment(text).Trim();
        if (source.IsEmpty) { return ""; }
        int labelLength = AssemblySyntax.IdentifierLength(source);
        if (labelLength != 0)
        {
            ReadOnlySpan<char> name = source[..labelLength];
            ReadOnlySpan<char> rest = source[labelLength..].TrimStart();
            if (rest.StartsWith(":=", StringComparison.Ordinal))
            {
                return $"{name} = {Expression(rest[2..].ToString(), time)}";
            }

            if (rest.Length != 0 && rest[0] == '=' && (rest.Length == 1 || rest[1] != '='))
            {
                return $"{name} = {Expression(rest[1..].ToString(), time)}";
            }

            if (rest.StartsWith(".set", StringComparison.OrdinalIgnoreCase)
                && (rest.Length == 4 || char.IsWhiteSpace(rest[4])))
            {
                return $"{name} .set {Expression(rest[4..].ToString(), time)}";
            }
        }

        string prefix = "";
        if (source[0] == ':' && (source.Length == 1 || source[1] != ':'))
        {
            prefix = ": ";
            source = source[1..].TrimStart();
        }
        else if (labelLength != 0 && labelLength < source.Length && source[labelLength] == ':')
        {
            prefix = $"{source[..(labelLength + 1)]} ";
            source = source[(labelLength + 1)..].TrimStart();
        }

        int end = 0;
        while (end < source.Length && !char.IsWhiteSpace(source[end])) { end++; }
        string operation = source[..end].ToString();
        string operand = source[end..].Trim().ToString();
        if (operation.Length == 0) { return prefix; }
        if (isMacro(operation)) { return $"{prefix}{operation} {operand}"; }

        // Only directives are matched by name, so instructions skip the uppercase copy.
        switch (operation[0] == '.' ? operation.ToUpperInvariant() : "")
        {
            case ".SETCPU":
                string cpu = operand switch
                {
                    "\"6502\"" => "Mos6502",

                    // ca65 2.19's 65C02 is the Rockwell set: bit instructions without WAI and STP.
                    "\"65C02\"" => "Rockwell65C02",
                    "\"65SC02\"" => "65SC02",
                    _ => operand
                };

                return $"{prefix}.cpu {cpu}";
            case ".P02":
                return $"{prefix}.cpu {RequireEmpty(operand, "Mos6502")}";
            case ".PC02":
                return $"{prefix}.cpu {RequireEmpty(operand, "Rockwell65C02")}";
            case ".PSC02":
                return $"{prefix}.cpu {RequireEmpty(operand, "65SC02")}";
            case ".CODE":
                return $"{prefix}.section {RequireEmpty(operand, "CODE")}";
            case ".RODATA":
                return $"{prefix}.section {RequireEmpty(operand, "RODATA")}";
            case ".DATA":
                return $"{prefix}.section {RequireEmpty(operand, "DATA")}";
            case ".BSS":
                return $"{prefix}.section {RequireEmpty(operand, "BSS")}";
            case ".ZEROPAGE":
                return $"{prefix}.section {RequireEmpty(operand, "ZEROPAGE")}";
            case ".SEGMENT":
                return $"{prefix}.section {Segment(operand)}";
            case ".ORG":
                return $"{prefix}.logicalorg {Expression(operand, time)}";
            case ".RELOC":
                // An empty .logicalorg returns to the section's own address, ending a .org region.
                return operand.Length == 0 ? $"{prefix}.logicalorg" : $"{prefix}.logicalorg \"{operand}\"";
            case ".MAC":
                return $"{prefix}.macro {operand}";
            case ".ENDMAC":
                return $"{prefix}.endmacro {operand}";
            case ".ENDREP":
                return $"{prefix}.endrepeat {operand}";
            case ".IMPORT":
            case ".IMPORTZP":
                // A single-object link resolves imports only from linker-defined symbols, which are always declared.
                foreach (string name in Split(SymbolNames(operand)))
                {
                    if (!AssemblySyntax.IsPlainIdentifier(name))
                    {
                        throw new AssemblyError(0, $"Invalid imported symbol '{name}'.");
                    }
                }

                return prefix;
            case ".EXPORT":
            case ".EXPORTZP":
                return $"{prefix}.export {SymbolNames(operand)}";
            case ".GLOBAL":
            case ".GLOBALZP":
                // A .global name is exported when defined and otherwise is an import, which a single object ignores.
                return $"{prefix}.global {SymbolNames(operand)}";
            case ".MACPACK":
                // ca65 builds its macro packages in; here they are the cc65 asminc files on the include path.
                return AssemblySyntax.IsPlainIdentifier(operand)
                    ? $"{prefix}.include \"{operand.ToLowerInvariant()}.mac\""
                    : throw new AssemblyError(0, ".macpack requires a package name.");

            case ".ADDR":
                return $"{prefix}.word {Expressions(operand, time, first: 0)}";
            case ".BYTE":
            case ".WORD":
            case ".DWORD":
            case ".DBYT":
            case ".FARADDR":
            case ".RES":
            case ".ALIGN":
            case ".IF":
            case ".ELSEIF":
                return $"{prefix}{operation} {Expressions(operand, time, first: 0)}";
            case ".REPEAT":
                return $"{prefix}{operation} {Expressions(operand, time, first: 0, last: 0)}";
            case ".INCBIN":
                return $"{prefix}{operation} {Expressions(operand, time, first: 1)}";
            case ".ASSERT":
                return $"{prefix}.assert {Assertion(operand, time)}";
        }

        return operation[0] == '.' ? $"{prefix}{operation} {operand}" : $"{prefix}{operation} {Instruction(operand, time)}";
    }

    private static string RequireEmpty(string operand, string replacement) =>
        operand.Length == 0 ? replacement : $"\"{operand}\"";

    private static string SymbolNames(string operand)
    {
        List<string> names = Split(operand);
        for (int index = 0; index < names.Count; index++)
        {
            int colon = names[index].IndexOf(':');
            if (colon < 0) { continue; }
            string size = names[index][(colon + 1)..].Trim().ToLowerInvariant();
            if (size is not ("zp" or "zeropage" or "absolute" or "abs" or "direct"))
            {
                throw new AssemblyError(0, "Unsupported symbol address size.");
            }

            names[index] = names[index][..colon].Trim();
        }

        return string.Join(", ", names);
    }

    private static string Segment(string operand)
    {
        if (!AssemblySyntax.IsStringLiteral(operand))
        {
            // An address-size suffix only describes how ca65 sizes symbols; the linker type still governs placement.
            int close = operand.Length > 1 && operand[0] == '"' ? operand.IndexOf('"', 1) : -1;
            string suffix = close < 0 ? "" : operand[(close + 1)..].Trim();
            if (suffix.Length < 2 || suffix[0] != ':') { return operand; }
            string size = suffix[1..].Trim();
            if (!size.Equals("zeropage", StringComparison.OrdinalIgnoreCase)
                && !size.Equals("absolute", StringComparison.OrdinalIgnoreCase)
                && !size.Equals("direct", StringComparison.OrdinalIgnoreCase))
            {
                throw new AssemblyError(0, $"Unsupported segment address size '{size}'.");
            }

            operand = operand[..(close + 1)];
        }

        return operand[1..^1];
    }

    private static string Assertion(string operand, DateTimeOffset time)
    {
        List<string> parts = Split(operand);
        if (parts.Count is < 1 or > 3)
        {
            throw new AssemblyError(0, ".assert requires an expression, severity and message.");
        }

        string expression = Expression(parts[0], time);
        if (parts.Count == 1) { return expression; }

        // Diagnostics have no warning level, so warning severities fail like errors when the condition is false.
        string severity = parts[1].ToLowerInvariant();
        return severity is not ("error" or "warning" or "lderror" or "ldwarning")
            ? throw new AssemblyError(0, $"Unknown .assert severity '{parts[1]}'.")
            : parts.Count == 3 ? $"{expression}, {parts[2]}" : expression;
    }

    private static string Instruction(string operand, DateTimeOffset time)
    {
        string text = operand;
        if (text.Length == 0 || text.Equals("a", StringComparison.OrdinalIgnoreCase)) { return text; }
        if (text[0] == '#') { return $"#{Expression(text[1..], time)}"; }
        string width = "";
        if (text.Length > 2 && text[1] == ':' && text[2] != ':' && text[0] is 'a' or 'A' or 'z' or 'Z' or 'f' or 'F')
        {
            width = text[..2];
            text = text[2..].TrimStart();
        }

        if (text.Length != 0 && text[0] == '(')
        {
            int close = Close(text);
            string inner = text[1..close];
            string after = text[(close + 1)..].Trim();
            if (after.Length == 0)
            {
                List<string> parts = Split(inner);
                if (parts.Count == 1) { return $"{width}({Expression(inner, time)})"; }
                if (parts.Count == 2 && parts[1].Equals("x", StringComparison.OrdinalIgnoreCase))
                {
                    return $"{width}({Expression(parts[0], time)},{parts[1]})";
                }
            }
            else if (after[0] == ',' && after.AsSpan(1).Trim().Equals("y", StringComparison.OrdinalIgnoreCase))
            {
                return $"{width}({Expression(inner, time)}),{after.AsSpan(1).Trim()}";
            }

            // ca65 always reads a leading parenthesis as indirect addressing.
            throw new AssemblyError(0, "Illegal addressing mode.");
        }

        if (text.Length != 0 && text[0] == '[') { return width + text; }
        List<string> items = Split(text);
        for (int index = 0; index < items.Count; index++)
        {
            bool register = index != 0 && index == items.Count - 1 && items[index] is "x" or "X" or "y" or "Y";
            if (!register) { items[index] = Expression(items[index], time); }
        }

        return width + string.Join(", ", items);
    }

    private static string Expressions(string operand, DateTimeOffset time, int first, int last = int.MaxValue)
    {
        if (operand.Length == 0) { return operand; }
        List<string> items = Split(operand);
        for (int index = first; index < items.Count && index <= last; index++)
        {
            if (!AssemblySyntax.IsStringLiteral(items[index]))
            {
                items[index] = Expression(items[index], time);
            }
        }

        return string.Join(", ", items);
    }

    private static string Expression(string text, DateTimeOffset time)
    {
        string trimmed = text.Trim();

        // Text this translator cannot read is left for the native evaluator to diagnose.
        return trimmed.Length == 0 ? trimmed : Ca65Expression.Translate(trimmed, time) ?? trimmed;
    }

    private static int Close(string text)
    {
        int depth = 0;
        for (int index = 0; index < text.Length; index++)
        {
            char character = text[index];
            if (character is '"' or '\'')
            {
                int close = text.IndexOf(character, index + 1);
                if (close < 0) { break; }
                index = close;
            }
            else if (character == '(')
            {
                depth++;
            }
            else if (character == ')' && --depth == 0)
            {
                return index;
            }
        }

        throw new AssemblyError(0, "Unbalanced parentheses.");
    }

    /// <summary>
    ///  Splits comma-delimited ca65 operands without splitting quoted or grouped text.
    /// </summary>
    /// <param name="text">The operand list.</param>
    /// <returns>Trimmed operand strings.</returns>
    internal static List<string> Split(string text)
    {
        List<string> items = [];
        if (string.IsNullOrWhiteSpace(text)) { return items; }
        int depth = 0;
        int start = 0;
        for (int index = 0; index < text.Length; index++)
        {
            char character = text[index];
            if (character is '"' or '\'')
            {
                int close = text.IndexOf(character, index + 1);
                if (close < 0) { break; }
                index = close;
            }
            else if (character is '(' or '[')
            {
                depth++;
            }
            else if (character is ')' or ']')
            {
                depth--;
            }
            else if (character == ',' && depth == 0)
            {
                items.Add(Trimmed(text, start, index));
                start = index + 1;
            }
        }

        items.Add(Trimmed(text, start, text.Length));
        return items;
    }

    /// <summary>
    ///  Gets part of a string without its surrounding whitespace, allocating only when that differs from the string.
    /// </summary>
    /// <param name="text">The whole string.</param>
    /// <param name="start">The first character of the part.</param>
    /// <param name="end">The end of the part, exclusive.</param>
    /// <returns>The trimmed part.</returns>
    private static string Trimmed(string text, int start, int end)
    {
        while (start < end && char.IsWhiteSpace(text[start])) { start++; }
        while (end > start && char.IsWhiteSpace(text[end - 1])) { end--; }
        return start == 0 && end == text.Length ? text : text[start..end];
    }
}
