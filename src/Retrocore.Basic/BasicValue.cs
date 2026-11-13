// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  A BASIC value: a number, or a string as its bytes.
/// </summary>
/// <param name="Number">The number; 0 for a string.</param>
/// <param name="Text">The string's bytes, or null for a number.</param>
/// <param name="Long">
///  A Business BASIC long integer exactly, which <paramref name="Number"/> may only approximate; null for other values.
/// </param>
public readonly record struct BasicValue(double Number, byte[]? Text = null, long? Long = null)
{
    /// <summary>
    ///  Gets whether the value is a string.
    /// </summary>
    public bool IsString => Text is not null;

    /// <summary>
    ///  Makes a string value.
    /// </summary>
    /// <param name="text">The string's bytes.</param>
    /// <returns>The value.</returns>
    public static BasicValue Of(byte[] text) => new(0, text);

    /// <summary>
    ///  Makes a long integer value.
    /// </summary>
    /// <param name="value">The long integer.</param>
    /// <returns>The value.</returns>
    public static BasicValue OfLong(long value) => new(value, Text: null, Long: value);
}
