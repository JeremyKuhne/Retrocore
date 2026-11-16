// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using System.Text.RegularExpressions;

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    // The names the hints give the system's procedures, by number: SYSTEM.43.
    private readonly Dictionary<int, string> _systemNames = [];

    // Names the system's procedures a (*$U-*) program declares, by their numbers, where the hints do and the names
    // are safe: the system's block reaches every procedure.
    private void RenameSystemProcedures()
    {
        foreach ((string key, string given) in _options.Names)
        {
            Match match = SystemProcedureHint().Match(key);
            if (!match.Success) { continue; }

            int number = int.Parse(match.Groups["number"].Value, CultureInfo.InvariantCulture);
            bool twice = _systemNames.Values.Any(other => Key(other) == Key(given));
            if (twice)
            {
                Warn($"The name {given} for {key} would clash with another of the system's procedures; it is left as the decompiler names it.");
                continue;
            }

            if (Safe(given, key, Program, key, out string? name)) { _systemNames[number] = name; }
        }
    }

    // A call's name: a system procedure's as the hints give it, or as it is.
    private string? SystemName(string? builtin)
    {
        Match match = builtin is null ? Match.Empty : SystemProcedureName().Match(builtin);
        return match.Success && _systemNames.TryGetValue(int.Parse(match.Groups["number"].Value, CultureInfo.InvariantCulture), out string? name)
            ? name
            : builtin;
    }

    // A view's name of a word used two ways (I, P, B, P2...), as the hints give it for the word's type: T15.I.
    private string ViewName(TypeNode type, string generated) => HintedField(type, generated);

    [GeneratedRegex("^SYSTEM\\.(?<number>[0-9]+)$", RegexOptions.IgnoreCase)]
    private static partial Regex SystemProcedureHint();

    [GeneratedRegex("^SYSTEM(?<number>[0-9]+)$")]
    private static partial Regex SystemProcedureName();
}
