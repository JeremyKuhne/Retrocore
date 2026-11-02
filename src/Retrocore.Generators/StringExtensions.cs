// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Runtime.CompilerServices;

namespace System;

/// <summary>
///  Supplies string APIs missing from the generator's .NET Standard reference surface.
/// </summary>
internal static class StringExtensions
{
    extension(string)
    {
        /// <summary>
        ///  Builds an interpolated string with a provider, such as the invariant culture for negative numbers.
        /// </summary>
        /// <param name="provider">Culture-specific formatting.</param>
        /// <param name="handler">The interpolated string.</param>
        /// <returns>The built string.</returns>
        internal static string Create(
            IFormatProvider? provider,
            [InterpolatedStringHandlerArgument(nameof(provider))] ref DefaultInterpolatedStringHandler handler)
        {
            return handler.ToStringAndClear();
        }
    }

    /// <param name="text">The string to search.</param>
    extension(string text)
    {
        /// <summary>
        ///  Determines whether a string contains a character.
        /// </summary>
        /// <param name="value">The character.</param>
        /// <returns>Whether it occurs.</returns>
        internal bool Contains(char value) => text.IndexOf(value) >= 0;

        /// <summary>
        ///  Determines whether a string contains another, with a comparison.
        /// </summary>
        /// <param name="value">The string to find.</param>
        /// <param name="comparison">How to compare.</param>
        /// <returns>Whether it occurs.</returns>
        internal bool Contains(string value, StringComparison comparison) => text.IndexOf(value, comparison) >= 0;

        /// <summary>
        ///  Determines whether a string starts with a character.
        /// </summary>
        /// <param name="value">The character.</param>
        /// <returns>Whether it starts with it.</returns>
        internal bool StartsWith(char value) => text.Length != 0 && text[0] == value;

        /// <summary>
        ///  Determines whether a string ends with a character.
        /// </summary>
        /// <param name="value">The character.</param>
        /// <returns>Whether it ends with it.</returns>
        internal bool EndsWith(char value) => text.Length != 0 && text[^1] == value;

        /// <summary>
        ///  Splits a string at a separator string.
        /// </summary>
        /// <param name="separator">The separator.</param>
        /// <returns>The parts.</returns>
        internal string[] Split(string separator) => text.Split([separator], StringSplitOptions.None);
    }
}
