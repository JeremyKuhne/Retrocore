// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;

namespace Retrocore.Basic;

public abstract partial class BasicDialect
{
    /// <summary>
    ///  Spells out a stored line, tracking strings, DATA and REM as the tokenizer does.
    /// </summary>
    /// <param name="line">The stored bytes.</param>
    /// <param name="expansion">How to spell it.</param>
    /// <returns>The text, which may not tokenize back exactly; <see cref="Detokenize"/> checks.</returns>
    internal string Expand(ReadOnlySpan<byte> line, BasicExpansion expansion)
    {
        StringBuilder builder = new(line.Length * 2);
        bool inString = false;
        bool inData = false;
        bool inRemark = false;
        bool spaceAfter = false;
        for (int index = 0; index < line.Length; index++)
        {
            byte value = line[index];
            if (inRemark)
            {
                BasicText.AppendCharacter(builder, value);
                continue;
            }

            if (inString)
            {
                if (value == '"') { inString = false; }
                BasicText.AppendCharacter(builder, value);
                continue;
            }

            if (inData)
            {
                if (value == '"') { inString = true; }
                if (value == ':') { inData = false; }
                BasicText.AppendCharacter(builder, value);
                continue;
            }

            if (spaceAfter && SpacesAfterWord(value))
            {
                builder.Append(' ');
            }

            spaceAfter = false;
            if (ExpandSpecial(line, ref index, builder, out bool startsRemark))
            {
                inRemark = startsRemark;
                continue;
            }

            if (Keyword(value) is { } keyword)
            {
                AppendKeyword(builder, keyword, out spaceAfter);
                inRemark = value == RemToken;
                inData = value == DataToken;
                continue;
            }

            if (value == '"')
            {
                inString = true;
                builder.Append('"');
            }
            else if (value >= FirstToken || (expansion == BasicExpansion.EscapeLiterals && StartsSearch(value)))
            {
                BasicText.AppendEscape(builder, value);
            }
            else
            {
                BasicText.AppendCharacter(builder, value);
                spaceAfter = value == ':' && ListingSpaces;
            }
        }

        return builder.ToString();
    }

    /// <summary>
    ///  Gets whether a listing adds spaces for readability, which only a dialect whose tokenizer drops spaces may.
    /// </summary>
    internal abstract bool ListingSpaces { get; }

    /// <summary>
    ///  Tests whether a listing puts a space between a reserved word ending in a letter and the byte after it.
    /// </summary>
    /// <param name="next">The byte after the word.</param>
    /// <returns>
    ///  Whether a space goes between them: by default, unless a colon, comma, semicolon or parenthesis follows.
    /// </returns>
    internal virtual bool SpacesAfterWord(byte next) => next is not (byte)':' and not (byte)',' and not (byte)';' and not (byte)')';
}
