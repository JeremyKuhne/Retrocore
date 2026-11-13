// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  Turns text pasted into the display panel into the keys a machine's keyboard types.
/// </summary>
/// <remarks>
///  <para>
///   Each line ending (CR, LF or CRLF) is RETURN and a tab is TAB. Other control characters are left out, so a
///   paste cannot press CONTROL-C or ESC. Printable ASCII is typed as it is, and each machine's keyboard makes of it
///   what it can: the II Plus types capitals, and the Model I drops what it has no key for. The quotes, dashes,
///   ellipsis and non-breaking space that editors and web pages substitute become their ASCII forms; other
///   characters are left out.
///  </para>
/// </remarks>
internal static class TypedText
{
    private const int Return = 13;
    private const int Tab = 9;

    /// <summary>
    ///  Gets the key codes, 0-127, to type for the text.
    /// </summary>
    /// <param name="text">The text.</param>
    /// <param name="skipped">How many characters have no key and were left out.</param>
    /// <returns>The codes, in order.</returns>
    public static List<int> Codes(string text, out int skipped)
    {
        List<int> codes = new(text.Length);
        skipped = 0;
        for (int index = 0; index < text.Length; index++)
        {
            char character = text[index];
            switch (character)
            {
                case '\r':
                    codes.Add(Return);
                    if (index + 1 < text.Length && text[index + 1] == '\n') { index++; }
                    break;
                case '\n':
                    codes.Add(Return);
                    break;
                case '\t':
                    codes.Add(Tab);
                    break;
                case >= ' ' and < '\u007F':
                    codes.Add(character);
                    break;
                case '‘' or '’' or '‚' or '‛' or '′':
                    codes.Add('\'');
                    break;
                case '“' or '”' or '„' or '‟' or '″':
                    codes.Add('"');
                    break;
                case '‐' or '‑' or '‒' or '–' or '—' or '−':
                    codes.Add('-');
                    break;
                case ' ' or ' ' or ' ':
                    codes.Add(' ');
                    break;
                case '…':
                    codes.AddRange(['.', '.', '.']);
                    break;
                default:
                    skipped++;
                    break;
            }
        }

        return codes;
    }
}
