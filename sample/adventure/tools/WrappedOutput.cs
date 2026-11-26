// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;

/// <summary>
///  Wraps text at word boundaries to a screen's width, as the 6502 engine's <c>Printer</c> does, and keeps the
///  characters it sends to the screen.
/// </summary>
/// <remarks>
///  <para>
///   A line holds at most one column fewer than the screen, so no line fills the screen's width and makes the
///   machine wrap it a second time. A word waits in a buffer until a space or a new line ends it, and spaces wait
///   until the next word: a word that fits on the line with them goes after them, and one that doesn't goes on the
///   next line without them, so no line ends in a space. At most a line's width of spaces wait. A word as wide as a
///   line is sent as it is.
///  </para>
/// </remarks>
/// <param name="columns">The screen's width.</param>
internal sealed class WrappedOutput(int columns)
{
    private readonly int _width = columns - 1;
    private readonly StringBuilder _word = new();
    private int _spaces;

    /// <summary>
    ///  The characters sent to the screen, with <c>\n</c> for each new line.
    /// </summary>
    internal StringBuilder Sent { get; } = new();

    /// <summary>
    ///  The column the next character goes in.
    /// </summary>
    internal int Column { get; private set; }

    /// <summary>
    ///  Writes a character.
    /// </summary>
    /// <param name="character">The character, <c>\n</c> for a new line.</param>
    internal void Write(char character)
    {
        if (character == '\n')
        {
            SendWord();
            _spaces = 0;
            Send('\n');
        }
        else if (character == ' ')
        {
            SendWord();
            if (_spaces < _width) { _spaces++; }
        }
        else
        {
            _word.Append(character);
            if (_word.Length == _width) { SendWord(); }
        }
    }

    /// <summary>
    ///  Writes text.
    /// </summary>
    /// <param name="text">The text.</param>
    internal void Write(string text)
    {
        foreach (char character in text) { Write(character); }
    }

    /// <summary>
    ///  Sends the word and the spaces waiting, before the engine waits for a line to be typed.
    /// </summary>
    internal void Flush()
    {
        SendWord();
        for (; _spaces > 0; _spaces--) { Send(' '); }
    }

    /// <summary>
    ///  Ends the line, unless nothing has been written on it.
    /// </summary>
    internal void EndLine()
    {
        SendWord();
        _spaces = 0;
        if (Column != 0) { Send('\n'); }
    }

    /// <summary>
    ///  Notes that the screen's cursor is at the start of a line, after a line typed in or a cleared screen, without
    ///  sending anything.
    /// </summary>
    internal void AtLineStart()
    {
        Flush();
        Column = 0;
    }

    // Sends the word waiting in the buffer after the spaces before it, or on a new line without them when they don't
    // fit on this one.
    private void SendWord()
    {
        if (_word.Length == 0) { return; }
        if (Column > 0 && Column + _spaces + _word.Length > _width)
        {
            Send('\n');
        }
        else
        {
            for (; _spaces > 0; _spaces--) { Send(' '); }
        }

        _spaces = 0;
        foreach (char character in _word.ToString()) { Send(character); }
        _word.Clear();
    }

    private void Send(char character)
    {
        Sent.Append(character);
        Column = character == '\n' ? 0 : Column + 1;
    }
}
