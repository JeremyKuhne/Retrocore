// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  Owned rows from the current display mapping, not a reconstruction of what the beam previously scanned.
/// </summary>
/// <param name="Machine">The machine family.</param>
/// <param name="Model">The model, when known.</param>
/// <param name="Mode">The display mode at capture.</param>
/// <param name="Columns">The number of text columns.</param>
/// <param name="DisplayRows">The full text grid height.</param>
/// <param name="FirstRow">The first returned row within that grid, zero-based.</param>
/// <param name="Rows">The decoded rows belonging to the surface.</param>
/// <param name="Decoding">The source and limitations of the decoding.</param>
/// <param name="Cursor">The known cursor location, if available.</param>
internal sealed record DebugTextSurface(
    string Machine,
    string? Model,
    string Mode,
    int Columns,
    int DisplayRows,
    int FirstRow,
    string[] Rows,
    string Decoding,
    (int Row, int Column)? Cursor = null);
