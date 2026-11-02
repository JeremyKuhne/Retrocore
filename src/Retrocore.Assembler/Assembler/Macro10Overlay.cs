// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using System.Security.Cryptography;
using System.Text;

namespace Retrocore.Assembler;

/// <summary>
///  Composes a MACRO-10 overlay with the pinned source it edits.
/// </summary>
/// <remarks>
///  <para>
///   An overlay names its base in its first-line pragma, <c>; retrocore: dialect=macro10 overlay=m6502.asm
///   sha256=...</c>, and holds only edits to the base's lines, so an unchanged line still comes from, and debugs
///   in, the original file. <c>;@REPLACE a-b</c> replaces base lines <c>a</c> through <c>b</c> with the block;
///   <c>;@INSERT AFTER n</c> and <c>;@INSERT BEFORE n</c> add the block beside line <c>n</c>; and
///   <c>;@DELETE a-b</c> removes lines and has no block.
///  </para>
///  <para>
///   A block ends with <c>;@END</c>. Line numbers are one-based and refer to the base as pinned; the optional
///   SHA-256 is of the base's text in UTF-8 with LF line endings, so edits cannot silently land on a different
///   revision. Edits must be in line order and may not overlap. Outside blocks, an overlay holds only comments
///   and blank lines.
///  </para>
/// </remarks>
internal static partial class Macro10Overlay
{
    /// <summary>
    ///  Composes an overlay with its base.
    /// </summary>
    /// <param name="overlay">The overlay source.</param>
    /// <param name="baseSource">The base source the overlay names.</param>
    /// <param name="parent">The including location, if any.</param>
    /// <returns>The composed text and the source location of each of its lines.</returns>
    /// <exception cref="AssemblyError">The overlay is malformed or its base does not match its hash.</exception>
    internal static (string Text, Func<int, AssemblyLocation> Location) Compose(
        AssemblySource overlay,
        AssemblySource baseSource,
        AssemblyLocation? parent)
    {
        string[] baseLines = Lines(baseSource.Text);
        if (AssemblyPreprocessor.PragmaValue(overlay.Text, "sha256") is { } expected)
        {
            string actual = Hash(string.Join("\n", baseLines));
            if (!actual.Equals(expected, StringComparison.OrdinalIgnoreCase))
            {
                throw new AssemblyError(0, $"Overlay base '{baseSource.Path}' has SHA-256 {actual}, not {expected}.");
            }
        }

        List<Edit> edits = Parse(Lines(overlay.Text), baseLines.Length);
        List<string> text = [];
        List<AssemblyLocation> locations = [];
        int next = 1;
        foreach (Edit edit in edits)
        {
            // Copy the base up to the edit, then the edit's own lines in place of the lines it replaces.
            for (; next < edit.First; next++)
            {
                text.Add(baseLines[next - 1]);
                locations.Add(new(baseSource.Path, next - 1, column: 0, parent));
            }

            for (int index = 0; index < edit.Lines.Count; index++)
            {
                text.Add(edit.Lines[index]);
                locations.Add(new(overlay.Path, edit.OverlayLine + index, column: 0, parent));
            }

            next = Math.Max(next, edit.Last + 1);
        }

        for (; next <= baseLines.Length; next++)
        {
            text.Add(baseLines[next - 1]);
            locations.Add(new(baseSource.Path, next - 1, column: 0, parent));
        }

        AssemblyLocation end = new(overlay.Path, 0, column: 0, parent);
        return (string.Join("\n", text), line => line < locations.Count ? locations[line] : end);
    }

    /// <summary>
    ///  Computes the SHA-256 an overlay pins its base with.
    /// </summary>
    /// <param name="text">The base text with LF line endings.</param>
    /// <returns>The uppercase hexadecimal hash.</returns>
    internal static string Hash(string text)
    {
        using SHA256 sha = SHA256.Create();
        byte[] hash = sha.ComputeHash(Encoding.UTF8.GetBytes(text));
        return string.Concat(hash.Select(value => value.ToString("X2", CultureInfo.InvariantCulture)));
    }

    private static string[] Lines(string text) => text.Replace("\r\n", "\n").Split('\n');

    private static List<Edit> Parse(string[] lines, int baseCount)
    {
        List<Edit> edits = [];
        for (int index = 1; index < lines.Length; index++)
        {
            string line = lines[index].Trim();
            if (!line.StartsWith(";@", StringComparison.Ordinal))
            {
                if (line.Length != 0 && line[0] != ';')
                {
                    throw new AssemblyError(index, "Overlay text must be inside a ;@REPLACE or ;@INSERT block.");
                }

                continue;
            }

            string[] words = line[2..].Split([' ', '\t'], StringSplitOptions.RemoveEmptyEntries);
            string command = words.Length == 0 ? "" : words[0].ToUpperInvariant();
            (int first, int last) = command switch
            {
                "REPLACE" or "DELETE" when words.Length == 2 => Range(words[1], index),
                "INSERT" when words.Length == 3 && words[1].Equals("AFTER", StringComparison.OrdinalIgnoreCase) =>
                    (Number(words[2], index) + 1, Number(words[2], index)),
                "INSERT" when words.Length == 3 && words[1].Equals("BEFORE", StringComparison.OrdinalIgnoreCase) =>
                    (Number(words[2], index), Number(words[2], index) - 1),
                _ => throw new AssemblyError(index, $"Unknown overlay command '{line}'.")
            };

            if (first < 1 || last > baseCount || first > last + 1)
            {
                throw new AssemblyError(index, $"Overlay lines {first}-{last} are outside the base's {baseCount} lines.");
            }

            if (edits.Count != 0 && (first < edits[^1].Last + 1 || (first == edits[^1].First && last < first)))
            {
                throw new AssemblyError(index, "Overlay edits must be in line order and may not overlap.");
            }

            List<string> block = [];
            int start = index + 1;
            if (command != "DELETE")
            {
                for (index++; index < lines.Length && !lines[index].Trim().Equals(";@END", StringComparison.OrdinalIgnoreCase); index++)
                {
                    block.Add(lines[index]);
                }

                if (index >= lines.Length)
                {
                    throw new AssemblyError(start - 1, "Unterminated overlay block; expected ;@END.");
                }
            }

            edits.Add(new(first, last, start, block));
        }

        return edits;
    }

    private static (int First, int Last) Range(string text, int line)
    {
        int dash = text.IndexOf('-');
        return dash < 0 ? (Number(text, line), Number(text, line)) : (Number(text[..dash], line), Number(text[(dash + 1)..], line));
    }

    private static int Number(string text, int line) =>
        int.TryParse(text, NumberStyles.None, CultureInfo.InvariantCulture, out int value)
            ? value
            : throw new AssemblyError(line, $"Expected an overlay line number, not '{text}'.");
}
