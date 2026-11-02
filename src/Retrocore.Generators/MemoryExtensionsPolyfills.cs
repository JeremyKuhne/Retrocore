// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace System;

/// <summary>
///  Supplies memory-trimming and counting overloads missing from the generator's .NET Standard reference surface.
/// </summary>
internal static class MemoryExtensionsPolyfills
{
    /// <summary>
    ///  Counts occurrences of a character using the vectorized search .NET Standard does provide.
    /// </summary>
    /// <param name="text">The characters to search.</param>
    /// <param name="value">The character to count.</param>
    /// <returns>The number of occurrences.</returns>
    internal static int Count(this ReadOnlySpan<char> text, char value)
    {
        int count = 0;
        for (int index = text.IndexOf(value); index >= 0; index = text.IndexOf(value))
        {
            count++;
            text = text[(index + 1)..];
        }

        return count;
    }

    /// <summary>
    ///  Removes leading and trailing whitespace while retaining the original memory owner.
    /// </summary>
    /// <param name="text">The original character memory.</param>
    /// <returns>The trimmed slice.</returns>
    internal static ReadOnlyMemory<char> Trim(this ReadOnlyMemory<char> text) => text.TrimStart().TrimEnd();

    /// <summary>
    ///  Removes leading whitespace without allocating a replacement string.
    /// </summary>
    /// <param name="text">The original character memory.</param>
    /// <returns>The slice starting at its first non-whitespace character, or at its end.</returns>
    internal static ReadOnlyMemory<char> TrimStart(this ReadOnlyMemory<char> text)
    {
        int remaining = text.Span.TrimStart().Length;
        return text[(text.Length - remaining)..];
    }

    /// <summary>
    ///  Removes trailing whitespace without allocating a replacement string.
    /// </summary>
    /// <param name="text">The original character memory.</param>
    /// <returns>The slice ending at its last non-whitespace character, or empty at its start.</returns>
    internal static ReadOnlyMemory<char> TrimEnd(this ReadOnlyMemory<char> text) => text[..text.Span.TrimEnd().Length];
}
