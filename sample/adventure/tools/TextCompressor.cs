// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;

/// <summary>
///  Compresses a game's text with a dictionary of common substrings: each byte from <see cref="FirstToken"/> up
///  stands for one entry of the dictionary, and the other bytes are the text's own characters.
/// </summary>
/// <remarks>
///  <para>
///   The dictionary is chosen greedily: each round takes the substring that saves the most bytes, counting what its
///   entry costs, and replaces it everywhere, until the dictionary is full or no substring saves anything. Entries
///   hold only characters, never other entries, so the interpreter expands one with a single copy.
///  </para>
/// </remarks>
internal static class TextCompressor
{
    /// <summary>
    ///  The first byte that stands for a dictionary entry; the entries run from it to <c>$FF</c>.
    /// </summary>
    internal const int FirstToken = 0x80;

    /// <summary>
    ///  The longest dictionary entry.
    /// </summary>
    internal const int LongestEntry = 24;

    /// <summary>
    ///  The byte that ends each string.
    /// </summary>
    internal const byte End = 0;

    /// <summary>
    ///  The byte for a new line.
    /// </summary>
    internal const byte NewLine = 0x0A;

    /// <summary>
    ///  Chooses a dictionary for the strings and compresses each.
    /// </summary>
    /// <param name="strings">The strings, in printable ASCII and new lines.</param>
    /// <returns>The dictionary's entries and each string's bytes, without its <see cref="End"/>.</returns>
    /// <exception cref="InvalidDataException">A string holds a character the format cannot store.</exception>
    internal static (List<byte[]> Dictionary, List<byte[]> Strings) Compress(IReadOnlyList<string> strings)
    {
        // Each string as symbols: a character below FirstToken, or FirstToken plus an entry's index.
        List<List<int>> texts = [.. strings.Select(Symbols)];
        List<byte[]> dictionary = [];
        while (dictionary.Count < 0x100 - FirstToken && Best(texts) is { } entry)
        {
            Replace(texts, entry, FirstToken + dictionary.Count);
            dictionary.Add(entry);
        }

        return (dictionary, [.. texts.Select(text => text.Select(symbol => (byte)symbol).ToArray())]);
    }

    private static List<int> Symbols(string text)
    {
        List<int> symbols = [];
        foreach (char character in text)
        {
            if (character != '\n' && character is < ' ' or > '~')
            {
                throw new InvalidDataException($"The text \"{text}\" holds U+{(int)character:X4}, which the format cannot store.");
            }

            symbols.Add(character);
        }

        return symbols;
    }

    // The substring that saves the most bytes, or null when none saves any. An entry costs its length and a length
    // byte; each use saves its length less the token byte.
    private static byte[]? Best(List<List<int>> texts)
    {
        Dictionary<string, int> counts = [with(StringComparer.Ordinal)];
        foreach (List<int> text in texts)
        {
            for (int start = 0; start < text.Count; start++)
            {
                if (text[start] >= FirstToken) { continue; }
                for (int length = 2; length <= LongestEntry && start + length <= text.Count; length++)
                {
                    if (text[start + length - 1] >= FirstToken) { break; }
                    string key = Key(text, start, length);
                    counts[key] = counts.GetValueOrDefault(key) + 1;
                }
            }
        }

        string? best = null;
        int bestSaving = 0;
        foreach ((string candidate, int count) in counts)
        {
            // Overlapping uses of a substring such as "aaa" are counted, so count them again as they would be replaced.
            if (count * (candidate.Length - 1) - (candidate.Length + 1) < bestSaving) { continue; }
            int saving = Uses(texts, candidate) * (candidate.Length - 1) - (candidate.Length + 1);
            if (saving > bestSaving
                || (saving == bestSaving && best is not null && string.CompareOrdinal(candidate, best) < 0))
            {
                best = candidate;
                bestSaving = saving;
            }
        }

        return best is null ? null : Encoding.ASCII.GetBytes(best);
    }

    private static string Key(List<int> text, int start, int length)
    {
        Span<char> characters = stackalloc char[length];
        for (int index = 0; index < length; index++)
        {
            characters[index] = (char)text[start + index];
        }

        return new string(characters);
    }

    // How many times the substring would be replaced, scanning each text from the left without overlaps.
    private static int Uses(List<List<int>> texts, string candidate)
    {
        int uses = 0;
        foreach (List<int> text in texts)
        {
            for (int start = 0; start + candidate.Length <= text.Count;)
            {
                if (Matches(text, start, candidate))
                {
                    uses++;
                    start += candidate.Length;
                }
                else
                {
                    start++;
                }
            }
        }

        return uses;
    }

    private static bool Matches(List<int> text, int start, string candidate)
    {
        for (int index = 0; index < candidate.Length; index++)
        {
            if (text[start + index] != candidate[index]) { return false; }
        }

        return true;
    }

    private static void Replace(List<List<int>> texts, byte[] entry, int token)
    {
        string candidate = Encoding.ASCII.GetString(entry);
        foreach (List<int> text in texts)
        {
            for (int start = 0; start + candidate.Length <= text.Count; start++)
            {
                if (Matches(text, start, candidate))
                {
                    text.RemoveRange(start, candidate.Length);
                    text.Insert(start, token);
                }
            }
        }
    }
}
