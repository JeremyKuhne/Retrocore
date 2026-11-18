// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;

namespace Retrocore.Debug;

/// <summary>
///  A command line's symbol definition, as <c>--define</c> takes it: <c>NAME</c>, which is 1, or <c>NAME=value</c>.
/// </summary>
internal static class DefineArgument
{
    /// <summary>
    ///  Parses a definition, the value a 64-bit integer written in decimal, with <c>$</c> or with <c>0x</c>.
    /// </summary>
    /// <param name="text">The definition.</param>
    /// <param name="name">The symbol.</param>
    /// <param name="value">Its value.</param>
    /// <returns>Whether the definition is well formed.</returns>
    internal static bool TryParse(string text, out string name, out long value)
    {
        string[] parts = text.Split('=', 2);
        name = parts[0].Trim();
        value = 1;
        if (name.Length == 0) { return false; }
        if (parts.Length == 1) { return true; }

        ReadOnlySpan<char> number = parts[1].AsSpan().Trim();
        NumberStyles hex = NumberStyles.AllowHexSpecifier;
        if (number.StartsWith('$')) { return long.TryParse(number[1..], hex, CultureInfo.InvariantCulture, out value); }
        if (number.StartsWith("0x", StringComparison.OrdinalIgnoreCase))
        {
            return long.TryParse(number[2..], hex, CultureInfo.InvariantCulture, out value);
        }

        return long.TryParse(number, NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out value);
    }
}
