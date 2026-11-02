// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  A line of BASIC text that holds statements, with the number it is stored under.
/// </summary>
/// <param name="Line">The zero-based line of the text.</param>
/// <param name="Number">The line number: its own, or the one numbering gave it; -1 when none could be.</param>
/// <param name="Numbered">Whether the text gives the number, which pins it.</param>
/// <param name="Column">The column the statements start at.</param>
/// <param name="Statements">The statements as written, with labels where they name lines.</param>
public sealed record BasicTextLine(int Line, int Number, bool Numbered, int Column, string Statements);
