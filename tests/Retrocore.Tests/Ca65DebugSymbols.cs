// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using System.Text.RegularExpressions;

namespace Retrocore.Tests;

/// <summary>
///  Keeps lexical names from ld65 debug data instead of flattening identically named type fields.
/// </summary>
internal static partial class Ca65DebugSymbols
{
    /// <summary>
    ///  Reads named values with their enclosing scope paths.
    /// </summary>
    /// <param name="path">The ld65 debug output.</param>
    /// <returns>Case-sensitive, qualified symbol values.</returns>
    internal static Dictionary<string, long> Read(string path)
    {
        Dictionary<string, (string Name, string? Parent)> scopes = new(StringComparer.Ordinal);
        List<Dictionary<string, string>> symbols = [];
        foreach (string line in File.ReadLines(path))
        {
            int space = line.IndexOf('\t');
            if (space < 0) { space = line.IndexOf(' '); }
            if (space < 0) { continue; }
            string kind = line[..space];
            if (kind is not ("scope" or "sym")) { continue; }
            Dictionary<string, string> fields = new(StringComparer.Ordinal);
            foreach (Match match in Fields().Matches(line[(space + 1)..]))
            {
                fields.Add(match.Groups[1].Value, match.Groups[2].Value.Trim('"'));
            }

            if (kind == "scope")
            {
                scopes.Add(fields["id"], (fields["name"], fields.TryGetValue("parent", out string? parent) ? parent : null));
            }
            else if (fields.ContainsKey("val"))
            {
                symbols.Add(fields);
            }
        }

        Dictionary<string, long> values = new(StringComparer.Ordinal);
        foreach (Dictionary<string, string> symbol in symbols)
        {
            string name = symbol["name"];
            if (name.StartsWith('.')) { continue; }
            string? scope = symbol.TryGetValue("scope", out string? id) ? id : null;
            while (scope is not null)
            {
                (string prefix, string? parent) = scopes[scope];
                if (prefix.Length != 0) { name = prefix + "::" + name; }
                scope = parent;
            }

            string text = symbol["val"];
            values[name] = text.StartsWith("0x", StringComparison.OrdinalIgnoreCase)
                ? long.Parse(text[2..], NumberStyles.HexNumber, CultureInfo.InvariantCulture)
                : long.Parse(text, CultureInfo.InvariantCulture);
        }

        return values;
    }

    [GeneratedRegex("""(?:^|,)(\w+)=("(?:\\.|[^"])*"|[^,]*)""")]
    private static partial Regex Fields();
}
