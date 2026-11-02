// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  A problem in BASIC text.
/// </summary>
/// <param name="Line">The zero-based line of the text.</param>
/// <param name="Severity">How serious it is.</param>
/// <param name="Message">What is wrong.</param>
/// <param name="Start">The column the problem starts at.</param>
/// <param name="End">The column past its end, or -1 for the rest of the line.</param>
public readonly record struct BasicDiagnostic(int Line, BasicSeverity Severity, string Message, int Start = 0, int End = -1)
{
    /// <inheritdoc/>
    public override string ToString() => $"{Line + 1}: {Severity.ToString().ToLowerInvariant()}: {Message}";
}
