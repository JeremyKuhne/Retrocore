// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Buffers;

namespace System.Runtime.CompilerServices;

/// <summary>
///  Lets the .NET Standard generator compilation build interpolated strings into one pooled buffer, as .NET does,
///  instead of through <see cref="string.Format(string, object[])"/>, which boxes and cannot take spans.
/// </summary>
/// <remarks>
///  <para>
///   Formatting follows .NET: an <see cref="IFormattable"/> value uses the format and provider, so a null provider
///   means the current culture. Custom formatters are not consulted.
///  </para>
/// </remarks>
[InterpolatedStringHandler]
internal ref struct DefaultInterpolatedStringHandler
{
    private readonly IFormatProvider? _provider;
    private char[] _buffer;
    private int _length;

    /// <summary>
    ///  Creates a handler sized for the literal text and an estimate for each hole.
    /// </summary>
    /// <param name="literalLength">The number of literal characters.</param>
    /// <param name="formattedCount">The number of interpolation holes.</param>
    internal DefaultInterpolatedStringHandler(int literalLength, int formattedCount)
        : this(literalLength, formattedCount, provider: null)
    {
    }

    /// <summary>
    ///  Creates a handler that formats holes with a provider.
    /// </summary>
    /// <param name="literalLength">The number of literal characters.</param>
    /// <param name="formattedCount">The number of interpolation holes.</param>
    /// <param name="provider">Culture-specific formatting, or null for the current culture.</param>
    internal DefaultInterpolatedStringHandler(int literalLength, int formattedCount, IFormatProvider? provider)
    {
        _provider = provider;
        _buffer = ArrayPool<char>.Shared.Rent(Math.Max(256, literalLength + (formattedCount * 11)));
        _length = 0;
    }

    /// <summary>
    ///  Appends literal text.
    /// </summary>
    /// <param name="value">The literal.</param>
    internal void AppendLiteral(string value) => AppendFormatted(value.AsSpan());

    /// <summary>
    ///  Appends characters.
    /// </summary>
    /// <param name="value">The characters.</param>
    internal void AppendFormatted(scoped ReadOnlySpan<char> value)
    {
        if (_length + value.Length > _buffer.Length) { Grow(value.Length); }
        value.CopyTo(_buffer.AsSpan(_length));
        _length += value.Length;
    }

    /// <summary>
    ///  Appends a string.
    /// </summary>
    /// <param name="value">The string, where null appends nothing.</param>
    internal void AppendFormatted(string? value) => AppendFormatted(value.AsSpan());

    /// <summary>
    ///  Appends one character.
    /// </summary>
    /// <param name="value">The character.</param>
    internal void AppendFormatted(char value)
    {
        if (_length == _buffer.Length) { Grow(1); }
        _buffer[_length++] = value;
    }

    /// <summary>
    ///  Appends a value's text.
    /// </summary>
    /// <typeparam name="T">The value type.</typeparam>
    /// <param name="value">The value.</param>
    internal void AppendFormatted<T>(T value) => AppendFormatted(value, format: null);

    /// <summary>
    ///  Appends a value's text in a format.
    /// </summary>
    /// <typeparam name="T">The value type.</typeparam>
    /// <param name="value">The value.</param>
    /// <param name="format">The format string, such as <c>X2</c>.</param>
    internal void AppendFormatted<T>(T value, string? format) =>
        AppendFormatted(value is IFormattable formattable ? formattable.ToString(format, _provider) : value?.ToString());

    /// <summary>
    ///  Gets the built string and returns the buffer to the pool; the handler must not be used afterwards.
    /// </summary>
    /// <returns>The built string.</returns>
    internal string ToStringAndClear()
    {
        string result = new(_buffer, 0, _length);
        ArrayPool<char>.Shared.Return(_buffer);
        _buffer = [];
        _length = 0;
        return result;
    }

    /// <inheritdoc/>
    public override readonly string ToString() => new(_buffer, 0, _length);

    private void Grow(int additional)
    {
        char[] larger = ArrayPool<char>.Shared.Rent(Math.Max(_buffer.Length * 2, _length + additional));
        _buffer.AsSpan(0, _length).CopyTo(larger);
        ArrayPool<char>.Shared.Return(_buffer);
        _buffer = larger;
    }
}
