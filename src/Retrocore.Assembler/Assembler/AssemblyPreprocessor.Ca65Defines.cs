// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;

namespace Retrocore.Assembler;

internal sealed partial class AssemblyPreprocessor
{
    private bool Ca65Definition(Line line, bool active)
    {
        Split(line.Text.Span, out _, out ReadOnlySpan<char> op, out ReadOnlySpan<char> text);
        bool define = op.Equals(".define", StringComparison.OrdinalIgnoreCase);
        if (!define && !op.Equals(".undefine", StringComparison.OrdinalIgnoreCase)) { return false; }
        if (!active) { return true; }
        int length = AssemblySyntax.IdentifierSegmentLength(text);
        if (length == 0) { throw new AssemblyError(0, "A textual definition requires an identifier."); }
        string name = text[..length].ToString();
        if (!define)
        {
            return text[length..].Trim().Length != 0 || !Ca65.Defines.Remove(name)
                ? throw new AssemblyError(0, ".undefine requires one existing textual definition.")
                : true;
        }

        string[]? parameters = null;
        int end = length;
        if (end < text.Length && text[end] == '(')
        {
            int last = text.IndexOf(')');
            if (last < 0) { throw new AssemblyError(0, "Unterminated .define parameter list."); }
            parameters = [.. Ca65Frontend.Split(text[(end + 1)..last].ToString())];
            if (parameters.Any(parameter => !AssemblySyntax.IsPlainIdentifier(parameter))
                || parameters.Distinct(StringComparer.Ordinal).Count() != parameters.Length)
            {
                throw new AssemblyError(0, "Invalid or duplicate .define parameter.");
            }

            end = last + 1;
        }

        if (!Ca65.Defines.TryAdd(name, new(parameters, text[end..].TrimStart().ToString())))
        {
            throw new AssemblyError(0, $"Duplicate textual definition '{name}'.");
        }

        Ca65.DefineLengths |= LengthBit(name.Length);
        return true;
    }

    private static ulong LengthBit(int length) => 1UL << Math.Min(length, 63);

    /// <summary>
    ///  Finds whether a line contains a word that could name a definition, without allocating for other words.
    /// </summary>
    /// <param name="source">The line.</param>
    /// <param name="state">The ca65 state with at least one definition.</param>
    /// <returns>Whether expansion may change the line.</returns>
    private static bool MentionsDefinition(ReadOnlySpan<char> source, Ca65State state)
    {
        for (int index = 0; index < source.Length;)
        {
            int length = AssemblySyntax.IdentifierSegmentLength(source[index..]);
            if (length == 0)
            {
                index++;
                continue;
            }

            if ((state.DefineLengths & LengthBit(length)) != 0
                && state.Defines.ContainsKey(source.Slice(index, length).ToString()))
            {
                return true;
            }

            index += length;
        }

        return false;
    }

    private string ExpandCa65Definitions(string text, int depth = 0)
    {
        if (depth >= _options.MaximumMacroDepth)
        {
            throw new AssemblyError(0, "Maximum textual definition recursion depth exceeded.");
        }

        if (_ca65State?.Defines.Count is not > 0) { return text; }
        StringBuilder? result = null;
        int copied = 0;
        AssemblyNameReferences cursor = new(text.AsMemory(), qualified: false);
        while (cursor.MoveNext())
        {
            int start = cursor.Start;
            if (start < copied
                || (Ca65.DefineLengths & LengthBit(cursor.Current.Length)) == 0
                || !Ca65.Defines.TryGetValue(cursor.Current.ToString(), out TextDefinition? definition))
            {
                continue;
            }

            int end = start + cursor.Current.Length;
            string replacement = definition.Text;
            if (definition.Parameters is { } parameters)
            {
                Dictionary<string, string> names = new(StringComparer.Ordinal);
                for (int index = 0; index < parameters.Length; index++)
                {
                    while (end < text.Length && char.IsWhiteSpace(text[end])) { end++; }
                    bool braces = end < text.Length && text[end] == '{';
                    if (braces) { end++; }
                    int argumentStart = end;
                    char terminator = braces ? '}' : ',';
                    while (end < text.Length && text[end] != terminator && text[end] != ';')
                    {
                        if (text[end] is '\'' or '"')
                        {
                            char quote = text[end++];
                            while (end < text.Length && text[end] != quote) { end++; }
                        }

                        if (end < text.Length) { end++; }
                    }

                    string argument = text[argumentStart..end].Trim();
                    if (argument.Length == 0) { throw new AssemblyError(0, "Empty .define argument."); }
                    names.Add(parameters[index], argument);
                    if (braces)
                    {
                        if (end == text.Length || text[end++] != '}')
                        {
                            throw new AssemblyError(0, "Unterminated .define argument.");
                        }
                    }

                    if (index + 1 < parameters.Length)
                    {
                        while (end < text.Length && char.IsWhiteSpace(text[end])) { end++; }
                        if (end == text.Length || text[end++] != ',')
                        {
                            throw new AssemblyError(0, "Missing .define argument separator.");
                        }
                    }
                }

                replacement = Substitute(replacement, names, frame: null);
            }

            replacement = ExpandCa65Definitions(replacement, depth + 1);
            result ??= new(text.Length);
            result.Append(text, copied, start - copied).Append(replacement);
            copied = end;
        }

        return result is null ? text : result.Append(text, copied, text.Length - copied).ToString();
    }
}
