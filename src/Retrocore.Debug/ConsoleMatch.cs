// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  Matches new sink bytes across drains without retaining or rescanning the stream.
/// </summary>
internal sealed class ConsoleMatch
{
    private readonly string _text;
    private readonly int[] _prefix;
    private int _matched;

    /// <summary>
    ///  Prepares a match with an overlapping-prefix table.
    /// </summary>
    /// <param name="text">The nonempty ASCII pattern.</param>
    internal ConsoleMatch(string text)
    {
        _text = text;
        _prefix = new int[text.Length];
        for (int index = 1, prefix = 0; index < text.Length; index++)
        {
            while (prefix != 0 && text[prefix] != text[index]) { prefix = _prefix[prefix - 1]; }
            if (text[prefix] == text[index]) { prefix++; }
            _prefix[index] = prefix;
        }
    }

    /// <summary>
    ///  Gets whether the whole pattern has appeared.
    /// </summary>
    internal bool Matched => _matched == _text.Length;

    /// <summary>
    ///  Observes the next byte.
    /// </summary>
    /// <param name="code">An accepted console byte.</param>
    internal void Add(byte code)
    {
        if (Matched) { return; }
        while (_matched != 0 && _text[_matched] != code) { _matched = _prefix[_matched - 1]; }
        if (_text[_matched] == code) { _matched++; }
    }
}
