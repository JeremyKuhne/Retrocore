// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;

namespace Retrocore.Debug;

/// <summary>
///  Reads an address given on the command line or in a hints file.
/// </summary>
internal static class CommandAddress
{
    /// <summary>
    ///  Parses an address written as <c>$6000</c>, <c>0x6000</c> or decimal.
    /// </summary>
    /// <param name="text">The address.</param>
    /// <returns>The value.</returns>
    /// <exception cref="FormatException">The text is not a number.</exception>
    internal static int Parse(string text)
    {
        int prefix = text.StartsWith('$') ? 1 : text.StartsWith("0x", StringComparison.OrdinalIgnoreCase) ? 2 : 0;
        NumberStyles style = prefix == 0 ? NumberStyles.Integer : NumberStyles.HexNumber;
        return int.Parse(text.AsSpan(prefix), style, CultureInfo.InvariantCulture);
    }
}
