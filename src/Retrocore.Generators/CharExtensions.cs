// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace System;

/// <summary>
///  Supplies modern ASCII predicates only to the .NET Standard generator compilation.
/// </summary>
internal static class CharExtensions
{
    extension(char)
    {
        /// <summary>
        ///  Determines whether a character is an ASCII letter.
        /// </summary>
        /// <param name="value">The candidate character.</param>
        /// <returns>Whether it is A-Z or a-z.</returns>
        internal static bool IsAsciiLetter(char value) => value is >= 'A' and <= 'Z' or >= 'a' and <= 'z';

        /// <summary>
        ///  Determines whether a character is an ASCII decimal digit.
        /// </summary>
        /// <param name="value">The candidate character.</param>
        /// <returns>Whether it is 0-9.</returns>
        internal static bool IsAsciiDigit(char value) => value is >= '0' and <= '9';

        /// <summary>
        ///  Determines whether a character is an ASCII letter or decimal digit.
        /// </summary>
        /// <param name="value">The candidate character.</param>
        /// <returns>Whether it is A-Z, a-z or 0-9.</returns>
        internal static bool IsAsciiLetterOrDigit(char value) => char.IsAsciiLetter(value) || char.IsAsciiDigit(value);

        /// <summary>
        ///  Determines whether a character is an ASCII hexadecimal digit.
        /// </summary>
        /// <param name="value">The candidate character.</param>
        /// <returns>Whether it is 0-9, A-F or a-f.</returns>
        internal static bool IsAsciiHexDigit(char value) => char.IsAsciiDigit(value) || value is >= 'A' and <= 'F' or >= 'a' and <= 'f';
    }
}
