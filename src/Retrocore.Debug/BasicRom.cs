// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  Where a machine's BASIC ROM runs statements, stops and reports errors, from the SDK's source of the ROM that is
///  running.
/// </summary>
/// <param name="StatementStart">
///  The statement fetcher, <c>NEWSTT</c>, where BASIC is between statements and saves its stack.
/// </param>
/// <param name="Gone">
///  Where each statement starts, <c>GONE</c>: the current line number is set, and the text pointer is at the colon or
///  the line's start before the statement.
/// </param>
/// <param name="Prompt">Where the command loop starts: AppleSoft's <c>MAIN</c>, Level II's <c>READY</c>.</param>
/// <param name="Error">Where an error is reported, <c>ERROR</c>.</param>
/// <param name="Run">Where the <c>RUN</c> statement's handler starts.</param>
/// <param name="Continue">Where the <c>CONT</c> statement's handler starts.</param>
/// <param name="Stops">
///  Where a program stops, by what stops it: STOP, END, BREAK, or running off the end of the program.
/// </param>
internal sealed record BasicRom(
    ushort StatementStart,
    ushort Gone,
    ushort Prompt,
    ushort Error,
    ushort Run,
    ushort Continue,
    IReadOnlyDictionary<ushort, string> Stops)
{
    /// <summary>
    ///  The stop where Integer BASIC prints STOPPED AT, for Control-C and for an error in a running program.
    /// </summary>
    internal const string IntegerStop = "INTSTOP";

    /// <summary>
    ///  The stop at Integer BASIC's END, which STOPPED AT runs into.
    /// </summary>
    internal const string IntegerEnd = "INTEND";

    /// <summary>
    ///  Gets the addresses from a ROM's assembled symbols.
    /// </summary>
    /// <param name="symbols">The symbols; null when the ROM's source was not assembled.</param>
    /// <param name="prompt">The name of the command loop's entry.</param>
    /// <param name="run">The name of the <c>RUN</c> handler.</param>
    /// <param name="resume">The name of the <c>CONT</c> handler.</param>
    /// <param name="stops">The labels where a program stops, and what each means.</param>
    /// <returns>The addresses, or null when the symbols lack any of them.</returns>
    internal static BasicRom? From(
        IReadOnlyDictionary<string, long>? symbols,
        string prompt,
        string run,
        string resume,
        (string Label, string Kind)[] stops)
    {
        if (symbols is null) { return null; }
        Dictionary<ushort, string> found = [];
        foreach ((string label, string kind) in stops)
        {
            if (!symbols.TryGetValue(label, out long address)) { return null; }
            found[(ushort)address] = kind;
        }

        if (symbols.TryGetValue("NEWSTT", out long statement)
            && symbols.TryGetValue("GONE", out long gone)
            && symbols.TryGetValue(prompt, out long entry)
            && symbols.TryGetValue("ERROR", out long error)
            && symbols.TryGetValue(run, out long runs)
            && symbols.TryGetValue(resume, out long resumes))
        {
            return new BasicRom(
                (ushort)statement,
                (ushort)gone,
                (ushort)entry,
                (ushort)error,
                (ushort)runs,
                (ushort)resumes,
                found);
        }

        return null;
    }
}
