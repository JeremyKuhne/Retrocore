// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  Where a statement starts: the first statement of a line, or the one after each colon.
/// </summary>
/// <param name="Offset">
///  The byte in the stored line the interpreter starts the statement at: 0, or just past a colon.
/// </param>
/// <param name="Column">The column of the statement's first character in the text.</param>
public readonly record struct BasicStatement(int Offset, int Column);
