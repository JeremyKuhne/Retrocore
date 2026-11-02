// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using System.Text.RegularExpressions;

namespace Retrocore.Debug;

internal sealed partial class DebugSession
{
    /// <summary>
    ///  A hit count condition: <c>N</c> or <c>=N</c> stops on the Nth hit, <c>&gt;N</c>, <c>&gt;=N</c>, <c>&lt;N</c>
    ///  and <c>&lt;=N</c> compare the hits with N, and <c>%N</c> stops on every Nth hit.
    /// </summary>
    /// <param name="Operator">
    ///  The comparison: <c>==</c>, <c>&gt;</c>, <c>&gt;=</c>, <c>&lt;</c>, <c>&lt;=</c> or <c>%</c>.
    /// </param>
    /// <param name="Count">The count compared with.</param>
    private readonly partial record struct HitCondition(string Operator, int Count)
    {
        /// <summary>
        ///  Describes the hit count syntax, for a breakpoint whose hit count is not in it.
        /// </summary>
        internal const string Syntax = "A hit count is N, =N, >N, >=N, <N, <=N or %N.";

        /// <summary>
        ///  Tests whether a hit stops.
        /// </summary>
        /// <param name="hits">The hits so far, counting this one.</param>
        /// <returns>Whether it stops.</returns>
        internal bool Matches(int hits) => Operator switch
        {
            ">" => hits > Count,
            ">=" => hits >= Count,
            "<" => hits < Count,
            "<=" => hits <= Count,
            "%" => hits % Count == 0,
            _ => hits == Count
        };

        /// <summary>
        ///  Parses a hit count condition.
        /// </summary>
        /// <param name="text">The condition.</param>
        /// <returns>The condition.</returns>
        /// <exception cref="FormatException">The text is not a hit count condition.</exception>
        internal static HitCondition Parse(string text)
        {
            Match match = Pattern().Match(text);
            if (!match.Success
                || !int.TryParse(match.Groups[2].Value, NumberStyles.None, CultureInfo.InvariantCulture, out int count))
            {
                throw new FormatException(Syntax);
            }

            string operation = match.Groups[1].Value switch { "" or "=" => "==", string value => value };
            return operation == "%" && count == 0 ? throw new FormatException(Syntax) : new(operation, count);
        }

        [GeneratedRegex(@"^\s*(==|=|>=|>|<=|<|%)?\s*(\d+)\s*$")]
        private static partial Regex Pattern();
    }
}
