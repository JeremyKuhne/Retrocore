// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug.Language;

/// <summary>
///  Where a name is defined, and what it is.
/// </summary>
/// <param name="Name">The name as the source spells it.</param>
/// <param name="Path">The full path of the defining file.</param>
/// <param name="Line">The zero-based line.</param>
/// <param name="Column">The zero-based column.</param>
/// <param name="Kind">A label, a constant or a macro.</param>
/// <param name="Value">The value, for labels and constants.</param>
internal sealed record SymbolSite(string Name, string Path, int Line, int Column, SymbolSiteKind Kind, long? Value);
