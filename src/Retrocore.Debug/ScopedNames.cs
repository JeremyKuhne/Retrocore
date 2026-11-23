// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Diagnostics.CodeAnalysis;
using System.Globalization;
using System.Text.RegularExpressions;
using Touki.Text;

namespace Retrocore.Debug;

/// <summary>
///  The names in scopes, such as <c>LowRes::Plot</c>, that a disassembly refers to outside what it disassembles.
/// </summary>
/// <remarks>
///  <para>
///   The disassembler's analysis takes only plain names, so each scoped name goes through it as a stand-in, a plain
///   name none of the disassembly's other names is, and the exported source is then rewritten: the code calls the name
///   by its qualified name, and its equate is defined inside its scopes, each scope opened once (and continued where a
///   later group of equates needs it again, as <see cref="DisassembleCommand"/> groups them).
///  </para>
/// </remarks>
internal sealed partial class ScopedNames
{
    // The prefix of a stand-in; a number after it makes the stand-in, skipping any the disassembly's names use.
    private const string StandInPrefix = "Scoped__";

    private readonly Dictionary<string, string> _qualified = [with(StringComparer.Ordinal)];
    private readonly Dictionary<string, string> _standIns = [with(StringComparer.Ordinal)];
    private readonly HashSet<string> _taken;
    private int _next;

    /// <summary>
    ///  Starts with the plain names the disassembly may also use, which no stand-in is.
    /// </summary>
    /// <param name="taken">The disassembly's other names, such as the hints' and the machine's.</param>
    internal ScopedNames(IEnumerable<string> taken) => _taken = new(taken, StringComparer.Ordinal);

    /// <summary>
    ///  Gets whether no scoped name has been given a stand-in.
    /// </summary>
    internal bool IsEmpty => _qualified.Count == 0;

    /// <summary>
    ///  Gets whether a name is a qualified one whose every part is a plain identifier, such as
    ///  <c>Disassembler::Decode::Opcode</c>; a cheap local such as <c>Main::@loop</c> is not.
    /// </summary>
    /// <param name="name">The name.</param>
    /// <returns><see langword="true"/> for a qualified name the native assembler can call.</returns>
    internal static bool IsScoped(string name) => QualifiedName().IsMatch(name);

    /// <summary>
    ///  Gets the stand-in for a qualified name, the same one each time it is asked for.
    /// </summary>
    /// <param name="qualified">The qualified name.</param>
    /// <returns>A plain name the analysis takes.</returns>
    internal string StandInFor(string qualified)
    {
        if (!_standIns.TryGetValue(qualified, out string? standIn))
        {
            do { standIn = $"{StandInPrefix}{_next++}"; } while (_taken.Contains(standIn));
            _standIns[qualified] = standIn;
            _qualified[standIn] = qualified;
        }

        return standIn;
    }

    /// <summary>
    ///  Gets the qualified name a stand-in stands for.
    /// </summary>
    /// <param name="standIn">The name, which may be a stand-in.</param>
    /// <param name="qualified">The qualified name.</param>
    /// <returns><see langword="true"/> when the name is a stand-in.</returns>
    internal bool TryGetQualified(string standIn, [NotNullWhen(returnValue: true)] out string? qualified) =>
        _qualified.TryGetValue(standIn, out qualified);

    /// <summary>
    ///  Replaces the stand-ins in a line of code with their qualified names; a comment line, the hints' text, is left
    ///  as it is.
    /// </summary>
    /// <param name="line">The line.</param>
    /// <returns>The line with the qualified names.</returns>
    internal string Qualify(string line) =>
        IsEmpty || line.StartsWith(';')
            ? line
            : StandInName().Replace(line, match => _qualified.GetValueOrDefault(match.Value, match.Value));

    /// <summary>
    ///  Writes the equates of stand-ins inside their scopes, in order of their qualified names so that a scope's names
    ///  are together.
    /// </summary>
    /// <param name="equates">The stand-ins and their values.</param>
    /// <param name="opened">
    ///  The scope paths already opened in the source; each is continued instead of opened again.
    /// </param>
    /// <returns>The equates' lines.</returns>
    internal string ScopedEquates(IEnumerable<(string StandIn, string Value)> equates, HashSet<string> opened)
    {
        using ValueStringBuilder text = new(stackalloc char[256]);
        List<string> open = [];
        foreach ((string qualified, string value) in equates
            .Select(equate => (_qualified[equate.StandIn], equate.Value))
            .OrderBy(equate => equate.Item1, StringComparer.Ordinal))
        {
            string[] parts = qualified.Split("::");
            int common = 0;
            while (common < open.Count && common < parts.Length - 1 && open[common] == parts[common]) { common++; }
            for (; open.Count > common; open.RemoveAt(open.Count - 1)) { text.Append(".endscope\n"); }
            for (; open.Count < parts.Length - 1; open.Add(parts[open.Count]))
            {
                string path = string.Join("::", parts[..(open.Count + 1)]);
                text.Append(opened.Add(path) ? $".scope {parts[open.Count]}\n" : $".scope {parts[open.Count]} continued\n");
            }

            text.Append($"{parts[^1]} = {value}\n");
        }

        for (; open.Count > 0; open.RemoveAt(open.Count - 1)) { text.Append(".endscope\n"); }
        return text.ToString();
    }

    /// <summary>
    ///  Rewrites an exported source whose equates may hold stand-ins: the plain equates as they are, then the scoped
    ///  ones inside their scopes, and the code with the qualified names.
    /// </summary>
    /// <param name="exported">
    ///  The analysis's exported source: its CPU line, its equates, then <c>.org</c> and the code.
    /// </param>
    /// <returns>The source with the qualified names.</returns>
    internal string Rewrite(string exported)
    {
        if (IsEmpty) { return exported; }

        string[] lines = exported.Split('\n');
        int code = Array.FindIndex(lines, line => line.StartsWith(".org ", StringComparison.Ordinal));
        if (code < 1) { return exported; }

        using ValueStringBuilder source = new(exported.Length + 256, CultureInfo.InvariantCulture);
        source.Append(lines[0]);
        source.Append('\n');
        List<(string StandIn, string Value)> scoped = [];
        foreach (string line in lines[1..code])
        {
            int equals = line.IndexOf(" = ", StringComparison.Ordinal);
            if (equals > 0 && _qualified.ContainsKey(line[..equals]))
            {
                scoped.Add((line[..equals], line[(equals + 3)..]));
            }
            else
            {
                source.Append(line);
                source.Append('\n');
            }
        }

        source.Append(ScopedEquates(scoped, [with(StringComparer.Ordinal)]));
        for (int index = code; index < lines.Length; index++)
        {
            source.Append(Qualify(lines[index]));
            if (index + 1 < lines.Length) { source.Append('\n'); }
        }

        return source.ToString();
    }

    // A qualified name with plain identifiers for parts.
    [GeneratedRegex("^[A-Za-z_][A-Za-z0-9_]*(::[A-Za-z_][A-Za-z0-9_]*)+$")]
    private static partial Regex QualifiedName();

    // A stand-in in the exported source.
    [GeneratedRegex(@"\bScoped__[0-9]+\b")]
    private static partial Regex StandInName();
}
