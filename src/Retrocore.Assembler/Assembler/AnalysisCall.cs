// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  A caller-supplied hint describing what a subroutine does with the bytes after its JSR.
/// </summary>
/// <remarks>
///  <para>
///   Static analysis cannot see a subroutine adjust its return address, so without a hint the bytes after
///   such a JSR are traced as code.
///  </para>
/// </remarks>
public sealed class AnalysisCall
{
    private AnalysisCall(AnalysisCallKind kind, int inlineLength)
    {
        Kind = kind;
        InlineLength = inlineLength;
    }

    /// <summary>
    ///  Gets the hint for a subroutine that never returns to its caller.
    /// </summary>
    public static AnalysisCall NoReturn { get; } = new(AnalysisCallKind.NoReturn, inlineLength: 0);

    /// <summary>
    ///  Gets the hint for a subroutine that reads a zero-terminated string after its JSR.
    /// </summary>
    public static AnalysisCall InlineZeroTerminated { get; } = new(AnalysisCallKind.InlineZeroTerminated, 0);

    /// <summary>
    ///  Gets the hint's behavior.
    /// </summary>
    public AnalysisCallKind Kind { get; }

    /// <summary>
    ///  Gets the inline argument byte count for <see cref="AnalysisCallKind.InlineBytes"/>, otherwise zero.
    /// </summary>
    public int InlineLength { get; }

    /// <summary>
    ///  Creates the hint for a subroutine that reads a fixed number of bytes after its JSR.
    /// </summary>
    /// <param name="length">The inline argument byte count.</param>
    /// <returns>The hint.</returns>
    public static AnalysisCall InlineBytes(int length)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(length);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(length, ushort.MaxValue);
        return new(AnalysisCallKind.InlineBytes, length);
    }
}
