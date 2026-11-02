// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug.Language;

/// <summary>
///  Text helpers shared by the language features: words, comments and lines.
/// </summary>
internal static class SourceText
{
    /// <summary>
    ///  Gets the CPU in effect at a line: the nearest <c>.cpu</c> above it, otherwise the 6502.
    /// </summary>
    /// <param name="lines">The file's lines.</param>
    /// <param name="line">The zero-based line.</param>
    /// <returns>The CPU's instruction set.</returns>
    internal static Retrocore.Isa.InstructionSet InstructionSetOf(string[] lines, int line)
    {
        for (int index = Math.Min(line, lines.Length - 1); index >= 0; index--)
        {
            string text = lines[index].Trim();
            if (!text.StartsWith(".cpu", StringComparison.OrdinalIgnoreCase)) { continue; }
            string rest = text[".cpu".Length..];
            int comment = CommentStart(rest);
            string name = (comment < 0 ? rest : rest[..comment]).Trim();
            if (Retrocore.Assembler.CpuCatalog.InstructionSets.TryGetValue(name, out Retrocore.Isa.InstructionSet? set))
            {
                return set;
            }

            return M6502Isa.Get(name.Contains("C02", StringComparison.OrdinalIgnoreCase)
                ? ProcessorVariant.Rockwell65C02
                : ProcessorVariant.Mos6502);
        }

        return M6502Isa.Get(ProcessorVariant.Mos6502);
    }

    /// <summary>
    ///  Splits text into lines without their terminators.
    /// </summary>
    /// <param name="text">The text.</param>
    /// <returns>The lines.</returns>
    internal static string[] Lines(string text) => text.Replace("\r\n", "\n", StringComparison.Ordinal).Split('\n');

    /// <summary>
    ///  Gets whether a character can be part of a name in any dialect.
    /// </summary>
    /// <param name="character">The character.</param>
    /// <returns>Whether it is a name character.</returns>
    internal static bool IsNameCharacter(char character) =>
        char.IsLetterOrDigit(character) || character is '_' or '@' or '.' or '$' or '%' or '?' or ']';

    /// <summary>
    ///  Gets the name under a column, including scope qualifiers such as <c>a::b</c>.
    /// </summary>
    /// <param name="line">The line.</param>
    /// <param name="column">The zero-based column.</param>
    /// <returns>The name and its start, or null.</returns>
    internal static (string Word, int Start)? WordAt(string line, int column)
    {
        int start = Math.Min(column, line.Length);
        while (start > 0 && (IsNameCharacter(line[start - 1]) || IsScope(line, start - 1))) { start--; }
        int end = Math.Min(column, line.Length);
        while (end < line.Length && (IsNameCharacter(line[end]) || IsScope(line, end))) { end++; }

        // Leading or trailing colons are label syntax, not scope.
        while (start < end && line[start] == ':') { start++; }
        while (end > start && line[end - 1] == ':') { end--; }
        return end > start ? (line[start..end], start) : null;
    }

    /// <summary>
    ///  Gets whether text ends where an operation goes: the first word after an optional label in column 0 (a
    ///  directive may start in column 0 too).
    /// </summary>
    /// <param name="before">The line up to the cursor or word.</param>
    /// <returns>Whether an instruction, directive or macro belongs there.</returns>
    internal static bool IsOperation(string before)
    {
        string rest = before;
        if (rest.Length != 0 && !char.IsWhiteSpace(rest[0]) && rest[0] != '.')
        {
            int end = rest.IndexOfAny([' ', '\t']);
            if (end < 0) { return false; }
            rest = rest[end..];
        }

        rest = rest.TrimStart();
        return rest.IndexOfAny([' ', '\t']) < 0;
    }

    /// <summary>
    ///  Gets the comment lines directly above a line, and the line's own trailing comment.
    /// </summary>
    /// <param name="lines">The file's lines.</param>
    /// <param name="line">The zero-based line.</param>
    /// <returns>The comment text, one entry per line.</returns>
    internal static List<string> CommentFor(string[] lines, int line)
    {
        if (line < 0 || line >= lines.Length) { return []; }

        List<string> above = [];
        for (int index = line - 1; index >= 0; index--)
        {
            string text = lines[index].TrimStart();
            if (text.StartsWith(';'))
            {
                above.Insert(0, text.TrimStart(';').Trim());
                continue;
            }

            // Stacked labels share the comment above the first.
            if (text.Length != 0 && text.EndsWith(':') && !text.Contains(' ', StringComparison.Ordinal)) { continue; }
            break;
        }

        if (line < lines.Length && Trailing(lines[line]) is { Length: > 0 } trailing) { above.Add(trailing); }
        return above;
    }

    /// <summary>
    ///  Gets a line's trailing comment, ignoring semicolons in quotes.
    /// </summary>
    /// <param name="line">The line.</param>
    /// <returns>The comment text, or empty.</returns>
    internal static string Trailing(string line)
    {
        int at = CommentStart(line);
        if (at <= 0) { return ""; }

        // An address comment alone, as the SDK's ROM sources put on each line, says nothing the hover does not.
        string text = line[(at + 1)..].Trim();
        return text.Length == 5 && text[0] == '$' ? "" : text;
    }

    /// <summary>
    ///  Gets where a line's comment starts, or -1.
    /// </summary>
    /// <param name="line">The line.</param>
    /// <returns>The semicolon's index.</returns>
    internal static int CommentStart(string line)
    {
        bool quoted = false;
        for (int index = 0; index < line.Length; index++)
        {
            char character = line[index];
            if (character is '"' or '\'') { quoted = !quoted; }
            if (character == ';' && !quoted) { return index; }
        }

        return -1;
    }

    /// <summary>
    ///  Finds a local label's definition: the nearest line in a file that defines the name.
    /// </summary>
    /// <param name="lines">The file's lines.</param>
    /// <param name="word">The name.</param>
    /// <param name="from">The zero-based line to search out from.</param>
    /// <returns>The definition, with no path, or null.</returns>
    internal static SymbolSite? LocalDefinition(string[] lines, string word, int from)
    {
        static bool Defines(string line, string word)
        {
            if (!line.StartsWith(word, StringComparison.OrdinalIgnoreCase)) { return false; }
            return line.Length == word.Length || line[word.Length] is ':' or ' ' or '\t' or '=';
        }

        // A directive in column 0 is not a local label, though it looks like one.
        if (word.StartsWith('.') && DirectiveDocs.Describe(word) is not null) { return null; }

        for (int distance = 0; distance < lines.Length; distance++)
        {
            foreach (int line in (int[])[from - distance, from + distance])
            {
                if (line >= 0 && line < lines.Length && Defines(lines[line], word))
                {
                    return new(word, "", line, 0, SymbolSiteKind.Label, Value: null);
                }
            }
        }

        return null;
    }

    private static bool IsScope(string line, int index)
    {
        if (line[index] != ':') { return false; }
        bool next = index + 1 < line.Length && line[index + 1] == ':';
        bool previous = index > 0 && line[index - 1] == ':';
        return next || previous;
    }
}
